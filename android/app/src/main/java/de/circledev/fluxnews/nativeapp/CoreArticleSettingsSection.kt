package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.ReadArticleRetention

@Composable
internal fun CoreArticleSettingsSection(settings: AndroidCoreArticleSettings) {
    var state by remember { mutableStateOf<AndroidCoreArticleSettings.State?>(null) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val audit_core_loadText = stringResource(R.string.audit_core_load)
    val audit_core_retentionText = stringResource(R.string.audit_core_retention)
    val audit_core_limitText = stringResource(R.string.audit_core_limit)
    val audit_core_immediateText = stringResource(R.string.audit_core_immediate)

    fun reload() {
        scope.launch {
            loading = true
            error = null
            settings.load().fold(
                onSuccess = { state = it },
                onFailure = { error = audit_core_loadText },
            )
            loading = false
        }
    }

    LaunchedEffect(settings) {
        settings.load().fold(
            onSuccess = { state = it },
            onFailure = { error = audit_core_loadText },
        )
        loading = false
    }

    HorizontalDivider()
    SettingsSectionTitle(stringResource(R.string.article_storage_reader))

    when {
        loading -> CircularProgressIndicator()
        state != null -> {
            val current = state!!
            val retentionOptions = listOf(
                ReadArticleRetention.DAYS30,
                ReadArticleRetention.DAYS60,
                ReadArticleRetention.DAYS90,
                ReadArticleRetention.DAYS180,
                ReadArticleRetention.DAYS365,
            )
            SettingsPickerRow(
                title = stringResource(R.string.audit_keep_read),
                selected = current.retention,
                options = retentionOptions.map { it to it.androidDisplayName() },
                enabled = !saving,
            ) { option ->
                val previous = current
                state = current.copy(retention = option)
                saving = true
                error = null
                scope.launch {
                    settings.setRetention(option).onFailure {
                        state = previous
                        error = audit_core_retentionText
                    }
                    saving = false
                }
            }

            val detailLimitOptions = listOf(5_000u, 10_000u, 20_000u)
            SettingsPickerRow(
                title = stringResource(R.string.audit_reader_limit),
                selected = current.detailCharacterLimit,
                options = detailLimitOptions.map { option ->
                    option to "${option.toInt().formattedWithGrouping()} characters"
                },
                enabled = !saving,
            ) { option ->
                val previous = current
                state = current.copy(detailCharacterLimit = option)
                saving = true
                error = null
                scope.launch {
                    settings.setDetailCharacterLimit(option).onFailure {
                        state = previous
                        error = audit_core_limitText
                    }
                    saving = false
                }
            }

            Text(
                "Read article retention controls how long synchronized read items remain in local history. The Reader detail limit controls how much article text the Core keeps when a feed uses truncated Reader content.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            HorizontalDivider()
            CoreSwitchRow("Sync article changes immediately", current.liveMutationDelivery, !saving) { enabled ->
                val previous = current
                state = current.copy(liveMutationDelivery = enabled)
                saving = true
                error = null
                scope.launch {
                    settings.setLiveMutationDelivery(enabled).onFailure {
                        state = previous
                        error = audit_core_immediateText
                    }
                    saving = false
                }
            }
            Text(
                "When enabled, read/unread and star changes are saved locally first and then sent to Miniflux immediately. If delivery fails, FluxNews keeps the change pending for a later retry.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (saving) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator()
            Text(stringResource(R.string.settings_saving), style = MaterialTheme.typography.bodySmall)
        }
    }

    error?.let {
        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        if (state == null) TextButton(onClick = ::reload) { Text(stringResource(R.string.list_retry)) }
    }
}

@Composable
private fun CoreSwitchRow(title: String, checked: Boolean, enabled: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth()
            .then(if (enabled) Modifier.clickable { onCheckedChange(!checked) } else Modifier)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
    }
}

private fun Int.formattedWithGrouping(): String = String.format("%,d", this)
