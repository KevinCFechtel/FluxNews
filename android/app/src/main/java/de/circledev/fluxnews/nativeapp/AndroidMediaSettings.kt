package de.circledev.fluxnews.nativeapp

import androidx.compose.runtime.staticCompositionLocalOf
import uniffi.flux_uniffi.DownloadNetworkPolicy
import uniffi.flux_uniffi.DownloadRetention

internal val LocalAndroidMediaSettings = staticCompositionLocalOf<AndroidMediaSettings> {
    error("AndroidMediaSettings was not provided")
}

internal enum class AndroidDownloadRetentionChoice(val displayName: String) {
    Forever("Forever"),
    Days7("7 days"),
    Days30("30 days"),
    Days90("90 days"),
    ;

    fun coreValue(): DownloadRetention = when (this) {
        Forever -> DownloadRetention.Forever
        Days7 -> DownloadRetention.Days(7u)
        Days30 -> DownloadRetention.Days(30u)
        Days90 -> DownloadRetention.Days(90u)
    }

    companion object {
        fun fromCore(value: DownloadRetention): AndroidDownloadRetentionChoice = when (value) {
            DownloadRetention.Forever -> Forever
            is DownloadRetention.Days -> when (value.days) {
                7u -> Days7
                30u -> Days30
                90u -> Days90
                else -> Forever
            }
        }
    }
}

/** Core-owned media policy bridge. Android deliberately keeps no DataStore mirror. */
internal class AndroidMediaSettings(
    private val coreRuntime: AndroidCoreRuntime,
    private val transferCoordinator: AndroidMediaTransferCoordinator? = null,
) {
    data class State(
        val downloadNetworkPolicy: DownloadNetworkPolicy,
        val downloadRetention: AndroidDownloadRetentionChoice,
        val deleteAfterPlayback: Boolean,
        val autoDownloadListeningList: Boolean,
        val removeCompletedListeningList: Boolean,
    )

    suspend fun load(): Result<State> = runCatching {
        coreRuntime.local { core ->
            val settings = core.coreSettings()
            State(
                downloadNetworkPolicy = settings.downloadNetworkPolicy,
                downloadRetention = AndroidDownloadRetentionChoice.fromCore(settings.downloadRetention),
                deleteAfterPlayback = settings.deleteAfterPlayback,
                autoDownloadListeningList = settings.autoDownloadListeningList,
                removeCompletedListeningList = settings.removeCompletedListeningList,
            )
        }
    }

    suspend fun setDownloadNetworkPolicy(value: DownloadNetworkPolicy): Result<Unit> = mutate {
        it.setDownloadNetworkPolicy(value)
    }

    suspend fun setDownloadRetention(value: AndroidDownloadRetentionChoice): Result<Unit> =
        runCatching {
            coreRuntime.local { core ->
                core.setDownloadRetention(value.coreValue())
                core.evaluateMediaCleanup()
            }
            transferCoordinator?.reconcileAndSignal()
        }

    suspend fun setDeleteAfterPlayback(value: Boolean): Result<Unit> = mutate {
        it.setDeleteAfterPlayback(value)
    }

    suspend fun setAutoDownloadListeningList(value: Boolean): Result<Unit> = mutate {
        it.setAutoDownloadListeningList(value)
    }

    suspend fun setRemoveCompletedListeningList(value: Boolean): Result<Unit> = mutate {
        it.setRemoveCompletedListeningList(value)
    }

    private suspend fun mutate(operation: (uniffi.flux_uniffi.Flux) -> Unit): Result<Unit> =
        runCatching {
            coreRuntime.local { core -> operation(core) }
            transferCoordinator?.reconcileAndSignal()
        }
}
