package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.compose.currentBackStackEntryAsState
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.CoreEvent
import uniffi.flux_uniffi.NavigationCountMode
import uniffi.flux_uniffi.NavigationProjection

private object ShellRoute {
    const val Timeline = "timeline"
    const val Search = "search"
    const val ListeningList = "listening-list"
    const val Settings = "settings"
    const val FeedSettings = "feed-settings"
}

internal data class NewsNavigationModel(
    val projection: NavigationProjection? = null,
    val error: String? = null,
)


/**
 * The timeline is the app root. Scope selection stays inside its transient/permanent news drawer;
 * Search, Listening List and Settings are real secondary Navigation Compose destinations.
 */
@Composable
internal fun AdaptiveAppShell(
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
    systemNotifications: AndroidSystemNotificationManager,
    widgetProjection: AndroidWidgetProjectionCoordinator,
    widgetRouting: AndroidWidgetRouting,
    state: AndroidAccountBootstrap.State.Ready,
    onAccountChanged: (AndroidAccountBootstrap.State) -> Unit,
    modifier: Modifier = Modifier,
) {
    val navController = rememberNavController()
    val sessionGeneration by coreRuntime.sessionGeneration.collectAsState()
    val pendingNotificationFeedId by systemNotifications.pendingFeedRoute.collectAsState()
    val pendingWidgetArticleId by widgetRouting.pendingArticleId.collectAsState()
    var pendingWidgetArticle by remember(sessionGeneration) {
        mutableStateOf<uniffi.flux_uniffi.ArticleSummary?>(null)
    }
    var feedSettingsTarget by remember { mutableStateOf<AndroidNavigationFeedRef?>(null) }
    var creationDialog by remember(sessionGeneration) { mutableStateOf<String?>(null) }
    var pendingCreatedItem by remember(sessionGeneration) { mutableStateOf<AndroidCreatedNavigationItem?>(null) }
    val retainedTimelineSelection = timelineStore.retainedSelectionForSession(sessionGeneration)
    var timelineSelection by remember(timelineStore, sessionGeneration) {
        mutableStateOf(
            retainedTimelineSelection ?: AndroidArticleTimelineSelection(scope = AndroidNewsScope.All),
        )
    }
    var navigation by remember { mutableStateOf(NewsNavigationModel()) }
    var preferenceState by remember { mutableStateOf<AndroidNavigationPreferenceState?>(null) }
    var startupScopeApplied by remember(timelineStore, sessionGeneration) {
        mutableStateOf(retainedTimelineSelection != null)
    }
    val navigationRefreshes = remember { Channel<Unit>(capacity = Channel.CONFLATED) }
    val navigationLoadError = stringResource(R.string.audit_navigation_load)

    LaunchedEffect(sessionGeneration) {
        searchStore.activateSession(sessionGeneration)
        readerStore.activateSession(sessionGeneration)
        sessionGeneration?.let { generation ->
            runCatching { widgetProjection.ensureAvailable(generation) }
        }
    }

    suspend fun reloadNavigation() {
        navigation = try {
            NewsNavigationModel(
                projection = coreRuntime.local { core -> core.navigationProjection(NavigationCountMode.UNREAD) },
            )
        } catch (_: Exception) {
            NewsNavigationModel(error = navigationLoadError)
        }
    }

    LaunchedEffect(coreRuntime, timelineStore) {
        coreRuntime.events.collect { runtimeEvent ->
            timelineStore.handleCoreEvent(runtimeEvent)
            if (runtimeEvent.event.requiresNavigationRefresh()) {
                navigationRefreshes.trySend(Unit)
            }
            if (runtimeEvent.event.requiresWidgetProjectionRefresh()) {
                widgetProjection.requestRefresh(runtimeEvent.generation)
            }
        }
    }
    LaunchedEffect(coreRuntime, navigationRefreshes) {
        reloadNavigation()
        for (ignored in navigationRefreshes) {
            reloadNavigation()
        }
    }
    LaunchedEffect(navigationPreferences) {
        navigationPreferences.state.collect { preferenceState = it }
    }
    LaunchedEffect(preferenceState, navigation.projection) {
        if (!startupScopeApplied) {
            val preferences = preferenceState
            val projection = navigation.projection
            if (preferences != null && projection != null) {
                timelineSelection = timelineSelection.selectingScope(
                    AndroidNavigationPolicy.resolveStartupScope(
                        preferences = preferences,
                        categories = projection.catalog.categories.map {
                            AndroidNavigationCategoryRef(it.id, it.title)
                        },
                        feeds = projection.catalog.feeds.map {
                            AndroidNavigationFeedRef(it.id, it.categoryId, it.title)
                        },
                    ),
                )
                startupScopeApplied = true
            }
        }
    }

    val currentPreferences = preferenceState ?: AndroidNavigationPreferenceState()
    val categories = navigation.projection?.catalog?.categories?.map {
        AndroidNavigationCategoryRef(it.id, it.title)
    }.orEmpty()
    val feeds = navigation.projection?.catalog?.feeds?.map {
        AndroidNavigationFeedRef(it.id, it.categoryId, it.title)
    }.orEmpty()

    LaunchedEffect(pendingCreatedItem, navigation.projection) {
        when (val item = pendingCreatedItem) {
            is AndroidCreatedNavigationItem.Feed -> {
                val feed = feeds.firstOrNull { it.id == item.id } ?: return@LaunchedEffect
                timelineSelection = timelineSelection.selectingScope(AndroidNewsScope.Feed(feed.id, feed.categoryId, feed.title))
                pendingCreatedItem = null
            }
            is AndroidCreatedNavigationItem.Category -> {
                val category = categories.firstOrNull { it.id == item.id } ?: return@LaunchedEffect
                timelineSelection = timelineSelection.selectingScope(AndroidNewsScope.Category(category.id, category.title))
                pendingCreatedItem = null
            }
            null -> Unit
        }
    }
    LaunchedEffect(pendingNotificationFeedId, navigation.projection, feeds, sessionGeneration) {
        val feedId = pendingNotificationFeedId ?: return@LaunchedEffect
        if (navigation.projection == null) return@LaunchedEffect
        val feed = feeds.firstOrNull { it.id == feedId }
        if (feed != null) {
            timelineSelection = timelineSelection.selectingScope(
                AndroidNewsScope.Feed(feed.id, feed.categoryId, feed.title),
            )
            navController.popBackStack(ShellRoute.Timeline, inclusive = false)
        }
        systemNotifications.consumeFeedRoute(feedId)
    }

    LaunchedEffect(pendingWidgetArticleId, sessionGeneration) {
        val articleId = pendingWidgetArticleId ?: return@LaunchedEffect
        val generation = sessionGeneration ?: return@LaunchedEffect
        val article = runCatching {
            coreRuntime.localForGeneration(generation) { core -> core.articleSummary(articleId) }
        }.getOrNull()
        widgetRouting.consumeArticle(articleId)
        if (article != null) {
            pendingWidgetArticle = article
            navController.popBackStack(ShellRoute.Timeline, inclusive = false)
        }
    }

    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
    androidx.compose.foundation.layout.BoxWithConstraints(modifier) {
        val tabletNavigation = maxWidth >= 840.dp && maxHeight >= 600.dp
        var tabletSidebarCollapsed by rememberSaveable { mutableStateOf(false) }
        val navHostContent: @Composable () -> Unit = {
    NavHost(
        navController = navController,
        startDestination = ShellRoute.Timeline,
        modifier = Modifier.fillMaxSize(),
        enterTransition = { AndroidMotion.topLevelEnter() },
        exitTransition = { AndroidMotion.topLevelExit() },
        popEnterTransition = { AndroidMotion.topLevelEnter() },
        popExitTransition = { AndroidMotion.topLevelExit() },
    ) {
        composable(ShellRoute.Timeline) {
            TimelineDestination(
                selection = timelineSelection,
                navigation = navigation,
                preferences = currentPreferences,
                state = state,
                timelineStore = timelineStore,
                syncCoordinator = syncCoordinator,
                mediaPlaybackCoordinator = mediaPlaybackCoordinator,
                readerStore = readerStore,
                articleOpenResolver = articleOpenResolver,
                sessionGeneration = sessionGeneration,
                navController = navController,
                pendingWidgetArticle = pendingWidgetArticle,
                onWidgetArticleConsumed = { articleId ->
                    if (pendingWidgetArticle?.id == articleId) pendingWidgetArticle = null
                },
                onAddFeed = { creationDialog = "feed" },
                onAddCategory = { creationDialog = "category" },
                onFeedSettings = { feed ->
                    feedSettingsTarget = feed
                    navController.navigate(ShellRoute.FeedSettings)
                },
                onSelectionChanged = { timelineSelection = it },
                tabletNavigationManaged = tabletNavigation,
                tabletSidebarCollapsed = tabletSidebarCollapsed,
                onExpandTabletSidebar = { tabletSidebarCollapsed = false },
            )
        }
        composable(ShellRoute.Search) {
            AndroidSearchDestination(
                store = searchStore,
                readerStore = readerStore,
                openResolver = articleOpenResolver,
                sessionGeneration = sessionGeneration,
                onBack = navController::popBackStack,
                onToggleSidebar = if (tabletNavigation) ({ tabletSidebarCollapsed = !tabletSidebarCollapsed }) else null,
                sidebarExpanded = tabletNavigation && !tabletSidebarCollapsed,
            )
        }
        composable(ShellRoute.ListeningList) {
            AndroidListeningListDestination(
                store = listeningListStore,
                playbackCoordinator = mediaPlaybackCoordinator,
                transferCoordinator = mediaTransferCoordinator,
                sessionGeneration = sessionGeneration,
                onBack = navController::popBackStack,
                onToggleSidebar = if (tabletNavigation) ({ tabletSidebarCollapsed = !tabletSidebarCollapsed }) else null,
                sidebarExpanded = tabletNavigation && !tabletSidebarCollapsed,
            )
        }
        composable(ShellRoute.FeedSettings) {
            val target = feedSettingsTarget
            if (target != null) {
                AndroidFeedSettingsDestination(
                    feedId = target.id,
                    feedTitle = target.title,
                    onBack = navController::popBackStack,
                )
            } else {
                LaunchedEffect(Unit) { navController.popBackStack() }
            }
        }
        composable(ShellRoute.Settings) {
            SettingsDestination(
                bootstrap = bootstrap,
                navigationPreferences = navigationPreferences,
                navigationPreferenceState = currentPreferences,
                navigationCategories = categories,
                navigationFeeds = feeds,
                onAccountChanged = onAccountChanged,
                onBack = navController::popBackStack,
            )
        }
    }
        }
        if (tabletNavigation && !tabletSidebarCollapsed &&
            currentRoute in listOf(ShellRoute.Timeline, ShellRoute.Search, ShellRoute.ListeningList)) {
            PermanentNavigationDrawer(
                drawerContent = {
                    PermanentDrawerSheet(
                        modifier = Modifier.width(320.dp),
                        drawerContainerColor = MaterialTheme.colorScheme.background,
                        drawerTonalElevation = 0.dp,
                    ) {
                        NewsNavigationContent(
                            navigation = navigation,
                            preferences = currentPreferences,
                            timelineStore = timelineStore,
                            selectedScope = timelineSelection.scope,
                            activeDestination = currentRoute ?: ShellRoute.Timeline,
                            onScopeSelected = { selectedScope ->
                                timelineSelection = timelineSelection.selectingScope(selectedScope)
                                navController.popBackStack(ShellRoute.Timeline, inclusive = false)
                            },
                            onSearch = {
                                if (currentRoute != ShellRoute.Search) navController.navigate(ShellRoute.Search) {
                                    popUpTo(ShellRoute.Timeline)
                                    launchSingleTop = true
                                }
                            },
                            onListeningList = {
                                if (currentRoute != ShellRoute.ListeningList) navController.navigate(ShellRoute.ListeningList) {
                                    popUpTo(ShellRoute.Timeline)
                                    launchSingleTop = true
                                }
                            },
                            onSettings = { navController.navigate(ShellRoute.Settings) },
                            onFeedSettings = { feed ->
                                feedSettingsTarget = feed
                                navController.navigate(ShellRoute.FeedSettings)
                            },
                            onAddFeed = { creationDialog = "feed" },
                            onAddCategory = { creationDialog = "category" },
                            sidebarMiniPlayer = {
                                val playback by mediaPlaybackCoordinator.state.collectAsState()
                                if (playback.enclosureId != null &&
                                    playback.status != AndroidMediaPlaybackPresentationStatus.Stopped) {
                                    AndroidCompactMiniPlayer(
                                        playback = playback,
                                        coordinator = mediaPlaybackCoordinator,
                                        onOpenPlayer = {
                                            if (currentRoute != ShellRoute.ListeningList) navController.navigate(ShellRoute.ListeningList) {
                                                popUpTo(ShellRoute.Timeline)
                                                launchSingleTop = true
                                            }
                                        },
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
                                    )
                                }
                            },
                            navigationToggleIcon = R.drawable.ic_sidebar_toggle,
                            navigationToggleDescription = stringResource(R.string.l10n_collapse_navigation),
                            onNavigationToggle = { tabletSidebarCollapsed = true },
                        )
                    }
                },
            ) { navHostContent() }
        } else {
            navHostContent()
        }
    }
    val generation = sessionGeneration
    if (generation != null) {
        val created: (AndroidCreatedNavigationItem) -> Unit = { item ->
            creationDialog = null
            pendingCreatedItem = item
            navigationRefreshes.trySend(Unit)
            syncCoordinator.requestSync(uniffi.flux_uniffi.SyncReason.MANUAL)
        }
        when (creationDialog) {
            "feed" -> AndroidAddFeedDialog(coreRuntime, generation, categories, { creationDialog = null }, created)
            "category" -> AndroidAddCategoryDialog(coreRuntime, generation, categories, { creationDialog = null }, created)
        }
    }
}

private fun CoreEvent.requiresWidgetProjectionRefresh(): Boolean = when (this) {
    is CoreEvent.ArticleReadStateChanged,
    is CoreEvent.ArticleStarredStateChanged,
    -> true
    else -> false
}

private fun CoreEvent.requiresNavigationRefresh(): Boolean = when (this) {
    is CoreEvent.ArticleReadStateChanged,
    is CoreEvent.ArticleStarredStateChanged,
    -> true
    is CoreEvent.SyncDidComplete -> metadata.navigationChanged || metadata.dataChanged
    else -> false
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimelineDestination(
    selection: AndroidArticleTimelineSelection,
    navigation: NewsNavigationModel,
    preferences: AndroidNavigationPreferenceState,
    state: AndroidAccountBootstrap.State.Ready,
    timelineStore: AndroidArticleTimelineStore,
    syncCoordinator: AndroidSyncCoordinator,
    mediaPlaybackCoordinator: AndroidMediaPlaybackCoordinator,
    readerStore: AndroidReaderStore,
    articleOpenResolver: AndroidArticleOpenResolver,
    sessionGeneration: Long?,
    navController: NavHostController,
    pendingWidgetArticle: uniffi.flux_uniffi.ArticleSummary?,
    onWidgetArticleConsumed: (Long) -> Unit,
    onFeedSettings: (AndroidNavigationFeedRef) -> Unit,
    onAddFeed: () -> Unit,
    onAddCategory: () -> Unit,
    onSelectionChanged: (AndroidArticleTimelineSelection) -> Unit,
    tabletNavigationManaged: Boolean = false,
    tabletSidebarCollapsed: Boolean = false,
    onExpandTabletSidebar: () -> Unit = {},
) {
    if (tabletNavigationManaged) {
        NewsRootContent(
            selection = selection,
            navigation = navigation,
            state = state,
            timelineStore = timelineStore,
            syncCoordinator = syncCoordinator,
            mediaPlaybackCoordinator = mediaPlaybackCoordinator,
            readerStore = readerStore,
            articleOpenResolver = articleOpenResolver,
            navigationPreferences = preferences,
            sessionGeneration = sessionGeneration,
            pendingWidgetArticle = pendingWidgetArticle,
            onWidgetArticleConsumed = onWidgetArticleConsumed,
            persistentNavigation = !tabletSidebarCollapsed,
            collapsedPersistentNavigation = tabletSidebarCollapsed,
            scopeTitleLeading = tabletSidebarCollapsed,
            onOpenNavigation = onExpandTabletSidebar,
            onSearch = { navController.navigate(ShellRoute.Search) },
            onListeningList = { navController.navigate(ShellRoute.ListeningList) },
            onSettings = { navController.navigate(ShellRoute.Settings) },
            onSelectionChanged = onSelectionChanged,
        )
        return
    }
    val scope = selection.scope
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        val supportsPersistentNavigation = maxWidth >= 840.dp && maxHeight >= 600.dp
        var persistentNavigationCollapsed by rememberSaveable { mutableStateOf(false) }
        val persistentNewsNavigation = supportsPersistentNavigation && !persistentNavigationCollapsed
        val collapsedPersistentNavigation = supportsPersistentNavigation && persistentNavigationCollapsed
        val compactLandscape = !supportsPersistentNavigation && maxWidth > maxHeight

        if (persistentNewsNavigation) {
            PermanentNavigationDrawer(
                drawerContent = {
                    PermanentDrawerSheet(
                        modifier = Modifier.width(320.dp),
                        drawerContainerColor = MaterialTheme.colorScheme.background,
                        drawerTonalElevation = 0.dp,
                    ) {
                        NewsNavigationContent(
                            navigation = navigation,
                            preferences = preferences,
                            timelineStore = timelineStore,
                            selectedScope = scope,
                            onScopeSelected = { onSelectionChanged(selection.selectingScope(it)) },
                            onSearch = { navController.navigate(ShellRoute.Search) },
                            onListeningList = { navController.navigate(ShellRoute.ListeningList) },
                            onSettings = { navController.navigate(ShellRoute.Settings) },
                            onFeedSettings = onFeedSettings,
                            onAddFeed = onAddFeed,
                            onAddCategory = onAddCategory,
                            sidebarMiniPlayer = {
                                val playback by mediaPlaybackCoordinator.state.collectAsState()
                                if (playback.enclosureId != null &&
                                    playback.status != AndroidMediaPlaybackPresentationStatus.Stopped) {
                                    AndroidCompactMiniPlayer(
                                        playback = playback,
                                        coordinator = mediaPlaybackCoordinator,
                                        onOpenPlayer = { navController.navigate(ShellRoute.ListeningList) },
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 8.dp),
                                    )
                                }
                            },
                            navigationToggleIcon = R.drawable.ic_sidebar_toggle,
                            navigationToggleDescription = stringResource(R.string.l10n_collapse_navigation),
                            onNavigationToggle = { persistentNavigationCollapsed = true },
                        )
                    }
                },
            ) {
                NewsRootContent(
                    selection = selection,
                    navigation = navigation,
                    state = state,
                    timelineStore = timelineStore,
                    syncCoordinator = syncCoordinator,
                    mediaPlaybackCoordinator = mediaPlaybackCoordinator,
                    readerStore = readerStore,
                    articleOpenResolver = articleOpenResolver,
                    navigationPreferences = preferences,
                    sessionGeneration = sessionGeneration,
                    pendingWidgetArticle = pendingWidgetArticle,
                    onWidgetArticleConsumed = onWidgetArticleConsumed,
                    persistentNavigation = true,
                    collapsedPersistentNavigation = false,
                    scopeTitleLeading = false,
                    onOpenNavigation = {},
                    onSearch = { navController.navigate(ShellRoute.Search) },
                    onListeningList = { navController.navigate(ShellRoute.ListeningList) },
                    onSettings = { navController.navigate(ShellRoute.Settings) },
                    onSelectionChanged = onSelectionChanged,
                )
            }
        } else if (collapsedPersistentNavigation) {
            // Tablet navigation toggles directly between the permanent sidebar and
            // the full-width timeline. A modal drawer is only used on compact windows.
            NewsRootContent(
                selection = selection,
                navigation = navigation,
                state = state,
                timelineStore = timelineStore,
                syncCoordinator = syncCoordinator,
                mediaPlaybackCoordinator = mediaPlaybackCoordinator,
                readerStore = readerStore,
                articleOpenResolver = articleOpenResolver,
                navigationPreferences = preferences,
                sessionGeneration = sessionGeneration,
                pendingWidgetArticle = pendingWidgetArticle,
                onWidgetArticleConsumed = onWidgetArticleConsumed,
                persistentNavigation = false,
                collapsedPersistentNavigation = true,
                scopeTitleLeading = true,
                onOpenNavigation = { persistentNavigationCollapsed = false },
                onSearch = { navController.navigate(ShellRoute.Search) },
                onListeningList = { navController.navigate(ShellRoute.ListeningList) },
                onSettings = { navController.navigate(ShellRoute.Settings) },
                onSelectionChanged = onSelectionChanged,
            )
        } else {
            val drawerState = rememberDrawerState(DrawerValue.Closed)
            val coroutineScope = rememberCoroutineScope()
            fun navigateAfterDrawerCloses(route: String) {
                coroutineScope.launch {
                    drawerState.close()
                    navController.navigate(route)
                }
            }
            val modalDrawerWidth = minOf(maxWidth * 0.85f, 360.dp)
            ModalNavigationDrawer(
                drawerState = drawerState,
                drawerContent = {
                    ModalDrawerSheet(
                        modifier = Modifier.width(modalDrawerWidth),
                        drawerContainerColor = MaterialTheme.colorScheme.background,
                        drawerTonalElevation = 0.dp,
                    ) {
                        NewsNavigationContent(
                            navigation = navigation,
                            preferences = preferences,
                            timelineStore = timelineStore,
                            selectedScope = scope,
                            onScopeSelected = { selectedScope ->
                                coroutineScope.launch {
                                    drawerState.close()
                                    onSelectionChanged(selection.selectingScope(selectedScope))
                                }
                            },
                            onSearch = { navigateAfterDrawerCloses(ShellRoute.Search) },
                            onListeningList = { navigateAfterDrawerCloses(ShellRoute.ListeningList) },
                            onSettings = { navigateAfterDrawerCloses(ShellRoute.Settings) },
                            onAddFeed = {
                                coroutineScope.launch { drawerState.close(); onAddFeed() }
                            },
                            onAddCategory = {
                                coroutineScope.launch { drawerState.close(); onAddCategory() }
                            },
                            onFeedSettings = { feed ->
                                coroutineScope.launch {
                                    drawerState.close()
                                    onFeedSettings(feed)
                                }
                            },
                            navigationToggleIcon = if (collapsedPersistentNavigation) R.drawable.ic_chevron_right else null,
                            navigationToggleDescription = if (collapsedPersistentNavigation) stringResource(R.string.l10n_expand_navigation) else null,
                            onNavigationToggle = if (collapsedPersistentNavigation) {
                                {
                                    coroutineScope.launch {
                                        drawerState.close()
                                        persistentNavigationCollapsed = false
                                    }
                                }
                            } else {
                                null
                            },
                        )
                    }
                },
            ) {
                NewsRootContent(
                    selection = selection,
                    navigation = navigation,
                    state = state,
                    timelineStore = timelineStore,
                    syncCoordinator = syncCoordinator,
                    mediaPlaybackCoordinator = mediaPlaybackCoordinator,
                    readerStore = readerStore,
                    articleOpenResolver = articleOpenResolver,
                    navigationPreferences = preferences,
                    sessionGeneration = sessionGeneration,
                    pendingWidgetArticle = pendingWidgetArticle,
                    onWidgetArticleConsumed = onWidgetArticleConsumed,
                    persistentNavigation = false,
                    collapsedPersistentNavigation = collapsedPersistentNavigation,
                    scopeTitleLeading = collapsedPersistentNavigation || compactLandscape,
                    onOpenNavigation = { coroutineScope.launch { drawerState.open() } },
                    onSearch = { navController.navigate(ShellRoute.Search) },
                    onListeningList = { navController.navigate(ShellRoute.ListeningList) },
                    onSettings = { navController.navigate(ShellRoute.Settings) },
                    onSelectionChanged = onSelectionChanged,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SecondaryDestination(title: String, message: String, onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            painter = painterResource(R.drawable.ic_arrow_back),
                            contentDescription = stringResource(R.string.audit_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            Text(
                message,
                modifier = Modifier.padding(24.dp),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SettingsDestination(
    bootstrap: AndroidAccountBootstrap,
    navigationPreferences: AndroidNavigationPreferences,
    navigationPreferenceState: AndroidNavigationPreferenceState,
    navigationCategories: List<AndroidNavigationCategoryRef>,
    navigationFeeds: List<AndroidNavigationFeedRef>,
    onAccountChanged: (AndroidAccountBootstrap.State) -> Unit,
    onBack: () -> Unit,
) {
    SettingsShell(
        bootstrap = bootstrap,
        navigationPreferences = navigationPreferences,
        navigationPreferenceState = navigationPreferenceState,
        navigationCategories = navigationCategories,
        navigationFeeds = navigationFeeds,
        onAccountChanged = onAccountChanged,
        onBack = onBack,
        modifier = Modifier.fillMaxSize(),
    )
}
