package de.circledev.fluxnews.nativeapp

/**
 * Runtime-only playback snapshot used to checkpoint the currently loaded enclosure before Core
 * lifecycle changes. The enclosure ID remains the Core media identity; this is not durable media
 * state.
 */
data class AndroidMediaPlaybackCheckpoint(
    val enclosureId: Long,
    val positionMs: Long,
    val durationMs: Long?,
)

internal interface AndroidMediaPlaybackHost {
    suspend fun checkpoint(): AndroidMediaPlaybackCheckpoint?
    suspend fun quiesce(clearPlayback: Boolean)
}

/**
 * Process-scoped owner for Android media execution.
 *
 * E6 keeps Core authoritative for playback progress and all durable media state. The native
 * playback service owns only Media3 execution. This runtime is the lifecycle bridge between the
 * two and deliberately does not create a second media-domain store.
 */
internal class AndroidMediaRuntime(
    private val coreRuntime: AndroidCoreRuntime,
    private val diagnostics: AndroidAppDiagnostics,
    private val playbackCoordinator: AndroidMediaPlaybackCoordinator,
    private val transferCoordinator: AndroidMediaTransferCoordinator,
) : AndroidCoreLifecycleParticipant {
    private val hostLock = Any()

    @Volatile
    private var attachedGeneration: Long? = null

    private var playbackHost: AndroidMediaPlaybackHost? = null

    internal fun attachPlaybackHost(host: AndroidMediaPlaybackHost) {
        synchronized(hostLock) {
            check(playbackHost == null || playbackHost === host) {
                "A different Android media playback host is already attached."
            }
            playbackHost = host
        }
    }

    internal fun detachPlaybackHost(host: AndroidMediaPlaybackHost) {
        synchronized(hostLock) {
            if (playbackHost === host) playbackHost = null
        }
    }

    override suspend fun prepareForCoreLifecycleChange(change: AndroidCoreLifecycleChange) {
        transferCoordinator.cancelAllScheduledWork()
        val host = synchronized(hostLock) { playbackHost }
        val generation = attachedGeneration ?: coreRuntime.activeSessionGeneration()

        if (host != null && generation != null) {
            val checkpoint = try {
                host.checkpoint()
            } catch (failure: Throwable) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "media",
                    "Playback checkpoint snapshot failed before Core lifecycle change: ${failure.javaClass.simpleName}",
                )
                null
            }

            if (checkpoint != null && coreRuntime.activeSessionGeneration() == generation) {
                try {
                    coreRuntime.localForGeneration(generation) { core ->
                        core.checkpointPlayback(
                            enclosureId = checkpoint.enclosureId,
                            positionMs = checkpoint.positionMs.coerceAtLeast(0L).toULong(),
                            durationMs = checkpoint.durationMs
                                ?.takeIf { it > 0L }
                                ?.toULong(),
                        )
                    }
                } catch (failure: Throwable) {
                    if (coreRuntime.activeSessionGeneration() == generation) {
                        diagnostics.record(
                            AndroidAppLogLevel.Warning,
                            "media",
                            "Playback checkpoint failed before Core lifecycle change: ${failure.javaClass.simpleName}",
                        )
                    }
                }
            }
        }

        if (host != null) {
            try {
                host.quiesce(
                    clearPlayback = change != AndroidCoreLifecycleChange.LocalStateRebuild,
                )
            } catch (failure: Throwable) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "media",
                    "Playback quiescence failed before Core lifecycle change: ${failure.javaClass.simpleName}",
                )
            }
        }

        if (change != AndroidCoreLifecycleChange.LocalStateRebuild) {
            playbackCoordinator.clearForCoreLifecycle()
        }
        attachedGeneration = null
    }

    override suspend fun resumeAfterCoreLifecycleChange(change: AndroidCoreLifecycleChange) {
        attachedGeneration = coreRuntime.activeSessionGeneration()
        attachedGeneration?.let { generation ->
            transferCoordinator.reconcile(generation)
        }
    }
}
