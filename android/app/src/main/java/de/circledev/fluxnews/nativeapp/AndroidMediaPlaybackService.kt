package de.circledev.fluxnews.nativeapp

import android.net.Uri
import android.os.Bundle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaConstants
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Single Media3 playback and browse container for E6/E7.
 *
 * The service continues to own the one native Android player introduced in E6. E7 extends that
 * same service with a MediaLibrarySession so Android Auto and other media browsers see a
 * Core-backed Listening List without introducing a second player, queue, database or cache.
 */
class AndroidMediaPlaybackService : MediaLibraryService(), AndroidMediaPlaybackHost {
    private companion object {
        const val CUSTOM_BROWSER_RESULT_BROWSE_NODE_KEY =
            "androidx.media.utils.extras.KEY_CUSTOM_BROWSER_ACTION_RESULT_BROWSE_NODE"
    }

    private lateinit var player: ExoPlayer
    private var mediaSession: MediaLibrarySession? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val app: FluxApplication
        get() = applicationContext as FluxApplication

    private val mediaRuntime: AndroidMediaRuntime
        get() = app.mediaRuntime

    private val libraryStore: AndroidAutoMediaLibraryStore
        get() = app.autoMediaLibraryStore

    @UnstableApi
    private val libraryCallback = object : MediaLibrarySession.Callback {
        @UnstableApi
        override fun onConnectAsync(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): ListenableFuture<MediaSession.ConnectionResult> {
            val playerCommands = MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS
                .buildUpon()
                .remove(Player.COMMAND_SEEK_TO_PREVIOUS)
                .remove(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                .remove(Player.COMMAND_SEEK_TO_NEXT)
                .remove(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                .build()
            val customBrowseActionLimit = controller.maxCommandsForMediaItems
            val supportsFeedFilter = customBrowseActionLimit > 0
            app.diagnostics.record(
                AndroidAppLogLevel.Info,
                "android-auto",
                "Media browser connected: package=" + controller.packageName +
                    ", customBrowseActionLimit=" + customBrowseActionLimit +
                    ", feedFilterSupported=" + supportsFeedFilter,
            )

            val sessionCommandsBuilder =
                MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
            if (supportsFeedFilter) {
                sessionCommandsBuilder.add(
                    SessionCommand(
                        AndroidAutoMediaLibraryProjection.FILTER_COMMAND_ACTION,
                        Bundle.EMPTY,
                    ),
                )
            }
            val sessionCommands = sessionCommandsBuilder.build()

            return Futures.immediateFuture(
                MediaSession.ConnectionResult.AcceptedResultBuilder(session, controller)
                    .setAvailablePlayerCommands(playerCommands)
                    .setAvailableSessionCommands(sessionCommands)
                    .build(),
            )
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            com.google.common.util.concurrent.Futures.immediateFuture(
                LibraryResult.ofItem(
                    AndroidAutoMediaLibraryProjection.rootItem(
                        supportsFeedFilter = browser.maxCommandsForMediaItems > 0,
                                context = this@AndroidMediaPlaybackService,
                    ),
                    params,
                ),
            )

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
            libraryResultFuture {
                val snapshot = refreshLibraryForHeadlessBrowser()
                    ?: return@libraryResultFuture LibraryResult.ofItemList(emptyList(), params)

                val items = when {
                    parentId == AndroidAutoMediaLibraryProjection.ROOT_MEDIA_ID -> snapshot.items

                    parentId == AndroidAutoMediaLibraryProjection.FILTER_ROOT_MEDIA_ID ->
                        AndroidAutoMediaLibraryProjection.filterItems(snapshot, this@AndroidMediaPlaybackService)

                    AndroidAutoMediaLibraryProjection.isFilterChoice(parentId) -> {
                        val requestedFeedId =
                            AndroidAutoMediaLibraryProjection.filterFeedId(parentId)
                        if (
                            requestedFeedId != null &&
                            snapshot.feeds.none { it.feedId == requestedFeedId }
                        ) {
                            return@libraryResultFuture LibraryResult.ofError(
                                SessionError.ERROR_BAD_VALUE,
                                params,
                            )
                        }
                        val filtered = libraryStore.refresh(
                            generation = snapshot.sessionGeneration
                                ?: return@libraryResultFuture LibraryResult.ofItemList(
                                    emptyList(),
                                    params,
                                ),
                            feedId = requestedFeedId,
                        )
                        notifyListeningListChanged(filtered.items.size)
                        filtered.items
                    }

                    else -> return@libraryResultFuture LibraryResult.ofError(
                        SessionError.ERROR_BAD_VALUE,
                        params,
                    )
                }

                val from = (page.toLong() * pageSize.toLong())
                    .coerceAtMost(items.size.toLong())
                    .toInt()
                val to = (from + pageSize).coerceAtMost(items.size)
                LibraryResult.ofItemList(items.subList(from, to), params)
            }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            when {
                mediaId == AndroidAutoMediaLibraryProjection.ROOT_MEDIA_ID ->
                    Futures.immediateFuture(
                        LibraryResult.ofItem(
                            AndroidAutoMediaLibraryProjection.rootItem(
                                supportsFeedFilter = browser.maxCommandsForMediaItems > 0,
                                context = this@AndroidMediaPlaybackService,
                            ),
                            null,
                        ),
                    )

                mediaId == AndroidAutoMediaLibraryProjection.FILTER_ROOT_MEDIA_ID ->
                    Futures.immediateFuture(
                        LibraryResult.ofItem(
                            AndroidAutoMediaLibraryProjection.filterRootItem(this@AndroidMediaPlaybackService),
                            null,
                        ),
                    )

                AndroidAutoMediaLibraryProjection.isFilterChoice(mediaId) ->
                    libraryResultFuture {
                        val snapshot = refreshLibraryForHeadlessBrowser()
                            ?: return@libraryResultFuture LibraryResult.ofError(
                                SessionError.ERROR_BAD_VALUE,
                            )
                        AndroidAutoMediaLibraryProjection.filterChoiceItem(snapshot, mediaId, this@AndroidMediaPlaybackService)
                            ?.let { LibraryResult.ofItem(it, null) }
                            ?: LibraryResult.ofError(SessionError.ERROR_BAD_VALUE)
                    }

                else -> libraryResultFuture {
                    val cached = libraryStore.snapshot().itemsByMediaId[mediaId]
                    val item = cached ?: refreshLibraryForHeadlessBrowser()
                        ?.itemsByMediaId
                        ?.get(mediaId)
                    item?.let { LibraryResult.ofItem(it, null) }
                        ?: LibraryResult.ofError(SessionError.ERROR_BAD_VALUE)
                }
            }


        override fun onSearch(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<Void>> =
            libraryResultFuture {
                val results = searchLibrary(query)
                session.notifySearchResultChanged(
                    browser,
                    query,
                    results.size,
                    params,
                )
                LibraryResult.ofVoid(params)
            }

        override fun onGetSearchResult(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
            libraryResultFuture {
                val results = searchLibrary(query)
                val from = (page.toLong() * pageSize.toLong())
                    .coerceAtMost(results.size.toLong())
                    .toInt()
                val to = (from + pageSize).coerceAtMost(results.size)
                LibraryResult.ofItemList(results.subList(from, to), params)
            }


        @UnstableApi
        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            if (
                customCommand.customAction !=
                AndroidAutoMediaLibraryProjection.FILTER_COMMAND_ACTION
            ) {
                return super.onCustomCommand(session, controller, customCommand, args)
            }

            if (controller.maxCommandsForMediaItems <= 0) {
                return Futures.immediateFuture(
                    SessionResult(SessionError.ERROR_NOT_SUPPORTED),
                )
            }

            val mediaId = args.getString(MediaConstants.EXTRA_KEY_MEDIA_ID)
            if (
                mediaId != null &&
                mediaId != AndroidAutoMediaLibraryProjection.ROOT_MEDIA_ID
            ) {
                return Futures.immediateFuture(
                    SessionResult(SessionError.ERROR_BAD_VALUE),
                )
            }

            val resultExtras = Bundle().apply {
                putString(
                    CUSTOM_BROWSER_RESULT_BROWSE_NODE_KEY,
                    AndroidAutoMediaLibraryProjection.FILTER_ROOT_MEDIA_ID,
                )
            }
            return Futures.immediateFuture(
                SessionResult(SessionResult.RESULT_SUCCESS, resultExtras),
            )
        }


        /**
         * Resolve Android Auto / legacy MediaBrowser selections through Core. The in-app
         * coordinator already supplies a fully resolved URI, so its own MediaController commands
         * pass through unchanged and cannot recursively re-enter Core preparation.
         */
        @UnstableApi
        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            if (mediaItems.size != 1) {
                return Futures.immediateFailedFuture(
                    UnsupportedOperationException("FluxNews does not expose a durable media queue."),
                )
            }

            val requested = mediaItems.single()
            if (
                controller.packageName == packageName &&
                requested.localConfiguration != null
            ) {
                return Futures.immediateFuture(
                    MediaSession.MediaItemsWithStartPosition(
                        mediaItems,
                        startIndex,
                        startPositionMs,
                    ),
                )
            }

            return mediaSessionItemsFuture {
                val snapshot = refreshLibraryForHeadlessBrowser()
                    ?: throw IllegalStateException("FluxNews media library is unavailable.")

                val requestedMediaItem = AndroidAutoMediaRequestPolicy.resolve(
                    snapshot = snapshot,
                    mediaId = requested.mediaId,
                    searchQuery = requested.requestMetadata.searchQuery,
                ) ?: throw IllegalArgumentException(
                    "Requested media is not in the Listening List.",
                )

                val enclosureId = requestedMediaItem.mediaId
                    .toLongOrNull()
                    ?.takeIf { it > 0L }
                    ?: throw IllegalArgumentException("Invalid Listening List media identity.")

                val resolved = app.mediaPlaybackCoordinator.prepareForMediaSession(enclosureId)
                val requestedStart = startPositionMs
                    .takeIf { it != C.TIME_UNSET && it >= 0L }
                    ?: resolved.startPositionMs

                MediaSession.MediaItemsWithStartPosition(
                    listOf(resolved.mediaItem),
                    0,
                    requestedStart,
                )
            }
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
        ): ListenableFuture<List<MediaItem>> =
            Futures.immediateFailedFuture(
                UnsupportedOperationException("FluxNews does not expose a durable media queue."),
            )

        @UnstableApi
        override fun onPlayerInteractionFinished(
            session: MediaSession,
            controllerInfo: MediaSession.ControllerInfo,
            playerCommands: Player.Commands,
        ) {
            if (playerCommands.contains(Player.COMMAND_STOP)) {
                serviceScope.launch {
                    app.mediaPlaybackCoordinator.handleExternalStop()
                }
            }
        }
    }

    @UnstableApi
    override fun onCreate() {
        super.onCreate()

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
            .build()

        player = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setSeekBackIncrementMs(15_000L)
            .setSeekForwardIncrementMs(30_000L)
            .build()

        val mediaButtonPreferences = listOf(
            CommandButton.Builder(CommandButton.ICON_SKIP_BACK_15)
                .setDisplayName(getString(R.string.auto_back_15))
                .setPlayerCommand(Player.COMMAND_SEEK_BACK)
                .setSlots(CommandButton.SLOT_BACK)
                .build(),
            CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD_30)
                .setDisplayName(getString(R.string.auto_forward_30))
                .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
                .setSlots(CommandButton.SLOT_FORWARD)
                .build(),
        )
        val filterButton = CommandButton.Builder(CommandButton.ICON_PLAYLIST_ADD)
            .setDisplayName(getString(R.string.auto_filter_by_feed))
            .setIconUri(
                Uri.parse(
                    "android.resource://$packageName/drawable/ic_filter",
                ),
            )
            .setSessionCommand(
                SessionCommand(
                    AndroidAutoMediaLibraryProjection.FILTER_COMMAND_ACTION,
                    Bundle.EMPTY,
                ),
            )
            .build()

        mediaSession = MediaLibrarySession.Builder(this, player, libraryCallback)
            .setMediaButtonPreferences(mediaButtonPreferences)
            .setCommandButtonsForMediaItems(listOf(filterButton))
            .build()
        app.carAppPlatformToken = mediaSession?.platformToken
        mediaRuntime.attachPlaybackHost(this)
        observeLibraryChanges()
    }

    private fun observeLibraryChanges() {
        serviceScope.launch {
            app.mediaTransferCoordinator.revision
                .drop(1)
                .collectLatest {
                    refreshAndInvalidateListeningList()
                }
        }
        serviceScope.launch {
            app.coreRuntime.sessionGeneration
                .drop(1)
                .collectLatest { generation ->
                    libraryStore.clear()
                    if (generation == null) {
                        notifyListeningListChanged(0)
                    } else {
                        refreshAndInvalidateListeningList()
                    }
                }
        }
    }

    private suspend fun refreshAndInvalidateListeningList() {
        val refreshed = refreshLibraryForHeadlessBrowser()
        notifyListeningListChanged(refreshed?.items?.size ?: 0)
    }

    private fun notifyListeningListChanged(itemCount: Int) {
        mediaSession?.notifyChildrenChanged(
            AndroidAutoMediaLibraryProjection.ROOT_MEDIA_ID,
            itemCount.coerceAtLeast(0),
            null,
        )
    }

    override fun onGetSession(
        controllerInfo: MediaSession.ControllerInfo,
    ): MediaLibrarySession? = mediaSession

    override suspend fun checkpoint(): AndroidMediaPlaybackCheckpoint? =
        withContext(Dispatchers.Main.immediate) {
            if (!::player.isInitialized) return@withContext null
            val enclosureId = player.currentMediaItem
                ?.mediaId
                ?.toLongOrNull()
                ?.takeIf { it > 0L }
                ?: return@withContext null
            val duration = player.duration
                .takeIf { it != C.TIME_UNSET && it > 0L }

            AndroidMediaPlaybackCheckpoint(
                enclosureId = enclosureId,
                positionMs = player.currentPosition.coerceAtLeast(0L),
                durationMs = duration,
            )
        }

    override suspend fun quiesce(clearPlayback: Boolean) {
        withContext(Dispatchers.Main.immediate) {
            if (!::player.isInitialized) return@withContext
            player.pause()
            if (clearPlayback) {
                player.stop()
                player.clearMediaItems()
                libraryStore.clear()
            }
        }
    }

    private suspend fun searchLibrary(query: String): List<MediaItem> {
        val normalized = query.trim()
        if (normalized.isEmpty()) return emptyList()
        val snapshot = refreshLibraryForHeadlessBrowser() ?: return emptyList()
        return snapshot.items.filter { item ->
            AndroidAutoMediaLibraryProjection.matchesSearch(item, normalized)
        }
    }

    private suspend fun refreshLibraryForHeadlessBrowser(): AndroidAutoMediaLibrarySnapshot? {
        val bootstrapState = app.accountBootstrap.restoreStoredAccount()
        if (bootstrapState !is AndroidAccountBootstrap.State.Ready) {
            libraryStore.clear()
            return null
        }
        val generation = app.coreRuntime.activeSessionGeneration() ?: return null
        val selectedFeedId = libraryStore.snapshot()
            .takeIf { it.sessionGeneration == generation }
            ?.selectedFeedId
        return libraryStore.refresh(generation, selectedFeedId)
    }

    @UnstableApi
    private fun mediaSessionItemsFuture(
        block: suspend () -> MediaSession.MediaItemsWithStartPosition,
    ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
        val future = SettableFuture.create<MediaSession.MediaItemsWithStartPosition>()
        serviceScope.launch {
            try {
                future.set(block())
            } catch (failure: Throwable) {
                app.diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "android-auto",
                    "Playback selection failed: ${failure.javaClass.simpleName}",
                )
                future.setException(failure)
            }
        }
        return future
    }

    private fun <T : Any> libraryResultFuture(
        block: suspend () -> LibraryResult<T>,
    ): ListenableFuture<LibraryResult<T>> {
        val future = SettableFuture.create<LibraryResult<T>>()
        serviceScope.launch {
            try {
                future.set(block())
            } catch (failure: Throwable) {
                app.diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "android-auto",
                    "Media library request failed: ${failure.javaClass.simpleName}",
                )
                future.set(
                    LibraryResult.ofError<T>(
                        SessionError.ERROR_UNKNOWN,
                    ),
                )
            }
        }
        return future
    }

    override fun onDestroy() {
        app.carAppPlatformToken = null
        mediaRuntime.detachPlaybackHost(this)
        serviceScope.cancel()
        libraryStore.clear()
        mediaSession?.release()
        mediaSession = null
        if (::player.isInitialized) player.release()
        super.onDestroy()
    }
}
