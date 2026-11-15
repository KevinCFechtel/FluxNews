package de.circledev.fluxnews.nativeapp

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.util.LruCache
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import java.io.File
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import uniffi.flux_uniffi.MediaArtworkSource
import uniffi.flux_uniffi.MediaChapter
import uniffi.flux_uniffi.PlaybackPreparation
import uniffi.flux_uniffi.PlaybackStatus
import uniffi.flux_uniffi.ReaderDocument

internal enum class AndroidMediaPlaybackSourceKind {
    Local,
    Remote,
}

internal enum class AndroidMediaPlaybackPresentationStatus {
    Idle,
    Paused,
    Playing,
    Stopped,
    Completed,
}

internal object AndroidMediaPlaybackSyncPolicy {
    fun shouldAdopt(status: AndroidMediaPlaybackPresentationStatus): Boolean =
        status != AndroidMediaPlaybackPresentationStatus.Playing

    fun targetPositionMs(playbackState: uniffi.flux_uniffi.PlaybackState): Long =
        if (playbackState.status == PlaybackStatus.COMPLETED) {
            (playbackState.durationMs ?: playbackState.positionMs).toLong()
        } else {
            playbackState.positionMs.toLong()
        }.coerceAtLeast(0L)
}

internal data class AndroidMediaPlaybackState(
    val enclosureId: Long? = null,
    val articleId: Long? = null,
    val articleTitle: String? = null,
    val feedTitle: String? = null,
    val positionMs: Long = 0L,
    val durationMs: Long? = null,
    val playbackRate: Float = 1.0f,
    val status: AndroidMediaPlaybackPresentationStatus = AndroidMediaPlaybackPresentationStatus.Idle,
    val sourceKind: AndroidMediaPlaybackSourceKind? = null,
    val isLoading: Boolean = false,
    val isBuffering: Boolean = false,
    val chapters: List<MediaChapter> = emptyList(),
    val artworkSource: MediaArtworkSource? = null,
    val errorMessage: String? = null,
)


internal data class AndroidMediaSleepTimerState(
    val enabled: Boolean = false,
    val intervalMinutes: Int = 30,
    val remainingSeconds: Int? = null,
)

internal class AndroidMediaSleepTimer(
    private val scope: CoroutineScope,
    private val onFire: suspend () -> Unit,
) {
    companion object {
        val SupportedIntervalsMinutes = (30..180 step 15).toList()
    }

    private val mutableState =
        kotlinx.coroutines.flow.MutableStateFlow(AndroidMediaSleepTimerState())
    val state: kotlinx.coroutines.flow.StateFlow<AndroidMediaSleepTimerState> = mutableState

    private var timerJob: Job? = null

    fun setEnabled(enabled: Boolean) {
        if (enabled) start(mutableState.value.intervalMinutes) else disable()
    }

    fun setInterval(minutes: Int) {
        if (minutes !in SupportedIntervalsMinutes) return
        if (mutableState.value.enabled) {
            start(minutes)
        } else {
            mutableState.value = mutableState.value.copy(intervalMinutes = minutes)
        }
    }

    fun disable() {
        timerJob?.cancel()
        timerJob = null
        mutableState.value = mutableState.value.copy(
            enabled = false,
            remainingSeconds = null,
        )
    }

    private fun start(minutes: Int) {
        timerJob?.cancel()
        mutableState.value = AndroidMediaSleepTimerState(
            enabled = true,
            intervalMinutes = minutes,
            remainingSeconds = minutes * 60,
        )
        timerJob = scope.launch {
            var remaining = minutes * 60
            while (remaining > 0) {
                delay(1_000L)
                remaining -= 1
                mutableState.value = mutableState.value.copy(
                    remainingSeconds = remaining.coerceAtLeast(0),
                )
            }
            timerJob = null
            mutableState.value = mutableState.value.copy(
                enabled = false,
                remainingSeconds = null,
            )
            onFire()
        }
    }
}

internal sealed interface AndroidResolvedPlaybackSource {
    data class Local(val file: File) : AndroidResolvedPlaybackSource
    data class Remote(val url: String) : AndroidResolvedPlaybackSource
}

internal data class AndroidMediaSessionPreparation(
    val mediaItem: MediaItem,
    val startPositionMs: Long,
)

internal class AndroidMediaSourceResolver(
    private val mediaRoot: File,
) {
    fun resolve(preparation: PlaybackPreparation): AndroidResolvedPlaybackSource {
        preparation.localFile
            ?.let(::readableLocalFile)
            ?.let { return AndroidResolvedPlaybackSource.Local(it) }

        val remote = preparation.enclosure.url.trim()
        val scheme = runCatching { java.net.URI(remote).scheme?.lowercase() }.getOrNull()
        require(scheme == "http" || scheme == "https") { "Media URL is not playable." }
        return AndroidResolvedPlaybackSource.Remote(remote)
    }

    private fun readableLocalFile(reference: String): File? {
        val trimmed = reference.trim()
        if (trimmed.isEmpty()) return null
        val relative = File(trimmed)
        if (relative.isAbsolute) return null

        val root = runCatching { mediaRoot.canonicalFile }.getOrNull() ?: return null
        val candidate = runCatching { File(root, trimmed).canonicalFile }.getOrNull() ?: return null
        if (!candidate.toPath().startsWith(root.toPath())) return null
        return candidate.takeIf { it.isFile && it.canRead() }
    }
}

/**
 * Process-scoped playback orchestrator.
 *
 * Core remains authoritative for durable progress, completion, source selection and metadata.
 * Media3 owns only native execution and transient high-frequency playback state.
 */
internal class AndroidMediaPlaybackCoordinator(
    context: Context,
    private val coreRuntime: AndroidCoreRuntime,
    mediaRoot: File,
    private val scope: CoroutineScope,
    private val diagnostics: AndroidAppDiagnostics,
    private val onCoreMediaMutation: suspend (Long) -> Unit = {},
    private val checkpointIntervalMs: Long = 20_000L,
) {
    private val applicationContext = context.applicationContext
    private val sourceResolver = AndroidMediaSourceResolver(mediaRoot)
    private val commandMutex = Mutex()
    private val directExecutor = Executor { command -> command.run() }
    private val artworkCache = object : LruCache<String, ByteArray>(16 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int =
            (value.size / 1024).coerceAtLeast(1)
    }

    private val mutableState = kotlinx.coroutines.flow.MutableStateFlow(AndroidMediaPlaybackState())
    val state: kotlinx.coroutines.flow.StateFlow<AndroidMediaPlaybackState> = mutableState

    val sleepTimer = AndroidMediaSleepTimer(scope) { pause() }

    @Volatile
    private var controller: MediaController? = null
    private var controllerFuture: com.google.common.util.concurrent.ListenableFuture<MediaController>? = null
    private var controllerListenerAttached = false

    @Volatile
    private var activeGeneration: Long? = null

    @Volatile
    private var preparedStatus: PlaybackStatus = PlaybackStatus.NOT_STARTED

    @Volatile
    private var completionSent = false

    @Volatile
    private var lastObservedDurationMs: Long? = null

    private var positionJob: Job? = null
    private var checkpointJob: Job? = null

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            val previous = mutableState.value.status
            mutableState.value = mutableState.value.copy(
                status = if (isPlaying) {
                    AndroidMediaPlaybackPresentationStatus.Playing
                } else if (previous == AndroidMediaPlaybackPresentationStatus.Playing) {
                    AndroidMediaPlaybackPresentationStatus.Paused
                } else {
                    previous
                },
            )
            if (isPlaying) {
                startRuntimeJobs()
            } else {
                stopRuntimeJobs()
                if (previous == AndroidMediaPlaybackPresentationStatus.Playing) {
                    scope.launch { checkpointCurrent() }
                }
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_BUFFERING -> {
                    mutableState.value = mutableState.value.copy(
                        isLoading = true,
                        isBuffering = true,
                    )
                }
                Player.STATE_READY -> {
                    mutableState.value = mutableState.value.copy(
                        isLoading = false,
                        isBuffering = false,
                    )
                    scope.launch { observeDurationFromController() }
                }
                Player.STATE_ENDED -> {
                    mutableState.value = mutableState.value.copy(
                        isLoading = false,
                        isBuffering = false,
                    )
                    stopRuntimeJobs()
                    scope.launch { handleNaturalCompletion() }
                }
                Player.STATE_IDLE -> {
                    mutableState.value = mutableState.value.copy(
                        isLoading = false,
                        isBuffering = false,
                    )
                }
            }
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            mutableState.value = mutableState.value.copy(
                positionMs = newPosition.positionMs.coerceAtLeast(0L),
            )
            if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                scope.launch { checkpointCurrent() }
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            mutableState.value = mutableState.value.copy(
                isLoading = false,
                isBuffering = false,
                status = AndroidMediaPlaybackPresentationStatus.Paused,
                errorMessage = error.localizedMessage ?: "Media playback failed.",
            )
            stopRuntimeJobs()
            scope.launch { checkpointCurrent() }
        }
    }

    suspend fun prepare(enclosureId: Long): PlaybackPreparation = commandMutex.withLock {
        val resolved = resolvePlaybackPreparationLocked(enclosureId)
        val mediaController = controller()

        withContext(Dispatchers.Main.immediate) {
            mediaController.pause()
            mediaController.setMediaItem(resolved.mediaItem, resolved.startPositionMs)
            mediaController.setPlaybackSpeed(mutableState.value.playbackRate)
            mediaController.prepare()
        }

        resolved.preparation
    }

    /**
     * Resolves an Android Auto / external MediaSession selection through the exact same Core source
     * and resume rules as the in-app player, but leaves Media3 to execute the requested set/play
     * command after the session callback returns.
     */
    suspend fun prepareForMediaSession(enclosureId: Long): AndroidMediaSessionPreparation =
        commandMutex.withLock {
            val resolved = resolvePlaybackPreparationLocked(enclosureId)
            // External playback still needs the process-scoped coordinator listener so pause/seek,
            // completion and periodic checkpoint semantics stay identical to in-app playback.
            controller()
            AndroidMediaSessionPreparation(
                mediaItem = resolved.mediaItem,
                startPositionMs = resolved.startPositionMs,
            )
        }

    private data class ResolvedPlaybackPreparation(
        val preparation: PlaybackPreparation,
        val mediaItem: MediaItem,
        val startPositionMs: Long,
    )

    private suspend fun resolvePlaybackPreparationLocked(
        enclosureId: Long,
    ): ResolvedPlaybackPreparation {
        require(enclosureId > 0L)
        val generation = coreRuntime.activeSessionGeneration()
            ?: error("No active Core session.")

        if (mutableState.value.enclosureId != null && mutableState.value.enclosureId != enclosureId) {
            checkpointCurrent()
        }

        val prepared = coreRuntime.localForGeneration(generation) { core ->
            val preparation = core.preparePlayback(enclosureId = enclosureId)
            val chapters = runCatching {
                core.mediaChapters(enclosureId = enclosureId)
            }.getOrDefault(emptyList())
            val artworkBytes = when (val artwork = preparation.artworkSource) {
                is MediaArtworkSource.LocalReference -> runCatching {
                    core.mediaArtwork(reference = artwork.reference)
                }.getOrNull()
                is MediaArtworkSource.RemoteUrl,
                null,
                -> null
            }
            Triple(preparation, chapters, artworkBytes)
        }
        val preparation = prepared.first
        val chapters = prepared.second
        val localArtworkBytes = prepared.third
        val source = sourceResolver.resolve(preparation)

        activeGeneration = generation
        completionSent = false
        preparedStatus = preparation.playbackState.status
        lastObservedDurationMs = (preparation.durationMs ?: preparation.playbackState.durationMs)
            ?.toLong()

        val startPositionMs = if (preparation.playbackState.status == PlaybackStatus.IN_PROGRESS) {
            preparation.playbackState.positionMs.toLong().coerceAtLeast(0L)
        } else {
            0L
        }
        val preparedDurationMs = preparation.durationMs
            ?.toLong()
            ?: preparation.playbackState.durationMs?.toLong()

        val mediaMetadata = MediaMetadata.Builder()
            .setTitle(preparation.articleTitle)
            .setArtist(preparation.feedTitle)
            .setAlbumTitle(preparation.feedTitle)
            .setArtworkUri(AndroidAutoArtworkProvider.nowPlayingUri(applicationContext, enclosureId))
            .apply {
                preparedDurationMs
                    ?.takeIf { it >= 0L }
                    ?.let(::setDurationMs)
                if (preparation.artworkSource is MediaArtworkSource.LocalReference) {
                    localArtworkBytes?.let { bytes ->
                        setArtworkData(bytes, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
                    }
                }
            }
            .build()

        val mediaItem = MediaItem.Builder()
            .setMediaId(enclosureId.toString())
            .setUri(
                when (source) {
                    is AndroidResolvedPlaybackSource.Local -> Uri.fromFile(source.file)
                    is AndroidResolvedPlaybackSource.Remote -> Uri.parse(source.url)
                },
            )
            .setMimeType(preparation.enclosure.mimeType)
            .setMediaMetadata(mediaMetadata)
            .build()

        mutableState.value = mutableState.value.copy(
            enclosureId = enclosureId,
            articleId = preparation.enclosure.articleId,
            articleTitle = preparation.articleTitle,
            feedTitle = preparation.feedTitle,
            positionMs = startPositionMs,
            durationMs = preparedDurationMs,
            status = if (preparation.playbackState.status == PlaybackStatus.COMPLETED) {
                AndroidMediaPlaybackPresentationStatus.Completed
            } else {
                AndroidMediaPlaybackPresentationStatus.Paused
            },
            sourceKind = when (source) {
                is AndroidResolvedPlaybackSource.Local -> AndroidMediaPlaybackSourceKind.Local
                is AndroidResolvedPlaybackSource.Remote -> AndroidMediaPlaybackSourceKind.Remote
            },
            isLoading = source is AndroidResolvedPlaybackSource.Remote,
            isBuffering = false,
            chapters = chapters,
            artworkSource = preparation.artworkSource,
            errorMessage = null,
        )

        return ResolvedPlaybackPreparation(
            preparation = preparation,
            mediaItem = mediaItem,
            startPositionMs = startPositionMs,
        )
    }

    suspend fun play(enclosureId: Long) {
        val current = mutableState.value
        if (current.enclosureId != enclosureId) {
            prepare(enclosureId)
        }
        commandMutex.withLock {
            if (preparedStatus == PlaybackStatus.COMPLETED) return@withLock
            val mediaController = controller()
            withContext(Dispatchers.Main.immediate) {
                mediaController.play()
            }
        }
    }

    suspend fun pause() {
        commandMutex.withLock {
            val mediaController = controller ?: return@withLock
            withContext(Dispatchers.Main.immediate) {
                mediaController.pause()
            }
            mutableState.value = mutableState.value.copy(
                status = AndroidMediaPlaybackPresentationStatus.Paused,
            )
            stopRuntimeJobs()
            checkpointCurrent()
        }
    }

    suspend fun stop() {
        commandMutex.withLock {
            val mediaController = controller ?: return@withLock
            withContext(Dispatchers.Main.immediate) {
                mediaController.pause()
            }
            mutableState.value = mutableState.value.copy(
                status = AndroidMediaPlaybackPresentationStatus.Stopped,
            )
            stopRuntimeJobs()
            checkpointCurrent()
        }
    }

    suspend fun handleExternalStop() {
        commandMutex.withLock {
            if (mutableState.value.enclosureId == null) return@withLock
            mutableState.value = mutableState.value.copy(
                status = AndroidMediaPlaybackPresentationStatus.Stopped,
            )
            stopRuntimeJobs()
            checkpointCurrent()
        }
    }

    suspend fun seekTo(positionMs: Long) {
        commandMutex.withLock {
            val mediaController = controller ?: return@withLock
            val duration = mutableState.value.durationMs
            val target = positionMs.coerceAtLeast(0L).let { value ->
                duration?.let { value.coerceAtMost(it) } ?: value
            }
            withContext(Dispatchers.Main.immediate) {
                mediaController.seekTo(target)
            }
            mutableState.value = mutableState.value.copy(positionMs = target)
            checkpointCurrent()
        }
    }

    suspend fun skipBy(seconds: Int) {
        val deltaMs = seconds.toLong() * 1_000L
        val current = currentPositionMs()
        seekTo((current + deltaMs).coerceAtLeast(0L))
    }

    suspend fun skipBackward15Seconds() = skipBy(-15)

    suspend fun skipForward30Seconds() = skipBy(30)

    suspend fun setPlaybackRate(rate: Float) {
        if (!rate.isFinite()) return
        val rounded = ((rate.coerceIn(0.5f, 3.0f) * 10f).toInt() / 10f)
        commandMutex.withLock {
            mutableState.value = mutableState.value.copy(playbackRate = rounded)
            controller?.let { mediaController ->
                withContext(Dispatchers.Main.immediate) {
                    mediaController.setPlaybackSpeed(rounded)
                }
            }
        }
    }

    suspend fun refreshCorePresentation(
        sessionGeneration: Long? = coreRuntime.activeSessionGeneration(),
    ) {
        val generation = sessionGeneration ?: return
        val enclosureId = mutableState.value.enclosureId ?: return
        if (coreRuntime.activeSessionGeneration() != generation) return

        val refreshed = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                core.mediaArtworkSource(enclosureId = enclosureId) to
                    core.mediaChapters(enclosureId = enclosureId)
            }
        }.getOrNull() ?: return

        if (
            coreRuntime.activeSessionGeneration() == generation &&
            mutableState.value.enclosureId == enclosureId
        ) {
            mutableState.value = mutableState.value.copy(
                artworkSource = refreshed.first,
                chapters = refreshed.second,
            )
        }
    }

    suspend fun reconcileAfterSuccessfulSync(
        sessionGeneration: Long? = coreRuntime.activeSessionGeneration(),
    ) = commandMutex.withLock {
        val generation = sessionGeneration ?: return@withLock
        val before = mutableState.value
        val enclosureId = before.enclosureId ?: return@withLock
        if (
            coreRuntime.activeSessionGeneration() != generation ||
            !AndroidMediaPlaybackSyncPolicy.shouldAdopt(before.status)
        ) {
            return@withLock
        }

        val playbackState = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                core.playbackState(enclosureId = enclosureId)
            }
        }.getOrNull() ?: return@withLock

        if (
            coreRuntime.activeSessionGeneration() != generation ||
            mutableState.value.enclosureId != enclosureId ||
            !AndroidMediaPlaybackSyncPolicy.shouldAdopt(mutableState.value.status)
        ) {
            return@withLock
        }

        val targetPositionMs = AndroidMediaPlaybackSyncPolicy.targetPositionMs(playbackState)
        val targetDurationMs = playbackState.durationMs?.toLong()

        controller?.let { mediaController ->
            withContext(Dispatchers.Main.immediate) {
                if (
                    !mediaController.isPlaying &&
                    mediaController.currentPosition.coerceAtLeast(0L) != targetPositionMs
                ) {
                    mediaController.seekTo(targetPositionMs.coerceAtLeast(0L))
                }
            }
        }

        if (
            coreRuntime.activeSessionGeneration() != generation ||
            mutableState.value.enclosureId != enclosureId ||
            !AndroidMediaPlaybackSyncPolicy.shouldAdopt(mutableState.value.status)
        ) {
            return@withLock
        }

        preparedStatus = playbackState.status
        targetDurationMs?.let {
            lastObservedDurationMs = it
        }
        mutableState.value = mutableState.value.copy(
            positionMs = targetPositionMs.coerceAtLeast(0L),
            durationMs = targetDurationMs ?: mutableState.value.durationMs,
        )
    }

    suspend fun artworkSource(enclosureId: Long): MediaArtworkSource? {
        val generation = activeGeneration ?: coreRuntime.activeSessionGeneration() ?: return null
        return runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                core.mediaArtworkSource(enclosureId = enclosureId)
            }
        }.getOrNull()?.takeIf {
            coreRuntime.activeSessionGeneration() == generation
        }
    }

    suspend fun chapters(enclosureId: Long): List<MediaChapter> {
        val generation = activeGeneration ?: coreRuntime.activeSessionGeneration()
            ?: return emptyList()
        return runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                core.mediaChapters(enclosureId = enclosureId)
            }
        }.getOrDefault(emptyList()).takeIf {
            coreRuntime.activeSessionGeneration() == generation
        } ?: emptyList()
    }

    suspend fun artworkBytes(reference: String): ByteArray? {
        artworkCache.get(reference)?.let { return it }
        val generation = activeGeneration ?: coreRuntime.activeSessionGeneration() ?: return null
        val bytes = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                core.mediaArtwork(reference = reference)
            }
        }.getOrNull()?.takeIf {
            coreRuntime.activeSessionGeneration() == generation
        } ?: return null
        artworkCache.put(reference, bytes)
        return bytes
    }

    suspend fun showNotes(articleId: Long): Result<ReaderDocument> {
        val generation = activeGeneration ?: coreRuntime.activeSessionGeneration()
            ?: return Result.failure(IllegalStateException("No active Core session."))
        val result = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                core.readerDocument(articleId = articleId)
            }
        }
        if (coreRuntime.activeSessionGeneration() != generation) {
            return Result.failure(IllegalStateException("Core session changed."))
        }
        return result
    }

    suspend fun restart(enclosureId: Long) {
        val wasPlaying = mutableState.value.status == AndroidMediaPlaybackPresentationStatus.Playing
        val wasCompleted = preparedStatus == PlaybackStatus.COMPLETED
        val generation = activeGeneration ?: coreRuntime.activeSessionGeneration()
            ?: error("No active Core session.")

        coreRuntime.localForGeneration(generation) { core ->
            core.restartPlayback(enclosureId = enclosureId)
        }
        if (coreRuntime.activeSessionGeneration() == generation) {
            runCatching { onCoreMediaMutation(generation) }
        }
        prepare(enclosureId)
        if (wasPlaying || wasCompleted) play(enclosureId)
    }

    suspend fun checkpointCurrent() {
        val enclosureId = mutableState.value.enclosureId ?: return
        val generation = activeGeneration ?: return
        if (coreRuntime.activeSessionGeneration() != generation) return

        val snapshot = controllerSnapshot() ?: return
        try {
            coreRuntime.localForGeneration(generation) { core ->
                core.checkpointPlayback(
                    enclosureId = enclosureId,
                    positionMs = snapshot.first.coerceAtLeast(0L).toULong(),
                    durationMs = snapshot.second
                        ?.takeIf { it > 0L }
                        ?.toULong(),
                )
            }
        } catch (failure: Throwable) {
            if (coreRuntime.activeSessionGeneration() == generation) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "media",
                    "Playback checkpoint failed: ${failure.javaClass.simpleName}",
                )
            }
        }
    }

    suspend fun clearForCoreLifecycle() {
        sleepTimer.disable()
        stopRuntimeJobs()
        val mediaController = controller
        if (mediaController != null) {
            withContext(Dispatchers.Main.immediate) {
                mediaController.pause()
                mediaController.clearMediaItems()
            }
        }
        activeGeneration = null
        artworkCache.evictAll()
        preparedStatus = PlaybackStatus.NOT_STARTED
        completionSent = false
        lastObservedDurationMs = null
        mutableState.value = AndroidMediaPlaybackState(
            playbackRate = mutableState.value.playbackRate,
        )
    }

    fun blocksMediaDeletion(enclosureId: Long): Boolean =
        mutableState.value.enclosureId == enclosureId &&
            mutableState.value.status == AndroidMediaPlaybackPresentationStatus.Playing

    private suspend fun controller(): MediaController {
        controller?.let { return it }

        val existingFuture = synchronized(this) {
            controllerFuture ?: MediaController.Builder(
                applicationContext,
                SessionToken(
                    applicationContext,
                    ComponentName(applicationContext, AndroidMediaPlaybackService::class.java),
                ),
            ).buildAsync().also { controllerFuture = it }
        }

        val built = suspendCancellableCoroutine { continuation ->
            existingFuture.addListener(
                {
                    try {
                        continuation.resume(existingFuture.get())
                    } catch (failure: Throwable) {
                        continuation.resumeWithException(failure)
                    }
                },
                directExecutor,
            )
            continuation.invokeOnCancellation {
                if (!existingFuture.isDone) existingFuture.cancel(true)
            }
        }

        synchronized(this) {
            if (controller == null) controller = built
        }
        attachControllerListener(built)
        return controller ?: built
    }

    private suspend fun attachControllerListener(mediaController: MediaController) {
        if (controllerListenerAttached) return
        withContext(Dispatchers.Main.immediate) {
            if (!controllerListenerAttached) {
                mediaController.addListener(playerListener)
                controllerListenerAttached = true
            }
        }
    }

    private fun startRuntimeJobs() {
        if (positionJob == null) {
            positionJob = scope.launch {
                while (true) {
                    delay(500L)
                    updatePositionFromController()
                }
            }
        }
        if (checkpointJob == null) {
            checkpointJob = scope.launch {
                while (true) {
                    delay(checkpointIntervalMs)
                    if (mutableState.value.status == AndroidMediaPlaybackPresentationStatus.Playing) {
                        checkpointCurrent()
                    }
                }
            }
        }
    }

    private fun stopRuntimeJobs() {
        positionJob?.cancel()
        positionJob = null
        checkpointJob?.cancel()
        checkpointJob = null
    }

    private suspend fun updatePositionFromController() {
        val snapshot = controllerSnapshot() ?: return
        mutableState.value = mutableState.value.copy(
            positionMs = snapshot.first,
            durationMs = snapshot.second ?: mutableState.value.durationMs,
        )
    }

    private suspend fun currentPositionMs(): Long =
        controllerSnapshot()?.first ?: mutableState.value.positionMs

    private suspend fun controllerSnapshot(): Pair<Long, Long?>? {
        val mediaController = controller ?: return null
        return withContext(Dispatchers.Main.immediate) {
            val duration = mediaController.duration
                .takeIf { it != C.TIME_UNSET && it > 0L }
            mediaController.currentPosition.coerceAtLeast(0L) to duration
        }
    }

    private suspend fun observeDurationFromController() {
        val enclosureId = mutableState.value.enclosureId ?: return
        val generation = activeGeneration ?: return
        if (coreRuntime.activeSessionGeneration() != generation) return

        val duration = controllerSnapshot()?.second ?: return
        mutableState.value = mutableState.value.copy(durationMs = duration)
        if (lastObservedDurationMs == duration) return
        lastObservedDurationMs = duration

        try {
            coreRuntime.localForGeneration(generation) { core ->
                core.observeMediaDuration(
                    enclosureId = enclosureId,
                    durationMs = duration.toULong(),
                )
            }
        } catch (failure: Throwable) {
            if (coreRuntime.activeSessionGeneration() == generation) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "media",
                    "Media duration observation failed: ${failure.javaClass.simpleName}",
                )
            }
        }
    }

    private suspend fun handleNaturalCompletion() {
        if (completionSent) return
        val enclosureId = mutableState.value.enclosureId ?: return
        val generation = activeGeneration ?: return
        if (coreRuntime.activeSessionGeneration() != generation) return
        val duration = controllerSnapshot()?.second ?: mutableState.value.durationMs

        try {
            coreRuntime.localForGeneration(generation) { core ->
                core.playbackCompleted(
                    enclosureId = enclosureId,
                    durationMs = duration
                        ?.takeIf { it > 0L }
                        ?.toULong(),
                )
            }
            if (coreRuntime.activeSessionGeneration() != generation) return
            runCatching { onCoreMediaMutation(generation) }
            completionSent = true
            preparedStatus = PlaybackStatus.COMPLETED
            mutableState.value = mutableState.value.copy(
                positionMs = duration ?: mutableState.value.positionMs,
                durationMs = duration ?: mutableState.value.durationMs,
                status = AndroidMediaPlaybackPresentationStatus.Completed,
            )
        } catch (failure: Throwable) {
            if (coreRuntime.activeSessionGeneration() == generation) {
                diagnostics.record(
                    AndroidAppLogLevel.Error,
                    "media",
                    "Playback completion failed: ${failure.javaClass.simpleName}",
                )
                mutableState.value = mutableState.value.copy(
                    status = AndroidMediaPlaybackPresentationStatus.Paused,
                    errorMessage = "Playback completion could not be saved.",
                )
            }
        }
    }
}
