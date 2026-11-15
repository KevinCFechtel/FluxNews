package de.circledev.fluxnews.nativeapp

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.DetailRenderingMode
import uniffi.flux_uniffi.FeedPreferences
import uniffi.flux_uniffi.FeedPreferencesPatch

@Composable
internal fun AndroidBulkFeedSettingsScreen(
    feeds: List<AndroidNavigationFeedRef>,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val application = context.applicationContext as FluxApplication
    val coreRuntime = application.coreRuntime
    val notifications = LocalAndroidSystemNotifications.current
    val scope = rememberCoroutineScope()
    val audit_feed_loadText = stringResource(R.string.audit_feed_load)
    val audit_feed_saveText = stringResource(R.string.audit_feed_save)
    val audit_permission_requiredText = stringResource(R.string.audit_permission_required)

    var query by remember { mutableStateOf("") }
    var selectedFeedIds by remember { mutableStateOf(setOf<Long>()) }
    var preferences by remember { mutableStateOf<Map<Long, FeedPreferences>>(emptyMap()) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshGeneration by remember { mutableIntStateOf(0) }
    var pendingNotificationFeedIds by remember { mutableStateOf<Set<Long>?>(null) }

    val feedIds = remember(feeds) { feeds.map { it.id } }
    val filteredFeeds = remember(feeds, query) {
        val normalized = query.trim()
        if (normalized.isEmpty()) feeds else feeds.filter {
            it.title.contains(normalized, ignoreCase = true)
        }
    }

    suspend fun reload() {
        loading = true
        runCatching {
            if (feedIds.isEmpty()) emptyList()
            else coreRuntime.local { core -> core.feedPreferencesBulk(feedIds) }
        }.onSuccess { values ->
            preferences = values.associateBy { it.feedId }
            selectedFeedIds = selectedFeedIds.intersect(feedIds.toSet())
            error = null
        }.onFailure {
            error = audit_feed_loadText
        }
        loading = false
    }

    fun applyPatch(feedIdsToUpdate: Set<Long>, patch: FeedPreferencesPatch) {
        if (feedIdsToUpdate.isEmpty() || saving) return
        scope.launch {
            saving = true
            error = null
            runCatching {
                coreRuntime.local { core ->
                    core.patchFeedPreferencesBulk(feedIdsToUpdate.sorted(), patch)
                }
            }.onSuccess {
                refreshGeneration += 1
            }.onFailure {
                error = audit_feed_saveText
            }
            saving = false
        }
    }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val pending = pendingNotificationFeedIds
        pendingNotificationFeedIds = null
        if (!granted || pending.isNullOrEmpty()) {
            error = audit_permission_requiredText
        } else {
            applyPatch(
                pending,
                FeedPreferencesPatch(
                    systemNotificationsEnabled = true,
                    detailRendering = null,
                    truncateDetail = null,
                    openInMiniflux = null,
                    autoDownloadAudio = null,
                ),
            )
        }
    }

    LaunchedEffect(feedIds, refreshGeneration) { reload() }

    val selectedPreferences = selectedFeedIds.mapNotNull(preferences::get)
    val hasSelection = selectedPreferences.isNotEmpty()

    Column(
        modifier = modifier.padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            stringResource(R.string.bulk_feeds_explanation),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )

        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text(stringResource(R.string.bulk_feeds_search)) },
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                if (selectedFeedIds.isEmpty()) stringResource(R.string.bulk_feeds_none_selected) else pluralStringResource(R.plurals.bulk_feeds_selected, selectedFeedIds.size, selectedFeedIds.size),
                modifier = Modifier.weight(1f),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(
                enabled = filteredFeeds.isNotEmpty() && !saving,
                onClick = { selectedFeedIds = selectedFeedIds + filteredFeeds.map { it.id } },
            ) {
                Text(stringResource(if (query.isBlank()) R.string.bulk_feeds_select_all else R.string.bulk_feeds_select_visible))
            }
            TextButton(
                enabled = selectedFeedIds.isNotEmpty() && !saving,
                onClick = { selectedFeedIds = emptySet() },
            ) {
                Text(stringResource(R.string.bulk_feeds_clear))
            }
        }

        if (loading && preferences.isEmpty()) {
            CircularProgressIndicator()
        } else if (feeds.isEmpty()) {
            Text(
                stringResource(R.string.bulk_feeds_waiting_sync),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = true),
            ) {
                items(filteredFeeds, key = { it.id }) { feed ->
                    val checked = feed.id in selectedFeedIds
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = !saving) {
                                selectedFeedIds = if (checked) {
                                    selectedFeedIds - feed.id
                                } else {
                                    selectedFeedIds + feed.id
                                }
                            }
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(
                            checked = checked,
                            onCheckedChange = if (saving) null else { value ->
                                selectedFeedIds = if (value) {
                                    selectedFeedIds + feed.id
                                } else {
                                    selectedFeedIds - feed.id
                                }
                            },
                        )
                        Text(
                            feed.title,
                            modifier = Modifier.weight(1f).padding(start = 8.dp),
                            maxLines = 2,
                        )
                    }
                }
            }
        }

        HorizontalDivider()

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 310.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                if (selectedFeedIds.isEmpty()) {
                    "Select feeds to edit their shared settings."
                } else {
                    "Settings for ${selectedFeedIds.size} selected " +
                        if (selectedFeedIds.size == 1) "feed" else "feeds"
                },
                style = MaterialTheme.typography.titleMedium,
            )

            if (hasSelection) {
                BulkChoiceRow(
                    title = stringResource(R.string.feed_detail_rendering),
                    selected = commonValue(selectedPreferences) { it.detailRendering },
                    options = listOf(
                        DetailRenderingMode.RENDERED to "Rendered",
                        DetailRenderingMode.TEXT_ONLY to "Text Only",
                    ),
                    enabled = !saving,
                ) { value ->
                    applyPatch(
                        selectedFeedIds,
                        FeedPreferencesPatch(null, value, null, null, null),
                    )
                }

                BulkBooleanRow(
                    title = stringResource(R.string.feed_truncate_detail),
                    selected = commonValue(selectedPreferences) { it.truncateDetail },
                    enabled = !saving,
                ) { value ->
                    applyPatch(
                        selectedFeedIds,
                        FeedPreferencesPatch(null, null, value, null, null),
                    )
                }

                BulkBooleanRow(
                    title = stringResource(R.string.feed_system_notifications),
                    selected = commonValue(selectedPreferences) { it.systemNotificationsEnabled },
                    enabled = !saving,
                ) { value ->
                    if (
                        value &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        !notifications.hasRuntimePermission()
                    ) {
                        pendingNotificationFeedIds = selectedFeedIds
                        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else {
                        applyPatch(
                            selectedFeedIds,
                            FeedPreferencesPatch(value, null, null, null, null),
                        )
                    }
                }

                BulkBooleanRow(
                    title = stringResource(R.string.feed_open_miniflux),
                    selected = commonValue(selectedPreferences) { it.openInMiniflux },
                    enabled = !saving,
                ) { value ->
                    applyPatch(
                        selectedFeedIds,
                        FeedPreferencesPatch(null, null, null, value, null),
                    )
                }

                BulkBooleanRow(
                    title = stringResource(R.string.feed_auto_download_audio),
                    selected = commonValue(selectedPreferences) { it.autoDownloadAudio },
                    enabled = !saving,
                ) { value ->
                    applyPatch(
                        selectedFeedIds,
                        FeedPreferencesPatch(null, null, null, null, value),
                    )
                }

                if (
                    selectedPreferences.any { it.systemNotificationsEnabled } &&
                    !notifications.notificationsEnabledBySystem()
                ) {
                    Text(
                        "Android notification settings currently block FluxNews notifications.",
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun <T> commonValue(
    values: List<FeedPreferences>,
    selector: (FeedPreferences) -> T,
): T? {
    val first = values.firstOrNull()?.let(selector) ?: return null
    return first.takeIf { candidate -> values.all { selector(it) == candidate } }
}

@Composable
private fun BulkBooleanRow(
    title: String,
    selected: Boolean?,
    enabled: Boolean,
    onSelected: (Boolean) -> Unit,
) {
    BulkChoiceRow(
        title = title,
        selected = selected,
        options = listOf(true to "On", false to "Off"),
        enabled = enabled,
        onSelected = onSelected,
    )
}

@Composable
private fun <T> BulkChoiceRow(
    title: String,
    selected: T?,
    options: List<Pair<T, String>>,
    enabled: Boolean,
    onSelected: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedLabel = selected?.let { value ->
        options.firstOrNull { it.first == value }?.second ?: value.toString()
    } ?: "Mixed"

    Box(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = enabled) { expanded = true }
                .padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, modifier = Modifier.weight(1f))
            Text(
                selectedLabel,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { (value, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        expanded = false
                        onSelected(value)
                    },
                )
            }
        }
    }
}
