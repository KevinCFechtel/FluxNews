package de.circledev.fluxnews.nativeapp

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.SyncReason

private const val ANDROID_ACTION_CAPSULE_MAX_FONT_SCALE = 1.35f

internal fun androidActionCapsuleScale(fontScale: Float): Float =
    fontScale.coerceIn(1f, ANDROID_ACTION_CAPSULE_MAX_FONT_SCALE)

internal object AndroidSyncPresentationPolicy {
    fun successVisible(
        state: AndroidSyncCoordinator.State,
        dismissedGeneration: Long?,
    ): Boolean {
        val succeeded = state as? AndroidSyncCoordinator.State.Succeeded ?: return false
        return succeeded.reason == SyncReason.MANUAL &&
            succeeded.generation != dismissedGeneration
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NewsRootContent(
    selection: AndroidArticleTimelineSelection,
    navigation: NewsNavigationModel,
    state: AndroidAccountBootstrap.State.Ready,
    timelineStore: AndroidArticleTimelineStore,
    syncCoordinator: AndroidSyncCoordinator,
    mediaPlaybackCoordinator: AndroidMediaPlaybackCoordinator,
    readerStore: AndroidReaderStore,
    articleOpenResolver: AndroidArticleOpenResolver,
    navigationPreferences: AndroidNavigationPreferenceState,
    sessionGeneration: Long?,
    pendingWidgetArticle: uniffi.flux_uniffi.ArticleSummary?,
    onWidgetArticleConsumed: (Long) -> Unit,
    persistentNavigation: Boolean,
    collapsedPersistentNavigation: Boolean,
    scopeTitleLeading: Boolean,
    onOpenNavigation: () -> Unit,
    onSearch: () -> Unit,
    onListeningList: () -> Unit,
    onSettings: () -> Unit,
    onSelectionChanged: (AndroidArticleTimelineSelection) -> Unit,
) {
    val scope = selection.scope
    val timelineState by timelineStore.state.collectAsState()
    val syncState by syncCoordinator.state.collectAsState()
    val articlePreferences by LocalAndroidArticlePreferences.current.state.collectAsState(
        initial = AndroidArticlePreferenceState(),
    )
    val actionBarState by LocalAndroidActionBarPreferences.current.state.collectAsState(
        initial = AndroidActionBarPreferenceState(),
    )
    val playbackState by mediaPlaybackCoordinator.state.collectAsState()
    var nowPlayingPresented by remember { mutableStateOf(false) }
    val configuration = LocalConfiguration.current
    val isLandscape = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    // The action bar can move to the top before the permanent tablet sidebar is available.
    val wideActionLayout = configuration.screenWidthDp >= 600
    val timelineCount = timelineState.total.takeIf { timelineState.selection?.scope == scope }
    val projection = navigation.projection
    val categoryRefs = projection?.catalog?.categories?.map {
        AndroidNavigationCategoryRef(it.id, it.title)
    }.orEmpty()
    val feedRefs = projection?.catalog?.feeds?.map {
        AndroidNavigationFeedRef(it.id, it.categoryId, it.title)
    }.orEmpty()
    val feedCounts = projection?.feedCounts?.associate { it.id to it.count }.orEmpty()
    val nextScope = AndroidNavigationPolicy.nextScope(
        after = scope,
        hidingEmpty = navigationPreferences.hideEmptyNavigationEntries,
        categories = categoryRefs,
        feeds = feedRefs,
        counts = feedCounts,
    )
    val resolvedActions = AndroidArticleListActionPolicy.resolvedActions(
        configuredActions = actionBarState.actions,
        directCapacity = if (persistentNavigation) 5 else 3,
        scope = scope,
        hasNextScope = nextScope != null,
    )
    val syncInProgress = syncState is AndroidSyncCoordinator.State.Syncing
    val manualSyncInProgress =
        (syncState as? AndroidSyncCoordinator.State.Syncing)?.reason == SyncReason.MANUAL
    // A successful sync retained by the coordinator must not flash again when
    // orientation changes recreate this composable.
    var dismissedSyncSuccessGeneration by remember {
        mutableStateOf((syncState as? AndroidSyncCoordinator.State.Succeeded)?.generation)
    }
    // The pull indicator belongs to the gesture, not every manual sync
    // (including toolbar actions and background-triggered requests).
    var pullRefreshRequested by remember { mutableStateOf(false) }
    var pullRefreshStarted by remember { mutableStateOf(false) }
    LaunchedEffect(syncState) {
        if (pullRefreshRequested) {
            if (syncState is AndroidSyncCoordinator.State.Syncing) {
                pullRefreshStarted = true
            } else if (pullRefreshStarted) {
                pullRefreshRequested = false
                pullRefreshStarted = false
            }
        }
    }
    val syncSuccessVisible = AndroidSyncPresentationPolicy.successVisible(
        state = syncState,
        dismissedGeneration = dismissedSyncSuccessGeneration,
    )
    val actionScope = rememberCoroutineScope()
    val shellSnackbar = remember { SnackbarHostState() }
    val invalidArticleUrl = stringResource(R.string.search_bad_article_url)
    val unableToOpenArticle = stringResource(R.string.audit_article_open)
    var markReadRequest by remember { mutableStateOf<AndroidPendingMarkRead?>(null) }
    var markReadRunning by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current

    fun openReader(article: uniffi.flux_uniffi.ArticleSummary) {
        readerStore.open(article, AndroidReaderSource.Timeline)
    }

    fun openArticle(article: uniffi.flux_uniffi.ArticleSummary) {
        timelineStore.requestSetRead(
            articleId = article.id,
            read = true,
            removeWhenRead = articlePreferences.removeArticlesWhenRead,
            providesFeedback = false,
        )
        if (articlePreferences.openArticle == AndroidArticleOpenPreference.Reader) {
            openReader(article)
            return
        }
        actionScope.launch {
            when (val destination = articleOpenResolver.resolve(article, articlePreferences.openArticle)) {
                AndroidNormalOpenDestination.Reader -> openReader(article)
                is AndroidNormalOpenDestination.Web -> {
                    if (!AndroidArticlePlatformActions.openUrl(context, destination.url)) {
                        shellSnackbar.showSnackbar(invalidArticleUrl)
                    }
                }
                null -> shellSnackbar.showSnackbar(unableToOpenArticle)
            }
        }
    }

    LaunchedEffect(pendingWidgetArticle?.id) {
        val article = pendingWidgetArticle ?: return@LaunchedEffect
        onWidgetArticleConsumed(article.id)
        openArticle(article)
    }

    LaunchedEffect(syncState) {
        val succeeded = syncState as? AndroidSyncCoordinator.State.Succeeded
        if (succeeded?.reason == SyncReason.MANUAL) {
            delay(1_500)
            dismissedSyncSuccessGeneration = succeeded.generation
        }
    }

    LaunchedEffect(syncState, shellSnackbar, context) {
        val failed = syncState as? AndroidSyncCoordinator.State.Failed
        if (failed?.reason == SyncReason.MANUAL) {
            shellSnackbar.showSnackbar(context.localizedLegacyUiMessage(failed.message))
        }
    }

    fun executeArticleListAction(action: AndroidActionBarAction) {
        when (action) {
            AndroidActionBarAction.Search -> onSearch()
            AndroidActionBarAction.ListeningList -> onListeningList()
            AndroidActionBarAction.Settings -> onSettings()
            AndroidActionBarAction.MarkAllRead -> {
                if (!markReadRunning) {
                    markReadRequest = AndroidPendingMarkRead(
                        workflow = AndroidMarkReadWorkflow.Read,
                        nextScope = null,
                    )
                }
            }
            AndroidActionBarAction.MarkAllReadAndNext -> {
                if (!markReadRunning && nextScope != null) {
                    markReadRequest = AndroidPendingMarkRead(
                        workflow = AndroidMarkReadWorkflow.ReadAndNext,
                        nextScope = nextScope,
                    )
                }
            }
            AndroidActionBarAction.FilterAndSort,
            AndroidActionBarAction.ToggleReadFilter,
            AndroidActionBarAction.ToggleSortOrder,
            -> Unit
        }
    }

    val layoutDirection = LocalLayoutDirection.current
    val density = LocalDensity.current
    val actionCapsuleScale = androidActionCapsuleScale(density.fontScale)
    val navigationBarHeight = with(density) {
        WindowInsets.navigationBars.getBottom(this).toDp()
    }
    val bottomActionsVisible = !isLandscape && !wideActionLayout && !persistentNavigation && !collapsedPersistentNavigation
    val miniPlayerVisible = playbackState.enclosureId != null &&
        playbackState.status != AndroidMediaPlaybackPresentationStatus.Stopped
    val toolbarMiniPlayerEligible = !persistentNavigation && (collapsedPersistentNavigation || isLandscape || wideActionLayout)
    val availableToolbarWidth = LocalConfiguration.current.screenWidthDp.dp -
        (if (persistentNavigation) 320.dp else 0.dp)
    // Landscape phones should use the compact player beside the scope title,
    // not consume a second row at the bottom of the timeline.
    val toolbarMiniPlayerVisible = miniPlayerVisible && toolbarMiniPlayerEligible
    val standaloneMiniPlayerVisible = miniPlayerVisible && !persistentNavigation && !bottomActionsVisible && !toolbarMiniPlayerVisible
    val bottomActionClearance = if (bottomActionsVisible) {
        navigationBarHeight +
            32.dp +
            (44.dp * actionCapsuleScale) +
            if (miniPlayerVisible) 78.dp else 0.dp
    } else if (standaloneMiniPlayerVisible) {
        navigationBarHeight + 110.dp
    } else {
        0.dp
    }
    val appBarColors = TopAppBarDefaults.topAppBarColors(
        containerColor = Color.Transparent,
        scrolledContainerColor = Color.Transparent,
    )
    Box(Modifier.fillMaxSize()) {
        Scaffold(
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            snackbarHost = {
                SnackbarHost(
                    hostState = shellSnackbar,
                    modifier = Modifier.padding(bottom = bottomActionClearance),
                )
            },
            topBar = {
                Box(Modifier.fillMaxWidth()) {
                    val toolbarPlayerVisible = !persistentNavigation && toolbarMiniPlayerVisible &&
                        (isLandscape || collapsedPersistentNavigation || wideActionLayout)
                    FloatingChromeTopGradient(
                        modifier = Modifier.align(Alignment.TopCenter),
                    )
                    if (persistentNavigation) {
                        TopAppBar(
                            title = {
                                if (toolbarPlayerVisible) {
                                    AndroidToolbarMiniPlayer(
                                        playback = playbackState,
                                        coordinator = mediaPlaybackCoordinator,
                                        onOpenPlayer = { nowPlayingPresented = true },
                                        modifier = Modifier.widthIn(max = 250.dp),
                                    )
                                }
                            },
                            actions = {
                                AndroidArticleActionCapsule(
                                    selection = selection,
                                    resolvedActions = resolvedActions,
                                    syncState = syncState,
                                    syncSuccessVisible = syncSuccessVisible,
                                    actionsEnabled = !markReadRunning,
                                    scale = actionCapsuleScale,
                                    onRequestManualSync = {
                                        syncCoordinator.requestSync(SyncReason.MANUAL)
                                    },
                                    onCancelManualSync = syncCoordinator::cancelManualSync,
                                    onSelectionChanged = onSelectionChanged,
                                    onAction = ::executeArticleListAction,
                                    modifier = Modifier.padding(end = 8.dp),
                                )
                            },
                            colors = appBarColors,
                        )
                    } else if (!bottomActionsVisible) {
                        TopAppBar(
                            navigationIcon = {
                                if (collapsedPersistentNavigation) {
                                    IconButton(onClick = onOpenNavigation) {
                                        Icon(
                                            painter = painterResource(R.drawable.ic_sidebar_toggle),
                                            contentDescription = stringResource(R.string.l10n_expand_navigation),
                                        )
                                    }
                                }
                            },
                            title = {
                                    ScopeNavigationCapsule(
                                        scope = scope,
                                        showArticleCount = articlePreferences.showArticleCount,
                                        timelineCount = timelineCount,
                                        readFilter = timelineState.selection?.readFilter,
                                        syncing = syncInProgress,
                                        opensNavigation = !persistentNavigation && !collapsedPersistentNavigation,
                                        onOpenNavigation = onOpenNavigation,
                                        trailingContent = if (toolbarPlayerVisible) {
                                            {
                                                AndroidToolbarMiniPlayer(
                                                    playback = playbackState,
                                                    coordinator = mediaPlaybackCoordinator,
                                                    onOpenPlayer = { nowPlayingPresented = true },
                                                    modifier = Modifier.widthIn(min = 120.dp, max = 240.dp),
                                                )
                                            }
                                        } else null,
                                    )
                            },
                            actions = {
                                if (isLandscape || wideActionLayout || collapsedPersistentNavigation) {
                                    AndroidArticleActionCapsule(
                                        selection = selection,
                                        resolvedActions = resolvedActions,
                                        syncState = syncState,
                                        syncSuccessVisible = syncSuccessVisible,
                                        actionsEnabled = !markReadRunning,
                                        scale = actionCapsuleScale,
                                        onRequestManualSync = {
                                            syncCoordinator.requestSync(SyncReason.MANUAL)
                                        },
                                        onCancelManualSync = syncCoordinator::cancelManualSync,
                                        onSelectionChanged = onSelectionChanged,
                                        onAction = ::executeArticleListAction,
                                        modifier = Modifier.padding(end = 8.dp),
                                    )
                                }
                            },
                            colors = appBarColors,
                        )
                    } else {
                        CenterAlignedTopAppBar(
                            title = {
                                        ScopeNavigationCapsule(
                                            scope = scope,
                                            showArticleCount = articlePreferences.showArticleCount,
                                            timelineCount = timelineCount,
                                            readFilter = timelineState.selection?.readFilter,
                                            syncing = syncInProgress,
                                            opensNavigation = !persistentNavigation && !collapsedPersistentNavigation,
                                            onOpenNavigation = onOpenNavigation,
                                                trailingContent = if (toolbarPlayerVisible) {
                                                {
                                                    AndroidToolbarMiniPlayer(
                                                        playback = playbackState,
                                                        coordinator = mediaPlaybackCoordinator,
                                                        onOpenPlayer = { nowPlayingPresented = true },
                                                        modifier = Modifier.widthIn(max = 220.dp),
                                                    )
                                                }
                                            } else null,
                                        )
                            },
                            actions = {
                                if (isLandscape || wideActionLayout) {
                                    AndroidArticleActionCapsule(
                                        selection = selection,
                                        resolvedActions = resolvedActions,
                                        syncState = syncState,
                                        syncSuccessVisible = syncSuccessVisible,
                                        actionsEnabled = !markReadRunning,
                                        scale = actionCapsuleScale,
                                        onRequestManualSync = {
                                            syncCoordinator.requestSync(SyncReason.MANUAL)
                                        },
                                        onCancelManualSync = syncCoordinator::cancelManualSync,
                                        onSelectionChanged = onSelectionChanged,
                                        onAction = ::executeArticleListAction,
                                        modifier = Modifier.padding(end = 8.dp),
                                    )
                                }
                            },
                            colors = appBarColors,
                        )
                    }
                }
            },
        ) { padding ->
            PullToRefreshBox(
                isRefreshing = pullRefreshRequested && manualSyncInProgress,
                onRefresh = {
                    if (!syncInProgress && !markReadRunning) {
                        pullRefreshRequested = syncCoordinator.requestSync(SyncReason.MANUAL)
                        pullRefreshStarted = false
                    }
                },
                modifier = Modifier
                    .fillMaxSize()
                    .padding(
                        start = padding.calculateStartPadding(layoutDirection),
                        end = padding.calculateEndPadding(layoutDirection),
                    ),
            ) {
                AndroidArticleTimeline(
                    store = timelineStore,
                    selection = selection,
                    sessionGeneration = sessionGeneration,
                    accountKey = state.serverUrl,
                    onOpenArticle = ::openArticle,
                    onOpenReader = ::openReader,
                    categoryFeedIds = when (val selectedScope = scope) {
                        is AndroidNewsScope.Category -> feedRefs
                            .asSequence()
                            .filter { it.categoryId == selectedScope.id }
                            .mapTo(mutableSetOf()) { it.id }
                        else -> emptySet()
                    },
                    topContentPadding = padding.calculateTopPadding(),
                    bottomOverlayPadding = bottomActionClearance,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        if (bottomActionsVisible) {
            if (miniPlayerVisible) {
                AndroidArticleListBottomDock(
                    coordinator = mediaPlaybackCoordinator,
                    onOpenPlayer = { nowPlayingPresented = true },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                ) {
                    AndroidArticleActionCapsule(
                        selection = selection,
                        resolvedActions = resolvedActions,
                        syncState = syncState,
                        syncSuccessVisible = syncSuccessVisible,
                        actionsEnabled = !markReadRunning,
                        scale = actionCapsuleScale,
                        onRequestManualSync = {
                            syncCoordinator.requestSync(SyncReason.MANUAL)
                        },
                        onCancelManualSync = syncCoordinator::cancelManualSync,
                        onSelectionChanged = onSelectionChanged,
                        onAction = ::executeArticleListAction,
                        embeddedInDock = true,
                    )
                }
            } else {
                AndroidArticleActionCapsule(
                    selection = selection,
                    resolvedActions = resolvedActions,
                    syncState = syncState,
                    syncSuccessVisible = syncSuccessVisible,
                    actionsEnabled = !markReadRunning,
                    scale = actionCapsuleScale,
                    onRequestManualSync = {
                        syncCoordinator.requestSync(SyncReason.MANUAL)
                    },
                    onCancelManualSync = syncCoordinator::cancelManualSync,
                    onSelectionChanged = onSelectionChanged,
                    onAction = ::executeArticleListAction,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .padding(bottom = 12.dp),
                )
            }
        }

        if (standaloneMiniPlayerVisible) {
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .windowInsetsPadding(WindowInsets.navigationBars)
                    .padding(horizontal = 12.dp, vertical = 8.dp)
                    .widthIn(max = 420.dp),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(22.dp),
                color = MaterialTheme.colorScheme.surface,
                tonalElevation = 2.dp,
                shadowElevation = 6.dp,
            ) {
                AndroidCompactMiniPlayer(
                    playback = playbackState,
                    coordinator = mediaPlaybackCoordinator,
                    onOpenPlayer = { nowPlayingPresented = true },
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
        }

        AndroidArticleReaderOverlay(
            store = readerStore,
            source = AndroidReaderSource.Timeline,
            onOpenOriginal = { article ->
                if (!AndroidArticlePlatformActions.openUrl(context, article.url)) {
                    actionScope.launch {
                        shellSnackbar.showSnackbar(invalidArticleUrl)
                    }
                }
            },
        )
    }

    if (nowPlayingPresented && playbackState.enclosureId != null) {
        AndroidMediaPlayerSheet(
            coordinator = mediaPlaybackCoordinator,
            onDismiss = { nowPlayingPresented = false },
        )
    }

    markReadRequest?.let { request ->
        val title = when (request.workflow) {
            AndroidMarkReadWorkflow.Read -> stringResource(R.string.audit_timeline_mark_all)
            AndroidMarkReadWorkflow.ReadAndNext -> stringResource(R.string.audit_timeline_mark_next)
        }
        AlertDialog(
            onDismissRequest = { if (!markReadRunning) markReadRequest = null },
            title = { Text(title) },
            text = { Text(stringResource(R.string.timeline_mark_all_description)) },
            confirmButton = {
                TextButton(
                    enabled = !markReadRunning,
                    onClick = {
                        markReadRequest = null
                        markReadRunning = true
                        actionScope.launch {
                            val succeeded = timelineStore.markCurrentScopeAsRead(
                                reloadCurrentScope = request.workflow == AndroidMarkReadWorkflow.Read,
                            )
                            if (
                                succeeded &&
                                request.workflow == AndroidMarkReadWorkflow.ReadAndNext &&
                                request.nextScope != null
                            ) {
                                onSelectionChanged(selection.selectingScope(request.nextScope))
                            }
                            markReadRunning = false
                        }
                    },
                ) {
                    Text(title, color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !markReadRunning,
                    onClick = { markReadRequest = null },
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }
}

private enum class AndroidMarkReadWorkflow {
    Read,
    ReadAndNext,
}

private data class AndroidPendingMarkRead(
    val workflow: AndroidMarkReadWorkflow,
    val nextScope: AndroidNewsScope?,
)

@Composable
private fun AndroidArticleActionCapsule(
    selection: AndroidArticleTimelineSelection,
    resolvedActions: AndroidArticleListResolvedActions,
    syncState: AndroidSyncCoordinator.State,
    syncSuccessVisible: Boolean,
    actionsEnabled: Boolean,
    scale: Float,
    onRequestManualSync: () -> Boolean,
    onCancelManualSync: () -> Boolean,
    onSelectionChanged: (AndroidArticleTimelineSelection) -> Unit,
    onAction: (AndroidActionBarAction) -> Unit,
    modifier: Modifier = Modifier,
    embeddedInDock: Boolean = false,
) {
    var overflowExpanded by remember { mutableStateOf(false) }
    var filterExpanded by remember { mutableStateOf(false) }
    val syncing = syncState is AndroidSyncCoordinator.State.Syncing
    val manualSyncing =
        (syncState as? AndroidSyncCoordinator.State.Syncing)?.reason == SyncReason.MANUAL
    val darkMode = isSystemInDarkTheme()
    val buttonSize = 44.dp * scale
    val iconSize = 20.dp * scale
    val progressSize = 30.dp * scale
    val progressIconSize = 15.dp * scale
    val progressStrokeWidth = 1.5.dp * scale

    fun perform(action: AndroidActionBarAction) {
        when (action) {
            AndroidActionBarAction.FilterAndSort -> filterExpanded = true
            AndroidActionBarAction.ToggleReadFilter -> onSelectionChanged(selection.togglingReadFilter())
            AndroidActionBarAction.ToggleSortOrder -> onSelectionChanged(selection.togglingSortOrder())
            else -> onAction(action)
        }
    }

    Box(modifier) {
        Surface(
            shape = CircleShape,
            color = if (embeddedInDock) {
                Color.Transparent
            } else {
                MaterialTheme.colorScheme.background.copy(alpha = if (darkMode) 0.70f else 0.85f)
            },
            contentColor = MaterialTheme.colorScheme.onSurface,
            tonalElevation = 0.dp,
            shadowElevation = if (embeddedInDock) 0.dp else if (darkMode) 0.5.dp else 0.dp,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    enabled = actionsEnabled && (!syncing || manualSyncing),
                    onClick = {
                        if (manualSyncing) onCancelManualSync() else onRequestManualSync()
                    },
                    modifier = Modifier.size(buttonSize),
                ) {
                    if (syncSuccessVisible) {
                        Icon(
                            painter = painterResource(R.drawable.ic_check),
                            contentDescription = stringResource(R.string.timeline_sync_complete),
                            modifier = Modifier.size(iconSize),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    } else if (syncing) {
                        Box(
                            modifier = Modifier.size(progressSize),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.fillMaxSize(),
                                strokeWidth = progressStrokeWidth,
                                color = MaterialTheme.colorScheme.primary,
                                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                            )
                            Icon(
                                painter = painterResource(
                                    if (manualSyncing) R.drawable.ic_close else R.drawable.ic_sync,
                                ),
                                contentDescription = stringResource(if (manualSyncing) R.string.timeline_cancel_sync else R.string.timeline_syncing),
                                modifier = Modifier.size(progressIconSize),
                            )
                        }
                    } else {
                        Icon(
                            painter = painterResource(R.drawable.ic_sync),
                            contentDescription = stringResource(R.string.timeline_sync),
                            modifier = Modifier.size(iconSize),
                        )
                    }
                }

                resolvedActions.direct.forEach { action ->
                    IconButton(
                        enabled = actionsEnabled,
                        onClick = { perform(action) },
                        modifier = Modifier.size(buttonSize),
                    ) {
                        Icon(
                            painter = painterResource(articleListActionIcon(action, selection)),
                            contentDescription = articleListActionContentDescription(action, selection),
                            modifier = Modifier.size(iconSize),
                        )
                    }
                }

                Box {
                    IconButton(
                        enabled = actionsEnabled,
                        onClick = { overflowExpanded = true },
                        modifier = Modifier.size(buttonSize),
                    ) {
                        Icon(
                            painter = painterResource(R.drawable.ic_more),
                            contentDescription = stringResource(R.string.timeline_more),
                            modifier = Modifier.size(iconSize),
                        )
                    }
                    DropdownMenu(
                        expanded = overflowExpanded,
                        onDismissRequest = { overflowExpanded = false },
                    ) {
                        if (resolvedActions.overflow.isEmpty()) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.timeline_no_additional_actions)) },
                                enabled = false,
                                onClick = {},
                            )
                        } else {
                            resolvedActions.overflow.forEach { action ->
                                DropdownMenuItem(
                                    leadingIcon = {
                                        Icon(
                                            painter = painterResource(articleListActionIcon(action, selection)),
                                            contentDescription = null,
                                        )
                                    },
                                    text = { Text(articleListActionMenuLabel(action, selection)) },
                                    onClick = {
                                        overflowExpanded = false
                                        perform(action)
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }

        DropdownMenu(
            expanded = filterExpanded,
            onDismissRequest = { filterExpanded = false },
        ) {
            if (selection.scope != AndroidNewsScope.Starred) {
                DropdownMenuItem(
                    text = {
                        Text(
                            if (selection.readFilter == AndroidArticleReadFilter.Unread) {
                                stringResource(R.string.l10n_show_all_articles)
                            } else {
                                stringResource(R.string.l10n_show_unread_only)
                            },
                        )
                    },
                    onClick = {
                        filterExpanded = false
                        onSelectionChanged(selection.togglingReadFilter())
                    },
                )
            }
            DropdownMenuItem(
                text = {
                    Text(
                        when (selection.sort) {
                            AndroidArticleSortOrder.OldestFirst -> stringResource(R.string.audit_sort_newest)
                            AndroidArticleSortOrder.NewestFirst -> stringResource(R.string.audit_sort_oldest)
                        },
                    )
                },
                onClick = {
                    filterExpanded = false
                    onSelectionChanged(selection.togglingSortOrder())
                },
            )
        }
    }
}

private fun articleListActionIcon(
    action: AndroidActionBarAction,
    selection: AndroidArticleTimelineSelection,
): Int = when (action) {
    AndroidActionBarAction.FilterAndSort -> R.drawable.ic_filter
    AndroidActionBarAction.ToggleReadFilter ->
        if (selection.readFilter == AndroidArticleReadFilter.Unread) R.drawable.ic_news else R.drawable.ic_mark_unread
    AndroidActionBarAction.ToggleSortOrder -> R.drawable.ic_sort
    AndroidActionBarAction.Search -> R.drawable.ic_search
    AndroidActionBarAction.MarkAllRead -> R.drawable.ic_mark_read
    AndroidActionBarAction.MarkAllReadAndNext -> R.drawable.ic_mark_read_next
    AndroidActionBarAction.ListeningList -> R.drawable.ic_headphones
    AndroidActionBarAction.Settings -> R.drawable.ic_settings
}

@Composable
private fun actionDisplayName(action: AndroidActionBarAction): String = when (action) {
    AndroidActionBarAction.FilterAndSort -> stringResource(R.string.audit_action_filter)
    AndroidActionBarAction.ToggleReadFilter -> stringResource(R.string.settings_preview_lines)
    AndroidActionBarAction.ToggleSortOrder -> stringResource(R.string.audit_sort_newest)
    AndroidActionBarAction.Search -> stringResource(R.string.audit_action_search)
    AndroidActionBarAction.MarkAllRead -> stringResource(R.string.audit_timeline_mark_all)
    AndroidActionBarAction.MarkAllReadAndNext -> stringResource(R.string.audit_timeline_mark_next)
    AndroidActionBarAction.ListeningList -> stringResource(R.string.audit_action_listening)
    AndroidActionBarAction.Settings -> stringResource(R.string.audit_action_settings)
}

@Composable
private fun articleListActionContentDescription(
    action: AndroidActionBarAction,
    selection: AndroidArticleTimelineSelection,
): String = when (action) {
    AndroidActionBarAction.ToggleReadFilter ->
        if (selection.readFilter == AndroidArticleReadFilter.Unread) stringResource(R.string.audit_show_all_articles) else stringResource(R.string.audit_show_unread_only)
    AndroidActionBarAction.ToggleSortOrder ->
        if (selection.sort == AndroidArticleSortOrder.OldestFirst) stringResource(R.string.audit_sort_newest) else stringResource(R.string.audit_sort_oldest)
    else -> actionDisplayName(action)
}

@Composable
private fun articleListActionMenuLabel(
    action: AndroidActionBarAction,
    selection: AndroidArticleTimelineSelection,
): String = when (action) {
    AndroidActionBarAction.ToggleReadFilter ->
        if (selection.readFilter == AndroidArticleReadFilter.Unread) stringResource(R.string.audit_show_all_articles_title) else stringResource(R.string.audit_show_unread_only_title)
    AndroidActionBarAction.ToggleSortOrder ->
        if (selection.sort == AndroidArticleSortOrder.OldestFirst) stringResource(R.string.audit_sort_newest_title) else stringResource(R.string.audit_sort_oldest_title)
    else -> actionDisplayName(action)
}

@Composable
private fun FloatingChromeTopGradient(
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val statusBarHeight = with(density) {
        WindowInsets.statusBars.getTop(this).toDp()
    }
    val background = MaterialTheme.colorScheme.background
    val totalHeight = statusBarHeight + 81.dp
    val opacities = if (isSystemInDarkTheme()) {
        listOf(0.96f, 0.94f, 0.88f, 0.74f, 0.50f, 0.25f, 0.10f, 0f)
    } else {
        listOf(0.96f, 0.91f, 0.84f, 0.68f, 0.44f, 0.20f, 0.08f, 0f)
    }
    val stopOffsets = listOf(
        0.dp,
        (statusBarHeight.value * 0.5f).dp,
        statusBarHeight,
        statusBarHeight + 10.dp,
        statusBarHeight + 28.dp,
        statusBarHeight + 52.dp,
        statusBarHeight + 68.dp,
        totalHeight,
    )
    val colorStops = stopOffsets
        .zip(opacities)
        .map { (offset, opacity) ->
            (offset.value / totalHeight.value).coerceIn(0f, 1f) to background.copy(alpha = opacity)
        }
        .toTypedArray()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(totalHeight)
            .background(
                Brush.verticalGradient(
                    colorStops = colorStops,
                ),
            ),
    )
}

@Composable
private fun ScopeNavigationCapsule(
    scope: AndroidNewsScope,
    showArticleCount: Boolean,
    timelineCount: ULong?,
    readFilter: AndroidArticleReadFilter?,
    syncing: Boolean,
    opensNavigation: Boolean,
    onOpenNavigation: () -> Unit,
    trailingContent: (@Composable androidx.compose.foundation.layout.RowScope.() -> Unit)? = null,
) {
    val darkMode = isSystemInDarkTheme()
    Surface(
        onClick = onOpenNavigation,
        enabled = opensNavigation,
        shape = CircleShape,
        color = MaterialTheme.colorScheme.background.copy(
            alpha = if (darkMode) 0.70f else 0.85f,
        ),
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
        shadowElevation = if (darkMode) 0.5.dp else 0.dp,
    ) {
        Row(
            modifier = (if (trailingContent != null) Modifier.fillMaxWidth() else Modifier)
                .padding(horizontal = 14.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                painter = painterResource(R.drawable.ic_fluxnews_logo),
                contentDescription = null,
                modifier = Modifier.size(26.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Column(
                modifier = if (trailingContent != null) Modifier.weight(1f, fill = false) else Modifier,
            ) {
                Text(
                    scopeTitle(scope),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                if (showArticleCount && (syncing || timelineCount != null)) {
                    Text(
                        if (syncing) {
                            "Syncing…"
                        } else {
                            scopeCountLabel(scope, readFilter, requireNotNull(timelineCount))
                        },
                        maxLines = 1,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (opensNavigation) {
                Icon(
                    painter = painterResource(R.drawable.ic_expand_more),
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (trailingContent != null) {
                trailingContent()
            }
        }
    }
}

@Composable
private fun scopeCountLabel(
    scope: AndroidNewsScope,
    readFilter: AndroidArticleReadFilter?,
    count: ULong,
): String {
    val countAsInt = count.coerceAtMost(Int.MAX_VALUE.toULong()).toInt()
    return if (readFilter == AndroidArticleReadFilter.Unread && scope != AndroidNewsScope.Starred) {
        pluralStringResource(R.plurals.audit_unread_count, countAsInt, countAsInt)
    } else {
        pluralStringResource(R.plurals.audit_article_count, countAsInt, countAsInt)
    }
}

@Composable
private fun scopeTitle(scope: AndroidNewsScope): String = when (scope) {
    AndroidNewsScope.All -> stringResource(R.string.audit_all_news)
    AndroidNewsScope.Starred -> stringResource(R.string.audit_scope_starred)
    is AndroidNewsScope.Category -> scope.title
    is AndroidNewsScope.Feed -> scope.title
}
