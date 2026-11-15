package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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

@Composable
internal fun BackgroundSyncSettingsScreen(
    backgroundSync: AndroidBackgroundSync,
    modifier: Modifier = Modifier,
) {
    var enabled by remember { mutableStateOf<Boolean?>(null) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val bgLoadError = stringResource(R.string.audit_bg_load)
    val bgSaveError = stringResource(R.string.audit_bg_save)

    suspend fun reload() {
        backgroundSync.enabled().fold(
            onSuccess = {
                enabled = it
                error = null
            },
            onFailure = {
                error = bgLoadError
            },
        )
    }

    LaunchedEffect(backgroundSync) { reload() }

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            stringResource(R.string.audit_bg_explanation),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        val current = enabled
        if (current == null) {
            CircularProgressIndicator()
        } else {
            SettingsSwitchRow(
                title = stringResource(R.string.audit_bg_title),
                checked = current,
                enabled = !saving,
            ) { requested ->
                val previous = current
                enabled = requested
                error = null
                scope.launch {
                    saving = true
                    backgroundSync.setEnabled(requested).fold(
                        onSuccess = { reload() },
                        onFailure = {
                            enabled = previous
                            error = bgSaveError
                        },
                    )
                    saving = false
                }
            }

            Text(
                stringResource(R.string.audit_bg_schedule),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (saving) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CircularProgressIndicator(Modifier.size(20.dp))
                Text(stringResource(R.string.settings_saving))
            }
        }

        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}
