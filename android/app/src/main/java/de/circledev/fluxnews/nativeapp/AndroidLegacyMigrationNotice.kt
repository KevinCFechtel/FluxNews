package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine

/**
 * Read-only, privacy-safe presentation of durable E9 stage markers. The UI never
 * reads Flutter secrets, filenames, server URLs, article titles, or API keys.
 * "Checked" is intentional: an import step can finish with no legacy data or
 * when existing native/Core values correctly take precedence.
 */
internal data class AndroidLegacyMigrationNotice(
    val importedServer: String = "",
    val acknowledged: Boolean = false,
    val settingsComplete: Boolean = false,
    val localComplete: Boolean = false,
    val feedsComplete: Boolean = false,
    val startupComplete: Boolean = false,
    val playbackComplete: Boolean = false,
    val downloadsComplete: Boolean = false,
    val widgetsComplete: Boolean = false,
    val playbackStatus: String = "",
    val downloadsStatus: String = "",
    val feedsStatus: String = "",
    val startupStatus: String = "",
    val completionKind: String = "",
    val skippedPlaybackDetails: String = "",
    val skippedDownloadDetails: String = "",
) {
    val steps: List<AndroidLegacyMigrationNoticeStep>
        get() = listOf(
            AndroidLegacyMigrationNoticeStep("Account", true, "Credentials transferred securely"),
            AndroidLegacyMigrationNoticeStep(
                "Settings",
                settingsComplete && localComplete,
                "App- und Medien-Settings geprüft",
            ),
            AndroidLegacyMigrationNoticeStep(
                "Feeds & startup view",
                feedsComplete && startupComplete,
                listOf(feedsStatus, startupStatus).filter(String::isNotBlank).joinToString("; ")
                    .ifBlank { "Feed preferences and startup view checked" },
            ),
            AndroidLegacyMigrationNoticeStep("Playback progress", playbackComplete, skippedPlaybackDetails.takeIf { it.isNotBlank() }?.let { "Completed with skipped items: $it" } ?: playbackStatus.ifBlank { "Audio positions checked" }),
            AndroidLegacyMigrationNoticeStep("Downloads", downloadsComplete, skippedDownloadDetails.takeIf { it.isNotBlank() }?.let { "Completed with skipped items: $it" } ?: downloadsStatus.ifBlank { "Offline audio checked" }),
            AndroidLegacyMigrationNoticeStep("Widgets", widgetsComplete, "Widget preferences checked"),
        )

    val completedSteps: Int get() = steps.count { it.complete }
    val complete: Boolean get() = steps.all { it.complete }
    val completedWithSkippedItems: Boolean get() = completionKind == "completed_with_skipped_items"
    val canFinishPartial: Boolean get() =
        settingsComplete && localComplete && feedsComplete && startupComplete && widgetsComplete &&
            (!playbackComplete || !downloadsComplete) &&
            (playbackComplete || playbackStatus.isNotBlank()) &&
            (downloadsComplete || downloadsStatus.isNotBlank())

    fun appliesTo(serverUrl: String?): Boolean =
        importedServer.isNotBlank() && serverUrl != null && importedServer == serverUrl && !acknowledged
}

internal data class AndroidLegacyMigrationNoticeStep(
    val title: String,
    val complete: Boolean,
    val description: String,
)

internal class AndroidLegacyMigrationNoticeStore(private val preferences: AndroidPreferenceStore) {
    private val account = preferences.observe(AndroidLegacyMigrationCoordinator.IMPORTED_ACCOUNT_SERVER, "")
    private val acknowledged = preferences.observe(ACKNOWLEDGED, false)
    private val completionFlags: Flow<Array<Boolean>> = combine(
        listOf(
            preferences.observe(AndroidLegacySettingsMigration.SETTINGS_DONE, false),
            preferences.observe(AndroidLegacySettingsMigration.LOCAL_DONE, false),
            preferences.observe(AndroidLegacySettingsMigration.FEEDS_DONE, false),
            preferences.observe(AndroidLegacySettingsMigration.STARTUP_DONE, false),
            preferences.observe(AndroidLegacyPlaybackMigration.PLAYBACK_DONE, false),
            preferences.observe(AndroidLegacyDownloadMigration.DOWNLOADS_DONE, false),
            preferences.observe(AndroidLegacySettingsMigration.WIDGET_DONE, false),
        ),
    ) { values -> values }

    private val finalization = combine(
        listOf(
            preferences.observe(COMPLETION_KIND, ""),
            preferences.observe(SKIPPED_PLAYBACK_DETAILS, ""),
            preferences.observe(SKIPPED_DOWNLOAD_DETAILS, ""),
        ),
    ) { values -> values }

    private val reasons: Flow<Array<String>> = combine(
        listOf(
            preferences.observe(AndroidLegacyPlaybackMigration.PLAYBACK_STATUS, ""),
            preferences.observe(AndroidLegacyDownloadMigration.DOWNLOADS_STATUS, ""),
            preferences.observe(AndroidLegacySettingsMigration.FEEDS_STATUS, ""),
            preferences.observe(AndroidLegacySettingsMigration.STARTUP_STATUS, ""),
        ),
    ) { values -> values }

    val state: Flow<AndroidLegacyMigrationNotice> = combine(
        account,
        acknowledged,
        completionFlags,
        reasons,
        finalization,
    ) { server, dismissed, flags, details, finish ->
        AndroidLegacyMigrationNotice(
            importedServer = server,
            acknowledged = dismissed,
            settingsComplete = flags[0],
            localComplete = flags[1],
            feedsComplete = flags[2],
            startupComplete = flags[3],
            playbackComplete = flags[4],
            downloadsComplete = flags[5],
            widgetsComplete = flags[6],
            playbackStatus = details[0],
            downloadsStatus = details[1],
            feedsStatus = details[2],
            startupStatus = details[3],
            completionKind = finish[0],
            skippedPlaybackDetails = finish[1],
            skippedDownloadDetails = finish[2],
        )
    }

    suspend fun acknowledge() {
        preferences.acknowledgeVerifiedLegacyMigration(
            requiredKeys = listOf(
                AndroidLegacySettingsMigration.SETTINGS_DONE,
                AndroidLegacySettingsMigration.LOCAL_DONE,
                AndroidLegacySettingsMigration.FEEDS_DONE,
                AndroidLegacySettingsMigration.STARTUP_DONE,
                AndroidLegacySettingsMigration.WIDGET_DONE,
                AndroidLegacyPlaybackMigration.PLAYBACK_DONE,
                AndroidLegacyDownloadMigration.DOWNLOADS_DONE,
            ),
            completionKind = COMPLETION_KIND,
            acknowledged = ACKNOWLEDGED,
        )
    }

    /** Finish only after successful import attempts, preserving exact retry reasons. */
    suspend fun finishWithUnresolvedMedia() {
        preferences.finishLegacyMigrationWithSkippedMedia(
            requiredKeys = listOf(
                AndroidLegacySettingsMigration.SETTINGS_DONE,
                AndroidLegacySettingsMigration.LOCAL_DONE,
                AndroidLegacySettingsMigration.FEEDS_DONE,
                AndroidLegacySettingsMigration.STARTUP_DONE,
                AndroidLegacySettingsMigration.WIDGET_DONE,
            ),
            playbackDone = AndroidLegacyPlaybackMigration.PLAYBACK_DONE,
            downloadsDone = AndroidLegacyDownloadMigration.DOWNLOADS_DONE,
            playbackReason = AndroidLegacyPlaybackMigration.PLAYBACK_STATUS,
            downloadsReason = AndroidLegacyDownloadMigration.DOWNLOADS_STATUS,
            skippedPlayback = SKIPPED_PLAYBACK_DETAILS,
            skippedDownloads = SKIPPED_DOWNLOAD_DETAILS,
            completionKind = COMPLETION_KIND,
            acknowledged = ACKNOWLEDGED,
        )
    }

    companion object {
        internal val ACKNOWLEDGED = AndroidPreferenceKey.boolean("migration-e9-summary-acknowledged")
        internal val COMPLETION_KIND = AndroidPreferenceKey.string("migration-e9-completion-kind-v1")
        internal val SKIPPED_PLAYBACK_DETAILS = AndroidPreferenceKey.string("migration-e9-skipped-playback-details-v1")
        internal val SKIPPED_DOWNLOAD_DETAILS = AndroidPreferenceKey.string("migration-e9-skipped-download-details-v1")
    }
}

@Composable
internal fun AndroidLegacyMigrationNoticeDialog(
    state: AndroidLegacyMigrationNotice,
    syncing: Boolean,
    onSync: () -> Unit,
    onClose: () -> Unit,
    onFinishPartial: () -> Unit,
) {
    // The persisted migration model keeps its legacy step identifiers; translate presentation here.
    val account = stringResource(R.string.audit_migration_account)
    val accountDone = stringResource(R.string.audit_migration_account_done)
    val settingsTitle = stringResource(R.string.audit_mig_settings)
    val settingsDone = stringResource(R.string.audit_mig_settings_done)
    val feedsTitle = stringResource(R.string.audit_mig_feeds)
    val feedsDone = stringResource(R.string.audit_migration_feeds_done)
    val playbackTitle = stringResource(R.string.audit_migration_playback)
    val audioDone = stringResource(R.string.audit_migration_audio_done)
    val downloadsTitle = stringResource(R.string.audit_migration_downloads)
    val offlineDone = stringResource(R.string.audit_migration_offline_done)
    val widgetsTitle = stringResource(R.string.audit_migration_widgets)
    val widgetsDone = stringResource(R.string.audit_migration_widget_done)
    val localizedMessageContext = LocalContext.current
    val skippedPlaybackDescription = stringResource(
        R.string.audit_migration_skipped,
        localizedMessageContext.localizedLegacyMigrationStatus(state.skippedPlaybackDetails),
    )
    val skippedDownloadDescription = stringResource(
        R.string.audit_migration_skipped,
        localizedMessageContext.localizedLegacyMigrationStatus(state.skippedDownloadDetails),
    )
    val steps = state.steps.mapIndexed { index, step ->
        when (index) {
            0 -> step.copy(title = account, description = accountDone)
            1 -> step.copy(title = settingsTitle, description = settingsDone)
            2 -> step.copy(title = feedsTitle, description = step.description.takeUnless { it == "Feed preferences and startup view checked" }?.let(localizedMessageContext::localizedLegacyMigrationStatus) ?: feedsDone)
            3 -> step.copy(title = playbackTitle, description = if (state.skippedPlaybackDetails.isNotBlank()) skippedPlaybackDescription else step.description.takeUnless { it == "Audio positions checked" }?.let(localizedMessageContext::localizedLegacyMigrationStatus) ?: audioDone)
            4 -> step.copy(title = downloadsTitle, description = if (state.skippedDownloadDetails.isNotBlank()) skippedDownloadDescription else step.description.takeUnless { it == "Offline audio checked" }?.let(localizedMessageContext::localizedLegacyMigrationStatus) ?: offlineDone)
            5 -> step.copy(title = widgetsTitle, description = widgetsDone)
            else -> step
        }
    }
    var confirmSkip by remember { mutableStateOf(false) }
    if (confirmSkip) {
        AlertDialog(
            onDismissRequest = { confirmSkip = false },
            title = { Text(stringResource(R.string.migration_finish_confirm)) },
            text = { Text(stringResource(R.string.migration_finish_explanation)) },
            confirmButton = {
                Button(onClick = { confirmSkip = false; onFinishPartial() }) {
                    Text(stringResource(R.string.migration_skip_unresolved))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmSkip = false }) { Text(stringResource(R.string.migration_keep_retrying)) }
            },
        )
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(if (state.completedWithSkippedItems) stringResource(R.string.audit_mig_partial) else if (state.complete) stringResource(R.string.audit_mig_complete) else stringResource(R.string.audit_mig_import)) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    if (state.complete) {
                        if (state.completedWithSkippedItems) stringResource(R.string.audit_mig_partial_body) else stringResource(R.string.audit_mig_done_body)
                    } else {
                        stringResource(R.string.audit_mig_inprogress_body)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
                LinearProgressIndicator(
                    progress = { state.completedSteps.toFloat() / steps.size },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    stringResource(R.string.audit_mig_progress, state.completedSteps, steps.size),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                steps.forEach { step ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            if (step.complete) "✓" else "○",
                            color = if (step.complete) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Column {
                            Text(step.title, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                if (step.complete) step.description else if ((step.title == "Playback progress" && state.playbackStatus.isNotBlank()) || (step.title == "Downloads" && state.downloadsStatus.isNotBlank()) || (step.title == "Feeds & startup view" && (state.feedsStatus.isNotBlank() || state.startupStatus.isNotBlank()))) step.description else stringResource(R.string.l10n_migration_pending_next_sync),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                if (!state.complete) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (syncing) CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(4.dp))
                        Text(
                            if (syncing) stringResource(R.string.l10n_migration_syncing)
                            else stringResource(R.string.l10n_migration_retry_after_sync),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        },
        // Keep all actions in a single aligned group instead of splitting
        // them between Material 3's widely separated dialog button slots.
        confirmButton = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.End,
            ) {
                if (!state.complete) {
                    TextButton(onClick = onSync, enabled = !syncing) {
                        Text(stringResource(R.string.migration_sync_now))
                    }
                    if (state.canFinishPartial) {
                        TextButton(onClick = { confirmSkip = true }, enabled = !syncing) {
                            Text(stringResource(R.string.migration_finish_unresolved))
                        }
                    }
                }
                Button(onClick = onClose) {
                    Text(stringResource(if (state.complete) R.string.l10n_done else R.string.l10n_continue_background))
                }
            }
        },
    )
}
