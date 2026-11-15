package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.ConfigBackupException
import uniffi.flux_uniffi.SyncReason

internal val LocalAndroidConfigurationBackup = staticCompositionLocalOf<AndroidConfigurationBackupController> {
    error("AndroidConfigurationBackupController was not provided")
}

@Composable
internal fun ConfigurationBackupScreen(
    controller: AndroidConfigurationBackupController,
    onRestored: () -> Unit,
    modifier: Modifier = Modifier,
    allowExport: Boolean = true,
    onDismiss: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val backupWriteError = stringResource(R.string.audit_backup_write)
    val backupExported = stringResource(R.string.audit_backup_exported)
    val backupRestoredSync = stringResource(R.string.l10n_backup_restored_sync)
    val scope = rememberCoroutineScope()
    var exportPassword by remember { mutableStateOf("") }
    var exportConfirmation by remember { mutableStateOf("") }
    var pendingExport by remember { mutableStateOf<ByteArray?>(null) }
    var pendingImport by remember { mutableStateOf<Uri?>(null) }
    var importPassword by remember { mutableStateOf("") }
    var confirmRestore by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val createDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val bytes = pendingExport
        pendingExport = null
        if (uri == null || bytes == null) return@rememberLauncherForActivityResult
        scope.launch {
            working = true
            try {
                context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("No writable output stream.")
                status = backupExported
            } catch (_: Exception) { error = backupWriteError }
            working = false
        }
    }
    val openDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        pendingImport = uri
        if (uri != null) error = null
    }

    if (confirmRestore) AlertDialog(
        onDismissRequest = { if (!working) confirmRestore = false },
        title = { Text(stringResource(R.string.backup_restore_confirm)) },
        text = { Text(stringResource(R.string.backup_restore_explanation)) },
        dismissButton = { TextButton(enabled = !working, onClick = { confirmRestore = false }) { Text(stringResource(R.string.action_cancel)) } },
        confirmButton = { TextButton(enabled = !working, onClick = {
            val uri = pendingImport ?: return@TextButton
            confirmRestore = false
            scope.launch {
                working = true; error = null; status = null
                try {
                    controller.restore(context.readBackup(uri), importPassword)
                    val app = context.applicationContext as FluxApplication
                    app.backgroundSync.reconcileFromCore()
                    app.syncCoordinator.requestSync(SyncReason.MANUAL)
                    status = backupRestoredSync
                    onRestored()
                } catch (failure: Exception) { error = backupMessage(failure, context) }
                working = false
            }
        }) { Text(stringResource(R.string.backup_restore), color = MaterialTheme.colorScheme.error) } },
    )

    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        onDismiss?.let { dismiss -> TextButton(onClick = dismiss) { Text(stringResource(R.string.backup_back_account)) } }
        if (allowExport) {
            Text(stringResource(R.string.backup_explanation), color = MaterialTheme.colorScheme.onSurfaceVariant)
            SettingsSectionTitle(stringResource(R.string.backup_export))
            OutlinedTextField(exportPassword, { exportPassword = it }, label = { Text(stringResource(R.string.backup_password)) }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(exportConfirmation, { exportConfirmation = it }, label = { Text(stringResource(R.string.backup_password_confirm)) }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
            Button(enabled = !working && exportPassword.isNotEmpty() && exportPassword == exportConfirmation, onClick = {
                scope.launch {
                    working = true; error = null; status = null
                    try {
                        pendingExport = controller.export(exportPassword)
                        createDocument.launch("FluxNews Configuration Backup ${LocalDate.now()}.fluxbackup")
                    } catch (failure: Exception) { error = backupMessage(failure, context); pendingExport = null }
                    working = false
                }
            }) { Text(stringResource(R.string.backup_export_action)) }
        }
        SettingsSectionTitle(stringResource(R.string.backup_restore))
        Text(stringResource(R.string.backup_restore_help), color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedButton(enabled = !working, onClick = { openDocument.launch(arrayOf("application/octet-stream", "application/*", "*/*")) }) { Text(if (pendingImport == null) "Choose Backup to Restore" else "Choose Another Backup") }
        OutlinedTextField(importPassword, { importPassword = it }, label = { Text(stringResource(R.string.backup_password)) }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
        Button(enabled = !working && pendingImport != null && importPassword.isNotEmpty(), onClick = { confirmRestore = true }) { Text(stringResource(R.string.account_restore_backup)) }
        if (working) CircularProgressIndicator(Modifier.size(24.dp))
        status?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

private fun Context.readBackup(uri: Uri): ByteArray {
    contentResolver.openInputStream(uri)?.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            if (output.size() + read > AndroidConfigurationBackupController.MAX_INPUT_BYTES) throw AndroidConfigurationBackupException.FileTooLarge
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }
    throw IllegalStateException("No readable input stream.")
}

private fun backupMessage(error: Exception, context: android.content.Context): String = when (error) {
    is ConfigBackupException.EmptyPassword -> context.getString(R.string.backup_empty_password)
    is ConfigBackupException.NotFluxBackup -> context.getString(R.string.backup_invalid)
    is ConfigBackupException.UnsupportedVersion -> context.getString(R.string.backup_unsupported)
    is ConfigBackupException.PlatformMismatch -> context.getString(R.string.backup_platform)
    is ConfigBackupException.DecryptionFailed -> context.getString(R.string.backup_decrypt)
    is ConfigBackupException.InvalidCryptoMetadata, is ConfigBackupException.MalformedPayload, is ConfigBackupException.InvalidContents -> context.getString(R.string.backup_corrupt)
    is ConfigBackupException.InputTooLarge, AndroidConfigurationBackupException.FileTooLarge -> context.getString(R.string.backup_too_large)
    AndroidConfigurationBackupException.InvalidPlatformSettings -> context.getString(R.string.backup_android_settings)
    AndroidConfigurationBackupException.NoConfiguredAccount -> context.getString(R.string.backup_no_account)
    AndroidConfigurationBackupException.RollbackFailed -> context.getString(R.string.backup_rollback)
    else -> context.getString(R.string.backup_operation_failed)
}
