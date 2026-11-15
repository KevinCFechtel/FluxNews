package de.circledev.fluxnews.nativeapp

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.flux_uniffi.SyncCompleted
import uniffi.flux_uniffi.SystemNotificationCandidate

internal val LocalAndroidSystemNotifications = staticCompositionLocalOf<AndroidSystemNotificationManager> {
    error("AndroidSystemNotificationManager was not provided")
}

internal class AndroidSystemNotificationManager(
    private val context: Context,
    private val coreRuntime: AndroidCoreRuntime,
    private val diagnostics: AndroidAppDiagnostics,
) : AndroidPostSyncEffect {
    private val notificationManager = NotificationManagerCompat.from(context)
    private val platformNotificationManager = context.getSystemService(NotificationManager::class.java)
    private val mutablePendingFeedRoute = MutableStateFlow<Long?>(null)
    private val delivery = AndroidSystemNotificationDelivery(
        activeSessionGeneration = coreRuntime::activeSessionGeneration,
        handoff = ::postCandidate,
        acknowledge = { generation, candidateId ->
            val result = runCatching {
                coreRuntime.localForGeneration(generation) { core ->
                    core.acknowledgeSystemNotification(candidateId)
                }
            }
            if (result.isSuccess) {
                diagnostics.record(AndroidAppLogLevel.Info, "notification", "candidate acknowledged id=" + candidateId)
            } else {
                val error = result.exceptionOrNull()
                diagnostics.record(
                    AndroidAppLogLevel.Error,
                    "notification",
                    "candidate acknowledge failed id=" + candidateId +
                        " type=" + error?.javaClass?.simpleName.orEmpty() +
                        " message=" + error?.message.orEmpty(),
                )
            }
            result.isSuccess
        },
    )

    val pendingFeedRoute: StateFlow<Long?> = mutablePendingFeedRoute.asStateFlow()

    fun configure() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            platformNotificationManager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.system_notification_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = context.getString(R.string.system_notification_channel_description)
                },
            )
        }
    }

    fun hasRuntimePermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    fun notificationsEnabledBySystem(): Boolean {
        if (!hasRuntimePermission() || !notificationManager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = platformNotificationManager.getNotificationChannel(CHANNEL_ID)
            if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    fun systemSettingsIntent(): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    suspend fun setFeedEnabled(feedId: Long, enabled: Boolean): Result<Unit> = runCatching {
        if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasRuntimePermission()) {
            throw AndroidSystemNotificationPermissionRequired()
        }
        coreRuntime.local { core ->
            core.setFeedSystemNotificationsEnabled(feedId, enabled)
        }
    }

    fun routeIntent(intent: Intent?): Boolean {
        if (intent?.action != ACTION_OPEN_FEED) return false
        val feedId = intent.getLongExtra(EXTRA_FEED_ID, INVALID_FEED_ID)
        if (feedId == INVALID_FEED_ID) return false
        mutablePendingFeedRoute.value = feedId
        return true
    }

    fun consumeFeedRoute(feedId: Long) {
        mutablePendingFeedRoute.compareAndSet(feedId, null)
    }

    override suspend fun apply(sessionGeneration: Long, metadata: SyncCompleted) {
        diagnostics.record(
            AndroidAppLogLevel.Info,
            "notification",
            "post-sync pass reason=" + metadata.reason +
                " new=" + metadata.newArticles +
                " feed_counts=" + metadata.newArticlesByFeed.joinToString(prefix = "[", postfix = "]") { it.feedId.toString() + ":" + it.count } +
                " candidates=" + metadata.systemNotificationCandidates.joinToString(prefix = "[", postfix = "]") { it.candidateId.toString() + ":" + it.feedId + ":" + it.newCount },
        )
        if (metadata.systemNotificationCandidates.isEmpty()) return
        delivery.deliver(sessionGeneration, metadata.systemNotificationCandidates)
    }

    @SuppressLint("MissingPermission")
    private fun postCandidate(candidate: SystemNotificationCandidate): Boolean {
        configure()
        if (!hasRuntimePermission()) {
            diagnostics.record(
                AndroidAppLogLevel.Warning,
                "notification",
                "candidate blocked id=" + candidate.candidateId + " feed=" + candidate.feedId + " reason=runtime_permission",
            )
            return false
        }
        if (!notificationManager.areNotificationsEnabled()) {
            diagnostics.record(
                AndroidAppLogLevel.Warning,
                "notification",
                "candidate blocked id=" + candidate.candidateId + " feed=" + candidate.feedId + " reason=app_notifications_disabled",
            )
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = platformNotificationManager.getNotificationChannel(CHANNEL_ID)
            if (channel?.importance == NotificationManager.IMPORTANCE_NONE) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "notification",
                    "candidate blocked id=" + candidate.candidateId + " feed=" + candidate.feedId + " reason=channel_disabled",
                )
                return false
            }
        }

        val count = candidate.newCount.coerceAtMost(Int.MAX_VALUE.toUInt()).toInt()
        val countText = context.resources.getQuantityString(
            R.plurals.system_notification_new_articles,
            count.coerceAtLeast(1),
            count,
        )
        val submittedAt = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date())
        val body = context.getString(R.string.system_notification_body, countText, submittedAt)
        val contentIntent = PendingIntent.getActivity(
            context,
            candidate.candidateId.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                action = ACTION_OPEN_FEED
                putExtra(EXTRA_FEED_ID, candidate.feedId)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(candidate.feedTitle)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()

        val notificationId = candidate.candidateId.hashCode()
        return try {
            notificationManager.notify(notificationId, notification)
            diagnostics.record(
                AndroidAppLogLevel.Info,
                "notification",
                "candidate posted id=" + candidate.candidateId +
                    " notification_id=" + notificationId +
                    " feed=" + candidate.feedId +
                    " count=" + candidate.newCount,
            )
            true
        } catch (error: Exception) {
            diagnostics.record(
                AndroidAppLogLevel.Error,
                "notification",
                "candidate post failed id=" + candidate.candidateId +
                    " feed=" + candidate.feedId +
                    " type=" + error.javaClass.simpleName +
                    " message=" + error.message.orEmpty(),
            )
            false
        }
    }

    private companion object {
        const val CHANNEL_ID = "new-articles"
        const val ACTION_OPEN_FEED = "de.circledev.fluxnews.nativeapp.action.OPEN_NOTIFICATION_FEED"
        const val EXTRA_FEED_ID = "flux.systemNotification.feedId"
        const val INVALID_FEED_ID = Long.MIN_VALUE
    }
}

internal class AndroidSystemNotificationDelivery(
    private val activeSessionGeneration: () -> Long?,
    private val handoff: (SystemNotificationCandidate) -> Boolean,
    private val acknowledge: suspend (Long, Long) -> Boolean,
) {
    suspend fun deliver(
        sessionGeneration: Long,
        candidates: List<SystemNotificationCandidate>,
    ) {
        for (candidate in candidates) {
            if (activeSessionGeneration() != sessionGeneration) return
            if (!handoff(candidate)) continue
            if (activeSessionGeneration() != sessionGeneration) return
            acknowledge(sessionGeneration, candidate.candidateId)
        }
    }
}

private class AndroidSystemNotificationPermissionRequired :
    IllegalStateException("Notification permission is required before enabling a feed.")
