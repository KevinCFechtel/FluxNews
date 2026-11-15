package de.circledev.fluxnews.nativeapp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Text
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.SyncReason

class MainActivity : ComponentActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val application = application as FluxApplication
        application.systemNotifications.routeIntent(intent)
        application.widgetRouting.routeIntent(intent)
    }

    private companion object {
        const val BASELINE_PROFILE_TIMELINE_EXTRA = "flux.baselineProfile.timeline"
    }
    private fun isBaselineProfileTimelineLaunch(): Boolean =
        BuildConfig.BUILD_TYPE == "nonMinifiedRelease" &&
            intent?.getBooleanExtra(BASELINE_PROFILE_TIMELINE_EXTRA, false) == true

    override fun onResume() {
        super.onResume()
        if (!isBaselineProfileTimelineLaunch()) {
            (application as FluxApplication).backgroundSync.requestResumeIfNeeded()
        }
    }

    override fun onStop() {
        if (!isBaselineProfileTimelineLaunch()) {
            val application = application as FluxApplication
            lifecycleScope.launch {
                application.mediaPlaybackCoordinator.checkpointCurrent()
            }
        }
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (isBaselineProfileTimelineLaunch()) {
            setContent {
                FluxNewsTheme {
                    BaselineProfileTimelineFixture()
                }
            }
            return
        }

        val application = application as FluxApplication
        application.systemNotifications.routeIntent(intent)
        application.widgetRouting.routeIntent(intent)
        val bootstrap = application.accountBootstrap
        val coreRuntime = application.coreRuntime
        val syncCoordinator = application.syncCoordinator
        val timelineStore = application.timelineStore
        val searchStore = application.searchStore
        val listeningListStore = application.listeningListStore
        val mediaPlaybackCoordinator = application.mediaPlaybackCoordinator
        val mediaTransferCoordinator = application.mediaTransferCoordinator
        val readerStore = application.readerStore
        val articleOpenResolver = application.articleOpenResolver
        val navigationPreferences = application.navigationPreferences
        val articlePreferences = application.articlePreferences
        val actionBarPreferences = application.actionBarPreferences
        val configurationBackup = application.configurationBackup
        val widgetProjection = application.widgetProjection
        val widgetRouting = application.widgetRouting
        val migrationNoticeStore = application.legacyMigrationNoticeStore
        setContent {
            FluxNewsTheme {
                val coreArticleSettings = remember(coreRuntime) { AndroidCoreArticleSettings(coreRuntime) }
                val mediaSettings = remember(coreRuntime, mediaTransferCoordinator) {
                    AndroidMediaSettings(coreRuntime, mediaTransferCoordinator)
                }
                val downloadedData = remember(coreRuntime, mediaTransferCoordinator) {
                    AndroidDownloadedData(coreRuntime, mediaTransferCoordinator)
                }
                val backgroundSync = application.backgroundSync
                val systemNotifications = application.systemNotifications
                CompositionLocalProvider(
                    LocalAndroidArticlePreferences provides articlePreferences,
                    LocalAndroidActionBarPreferences provides actionBarPreferences,
                    LocalAndroidCoreArticleSettings provides coreArticleSettings,
                    LocalAndroidMediaSettings provides mediaSettings,
                    LocalAndroidDownloadedData provides downloadedData,
                    LocalAndroidBackgroundSync provides backgroundSync,
                    LocalAndroidSystemNotifications provides systemNotifications,
                    LocalAndroidConfigurationBackup provides configurationBackup,
                ) {
                    FluxNewsApp(
                        bootstrap,
                        coreRuntime,
                        syncCoordinator,
                        timelineStore,
                        searchStore,
                        listeningListStore,
                        mediaPlaybackCoordinator,
                        mediaTransferCoordinator,
                        readerStore,
                        articleOpenResolver,
                        navigationPreferences,
                        backgroundSync,
                        systemNotifications,
                        widgetProjection,
                        widgetRouting,
                        migrationNoticeStore,
                    )
                }
            }
        }
    }
}

@Composable
private fun FluxNewsApp(
    bootstrap: AndroidAccountBootstrap,
    coreRuntime: AndroidCoreRuntime,
    syncCoordinator: AndroidSyncCoordinator,
    timelineStore: AndroidArticleTimelineStore,
    searchStore: AndroidSearchStore,
    listeningListStore: AndroidListeningListStore,
    mediaPlaybackCoordinator: AndroidMediaPlaybackCoordinator,
    mediaTransferCoordinator: AndroidMediaTransferCoordinator,
    readerStore: AndroidReaderStore,
    articleOpenResolver: AndroidArticleOpenResolver,
    navigationPreferences: AndroidNavigationPreferences,
    backgroundSync: AndroidBackgroundSync,
    systemNotifications: AndroidSystemNotificationManager,
    widgetProjection: AndroidWidgetProjectionCoordinator,
    widgetRouting: AndroidWidgetRouting,
    migrationNoticeStore: AndroidLegacyMigrationNoticeStore,
) {
    var bootstrapState by remember { mutableStateOf(bootstrap.state) }; var retryGeneration by remember { mutableStateOf(0) }; var showingRestore by remember { mutableStateOf(false) }
    LaunchedEffect(bootstrap, retryGeneration) { bootstrapState = bootstrap.restoreStoredAccount() }
    val migrationNotice by migrationNoticeStore.state.collectAsState(initial = AndroidLegacyMigrationNotice())
    val syncState by syncCoordinator.state.collectAsState()
    val migrationAckScope = rememberCoroutineScope()
    var migrationHiddenThisSession by remember { mutableStateOf(false) }
    var migrationAccountPreviouslyShown by remember { mutableStateOf("") }
    val readyState = bootstrapState as? AndroidAccountBootstrap.State.Ready
    LaunchedEffect(readyState?.serverUrl) {
        if (readyState != null) {
            backgroundSync.reconcileFromCore()
            mediaTransferCoordinator.reconcile()
        }
    }
    fun acceptActivatedAccount(ready: AndroidAccountBootstrap.State.Ready) { bootstrapState = ready; syncCoordinator.requestSync(SyncReason.APP_START) }
    Box(modifier = Modifier.fillMaxSize()) {
    Surface(modifier = Modifier.fillMaxSize()) {
        when (val state = bootstrapState) {
            AndroidAccountBootstrap.State.Starting -> StartupProgress()
            AndroidAccountBootstrap.State.AccountRequired -> if (showingRestore) {
                StandaloneStartupSurface(title = stringResource(R.string.audit_app_restore)) { contentModifier ->
                    ConfigurationBackupScreen(
                        LocalAndroidConfigurationBackup.current,
                        { showingRestore = false; (bootstrap.state as? AndroidAccountBootstrap.State.Ready)?.let(::acceptActivatedAccount) },
                        contentModifier,
                        allowExport = false,
                        onDismiss = { showingRestore = false },
                    )
                }
            } else {
                StandaloneStartupSurface(title = stringResource(R.string.audit_app_setup)) { contentModifier ->
                    AccountConfigurationScreen(
                        bootstrap,
                        false,
                        ::acceptActivatedAccount,
                        { bootstrapState = AndroidAccountBootstrap.State.AccountRequired },
                        { showingRestore = true },
                        contentModifier,
                        showTitle = false,
                    )
                }
            }
            is AndroidAccountBootstrap.State.RecoverableError -> RecoverableStartup(LocalContext.current.localizedLegacyUiMessage(state.message), bootstrap, { bootstrapState = AndroidAccountBootstrap.State.Starting; retryGeneration += 1 }, ::acceptActivatedAccount)
            is AndroidAccountBootstrap.State.Ready -> AdaptiveAppShell(
                bootstrap = bootstrap,
                coreRuntime = coreRuntime,
                syncCoordinator = syncCoordinator,
                timelineStore = timelineStore,
                searchStore = searchStore,
                listeningListStore = listeningListStore,
                mediaPlaybackCoordinator = mediaPlaybackCoordinator,
                mediaTransferCoordinator = mediaTransferCoordinator,
                readerStore = readerStore,
                articleOpenResolver = articleOpenResolver,
                navigationPreferences = navigationPreferences,
                systemNotifications = systemNotifications,
                widgetProjection = widgetProjection,
                widgetRouting = widgetRouting,
                state = state,
                onAccountChanged = { changedState ->
                    bootstrapState = changedState
                    if (changedState is AndroidAccountBootstrap.State.Ready) {
                        syncCoordinator.requestSync(SyncReason.APP_START)
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
    val showMigration = migrationNotice.appliesTo(readyState?.serverUrl) && !migrationHiddenThisSession
    LaunchedEffect(migrationNotice.importedServer) {
        if (migrationNotice.importedServer != migrationAccountPreviouslyShown) {
            migrationHiddenThisSession = false
            migrationAccountPreviouslyShown = migrationNotice.importedServer
        }
    }
    if (showMigration) {
        AndroidLegacyMigrationNoticeDialog(
            state = migrationNotice,
            syncing = syncState is AndroidSyncCoordinator.State.Syncing,
            onSync = { syncCoordinator.requestSync(SyncReason.MANUAL) },
            onClose = {
                migrationHiddenThisSession = true
                if (migrationNotice.complete) {
                    // Only a fully verified migration is permanently acknowledged.
                    // Partial migrations remain visible on a later app launch.
                    migrationAckScope.launch { migrationNoticeStore.acknowledge() }
                }
            },
            onFinishPartial = {
                migrationAckScope.launch {
                    runCatching { migrationNoticeStore.finishWithUnresolvedMedia() }
                        .onSuccess { migrationHiddenThisSession = true }
                }
            },
        )
    }
    }
}

@Composable private fun StartupProgress() { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) { CircularProgressIndicator(); Text(stringResource(R.string.audit_app_starting), style = MaterialTheme.typography.bodyLarge) } } }
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StandaloneStartupSurface(
    title: String,
    content: @Composable (Modifier) -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
            )
        },
    ) { padding ->
        AndroidCenteredContent(
            maxWidth = AndroidFormContentMaxWidth,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            content = content,
        )
    }
}

@Composable
private fun RecoverableStartup(
    message: String,
    bootstrap: AndroidAccountBootstrap,
    onRetry: () -> Unit,
    onAccountActivated: (AndroidAccountBootstrap.State.Ready) -> Unit,
) {
    StandaloneStartupSurface(title = stringResource(R.string.audit_app_failed)) { contentModifier ->
        Column(modifier = contentModifier) {
            Column(
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(message, color = MaterialTheme.colorScheme.error)
                Button(onClick = onRetry) { Text(stringResource(R.string.list_retry)) }
            }
            AccountConfigurationScreen(
                bootstrap,
                false,
                onAccountActivated,
                {},
                modifier = Modifier.weight(1f),
                showTitle = false,
            )
        }
    }
}
