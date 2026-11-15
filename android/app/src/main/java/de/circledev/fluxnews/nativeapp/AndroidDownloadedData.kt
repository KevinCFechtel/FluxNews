package de.circledev.fluxnews.nativeapp

import androidx.compose.runtime.staticCompositionLocalOf

internal val LocalAndroidDownloadedData = staticCompositionLocalOf<AndroidDownloadedData> {
    error("AndroidDownloadedData was not provided")
}

/**
 * Core-owned downloaded-media storage bridge.
 *
 * Deletion here only requests deletion of local media files in the Core. Listening List state
 * and playback progress are intentionally not cleared.
 */
internal class AndroidDownloadedData(
    private val coreRuntime: AndroidCoreRuntime,
    private val transferCoordinator: AndroidMediaTransferCoordinator? = null,
) {
    data class Summary(
        val fileCount: ULong,
        val totalSizeBytes: ULong,
    )

    suspend fun summary(): Result<Summary> = runCatching {
        coreRuntime.local { core ->
            val value = core.downloadedMediaSummary()
            Summary(
                fileCount = value.fileCount,
                totalSizeBytes = value.totalSizeBytes,
            )
        }
    }

    suspend fun requestDeleteAll(): Result<ULong> = runCatching {
        val requested = coreRuntime.local { core -> core.requestAllDownloadDeletions() }
        transferCoordinator?.reconcileAndSignal()
        requested
    }
}
