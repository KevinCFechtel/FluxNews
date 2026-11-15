package de.circledev.fluxnews.nativeapp

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.DownloadNetworkPolicy

private enum class SettingsDestination(val titleRes: Int, val subtitleRes: Int) {
    Account(R.string.settings_account_title, R.string.settings_account_subtitle),
    Articles(R.string.settings_articles_title, R.string.settings_articles_subtitle),
    ActionBar(R.string.settings_action_bar_title, R.string.settings_action_bar_subtitle),
    Navigation(R.string.settings_navigation_title, R.string.settings_navigation_subtitle),
    FeedSettings(R.string.settings_feed_settings_title, R.string.settings_feed_settings_subtitle),
    Media(R.string.settings_media_title, R.string.settings_media_subtitle),
    DownloadedData(R.string.settings_downloaded_data_title, R.string.settings_downloaded_data_subtitle),
    BackgroundSync(R.string.settings_background_sync_title, R.string.settings_background_sync_subtitle),
    ConfigurationBackup(R.string.settings_configuration_backup_title, R.string.settings_configuration_backup_subtitle),
    SupportDiagnostics(R.string.settings_support_diagnostics_title, R.string.settings_support_diagnostics_subtitle),
    About(R.string.settings_about_title, R.string.settings_about_subtitle),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsShell(
    bootstrap: AndroidAccountBootstrap,
    navigationPreferences: AndroidNavigationPreferences,
    navigationPreferenceState: AndroidNavigationPreferenceState,
    navigationCategories: List<AndroidNavigationCategoryRef>,
    navigationFeeds: List<AndroidNavigationFeedRef>,
    onAccountChanged: (AndroidAccountBootstrap.State) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val articlePreferences = LocalAndroidArticlePreferences.current
    val actionBarPreferences = LocalAndroidActionBarPreferences.current
    val coreArticleSettings = LocalAndroidCoreArticleSettings.current
    val mediaSettings = LocalAndroidMediaSettings.current
    val downloadedData = LocalAndroidDownloadedData.current
    val backgroundSync = LocalAndroidBackgroundSync.current
    val configurationBackup = LocalAndroidConfigurationBackup.current
    val diagnostics = (LocalContext.current.applicationContext as FluxApplication).diagnostics
    var articleState by remember { mutableStateOf(AndroidArticlePreferenceState()) }
    var actionBarState by remember { mutableStateOf(AndroidActionBarPreferenceState()) }

    LaunchedEffect(articlePreferences) { articlePreferences.state.collect { articleState = it } }
    LaunchedEffect(actionBarPreferences) { actionBarPreferences.state.collect { actionBarState = it } }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val listDetail = maxWidth >= 840.dp
        var selected by remember { mutableStateOf<SettingsDestination?>(if (listDetail) SettingsDestination.Account else null) }
        val compactDetail = !listDetail && selected != null
        BackHandler(enabled = compactDetail) { selected = null }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        AnimatedContent(
                            targetState = selected ?: SettingsDestination.Account,
                            transitionSpec = { AndroidMotion.detailCrossfade() },
                            label = "settings-title",
                        ) { destination ->
                            Text(if (selected == null) stringResource(R.string.nav_settings) else stringResource(destination.titleRes))
                        }
                    },
                    navigationIcon = {
                        IconButton(onClick = { if (compactDetail) selected = null else onBack() }) {
                            Icon(
                                painter = painterResource(R.drawable.ic_arrow_back),
                                contentDescription = stringResource(R.string.settings_back),
                            )
                        }
                    },
                )
            },
        ) { padding ->
            val contentModifier = Modifier.fillMaxSize().padding(padding)
            if (listDetail) {
                Row(contentModifier) {
                    SettingsList(selected, { selected = it }, Modifier.width(340.dp).fillMaxHeight())
                    HorizontalDivider(Modifier.width(1.dp).fillMaxHeight())
                    AndroidCenteredContent(
                        maxWidth = AndroidSettingsDetailMaxWidth,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    ) { detailModifier ->
                        AnimatedContent(
                            targetState = selected ?: SettingsDestination.Account,
                            transitionSpec = { AndroidMotion.detailCrossfade() },
                            label = "settings-detail",
                            modifier = detailModifier,
                        ) { destination ->
                            SettingsDetail(destination, bootstrap, navigationPreferences, navigationPreferenceState, navigationCategories, navigationFeeds, articlePreferences, articleState, actionBarPreferences, actionBarState, coreArticleSettings, mediaSettings, downloadedData, backgroundSync, configurationBackup, diagnostics, onAccountChanged, Modifier.fillMaxSize())
                        }
                    }
                }
            } else {
                AnimatedContent(
                    targetState = selected,
                    transitionSpec = {
                        when {
                            initialState == null && targetState != null -> AndroidMotion.settingsForward()
                            initialState != null && targetState == null -> AndroidMotion.settingsBack()
                            else -> AndroidMotion.detailCrossfade()
                        }
                    },
                    label = "settings-navigation",
                    modifier = contentModifier,
                ) { destination ->
                    if (destination == null) {
                        SettingsList(null, { selected = it }, Modifier.fillMaxSize())
                    } else {
                        AndroidCenteredContent(
                            maxWidth = AndroidSettingsDetailMaxWidth,
                            modifier = Modifier.fillMaxSize(),
                        ) { detailModifier ->
                            SettingsDetail(destination, bootstrap, navigationPreferences, navigationPreferenceState, navigationCategories, navigationFeeds, articlePreferences, articleState, actionBarPreferences, actionBarState, coreArticleSettings, mediaSettings, downloadedData, backgroundSync, configurationBackup, diagnostics, onAccountChanged, detailModifier)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsList(selected: SettingsDestination?, onSelected: (SettingsDestination) -> Unit, modifier: Modifier) {
    Column(modifier.verticalScroll(rememberScrollState()).padding(vertical = 8.dp)) {
        SettingsDestination.entries.forEach { destination ->
            val isSelected = selected == destination
            Surface(
                color = MaterialTheme.colorScheme.background,
                modifier = Modifier.fillMaxWidth().clickable { onSelected(destination) },
            ) {
                Row(
                    Modifier.padding(horizontal = 24.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(destination.titleRes),
                            style = MaterialTheme.typography.titleMedium,
                            color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                        )
                        Text(
                            stringResource(destination.subtitleRes),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        "›",
                        style = MaterialTheme.typography.titleLarge,
                        color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsDetail(destination: SettingsDestination, bootstrap: AndroidAccountBootstrap, navigationPreferences: AndroidNavigationPreferences, navigationState: AndroidNavigationPreferenceState, categories: List<AndroidNavigationCategoryRef>, feeds: List<AndroidNavigationFeedRef>, articlePreferences: AndroidArticlePreferences, articleState: AndroidArticlePreferenceState, actionBarPreferences: AndroidActionBarPreferences, actionBarState: AndroidActionBarPreferenceState, coreArticleSettings: AndroidCoreArticleSettings, mediaSettings: AndroidMediaSettings, downloadedData: AndroidDownloadedData, backgroundSync: AndroidBackgroundSync, configurationBackup: AndroidConfigurationBackupController, diagnostics: AndroidAppDiagnostics, onAccountChanged: (AndroidAccountBootstrap.State) -> Unit, modifier: Modifier) {
    when (destination) {
        SettingsDestination.Account -> AccountConfigurationScreen(
            bootstrap,
            true,
            onAccountChanged,
            { onAccountChanged(AndroidAccountBootstrap.State.AccountRequired) },
            modifier = modifier,
            showTitle = false,
        )
        SettingsDestination.Articles -> ArticleSettingsScreen(articlePreferences, articleState, coreArticleSettings, modifier)
        SettingsDestination.ActionBar -> ActionBarSettingsScreen(actionBarPreferences, actionBarState, modifier)
        SettingsDestination.Navigation -> NavigationSettingsScreen(navigationPreferences, navigationState, categories, feeds, modifier)
        SettingsDestination.FeedSettings -> AndroidBulkFeedSettingsScreen(feeds, modifier)
        SettingsDestination.Media -> MediaSettingsScreen(mediaSettings, modifier)
        SettingsDestination.DownloadedData -> DownloadedDataSettingsScreen(downloadedData, modifier)
        SettingsDestination.BackgroundSync -> BackgroundSyncSettingsScreen(backgroundSync, modifier)
        SettingsDestination.ConfigurationBackup -> ConfigurationBackupScreen(configurationBackup, { (bootstrap.state as? AndroidAccountBootstrap.State.Ready)?.let(onAccountChanged) }, modifier)
        SettingsDestination.SupportDiagnostics -> SupportDiagnosticsScreen(diagnostics, modifier)
        SettingsDestination.About -> AboutSettingsScreen(modifier)
    }
}

@Composable
private fun ArticleSettingsScreen(preferences: AndroidArticlePreferences, state: AndroidArticlePreferenceState, core: AndroidCoreArticleSettings, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.settings_article_explanation), color = MaterialTheme.colorScheme.onSurfaceVariant)
        SettingsPickerRow(
            title = stringResource(R.string.settings_open_article),
            selected = state.openArticle,
            options = AndroidArticleOpenPreference.entries.map { it to prefLabel(it) },
        ) { option -> scope.launch { preferences.setOpenArticle(option) } }
        SettingsPickerRow(
            title = stringResource(R.string.settings_presentation),
            selected = state.presentationMode,
            options = AndroidArticlePresentationMode.entries.map { it to prefLabel(it) },
        ) { option -> scope.launch { preferences.setPresentationMode(option) } }
        SettingsPickerRow(
            title = stringResource(R.string.settings_preview_lines),
            selected = state.previewLines,
            options = AndroidArticlePreviewLines.entries.map { it to prefLabel(it) },
        ) { option -> scope.launch { preferences.setPreviewLines(option) } }
        HorizontalDivider()
        SettingsSwitchRow(stringResource(R.string.settings_show_article_count), state.showArticleCount) { scope.launch { preferences.setShowArticleCount(it) } }
        SettingsSwitchRow(stringResource(R.string.settings_relative_publication), state.showRelativePublicationTime) { scope.launch { preferences.setShowRelativePublicationTime(it) } }
        SettingsSwitchRow(stringResource(R.string.settings_remove_read), state.removeArticlesWhenRead) { scope.launch { preferences.setRemoveArticlesWhenRead(it) } }
        SettingsSwitchRow(stringResource(R.string.settings_scrollover_read), state.markReadOnScrollover) { scope.launch { preferences.setMarkReadOnScrollover(it) } }
        CoreArticleSettingsSection(core); ArticleSwipeSettingsSection(preferences, state.swipeConfiguration)
    }
}

@Composable private fun ArticleSwipeSettingsSection(preferences: AndroidArticlePreferences, configuration: AndroidArticleSwipeConfiguration) { val scope = rememberCoroutineScope(); HorizontalDivider(); SettingsSectionTitle(stringResource(R.string.settings_swipe_actions)); Text(stringResource(R.string.settings_swipe_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant); SwipeSideSettings(stringResource(R.string.settings_swipe_right), AndroidArticleSwipeSide.Leading, configuration, preferences, scope); SwipeSideSettings(stringResource(R.string.settings_swipe_left), AndroidArticleSwipeSide.Trailing, configuration, preferences, scope) }
@Composable private fun SwipeSideSettings(title: String, side: AndroidArticleSwipeSide, configuration: AndroidArticleSwipeConfiguration, preferences: AndroidArticlePreferences, scope: CoroutineScope) { Column { Text(title, style = MaterialTheme.typography.titleSmall); SwipeSlotSettings("Full Swipe", side, AndroidArticleSwipeSlot.FullSwipe, configuration.fullSwipeAction(side), configuration, preferences, scope, true); SwipeSlotSettings("Additional Action", side, AndroidArticleSwipeSlot.Additional, configuration.additionalAction(side), configuration, preferences, scope, true, configuration.fullSwipeAction(side) != null) } }
@Composable
private fun SwipeSlotSettings(
    label: String,
    side: AndroidArticleSwipeSide,
    slot: AndroidArticleSwipeSlot,
    selected: AndroidArticleSwipeAction?,
    configuration: AndroidArticleSwipeConfiguration,
    preferences: AndroidArticlePreferences,
    scope: CoroutineScope,
    allowNone: Boolean,
    enabled: Boolean = true,
) {
    val options = buildList<Pair<AndroidArticleSwipeAction?, String>> {
        if (allowNone) add(null to stringResource(R.string.pref_none))
        AndroidArticleSwipeAction.entries.forEach { add(it to prefLabel(it)) }
    }
    SettingsPickerRow(
        title = label,
        selected = selected,
        options = options,
        enabled = enabled,
    ) { action ->
        scope.launch { preferences.setSwipeAction(configuration, action, side, slot) }
    }
}

@Composable
private fun ActionBarSettingsScreen(preferences: AndroidActionBarPreferences, state: AndroidActionBarPreferenceState, modifier: Modifier) {
    val scope = rememberCoroutineScope(); val available = AndroidActionBarAction.entries.filterNot(state.actions::contains)
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
Text(stringResource(R.string.settings_action_bar_explanation), color = MaterialTheme.colorScheme.onSurfaceVariant); SettingsSectionTitle(stringResource(R.string.settings_action_list)); ActionBarFixedRow(stringResource(R.string.settings_action_sync), stringResource(R.string.settings_always_shown))
        state.actions.forEachIndexed { index, action -> Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text(prefLabel(action), Modifier.weight(1f)); TextButton(enabled = index > 0, onClick = { scope.launch { preferences.moveUp(action, state.actions) } }) { Text("↑") }; TextButton(enabled = index < state.actions.lastIndex, onClick = { scope.launch { preferences.moveDown(action, state.actions) } }) { Text("↓") }; TextButton(onClick = { scope.launch { preferences.remove(action, state.actions) } }) { Text(stringResource(R.string.settings_remove)) } } }
        ActionBarFixedRow(stringResource(R.string.settings_action_more), stringResource(R.string.settings_always_available)); Text(stringResource(R.string.settings_action_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (available.isNotEmpty()) { HorizontalDivider(); SettingsSectionTitle(stringResource(R.string.settings_available_actions)); available.forEach { action -> TextButton(onClick = { scope.launch { preferences.add(action, state.actions) } }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.pref_add_action, prefLabel(action)), Modifier.fillMaxWidth()) } } }
        HorizontalDivider(); TextButton(onClick = { scope.launch { preferences.resetToDefault() } }) { Text(stringResource(R.string.settings_reset_default)) }
    }
}
@Composable private fun ActionBarFixedRow(title: String, status: String) { Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Text(title, Modifier.weight(1f)); Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }

@Composable
private fun NavigationSettingsScreen(preferences: AndroidNavigationPreferences, state: AndroidNavigationPreferenceState, categories: List<AndroidNavigationCategoryRef>, feeds: List<AndroidNavigationFeedRef>, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            stringResource(R.string.pref_nav_explanation),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SettingsSwitchRow(stringResource(R.string.settings_hide_empty), state.hideEmptyNavigationEntries) {
            scope.launch { preferences.setHideEmptyNavigationEntries(it) }
        }
        HorizontalDivider()
        val startupScopeOptions = AndroidStartupScopePreference.entries
            .filter { option ->
                when (option) {
                    AndroidStartupScopePreference.Category -> categories.isNotEmpty()
                    AndroidStartupScopePreference.Feed -> feeds.isNotEmpty()
                    else -> true
                }
            }
            .map { it to prefLabel(it) }
        SettingsPickerRow(
            title = stringResource(R.string.settings_startup_scope),
            selected = state.startupScope,
            options = startupScopeOptions,
        ) { option ->
            scope.launch {
                preferences.setStartupScope(option)
                if (option == AndroidStartupScopePreference.Category && state.startupCategoryId == null) {
                    categories.firstOrNull()?.let { preferences.setStartupCategoryId(it.id) }
                }
                if (option == AndroidStartupScopePreference.Feed && state.startupFeedId == null) {
                    feeds.firstOrNull()?.let { preferences.setStartupFeedId(it.id) }
                }
            }
        }
        if (categories.isEmpty() || feeds.isEmpty()) {
            Text(
                "Category and Feed startup scopes become available after the first successful sync.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (state.startupScope == AndroidStartupScopePreference.Category && categories.isNotEmpty()) {
            val selectedCategory = categories.firstOrNull { it.id == state.startupCategoryId } ?: categories.first()
            SettingsPickerRow(
                title = stringResource(R.string.settings_startup_category),
                selected = selectedCategory.id,
                options = categories.map { it.id to it.title },
            ) { categoryId -> scope.launch { preferences.setStartupCategoryId(categoryId) } }
        }
        if (state.startupScope == AndroidStartupScopePreference.Feed && feeds.isNotEmpty()) {
            val selectedFeed = feeds.firstOrNull { it.id == state.startupFeedId } ?: feeds.first()
            SettingsPickerRow(
                title = stringResource(R.string.settings_startup_feed),
                selected = selectedFeed.id,
                options = feeds.map { it.id to it.title },
            ) { feedId -> scope.launch { preferences.setStartupFeedId(feedId) } }
        }
    }
}

@Composable
private fun MediaSettingsScreen(settings: AndroidMediaSettings, modifier: Modifier) {
    var state by remember { mutableStateOf<AndroidMediaSettings.State?>(null) }; var saving by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }; val scope = rememberCoroutineScope()
    val mediaLoadError = stringResource(R.string.audit_media_load)
    val mediaSaveError = stringResource(R.string.audit_media_save)
    suspend fun reload() { settings.load().fold({ state = it; error = null }, { error = mediaLoadError }) }; LaunchedEffect(settings) { reload() }
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
val current = state
        if (current == null) CircularProgressIndicator() else {
            SettingsSectionTitle(stringResource(R.string.settings_downloads))
            SettingsPickerRow(
                title = stringResource(R.string.settings_download_network),
                selected = current.downloadNetworkPolicy,
                options = listOf(
                    DownloadNetworkPolicy.ANY_NETWORK to stringResource(R.string.audit_network_any),
                    DownloadNetworkPolicy.UNMETERED_ONLY to stringResource(R.string.audit_network_unmetered),
                ),
                enabled = !saving,
            ) { policy ->
                scope.launch {
                    saving = true
                    settings.setDownloadNetworkPolicy(policy).fold(
                        { reload() },
                        { error = mediaSaveError },
                    )
                    saving = false
                }
            }
            SettingsPickerRow(
                title = stringResource(R.string.settings_keep_downloads),
                selected = current.downloadRetention,
                options = AndroidDownloadRetentionChoice.entries.map { it to prefLabel(it) },
                enabled = !saving,
            ) { choice ->
                scope.launch {
                    saving = true
                    settings.setDownloadRetention(choice).fold(
                        { reload() },
                        { error = mediaSaveError },
                    )
                    saving = false
                }
            }
            HorizontalDivider()
            SettingsSectionTitle(stringResource(R.string.nav_listening_list))
            SettingsSwitchRow(stringResource(R.string.settings_auto_listening_download), current.autoDownloadListeningList, !saving) { value ->
                scope.launch {
                    saving = true
                    settings.setAutoDownloadListeningList(value).fold(
                        { reload() },
                        { error = mediaSaveError },
                    )
                    saving = false
                }
            }
            SettingsSwitchRow(stringResource(R.string.settings_delete_after_playback), current.deleteAfterPlayback, !saving) { value ->
                scope.launch {
                    saving = true
                    settings.setDeleteAfterPlayback(value).fold(
                        { reload() },
                        { error = mediaSaveError },
                    )
                    saving = false
                }
            }
            SettingsSwitchRow(stringResource(R.string.settings_remove_completed_listening), current.removeCompletedListeningList, !saving) { value ->
                scope.launch {
                    saving = true
                    settings.setRemoveCompletedListeningList(value).fold(
                        { reload() },
                        { error = mediaSaveError },
                    )
                    saving = false
                }
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun DownloadedDataSettingsScreen(downloadedData: AndroidDownloadedData, modifier: Modifier) {
    var summary by remember { mutableStateOf<AndroidDownloadedData.Summary?>(null) }; var loading by remember { mutableStateOf(false) }; var deleting by remember { mutableStateOf(false) }; var confirmDelete by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }; val scope = rememberCoroutineScope()
    val downloadedLoadError = stringResource(R.string.audit_downloaded_load)
    val downloadedDeleteError = stringResource(R.string.audit_downloaded_delete)
    suspend fun reload() { loading = true; downloadedData.summary().fold({ summary = it; error = null }, { error = downloadedLoadError }); loading = false }; LaunchedEffect(downloadedData) { reload() }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text(stringResource(R.string.downloads_delete_confirm_title)) }, text = { Text(stringResource(R.string.downloads_delete_confirm_body)) }, confirmButton = { TextButton(onClick = { confirmDelete = false; scope.launch { deleting = true; downloadedData.requestDeleteAll().fold({ reload() }, { error = downloadedDeleteError }); deleting = false } }) { Text(stringResource(R.string.downloads_delete)) } }, dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.action_cancel)) } })
    Column(modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (loading && summary == null) CircularProgressIndicator() else summary?.let { current -> DownloadedDataValueRow(stringResource(R.string.downloads_files), NumberFormat.getIntegerInstance().format(current.fileCount.toLong())); DownloadedDataValueRow(stringResource(R.string.downloads_storage_used), formatBytes(current.totalSizeBytes)); Text(stringResource(R.string.downloads_storage_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant); HorizontalDivider(); Button(enabled = !deleting && current.fileCount > 0uL, onClick = { confirmDelete = true }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError)) { Text(stringResource(R.string.downloads_delete_all)) } }
        if (deleting) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) { CircularProgressIndicator(Modifier.size(20.dp)); Text(stringResource(R.string.downloads_deleting)) }; error?.let { Text(it, color = MaterialTheme.colorScheme.error) }; TextButton(enabled = !loading && !deleting, onClick = { scope.launch { reload() } }) { Text(stringResource(R.string.action_refresh)) }
    }
}
@Composable private fun DownloadedDataValueRow(label: String, value: String) { Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) { Text(label, Modifier.weight(1f)); Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
private fun formatBytes(bytes: ULong): String { var amount = bytes.toDouble(); val units = arrayOf("B", "KB", "MB", "GB", "TB"); var index = 0; while (amount >= 1000.0 && index < units.lastIndex) { amount /= 1000.0; index++ }; return if (index == 0) "$bytes B" else String.format(java.util.Locale.getDefault(), "%.1f %s", amount, units[index]) }

@Composable
internal fun SettingsSectionTitle(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
internal fun <T> SettingsPickerRow(
    title: String,
    selected: T,
    options: List<Pair<T, String>>,
    enabled: Boolean = true,
    onSelected: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selectedLabel = options.firstOrNull { it.first == selected }?.second ?: selected.toString()
    Box(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(if (enabled) Modifier.clickable { expanded = true } else Modifier)
                .padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                modifier = Modifier.weight(1f),
                color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = .38f),
            )
            Text(
                selectedLabel,
                color = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .38f),
                style = MaterialTheme.typography.bodyMedium,
            )
            Icon(
                painter = painterResource(R.drawable.ic_expand_more),
                contentDescription = null,
                modifier = Modifier.padding(start = 6.dp),
                tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .38f),
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
                        if (value != selected) onSelected(value)
                    },
                    trailingIcon = {
                        if (value == selected) {
                            Text("✓", color = MaterialTheme.colorScheme.primary)
                        }
                    },
                )
            }
        }
    }
}

@Composable
internal fun SettingsSwitchRow(
    title: String,
    checked: Boolean,
    enabled: Boolean = true,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (enabled) Modifier.clickable { onCheckedChange(!checked) } else Modifier)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f))
        Switch(checked, onCheckedChange, enabled = enabled)
    }
}

@Composable
private fun prefLabel(value: AndroidArticleOpenPreference): String = when (value) {
    AndroidArticleOpenPreference.OriginalLink -> stringResource(R.string.pref_original_link)
    AndroidArticleOpenPreference.Reader -> stringResource(R.string.pref_reader)
}

@Composable
private fun prefLabel(value: AndroidArticlePresentationMode): String = when (value) {
    AndroidArticlePresentationMode.Compact -> stringResource(R.string.pref_compact)
    AndroidArticlePresentationMode.Visual -> stringResource(R.string.pref_visual)
    AndroidArticlePresentationMode.VisualCompact -> stringResource(R.string.pref_visual_compact)
}

@Composable
private fun prefLabel(value: AndroidArticlePreviewLines): String = when (value) {
    AndroidArticlePreviewLines.Compact -> stringResource(R.string.pref_two_lines)
    AndroidArticlePreviewLines.Standard -> stringResource(R.string.pref_three_lines)
    AndroidArticlePreviewLines.Extended -> stringResource(R.string.pref_five_lines)
}

@Composable
private fun prefLabel(value: AndroidArticleSwipeAction): String = when (value) {
    AndroidArticleSwipeAction.ReadUnread -> stringResource(R.string.pref_read_unread)
    AndroidArticleSwipeAction.StarUnstar -> stringResource(R.string.pref_star_unstar)
    AndroidArticleSwipeAction.OpenOriginal -> stringResource(R.string.pref_open_original)
    AndroidArticleSwipeAction.OpenMiniflux -> stringResource(R.string.pref_open_miniflux)
    AndroidArticleSwipeAction.Comments -> stringResource(R.string.pref_open_comments)
    AndroidArticleSwipeAction.Share -> stringResource(R.string.audit_share)
    AndroidArticleSwipeAction.SaveToService -> stringResource(R.string.pref_save_external)
    AndroidArticleSwipeAction.ListeningList -> stringResource(R.string.audit_action_listening)
    AndroidArticleSwipeAction.DownloadAudio -> stringResource(R.string.pref_download_audio)
}

@Composable
private fun prefLabel(value: AndroidActionBarAction): String = when (value) {
    AndroidActionBarAction.FilterAndSort -> stringResource(R.string.pref_filter_sort)
    AndroidActionBarAction.ToggleReadFilter -> stringResource(R.string.pref_all_unread)
    AndroidActionBarAction.ToggleSortOrder -> stringResource(R.string.pref_sort_order)
    AndroidActionBarAction.Search -> stringResource(R.string.audit_action_search)
    AndroidActionBarAction.MarkAllRead -> stringResource(R.string.audit_timeline_mark_all)
    AndroidActionBarAction.MarkAllReadAndNext -> stringResource(R.string.audit_timeline_mark_next)
    AndroidActionBarAction.ListeningList -> stringResource(R.string.audit_action_listening)
    AndroidActionBarAction.Settings -> stringResource(R.string.audit_action_settings)
}

@Composable
private fun prefLabel(value: AndroidStartupScopePreference): String = when (value) {
    AndroidStartupScopePreference.AllNews -> stringResource(R.string.audit_all_news)
    AndroidStartupScopePreference.Starred -> stringResource(R.string.audit_scope_starred)
    AndroidStartupScopePreference.Category -> stringResource(R.string.pref_startup_category)
    AndroidStartupScopePreference.Feed -> stringResource(R.string.pref_startup_feed)
}

@Composable
private fun prefLabel(value: AndroidDownloadRetentionChoice): String = when (value) {
    AndroidDownloadRetentionChoice.Forever -> stringResource(R.string.pref_retention_forever)
    AndroidDownloadRetentionChoice.Days7 -> stringResource(R.string.pref_retention_7)
    AndroidDownloadRetentionChoice.Days30 -> stringResource(R.string.pref_retention_30)
    AndroidDownloadRetentionChoice.Days90 -> stringResource(R.string.pref_retention_90)
}
