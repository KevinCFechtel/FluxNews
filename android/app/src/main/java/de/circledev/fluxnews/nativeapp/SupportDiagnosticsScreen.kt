package de.circledev.fluxnews.nativeapp

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import java.io.File
import kotlinx.coroutines.launch

private enum class AndroidLogLevelFilter(val titleRes: Int) {
    All(R.string.diagnostics_filter_all), Trace(R.string.diagnostics_filter_trace), Debug(R.string.diagnostics_filter_debug), Info(R.string.diagnostics_filter_info), Warning(R.string.diagnostics_filter_warning), Error(R.string.diagnostics_filter_error);
    fun accepts(level: AndroidAppLogLevel): Boolean = this == All || name == level.name
}

@Composable
internal fun SupportDiagnosticsScreen(diagnostics: AndroidAppDiagnostics, modifier: Modifier = Modifier) {
    val records by diagnostics.entries.collectAsState()
    var debugEnabled by remember { mutableStateOf(diagnostics.isDebugLoggingEnabled()) }
    var viewerOpen by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    if (viewerOpen) { AndroidLogViewer(diagnostics, { viewerOpen = false }, modifier); return }
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SettingsSectionTitle(stringResource(R.string.diagnostics_logging))
        SettingsSwitchRow(stringResource(R.string.diagnostics_debug_logging), debugEnabled) { enabled -> scope.launch { diagnostics.setDebugLoggingEnabled(enabled); debugEnabled = enabled } }
        ValueRow(stringResource(R.string.diagnostics_stored_records), records.size.toString())
        TextButton(onClick = { viewerOpen = true }) { Text(stringResource(R.string.diagnostics_viewer)) }
        Text(stringResource(R.string.diagnostics_logging_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider(); SettingsSectionTitle(stringResource(R.string.diagnostics_support_export))
        Button(onClick = { shareDiagnostics(context, diagnostics) }) { Text(stringResource(R.string.diagnostics_export)) }
        Text(stringResource(R.string.diagnostics_export_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider(); TextButton(onClick = { confirmClear = true }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.diagnostics_clear)) }
        Text(stringResource(R.string.diagnostics_retention), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text(stringResource(R.string.diagnostics_clear_confirm)) }, text = { Text(stringResource(R.string.diagnostics_clear_description)) }, confirmButton = { TextButton(onClick = { diagnostics.clear(); confirmClear = false }) { Text(stringResource(R.string.diagnostics_clear)) } }, dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.action_cancel)) } })
}

@Composable
private fun AndroidLogViewer(diagnostics: AndroidAppDiagnostics, onBack: () -> Unit, modifier: Modifier) {
    val records by diagnostics.entries.collectAsState(); var search by remember { mutableStateOf("") }; var filter by remember { mutableStateOf(AndroidLogLevelFilter.All) }; var menuOpen by remember { mutableStateOf(false) }; val context = LocalContext.current
    val visible = remember(records, search, filter) { records.asReversed().filter { entry -> filter.accepts(entry.level) && (search.isBlank() || entry.category.contains(search, true) || entry.message.contains(search, true)) } }
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            IconButton(onClick = onBack) {
                Icon(
                    painter = painterResource(R.drawable.ic_arrow_back),
                    contentDescription = stringResource(R.string.settings_back),
                )
            }
            TextButton(onClick = {}) { Text(stringResource(R.string.action_refresh)) }
        }
        Text(stringResource(R.string.diagnostics_viewer), style = MaterialTheme.typography.headlineMedium)
        OutlinedTextField(search, { search = it }, label = { Text(stringResource(R.string.diagnostics_search)) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        Box { OutlinedButton(onClick = { menuOpen = true }) { Text(stringResource(R.string.diagnostics_level, stringResource(filter.titleRes))) }; DropdownMenu(menuOpen, { menuOpen = false }) { AndroidLogLevelFilter.entries.forEach { item -> DropdownMenuItem({ Text(stringResource(item.titleRes)) }, { filter = item; menuOpen = false }) } } }
        Text(pluralStringResource(R.plurals.diagnostics_visible_records, visible.size, visible.size), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (visible.isEmpty()) Text(stringResource(R.string.diagnostics_no_results), color = MaterialTheme.colorScheme.onSurfaceVariant)
        visible.forEach { entry -> Card(Modifier.fillMaxWidth().clickable { copy(context, AndroidAppDiagnostics.recordText(entry)) }) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { Text("${entry.level.name.uppercase()} · ${entry.category}", style = MaterialTheme.typography.labelLarge); Text(entry.timestamp, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(entry.message, style = MaterialTheme.typography.bodyMedium); Text(stringResource(R.string.diagnostics_tap_copy), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } } }
    }
}

@Composable private fun ValueRow(label: String, value: String) { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(label); Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
private fun copy(context: Context, text: String) { val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager; clipboard.setPrimaryClip(ClipData.newPlainText("FluxNews diagnostic record", text)) }
private fun shareDiagnostics(context: Context, diagnostics: AndroidAppDiagnostics) {
    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
    val text = diagnostics.exportText(packageInfo.versionName ?: "unknown", packageInfo.longVersionCode)
    val directory = File(context.cacheDir, "diagnostics-export").apply { mkdirs() }
    val file = File(directory, "FluxNews-Diagnostics-${System.currentTimeMillis()}.txt").apply { writeText(text) }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }, "Export Diagnostics"))
}
