package de.circledev.fluxnews.nativeapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import uniffi.flux_uniffi.DownloadFailureKind
import uniffi.flux_uniffi.DownloadNetworkPolicy
import uniffi.flux_uniffi.MediaKind
import uniffi.flux_uniffi.MediaTransferWork
import uniffi.flux_uniffi.SyncCompleted

internal object AndroidMediaTransferFileLayout {
    fun reference(enclosureId: Long, url: String, mimeType: String): String {
        require(enclosureId > 0L)
        return "downloads/" + enclosureId + "." + extension(url, mimeType)
    }

    fun destination(mediaRoot: File, reference: String): File {
        val relative = File(reference)
        require(!relative.isAbsolute) { "Media reference must be relative." }
        val root = mediaRoot.canonicalFile
        val target = File(root, reference).canonicalFile
        require(target.toPath().startsWith(root.toPath())) { "Media reference escapes media root." }
        return target
    }

    private fun extension(url: String, mimeType: String): String {
        val pathExtension = runCatching {
            URI(url).path
                ?.substringAfterLast('/', "")
                ?.substringAfterLast('.', "")
                ?.lowercase()
                ?.takeIf { it.matches(Regex("[a-z0-9]{1,5}")) }
        }.getOrNull()
        if (pathExtension in setOf("mp3", "m4a", "aac", "ogg", "oga", "opus", "wav", "flac", "mp4", "m4v", "webm")) {
            return pathExtension!!
        }
        return when (mimeType.substringBefore(';').trim().lowercase()) {
            "audio/mpeg" -> "mp3"
            "audio/mp4", "audio/x-m4a" -> "m4a"
            "audio/aac" -> "aac"
            "audio/ogg", "application/ogg" -> "ogg"
            "audio/opus" -> "opus"
            "audio/wav", "audio/x-wav" -> "wav"
            "audio/flac" -> "flac"
            "video/mp4" -> "mp4"
            "video/webm", "audio/webm" -> "webm"
            else -> "bin"
        }
    }
}

/** Tags distinguish previously enqueued constraints without cancelling running work. */
internal object AndroidMediaTransferPolicyTags {
    private const val PREFIX = "flux-media-network:"

    fun tag(networkType: NetworkType): String = PREFIX + networkType.name

    // Legacy requests have no policy tag; update them once to reconcile their constraints.
    fun needsUpdate(tags: Set<String>, desired: NetworkType): Boolean =
        tag(desired) !in tags
}

internal data class AndroidMediaTransferProgress(
    val enclosureId: Long,
    val bytesDownloaded: Long,
    val totalBytes: Long?,
) {
    val fraction: Float?
        get() = totalBytes
            ?.takeIf { it > 0L }
            ?.let { (bytesDownloaded.toFloat() / it.toFloat()).coerceIn(0f, 1f) }
}

internal class AndroidMediaTransferCoordinator(
    context: Context,
    private val coreRuntime: AndroidCoreRuntime,
    private val playbackCoordinator: AndroidMediaPlaybackCoordinator,
    private val diagnostics: AndroidAppDiagnostics,
) : AndroidPostSyncEffect {
    private val applicationContext = context.applicationContext
    private val workManager = WorkManager.getInstance(applicationContext)
    private val mutableProgress =
        MutableStateFlow<Map<Long, AndroidMediaTransferProgress>>(emptyMap())
    val progress = mutableProgress.asStateFlow()
    private val mutableRevision = MutableStateFlow(0L)
    val revision = mutableRevision.asStateFlow()
    private val probeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override suspend fun apply(sessionGeneration: Long, metadata: SyncCompleted) {
        playbackCoordinator.reconcileAfterSuccessfulSync(sessionGeneration)
        reconcileAndSignal(sessionGeneration)
    }

    fun requestArtworkProbe(sessionGeneration: Long, articleId: Long) {
        if (articleId <= 0L || coreRuntime.activeSessionGeneration() != sessionGeneration) return
        probeScope.launch {
            val changed = runCatching {
                coreRuntime.remoteForGeneration(sessionGeneration) { core ->
                    var anyChanged = false
                    core.articleEnclosures(articleId = articleId)
                        .asSequence()
                        .filter { it.mediaKind == MediaKind.AUDIO }
                        .forEach { enclosure ->
                            if (
                                runCatching {
                                    core.probeMediaArtwork(enclosureId = enclosure.id)
                                }.getOrDefault(false)
                            ) {
                                anyChanged = true
                            }
                        }
                    anyChanged
                }
            }.getOrDefault(false)

            if (changed && coreRuntime.activeSessionGeneration() == sessionGeneration) {
                signalCoreMediaChanged(sessionGeneration)
            }
        }
    }

    suspend fun reconcile(sessionGeneration: Long? = coreRuntime.activeSessionGeneration()) {
        val generation = sessionGeneration ?: return
        if (coreRuntime.activeSessionGeneration() != generation) return

        val snapshot = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                Triple(
                    core.coreSettings(),
                    core.downloadsRequiringTransfer(),
                    core.downloadsRequiringDeletion(),
                )
            }
        }.getOrElse { failure ->
            diagnostics.record(
                AndroidAppLogLevel.Warning,
                "media-transfer",
                "Transfer reconciliation could not read Core work: " + failure.javaClass.simpleName,
            )
            return
        }

        val requestedTransfers = snapshot.second.associateBy { it.enclosureId }
        val requestedDeletions = snapshot.third.associateBy { it.enclosureId }
        cancelStaleWork(requestedTransfers.keys, requestedDeletions.keys)

        val networkType = when (snapshot.first.downloadNetworkPolicy) {
            DownloadNetworkPolicy.ANY_NETWORK -> NetworkType.CONNECTED
            DownloadNetworkPolicy.UNMETERED_ONLY -> NetworkType.UNMETERED
        }
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(networkType)
            .build()

        // WorkManager KEEP does not change constraints on previously scheduled work.
        // Keep an identity-stable WorkRequest and update only when the policy changes;
        // updateWork preserves the enqueue time and does not cancel a running worker.
        val activeTransfers = withContext(Dispatchers.IO) {
            runCatching { workManager.getWorkInfosByTag(TRANSFER_TAG).get() }
                .getOrDefault(emptyList())
                .filterNot { it.state.isFinished }
                .mapNotNull { info ->
                    AndroidMediaTransferWorkerInput.enclosureId(info)?.let { it to info }
                }
                .toMap()
        }
        requestedTransfers.values.forEach { work ->
            val existing = activeTransfers[work.enclosureId]
            val builder = OneTimeWorkRequestBuilder<AndroidMediaDownloadWorker>()
                .setInputData(AndroidMediaTransferWorkerInput.data(work.enclosureId))
                .setConstraints(constraints)
                .addTag(TRANSFER_TAG)
                .addTag(AndroidMediaTransferWorkerInput.enclosureTag(work.enclosureId))
                .addTag(AndroidMediaTransferPolicyTags.tag(networkType))
            if (existing == null) {
                workManager.enqueueUniqueWork(
                    transferWorkName(work.enclosureId),
                    ExistingWorkPolicy.KEEP,
                    builder.build(),
                )
            } else if (AndroidMediaTransferPolicyTags.needsUpdate(existing.tags, networkType)) {
                val updated = builder.setId(existing.id).build()
                withContext(Dispatchers.IO) {
                    runCatching { workManager.updateWork(updated).get() }
                        .onFailure { failure ->
                            diagnostics.record(
                                AndroidAppLogLevel.Warning,
                                "media-transfer",
                                "Could not update download network constraint: " +
                                    failure.javaClass.simpleName,
                            )
                        }
                }
            }
        }

        requestedDeletions.values.forEach { work ->
            if (playbackCoordinator.blocksMediaDeletion(work.enclosureId)) return@forEach
            val request = OneTimeWorkRequestBuilder<AndroidMediaDeletionWorker>()
                .setInputData(AndroidMediaTransferWorkerInput.data(work.enclosureId))
                .addTag(DELETION_TAG)
                .addTag(AndroidMediaTransferWorkerInput.enclosureTag(work.enclosureId))
                .build()
            workManager.enqueueUniqueWork(
                deletionWorkName(work.enclosureId),
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }

    fun cancelAllScheduledWork() {
        workManager.cancelAllWorkByTag(TRANSFER_TAG)
        workManager.cancelAllWorkByTag(DELETION_TAG)
        mutableProgress.value = emptyMap()
    }

    internal fun updateProgress(enclosureId: Long, bytesDownloaded: Long, totalBytes: Long?) {
        val progress = AndroidMediaTransferProgress(
            enclosureId = enclosureId,
            bytesDownloaded = bytesDownloaded.coerceAtLeast(0L),
            totalBytes = totalBytes?.takeIf { it > 0L },
        )
        mutableProgress.value = mutableProgress.value + (enclosureId to progress)
    }

    internal fun clearProgress(enclosureId: Long) {
        if (enclosureId !in mutableProgress.value) return
        mutableProgress.value = mutableProgress.value - enclosureId
    }

    suspend fun reconcileAndSignal(
        sessionGeneration: Long? = coreRuntime.activeSessionGeneration(),
    ) {
        reconcile(sessionGeneration)
        signalCoreMediaChanged(sessionGeneration)
    }

    internal suspend fun signalCoreMediaChanged(
        sessionGeneration: Long? = coreRuntime.activeSessionGeneration(),
    ) {
        playbackCoordinator.refreshCorePresentation(sessionGeneration)
        mutableRevision.value = mutableRevision.value + 1L
    }

    private suspend fun cancelStaleWork(
        requestedTransferIds: Set<Long>,
        requestedDeletionIds: Set<Long>,
    ) = withContext(Dispatchers.IO) {
        val transfers = runCatching {
            workManager.getWorkInfosByTag(TRANSFER_TAG).get()
        }.getOrDefault(emptyList())
        transfers
            .filter { !it.state.isFinished }
            .mapNotNull(AndroidMediaTransferWorkerInput::enclosureId)
            .filter { it !in requestedTransferIds }
            .forEach {
                workManager.cancelUniqueWork(transferWorkName(it))
                clearProgress(it)
            }

        val deletions = runCatching {
            workManager.getWorkInfosByTag(DELETION_TAG).get()
        }.getOrDefault(emptyList())
        deletions
            .filter { !it.state.isFinished }
            .mapNotNull(AndroidMediaTransferWorkerInput::enclosureId)
            .filter { it !in requestedDeletionIds }
            .forEach { workManager.cancelUniqueWork(deletionWorkName(it)) }
    }

    companion object {
        internal const val TRANSFER_TAG = "flux-media-transfer"
        internal const val DELETION_TAG = "flux-media-deletion"
        internal fun transferWorkName(id: Long) = "flux-media-transfer-" + id
        internal fun deletionWorkName(id: Long) = "flux-media-deletion-" + id
    }
}

private object AndroidMediaTransferWorkerInput {
    private const val ENCLOSURE_ID = "enclosure_id"
    fun data(enclosureId: Long) = Data.Builder().putLong(ENCLOSURE_ID, enclosureId).build()
    fun enclosureTag(enclosureId: Long) = "flux-media-enclosure-" + enclosureId
    fun enclosureId(info: WorkInfo): Long? =
        info.tags.firstNotNullOfOrNull { tag ->
            tag.removePrefix("flux-media-enclosure-")
                .takeIf { it != tag }
                ?.toLongOrNull()
        }
    fun enclosureId(parameters: WorkerParameters): Long =
        parameters.inputData.getLong(ENCLOSURE_ID, -1L)
}

internal class AndroidMediaDownloadWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    private val application = appContext.applicationContext as FluxApplication
    private val enclosureId = AndroidMediaTransferWorkerInput.enclosureId(parameters)
    private val httpClient = OkHttpClient.Builder()
        .fastFallback(true)
        .retryOnConnectionFailure(true)
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result {
        if (enclosureId <= 0L) return Result.failure()
        val ready = application.accountBootstrap.restoreStoredAccount()
        if (ready !is AndroidAccountBootstrap.State.Ready) return Result.retry()
        val generation = application.coreRuntime.activeSessionGeneration() ?: return Result.retry()

        val work = currentWork(generation) ?: return Result.success()
        if (!networkPolicyAllows(generation)) return Result.retry()

        setForeground(foregroundInfo(work))
        application.mediaTransferCoordinator.updateProgress(enclosureId, 0L, null)
        val reference = AndroidMediaTransferFileLayout.reference(
            work.enclosureId,
            work.url,
            work.mimeType,
        )
        val destination = runCatching {
            AndroidMediaTransferFileLayout.destination(application.storagePaths.media, reference)
        }.getOrElse {
            reportFailure(generation, DownloadFailureKind.STORAGE)
            application.mediaTransferCoordinator.clearProgress(enclosureId)
            return Result.success()
        }

        if (destination.isFile && destination.length() > 0L) {
            reportFinished(generation, reference, destination.length())
            application.mediaTransferCoordinator.clearProgress(enclosureId)
            return Result.success()
        }

        destination.parentFile?.let { parent ->
            if (!parent.mkdirs() && !parent.isDirectory) {
                reportFailure(generation, DownloadFailureKind.STORAGE)
                application.mediaTransferCoordinator.clearProgress(enclosureId)
                return Result.success()
            }
        }
        val temporary = File(destination.parentFile, "." + destination.name + ".part")
        temporary.delete()

        try {
            val uri = URI(work.url)
            if (uri.scheme?.lowercase() !in setOf("http", "https")) {
                reportFailure(generation, DownloadFailureKind.INVALID_MEDIA)
                application.mediaTransferCoordinator.clearProgress(enclosureId)
                return Result.success()
            }
            val call = httpClient.newCall(Request.Builder().url(work.url).build())
            val response = runInterruptible(Dispatchers.IO) { call.execute() }
            response.use { result ->
                    if (!result.isSuccessful) {
                        reportFailure(generation, DownloadFailureKind.NETWORK)
                        application.mediaTransferCoordinator.clearProgress(enclosureId)
                        return Result.success()
                    }
                    val body = result.body
                    val totalBytes = body.contentLength().takeIf { it > 0L }
                    application.mediaTransferCoordinator.updateProgress(
                        enclosureId,
                        0L,
                        totalBytes,
                    )
                    runInterruptible(Dispatchers.IO) {
                        body.byteStream().use { input ->
                            FileOutputStream(temporary).use { output ->
                                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                                var downloaded = 0L
                                var lastReported = 0L
                                while (true) {
                                    val read = input.read(buffer)
                                    if (read < 0) break
                                    output.write(buffer, 0, read)
                                    downloaded += read
                                    if (
                                        downloaded - lastReported >= 256L * 1024L ||
                                        totalBytes != null && downloaded >= totalBytes
                                    ) {
                                        application.mediaTransferCoordinator.updateProgress(
                                            enclosureId,
                                            downloaded,
                                            totalBytes,
                                        )
                                        lastReported = downloaded
                                    }
                                }
                                output.fd.sync()
                            }
                        }
                        require(temporary.length() > 0L)
                        try {
                            Files.move(
                                temporary.toPath(),
                                destination.toPath(),
                                StandardCopyOption.ATOMIC_MOVE,
                                StandardCopyOption.REPLACE_EXISTING,
                            )
                        } catch (_: Exception) {
                            Files.move(
                                temporary.toPath(),
                                destination.toPath(),
                                StandardCopyOption.REPLACE_EXISTING,
                            )
                        }
                    }
                }
            if (currentWork(generation) == null) {
                destination.delete()
                application.mediaTransferCoordinator.clearProgress(enclosureId)
                return Result.success()
            }
            reportFinished(generation, reference, destination.length())
            application.mediaTransferCoordinator.clearProgress(enclosureId)
            return Result.success()
        } catch (cancelled: CancellationException) {
            temporary.delete()
            application.mediaTransferCoordinator.clearProgress(enclosureId)
            throw cancelled
        } catch (failure: Throwable) {
            temporary.delete()
            if (isStopped) {
                application.mediaTransferCoordinator.clearProgress(enclosureId)
                return Result.success()
            }
            val kind = when (failure) {
                is java.io.IOException -> DownloadFailureKind.NETWORK
                is SecurityException -> DownloadFailureKind.STORAGE
                else -> DownloadFailureKind.UNKNOWN
            }
            reportFailure(generation, kind)
            application.mediaTransferCoordinator.clearProgress(enclosureId)
            return Result.success()
        }
    }

    private suspend fun currentWork(generation: Long): MediaTransferWork? =
        runCatching {
            application.coreRuntime.localForGeneration(generation) { core ->
                core.downloadsRequiringTransfer().firstOrNull { it.enclosureId == enclosureId }
            }
        }.getOrNull()

    private suspend fun networkPolicyAllows(generation: Long): Boolean {
        val policy = runCatching {
            application.coreRuntime.localForGeneration(generation) {
                it.coreSettings().downloadNetworkPolicy
            }
        }.getOrNull() ?: return false
        if (policy == DownloadNetworkPolicy.ANY_NETWORK) return true
        val connectivity = applicationContext.getSystemService(ConnectivityManager::class.java)
        return connectivity != null && !connectivity.isActiveNetworkMetered
    }

    private suspend fun reportFinished(generation: Long, reference: String, size: Long) {
        val result = runCatching {
            application.coreRuntime.localForGeneration(generation) { core ->
                core.downloadFinished(
                    enclosureId = enclosureId,
                    localFile = reference,
                    fileSizeBytes = size.coerceAtLeast(0L).toULong(),
                )
            }
        }
        if (result.isSuccess) {
            application.mediaTransferCoordinator.signalCoreMediaChanged(generation)
        }
    }

    private suspend fun reportFailure(generation: Long, kind: DownloadFailureKind) {
        if (currentWork(generation) == null) return
        val result = runCatching {
            application.coreRuntime.localForGeneration(generation) { core ->
                core.downloadFailed(enclosureId = enclosureId, failureKind = kind)
            }
        }
        if (result.isSuccess) application.mediaTransferCoordinator.signalCoreMediaChanged()
    }

    private fun foregroundInfo(work: MediaTransferWork): ForegroundInfo {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                applicationContext.getString(R.string.media_download_channel),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_sync)
            .setContentTitle(applicationContext.getString(R.string.media_downloading_audio))
            .setContentText(applicationContext.getString(R.string.media_downloading_explanation))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .build()
        return ForegroundInfo(
            NOTIFICATION_ID_BASE + (work.enclosureId % 10_000L).toInt(),
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    companion object {
        private const val CHANNEL_ID = "flux-media-downloads"
        private const val NOTIFICATION_ID_BASE = 31_000
    }
}

internal class AndroidMediaDeletionWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    private val application = appContext.applicationContext as FluxApplication
    private val enclosureId = AndroidMediaTransferWorkerInput.enclosureId(parameters)

    override suspend fun doWork(): Result {
        if (enclosureId <= 0L) return Result.failure()
        val ready = application.accountBootstrap.restoreStoredAccount()
        if (ready !is AndroidAccountBootstrap.State.Ready) return Result.retry()
        val generation = application.coreRuntime.activeSessionGeneration() ?: return Result.retry()
        if (application.mediaPlaybackCoordinator.blocksMediaDeletion(enclosureId)) return Result.retry()

        val work = runCatching {
            application.coreRuntime.localForGeneration(generation) { core ->
                core.downloadsRequiringDeletion().firstOrNull { it.enclosureId == enclosureId }
            }
        }.getOrNull() ?: return Result.success()

        val reference = work.localFile
        if (!reference.isNullOrBlank()) {
            val target = runCatching {
                AndroidMediaTransferFileLayout.destination(application.storagePaths.media, reference)
            }.getOrElse { return Result.failure() }
            if (target.exists() && !target.delete()) return Result.retry()
        }

        return runCatching {
            application.coreRuntime.localForGeneration(generation) { core ->
                core.downloadDeleted(enclosureId = enclosureId)
            }
            application.mediaTransferCoordinator.signalCoreMediaChanged(generation)
            Result.success()
        }.getOrElse { Result.retry() }
    }
}
