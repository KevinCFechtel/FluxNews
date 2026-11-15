package de.circledev.fluxnews.nativeapp

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.support.v4.media.session.MediaSessionCompat
import androidx.annotation.OptIn
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.ScreenManager
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.annotations.ExperimentalCarApi
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.media.MediaConstants as CarMediaConstants
import androidx.car.app.media.MediaPlaybackManager
import androidx.car.app.media.model.MediaPlaybackTemplate
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarProgressBar
import androidx.car.app.model.Chip
import androidx.car.app.model.ChipSection
import androidx.car.app.model.Header
import androidx.car.app.model.Row
import androidx.car.app.model.RowSection
import androidx.car.app.model.SearchCallback
import androidx.car.app.model.SearchHeader
import androidx.car.app.model.SectionedItemTemplate
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaConstants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/**
 * Development-only Car App Library surface.
 *
 * Production intentionally keeps the stable MediaLibraryService browse UI until templated
 * media apps are generally available for Android Auto distribution.
 */
class FluxCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(sessionInfo: SessionInfo): Session =
        FluxCarAppSession()
}

private class FluxCarAppSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        val app = carContext.applicationContext as FluxApplication
        app.diagnostics.record(
            AndroidAppLogLevel.Info,
            "car-app",
            "CAL session opened carApi=" + carContext.carAppApiLevel +
                " action=" + intent.action.orEmpty(),
        )
        registerPlaybackTokenWhenAvailable()

        return if (intent.action == CarMediaConstants.ACTION_SHOW_MEDIA_PLAYBACK) {
            FluxMediaPlaybackCarScreen(carContext)
        } else {
            FluxListeningListCarScreen(carContext)
        }
    }

    override fun onNewIntent(intent: Intent) {
        if (intent.action != CarMediaConstants.ACTION_SHOW_MEDIA_PLAYBACK) return

        val app = carContext.applicationContext as FluxApplication
        val registered = registerPlaybackToken(carContext, app)
        app.diagnostics.record(
            if (registered) AndroidAppLogLevel.Info else AndroidAppLogLevel.Warning,
            "car-app",
            "CAL playback entrypoint requested tokenRegistered=" + registered,
        )
        carContext.getCarService(ScreenManager::class.java)
            .push(FluxMediaPlaybackCarScreen(carContext))
    }

    private fun registerPlaybackTokenWhenAvailable(attempt: Int = 0) {
        val app = carContext.applicationContext as FluxApplication
        if (registerPlaybackToken(carContext, app)) {
            if (attempt > 0) {
                app.diagnostics.record(
                    AndroidAppLogLevel.Info,
                    "car-app",
                    "CAL playback token registered startupAttempt=" + attempt,
                )
            }
            return
        }

        if (attempt >= 20) {
            app.diagnostics.record(
                AndroidAppLogLevel.Debug,
                "car-app",
                "CAL playback token not available during startup",
            )
            return
        }
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(
            { registerPlaybackTokenWhenAvailable(attempt + 1) },
            250L,
        )
    }
}

@Suppress("DEPRECATION")
private fun registerPlaybackToken(
    carContext: CarContext,
    app: FluxApplication,
): Boolean {
    val platformToken = app.carAppPlatformToken ?: return false
    return runCatching {
        val compatToken = MediaSessionCompat.Token.fromToken(platformToken)
        carContext.getCarService(MediaPlaybackManager::class.java)
            .registerMediaPlaybackToken(compatToken)
    }.isSuccess
}

private class FluxMediaPlaybackCarScreen(
    carContext: CarContext,
) : Screen(carContext) {
    override fun onGetTemplate(): Template =
        MediaPlaybackTemplate.Builder()
            .setHeader(
                Header.Builder()
                    .setTitle("Now Playing")
                    .setStartHeaderAction(Action.BACK)
                    .build(),
            )
            .build()
}

@OptIn(ExperimentalCarApi::class)
private class FluxListeningListCarScreen(
    carContext: CarContext,
) : Screen(carContext), DefaultLifecycleObserver {
    private val app = carContext.applicationContext as FluxApplication
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val rowLimit: Int by lazy {
        runCatching {
            carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
        }.getOrDefault(6).coerceAtLeast(1)
    }

    private var snapshot = AndroidAutoMediaLibrarySnapshot()
    private var selectedFeedId: Long? = null
    private var searchText = ""
    private var loading = true
    private var playbackEnclosureId: Long? = app.mediaPlaybackCoordinator.state.value.enclosureId
    private var playbackStatus: AndroidMediaPlaybackPresentationStatus =
        app.mediaPlaybackCoordinator.state.value.status

    init {
        lifecycle.addObserver(this)
        scope.launch {
            app.mediaPlaybackCoordinator.state
                .map { state -> state.enclosureId to state.status }
                .distinctUntilChanged()
                .collect { (enclosureId, status) ->
                    playbackEnclosureId = enclosureId
                    playbackStatus = status
                    invalidate()
                }
        }
        reload()
    }

    override fun onDestroy(owner: LifecycleOwner) {
        scope.cancel()
    }

    @UnstableApi
    override fun onGetTemplate(): Template {
        if (loading) {
            return SectionedItemTemplate.Builder()
                .setLoading(true)
                .setHeader(Header.Builder().setTitle("Listening List").build())
                .build()
        }

        val visibleItems = snapshot.items
            .asSequence()
            .filter { item ->
                searchText.isBlank() ||
                    AndroidAutoMediaLibraryProjection.matchesSearch(item, searchText)
            }
            .take(rowLimit)
            .toList()

        val hasNowPlaying =
            playbackEnclosureId != null &&
                playbackStatus != AndroidMediaPlaybackPresentationStatus.Idle &&
                playbackStatus != AndroidMediaPlaybackPresentationStatus.Stopped
        val nowPlayingAction = Action.Builder()
            .setIcon(CarIcon.MEDIA_PLAYBACK)
            .setOnClickListener {
                screenManager.push(FluxMediaPlaybackCarScreen(carContext))
            }
            .build()

        val rows = visibleItems.map { item ->
            val metadata = item.mediaMetadata
            val enclosureId = item.mediaId.toLongOrNull()
            val isNowPlaying = hasNowPlaying && enclosureId == playbackEnclosureId
            Row.Builder()
                .setTitle(metadata.title ?: "Untitled News")
                .addText(
                    if (isNowPlaying) {
                        "Now Playing • " + (metadata.artist ?: "Unknown Feed")
                    } else {
                        metadata.artist ?: "Unknown Feed"
                    },
                )
                .apply {
                    if (isNowPlaying) {
                        setEndImage(CarIcon.MEDIA_PLAYBACK)
                    }
                    metadata.artworkUri?.let { uri ->
                        setImage(
                            CarIcon.Builder(IconCompat.createWithContentUri(uri)).build(),
                            Row.IMAGE_TYPE_LARGE,
                        )
                    }
                    if (carContext.carAppApiLevel >= 9) {
                        metadata.extras
                            ?.takeIf {
                                it.containsKey(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE)
                            }
                            ?.getDouble(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE)
                            ?.toFloat()
                            ?.let { progress ->
                                setProgressBar(CarProgressBar.Builder(progress).build())
                            }
                    }
                    enclosureId?.let { selectedEnclosureId ->
                        setOnClickListener {
                            scope.launch {
                                playAndShowNowPlaying(selectedEnclosureId)
                            }
                        }
                    }
                }
                .build()
        }

        val builder = SectionedItemTemplate.Builder()
            .setScrollStatePersistenceStrategy(
                SectionedItemTemplate.SCROLL_STATE_PRESERVE_INDEX,
            )
        if (carContext.carAppApiLevel >= 9) {
            val chips = buildList {
                add(
                    Chip.Builder()
                        .setTitle("All Feeds")
                        .setSelected(selectedFeedId == null)
                        .setOnClickListener { selectFeed(null) }
                        .build(),
                )
                snapshot.feeds.forEach { feed ->
                    add(
                        Chip.Builder()
                            .setTitle(feed.feedTitle.ifBlank { "Unknown Feed" })
                            .setSelected(selectedFeedId == feed.feedId)
                            .setOnClickListener { selectFeed(feed.feedId) }
                            .build(),
                    )
                }
            }
            if (chips.isNotEmpty()) {
                builder.addSection(ChipSection.Builder().setItems(chips).build())
            }

            builder.setSearchHeader(
                SearchHeader.Builder(
                    object : SearchCallback {
                        override fun onSearchTextChanged(searchText: String) {
                            this@FluxListeningListCarScreen.searchText = searchText
                            invalidate()
                        }

                        override fun onSearchSubmitted(searchText: String) {
                            this@FluxListeningListCarScreen.searchText = searchText
                            invalidate()
                        }
                    },
                )
                    .setInitialSearchText(searchText)
                    .setSearchHint("Search episodes or feeds")
                    .setShowKeyboardByDefault(false)
                    .apply {
                        if (hasNowPlaying) {
                            setEndHeaderActions(listOf(nowPlayingAction))
                        }
                    }
                    .build(),
            )
        } else {
            builder.setHeader(
                Header.Builder()
                    .setTitle("Listening List")
                    .apply {
                        if (hasNowPlaying) {
                            addEndHeaderAction(nowPlayingAction)
                        }
                    }
                    .build(),
            )
        }

        builder.addSection(
            RowSection.Builder()
                .setItems(rows)
                .setNoItemsMessage(
                    if (searchText.isBlank()) {
                        "No items in the Listening List"
                    } else {
                        "No matching episodes"
                    },
                )
                .build(),
        )

        return builder.build()
    }

    private suspend fun playAndShowNowPlaying(enclosureId: Long) {
        app.diagnostics.record(
            AndroidAppLogLevel.Info,
            "car-app",
            "CAL item selected enclosure=" + enclosureId,
        )

        val playbackStarted = runCatching {
            app.mediaPlaybackCoordinator.play(enclosureId)
        }.onFailure { failure ->
            app.diagnostics.record(
                AndroidAppLogLevel.Warning,
                "car-app",
                "CAL playback start failed: " + failure.javaClass.simpleName,
            )
        }.isSuccess

        if (!playbackStarted) return

        var tokenRegistered = false
        for (attempt in 0 until 30) {
            if (registerPlaybackToken(carContext, app)) {
                tokenRegistered = true
                break
            }
            delay(100L)
        }

        app.diagnostics.record(
            if (tokenRegistered) AndroidAppLogLevel.Info else AndroidAppLogLevel.Warning,
            "car-app",
            "CAL opening Now Playing tokenRegistered=" + tokenRegistered,
        )

        withContext(Dispatchers.Main.immediate) {
            screenManager.push(FluxMediaPlaybackCarScreen(carContext))
        }
    }

    private fun selectFeed(feedId: Long?) {
        if (selectedFeedId == feedId) return
        selectedFeedId = feedId
        reload()
    }

    private fun reload() {
        loading = true
        invalidate()
        scope.launch(Dispatchers.IO) {
            val restored = app.accountBootstrap.restoreStoredAccount()
            val generation = if (restored is AndroidAccountBootstrap.State.Ready) {
                app.coreRuntime.activeSessionGeneration()
            } else {
                null
            }
            val refreshed = if (generation != null) {
                app.autoMediaLibraryStore.refresh(generation, selectedFeedId)
            } else {
                AndroidAutoMediaLibrarySnapshot()
            }

            withContext(Dispatchers.Main.immediate) {
                snapshot = refreshed
                selectedFeedId = refreshed.selectedFeedId
                loading = false
                app.diagnostics.record(
                    AndroidAppLogLevel.Info,
                    "car-app",
                    "CAL list ready carApi=" + carContext.carAppApiLevel +
                        " items=" + refreshed.items.size +
                        " feeds=" + refreshed.feeds.size +
                        " rowLimit=" + rowLimit +
                        " api9Features=" + (carContext.carAppApiLevel >= 9),
                )
                invalidate()
            }
        }
    }
}
