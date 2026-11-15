package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

private data class EditableHeader(val id: Long, val name: String, val value: String)

@Composable
internal fun AccountConfigurationScreen(
    bootstrap: AndroidAccountBootstrap,
    allowsRemoval: Boolean,
    onAccountActivated: (AndroidAccountBootstrap.State.Ready) -> Unit,
    onAccountRemoved: () -> Unit,
    onRestoreRequested: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    showTitle: Boolean = true,
) {
    val stored = remember(bootstrap) { bootstrap.credentialsForEditing() }
    var server by remember(stored) { mutableStateOf(stored?.serverUrl.orEmpty()) }
    var apiKey by remember(stored) { mutableStateOf(stored?.apiKey.orEmpty()) }
    val headers = remember(stored) {
        mutableStateListOf<EditableHeader>().apply {
            stored?.customHeaders?.forEachIndexed { index, header ->
                add(EditableHeader(index.toLong(), header.name, header.value))
            }
        }
    }
    var nextHeaderId by remember { mutableStateOf(headers.size.toLong()) }
    var isConfiguring by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var rebuildState by remember { mutableStateOf(bootstrap.localStateRebuildState) }
    var confirmRebuild by remember { mutableStateOf(false) }
    var confirmRemoval by remember { mutableStateOf(false) }
    var version by remember { mutableStateOf((bootstrap.state as? AndroidAccountBootstrap.State.Ready)?.serverVersion) }

    LaunchedEffect(bootstrap.state) {
        val ready = bootstrap.state as? AndroidAccountBootstrap.State.Ready
        if (ready != null && ready.serverUrl == server.trim()) version = ready.serverVersion
    }

    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (showTitle) {
            Text(
                if (allowsRemoval) stringResource(R.string.settings_account_title) else stringResource(R.string.l10n_account_setup),
                style = MaterialTheme.typography.headlineMedium,
            )
        }

        SectionTitle(stringResource(R.string.l10n_account_miniflux))
        OutlinedTextField(
            value = server,
            onValueChange = { server = it; if (it.trim() != stored?.serverUrl) version = null },
            label = { Text(stringResource(R.string.account_server_url)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = apiKey,
            onValueChange = { apiKey = it },
            label = { Text(stringResource(R.string.account_api_key)) },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        val displayedVersion = AndroidAccountPresentation.normalizedServerVersion(version)
        if (displayedVersion != null || AndroidAccountPresentation.usesUnencryptedHttp(server)) {
            SectionTitle(stringResource(R.string.l10n_account_server_info))
            if (displayedVersion != null) {
                LabeledValue(stringResource(R.string.l10n_account_miniflux_version), displayedVersion)
            }
            if (AndroidAccountPresentation.usesUnencryptedHttp(server)) {
                Text(
                    stringResource(R.string.l10n_account_http_warning),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }

        SectionTitle(stringResource(R.string.l10n_account_custom_headers))
        headers.forEachIndexed { index, header ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = header.name,
                    onValueChange = { headers[index] = header.copy(name = it) },
                    label = { Text(stringResource(R.string.account_header_name)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = header.value,
                    onValueChange = { headers[index] = header.copy(value = it) },
                    label = { Text(stringResource(R.string.account_header_value)) },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(onClick = { headers.removeAt(index) }) { Text(stringResource(R.string.account_remove_header)) }
            }
        }
        OutlinedButton(onClick = { headers += EditableHeader(nextHeaderId++, "", "") }) {
            Text(stringResource(R.string.account_add_header))
        }

        message?.let {
            Text(LocalContext.current.localizedLegacyUiMessage(it), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        Button(
            onClick = {
                isConfiguring = true
                message = null
            },
            enabled = server.trim().isNotEmpty() && apiKey.isNotEmpty() && !isConfiguring &&
                rebuildState != AndroidAccountBootstrap.LocalStateRebuildState.Rebuilding,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isConfiguring) {
                CircularProgressIndicator(modifier = Modifier.width(20.dp).height(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(12.dp))
            }
            Text(stringResource(R.string.account_validate_continue))
        }

        LaunchedEffect(isConfiguring) {
            if (!isConfiguring) return@LaunchedEffect
            when (val result = bootstrap.activateAccount(
                server,
                apiKey,
                headers.map { StoredCredentialHeader(it.name, it.value) },
            )) {
                is AndroidAccountBootstrap.ActivationResult.Activated -> {
                    server = result.serverUrl
                    version = result.serverVersion
                    onAccountActivated(AndroidAccountBootstrap.State.Ready(result.serverUrl, result.serverVersion))
                }
                is AndroidAccountBootstrap.ActivationResult.Rejected -> message = result.message
            }
            isConfiguring = false
        }

        if (allowsRemoval) {
            HorizontalDivider()
            SectionTitle(stringResource(R.string.l10n_account_data))
            OutlinedButton(
                onClick = { confirmRebuild = true },
                enabled = rebuildState != AndroidAccountBootstrap.LocalStateRebuildState.Rebuilding && !isConfiguring,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (rebuildState == AndroidAccountBootstrap.LocalStateRebuildState.Rebuilding) {
                    CircularProgressIndicator(modifier = Modifier.width(20.dp).height(20.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.account_rebuilding))
                } else {
                    Text(stringResource(R.string.account_rebuild_local))
                }
            }
            when (rebuildState) {
                AndroidAccountBootstrap.LocalStateRebuildState.Succeeded ->
                    Text(stringResource(R.string.account_rebuilt), color = MaterialTheme.colorScheme.primary)
                AndroidAccountBootstrap.LocalStateRebuildState.Failed ->
                    Text(
                        stringResource(R.string.l10n_account_rebuild_failed),
                        color = MaterialTheme.colorScheme.error,
                    )
                else -> Unit
            }
            Text(
                stringResource(R.string.l10n_account_rebuild_data_explanation),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(
                onClick = { confirmRemoval = true },
                enabled = rebuildState != AndroidAccountBootstrap.LocalStateRebuildState.Rebuilding,
            ) {
                Text(stringResource(R.string.account_remove), color = MaterialTheme.colorScheme.error)
            }
        }
        if (!allowsRemoval) {
            HorizontalDivider()
            Text(stringResource(R.string.account_backup_prompt), style = MaterialTheme.typography.titleMedium)
            OutlinedButton(onClick = { onRestoreRequested?.invoke() }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.account_restore_backup))
            }
        }
    }

    if (confirmRebuild) {
        AlertDialog(
            onDismissRequest = { confirmRebuild = false },
            title = { Text(stringResource(R.string.account_rebuild_confirm)) },
            text = { Text(stringResource(R.string.account_rebuild_explanation)) },
            confirmButton = {
                TextButton(onClick = { confirmRebuild = false; rebuildState = AndroidAccountBootstrap.LocalStateRebuildState.Rebuilding }) {
                    Text(stringResource(R.string.account_rebuild), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmRebuild = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }

    LaunchedEffect(rebuildState) {
        if (rebuildState == AndroidAccountBootstrap.LocalStateRebuildState.Rebuilding) {
            rebuildState = bootstrap.rebuildLocalState()
        }
    }

    if (confirmRemoval) {
        AlertDialog(
            onDismissRequest = { confirmRemoval = false },
            title = { Text(stringResource(R.string.account_remove_confirm)) },
            text = { Text(stringResource(R.string.account_remove_explanation)) },
            confirmButton = {
                TextButton(onClick = { confirmRemoval = false; message = "__remove__" }) {
                    Text(stringResource(R.string.account_remove), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmRemoval = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }

    LaunchedEffect(message) {
        if (message != "__remove__") return@LaunchedEffect
        message = null
        when (val result = bootstrap.removeAccount()) {
            AndroidAccountBootstrap.RemovalResult.Removed -> onAccountRemoved()
            is AndroidAccountBootstrap.RemovalResult.Rejected -> message = result.message
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
}

@Composable
private fun LabeledValue(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
