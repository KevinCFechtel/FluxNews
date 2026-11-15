package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.os.Build
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.work.Constraints
import androidx.work.Worker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import uniffi.flux_uniffi.SyncCancellation
import uniffi.flux_uniffi.SyncOutcome
import uniffi.flux_uniffi.SyncReason

internal val LocalAndroidBackgroundSync = staticCompositionLocalOf<AndroidBackgroundSync> {
    error("AndroidBackgroundSync was not provided")
}

internal class AndroidBackgroundSync(
    private val context: Context,
    private val coreRuntime: AndroidCoreRuntime,
    private val accountBootstrap: AndroidAccountBootstrap,
    private val postSyncEffects: AndroidPostSyncEffects,
    private val diagnostics: AndroidAppDiagnostics,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    private val resumeLock = Any()
    private var resumeJob: Job? = null
    private var resumeCancellation: SyncCancellation? = null

    suspend fun enabled(): Result<Boolean> =
        runCatching { coreRuntime.local { it.coreSettings().backgroundSyncEnabled } }

    suspend fun setEnabled(enabled: Boolean): Result<Unit> = runCatching {
        coreRuntime.local { it.setBackgroundSyncEnabled(enabled) }
        reconcile(enabled)
        diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "setting enabled=$enabled")
        if (enabled) requestResumeIfNeeded()
    }

    suspend fun reconcileFromCore(): Result<Unit> = enabled().map { reconcile(it) }

    /**
     * Requests Core-owned foreground/resume freshness without introducing Android freshness state.
     *
     * The Core decides whether Background Sync is enabled, whether the last successful Sync is
     * stale and whether the request becomes a no-op, Delta or Full Sync.
     */
    fun requestResumeIfNeeded(): Boolean = synchronized(resumeLock) {
        if (resumeJob?.isActive == true) return false

        val cancellation = SyncCancellation()
        val job = scope.launch {
            diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "resume requested")
            try {
                val state = accountBootstrap.restoreStoredAccount()
                if (state !is AndroidAccountBootstrap.State.Ready) return@launch

                val generation = coreRuntime.activeSessionGeneration() ?: return@launch
                when (
                    val outcome = coreRuntime.remoteForGeneration(generation) { core ->
                        core.syncCancellable(SyncReason.RESUME, cancellation)
                    }
                ) {
                    is SyncOutcome.Completed -> {
                        val metadata = outcome.metadata
                        diagnostics.record(
                            AndroidAppLogLevel.Info,
                            "background-sync",
                            "resume completed new=" + metadata.newArticles +
                                " updated=" + metadata.updatedArticles +
                                " feed_counts=" + metadata.newArticlesByFeed.joinToString(prefix = "[", postfix = "]") { it.feedId.toString() + ":" + it.count } +
                                " candidates=" + metadata.systemNotificationCandidates.size,
                        )
                        if (!cancellation.isCancelled() && coreRuntime.activeSessionGeneration() == generation) {
                            postSyncEffects.handle(generation, metadata)
                        }
                    }
                    is SyncOutcome.Cancelled -> {
                        diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "resume cancelled")
                    }
                }
            } catch (error: Exception) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "background-sync",
                    "resume failed type=" + error.javaClass.simpleName + " message=" + error.message.orEmpty(),
                )
                // Resume is an opportunistic fallback. Normal foreground data remains available.
            } finally {
                synchronized(resumeLock) {
                    if (resumeCancellation === cancellation) {
                        resumeCancellation = null
                        resumeJob = null
                    }
                }
            }
        }
        resumeCancellation = cancellation
        resumeJob = job
        true
    }

    private fun reconcile(enabled: Boolean) {
        val manager = WorkManager.getInstance(context)
        if (!enabled) {
            manager.cancelUniqueWork(WORK_NAME)
            return
        }
        val request = PeriodicWorkRequestBuilder<AndroidBackgroundSyncWorker>(30, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        manager.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    companion object { internal const val WORK_NAME = "flux-background-sync" }
}

internal class AndroidBackgroundSyncWorker(appContext: Context, params: WorkerParameters) : Worker(appContext, params) {
    @Volatile
    private var activeCancellation: SyncCancellation? = null

    override fun doWork(): Result = runBlocking {
        val app = applicationContext as FluxApplication
        val diagnostics = app.diagnostics
        diagnostics.record(
            AndroidAppLogLevel.Info,
            "background-sync",
            "worker started attempt=" + runAttemptCount +
                " previous_stop_reason=" + stopReasonForDiagnostics(),
        )

        val state = app.accountBootstrap.restoreStoredAccount()
        if (state !is AndroidAccountBootstrap.State.Ready) {
            diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "worker finished no_account")
            return@runBlocking Result.success()
        }

        val generation = app.coreRuntime.activeSessionGeneration()
        if (generation == null) {
            diagnostics.record(AndroidAppLogLevel.Warning, "background-sync", "worker retry no_active_session")
            return@runBlocking Result.retry()
        }

        val enabled = runCatching {
            app.coreRuntime.localForGeneration(generation) { it.coreSettings().backgroundSyncEnabled }
        }.getOrElse { error ->
            diagnostics.record(
                AndroidAppLogLevel.Warning,
                "background-sync",
                "worker retry setting_read_failed type=" + error.javaClass.simpleName + " message=" + error.message.orEmpty(),
            )
            return@runBlocking Result.retry()
        }
        if (!enabled) {
            diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "worker disabled cancelling_periodic_work")
            WorkManager.getInstance(applicationContext).cancelUniqueWork(AndroidBackgroundSync.WORK_NAME)
            return@runBlocking Result.success()
        }

        val cancellation = SyncCancellation()
        activeCancellation = cancellation
        try {
            diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "core background sync starting")
            when (
                val outcome = app.coreRuntime.remoteForGeneration(generation) {
                    it.syncCancellable(SyncReason.BACKGROUND, cancellation)
                }
            ) {
                is SyncOutcome.Completed -> {
                    val metadata = outcome.metadata
                    diagnostics.record(
                        AndroidAppLogLevel.Info,
                        "background-sync",
                        "core background sync completed new=" + metadata.newArticles +
                            " updated=" + metadata.updatedArticles +
                            " feed_counts=" + metadata.newArticlesByFeed.joinToString(prefix = "[", postfix = "]") { it.feedId.toString() + ":" + it.count } +
                            " candidates=" + metadata.systemNotificationCandidates.joinToString(prefix = "[", postfix = "]") { it.candidateId.toString() + ":" + it.feedId + ":" + it.newCount },
                    )
                    if (cancellation.isCancelled() || app.coreRuntime.activeSessionGeneration() != generation) {
                        diagnostics.record(
                            AndroidAppLogLevel.Warning,
                            "background-sync",
                            "post-sync skipped cancelled=" + cancellation.isCancelled() +
                                " session_changed=" + (app.coreRuntime.activeSessionGeneration() != generation),
                        )
                        Result.success()
                    } else {
                        diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "post-sync starting")
                        app.postSyncEffects.handle(generation, metadata)
                        diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "post-sync completed worker_success")
                        Result.success()
                    }
                }
                is SyncOutcome.Cancelled -> {
                    diagnostics.record(AndroidAppLogLevel.Info, "background-sync", "core background sync cancelled")
                    Result.retry()
                }
            }
        } catch (error: Exception) {
            diagnostics.record(
                AndroidAppLogLevel.Warning,
                "background-sync",
                "worker retry type=" + error.javaClass.simpleName + " message=" + error.message.orEmpty(),
            )
            Result.retry()
        } finally {
            if (activeCancellation === cancellation) activeCancellation = null
        }
    }

    override fun onStopped() {
        activeCancellation?.cancel()
        val app = applicationContext as FluxApplication
        app.diagnostics.record(
            AndroidAppLogLevel.Warning,
            "background-sync",
            "worker stopped stop_reason=" + stopReasonForDiagnostics(),
        )
        super.onStopped()
    }

    private fun stopReasonForDiagnostics(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) stopReason.toString() else "unavailable_api_" + Build.VERSION.SDK_INT
}
