package de.circledev.fluxnews.nativeapp

import android.os.Build
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.FeedIconVariant

private const val ANDROID_ARTICLE_TIMELINE_PREFETCH_DISTANCE = 8

@Composable
internal fun AndroidArticleTimeline(
    store: AndroidArticleTimelineStore,
    selection: AndroidArticleTimelineSelection,
    sessionGeneration: Long?,
    accountKey: String,
    onOpenArticle: (ArticleSummary) -> Unit,
    onOpenReader: (ArticleSummary) -> Unit,
    categoryFeedIds: Set<Long> = emptySet(),
    topContentPadding: Dp = 0.dp,
    bottomOverlayPadding: Dp = 0.dp,
    modifier: Modifier = Modifier,
) {
    val state by store.contentState.collectAsState()
    val undoState by store.undoState.collectAsState()
    val preferencesFlow = LocalAndroidArticlePreferences.current.state
    val articlePreferences by produceState<AndroidArticlePreferenceState?>(
        initialValue = null,
        key1 = preferencesFlow,
    ) {
        preferencesFlow.collect { value = it }
    }
    val loadedArticlePreferences = articlePreferences ?: return
    var pendingDownloadChoice by remember {
        mutableStateOf<AndroidArticleMediaActionState?>(null)
    }
    val errorMessage = state.errorMessage?.let(LocalContext.current::localizedLegacyUiMessage)
    val pendingNewDataForCurrentScope = store.hasPendingNewDataForScope(
        scope = selection.scope,
        categoryFeedIds = categoryFeedIds,
    )
    val listState = rememberLazyListState()
    val scrolloverTracker = remember { AndroidScrolloverTracker() }
    val actionScope = rememberCoroutineScope()
    val actionSnackbar = remember { SnackbarHostState() }
    val minifluxUrlError = stringResource(R.string.audit_miniflux_url)
    val shareFailedMessage = stringResource(R.string.audit_shared_fail)
    val context = LocalContext.current
    val view = LocalView.current
    val publicationReferenceMillis = remember(state.queryGeneration) { System.currentTimeMillis() }
    val articleIds = remember(state.articles) {
        state.articles.map { it.id }
    }
    val articleFeedIds = remember(state.articles) {
        state.articles.map { it.feedId }.distinct()
    }
    val feedIconVariant = if (isSystemInDarkTheme()) {
        FeedIconVariant.DARK
    } else {
        FeedIconVariant.NORMAL
    }

    fun showActionMessage(message: String) {
        actionScope.launch { actionSnackbar.showSnackbar(context.localizedLegacyUiMessage(message)) }
    }

    fun performSwipeAction(article: ArticleSummary, action: AndroidArticleSwipeAction) {
        when (action) {
            AndroidArticleSwipeAction.ReadUnread -> {
                store.requestSetRead(
                    articleId = article.id,
                    read = !article.isRead,
                    removeWhenRead = loadedArticlePreferences.removeArticlesWhenRead,
                )
            }
            AndroidArticleSwipeAction.StarUnstar -> {
                store.requestSetStarred(article.id, !article.isStarred)
            }
            AndroidArticleSwipeAction.OpenOriginal -> {
                store.requestSetRead(
                    articleId = article.id,
                    read = true,
                    removeWhenRead = loadedArticlePreferences.removeArticlesWhenRead,
                    providesFeedback = false,
                )
                if (!AndroidArticlePlatformActions.openUrl(context, article.url)) {
                    showActionMessage("The article does not have a valid web URL.")
                }
            }
            AndroidArticleSwipeAction.OpenMiniflux -> {
                store.requestSetRead(
                    articleId = article.id,
                    read = true,
                    removeWhenRead = loadedArticlePreferences.removeArticlesWhenRead,
                    providesFeedback = false,
                )
                actionScope.launch {
                    val url = store.resolveMinifluxEntryUrl(article.id)
                    if (url == null || !AndroidArticlePlatformActions.openUrl(context, url)) {
                        actionSnackbar.showSnackbar(minifluxUrlError)
                    }
                }
            }
            AndroidArticleSwipeAction.Comments -> {
                if (!AndroidArticlePlatformActions.openUrl(context, article.commentsUrl)) {
                    showActionMessage("The article does not have a valid comments URL.")
                }
            }
            AndroidArticleSwipeAction.Share -> {
                if (!AndroidArticlePlatformActions.share(context, article)) {
                    showActionMessage(shareFailedMessage)
                }
            }
            AndroidArticleSwipeAction.SaveToService -> {
                store.requestSaveToService(article.id)
            }
            AndroidArticleSwipeAction.ListeningList -> {
                val current = state.mediaActionStates[article.id]?.isInListeningList ?: false
                store.requestSetListeningList(article.id, !current)
            }
            AndroidArticleSwipeAction.DownloadAudio -> {
                val mediaState = state.mediaActionStates[article.id] ?: return
                when (mediaState.audioEnclosures.size) {
                    0 -> Unit
                    1 -> store.requestToggleDownload(
                        article.id,
                        mediaState.audioEnclosures.first().id,
                    )
                    else -> pendingDownloadChoice = mediaState
                }
            }
        }
    }

    fun performContextAction(article: ArticleSummary, action: AndroidArticleContextAction) {
        when (action) {
            AndroidArticleContextAction.ReadUnread ->
                performSwipeAction(article, AndroidArticleSwipeAction.ReadUnread)
            AndroidArticleContextAction.StarUnstar ->
                performSwipeAction(article, AndroidArticleSwipeAction.StarUnstar)
            AndroidArticleContextAction.OpenOriginal ->
                performSwipeAction(article, AndroidArticleSwipeAction.OpenOriginal)
            AndroidArticleContextAction.Reader -> {
                store.requestSetRead(
                    articleId = article.id,
                    read = true,
                    removeWhenRead = loadedArticlePreferences.removeArticlesWhenRead,
                    providesFeedback = false,
                )
                onOpenReader(article)
            }
            AndroidArticleContextAction.OpenMiniflux ->
                performSwipeAction(article, AndroidArticleSwipeAction.OpenMiniflux)
            AndroidArticleContextAction.Comments ->
                performSwipeAction(article, AndroidArticleSwipeAction.Comments)
            AndroidArticleContextAction.CopyLink -> {
                if (AndroidArticlePlatformActions.copyLink(context, article)) {
                    showActionMessage("Link copied.")
                } else {
                    showActionMessage("The article does not have a valid web URL.")
                }
            }
            AndroidArticleContextAction.Share ->
                performSwipeAction(article, AndroidArticleSwipeAction.Share)
            AndroidArticleContextAction.SaveToService ->
                performSwipeAction(article, AndroidArticleSwipeAction.SaveToService)
            AndroidArticleContextAction.ListeningList ->
                performSwipeAction(article, AndroidArticleSwipeAction.ListeningList)
            AndroidArticleContextAction.DownloadAudio ->
                performSwipeAction(article, AndroidArticleSwipeAction.DownloadAudio)
        }
    }

    LaunchedEffect(store, actionSnackbar) {
        store.actionMessages.collect { message ->
            actionSnackbar.showSnackbar(context.localizedLegacyUiMessage(message))
        }
    }

    LaunchedEffect(store, view) {
        store.feedback.collect { feedback ->
            when (feedback) {
                AndroidTimelineHaptic.Confirmation -> view.performFluxConfirmationHaptic()
                AndroidTimelineHaptic.Selection -> view.performFluxSelectionHaptic()
            }
        }
    }

    LaunchedEffect(undoState.revision, undoState.expiresAtUptimeMillis) {
        val expiresAt = undoState.expiresAtUptimeMillis ?: return@LaunchedEffect
        val delayMillis = (expiresAt - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
        delay(delayMillis)
        store.expireScrolloverUndo(undoState.revision)
    }

    LaunchedEffect(articleIds) {
        scrolloverTracker.updateSnapshot(articleIds)
    }

    DisposableEffect(store, state.queryGeneration) {
        onDispose {
            store.enqueueScrolloverInteractionComplete()
        }
    }

    LaunchedEffect(store, listState, scrolloverTracker) {
        store.scrollResetRequests.collect {
            if (listState.layoutInfo.totalItemsCount > 0) {
                scrolloverTracker.beginProgrammaticScroll(listState.firstVisibleItemIndex)
                try {
                    listState.scrollToItem(0)
                } finally {
                    scrolloverTracker.endProgrammaticScroll(listState.firstVisibleItemIndex)
                }
            }
        }
    }

    LaunchedEffect(store, scrolloverTracker) {
        store.scrolloverRearmRequests.collect { articleIds ->
            scrolloverTracker.rearm(articleIds)
        }
    }

    LaunchedEffect(articleFeedIds, feedIconVariant) {
        store.ensureFeedIcons(articleFeedIds, feedIconVariant)
    }

    LaunchedEffect(
        listState,
        scrolloverTracker,
        loadedArticlePreferences.markReadOnScrollover,
        state.queryGeneration,
    ) {
        if (!loadedArticlePreferences.markReadOnScrollover) {
            scrolloverTracker.synchronizeIdlePosition(listState.firstVisibleItemIndex)
            return@LaunchedEffect
        }
        scrolloverTracker.synchronizeIdlePosition(listState.firstVisibleItemIndex)
        snapshotFlow {
            Triple(
                listState.firstVisibleItemIndex,
                listState.isScrollInProgress,
                !listState.canScrollForward && state.nextCursor == null,
            )
        }
            .collect { (firstVisibleIndex, scrolling, atDatasetEnd) ->
                val candidates = scrolloverTracker.observe(
                    sample = AndroidScrolloverPositionSample(
                        firstVisibleIndex = firstVisibleIndex,
                        atDatasetEnd = atDatasetEnd,
                    ),
                    scrolling = scrolling,
                    enabled = true,
                )
                if (!scrolling) {
                    store.enqueueScrolloverCandidates(candidates)
                    store.enqueueScrolloverInteractionComplete()
                }
            }
    }

    LaunchedEffect(selection, sessionGeneration, accountKey) {
        val current = store.state.value
        val sameContext =
            current.selection == selection &&
                current.sessionGeneration == sessionGeneration
        if (sameContext) return@LaunchedEffect

        if (listState.firstVisibleItemIndex != 0 || listState.firstVisibleItemScrollOffset != 0) {
            scrolloverTracker.beginProgrammaticScroll(listState.firstVisibleItemIndex)
            try {
                listState.scrollToItem(0)
            } finally {
                scrolloverTracker.endProgrammaticScroll(listState.firstVisibleItemIndex)
            }
        } else {
            scrolloverTracker.synchronizeIdlePosition(0)
        }
        store.acknowledgePendingNewDataForScope(selection.scope, categoryFeedIds)
        store.reset(selection)
    }

    LaunchedEffect(
        listState,
        state.queryGeneration,
        state.articles.size,
        state.nextCursor != null,
    ) {
        if (state.articles.isEmpty() || state.nextCursor == null) return@LaunchedEffect
        snapshotFlow {
            val lastVisibleIndex = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1
            val threshold = (state.articles.lastIndex - ANDROID_ARTICLE_TIMELINE_PREFETCH_DISTANCE).coerceAtLeast(0)
            lastVisibleIndex >= threshold
        }
            .distinctUntilChanged()
            .collect { approachingEnd ->
                if (approachingEnd) store.loadNextPage()
            }
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
    val availableWidth = (maxWidth - 32.dp).coerceAtLeast(0.dp)
    val availableWidthDp = availableWidth.value.toInt()
    when {
        state.initialLoading && state.articles.isEmpty() -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        errorMessage != null && state.articles.isEmpty() -> {
            TimelineMessage(
                message = errorMessage,
                actionLabel = stringResource(R.string.list_retry),
                onAction = { actionScope.launch { store.reset(selection) } },
                modifier = Modifier.fillMaxSize(),
            )
        }
        state.empty -> {
            TimelineMessage(
                message = stringResource(R.string.timeline_empty),
                modifier = Modifier.fillMaxSize(),
            )
        }
        else -> {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = topContentPadding, bottom = bottomOverlayPadding),
            ) {
                items(
                    items = state.articles,
                    key = { article -> article.id },
                    contentType = { article ->
                        AndroidArticleRowPolicy.layoutVariant(
                            mode = loadedArticlePreferences.presentationMode,
                            imageUrl = article.imageUrl,
                            availableWidthDp = availableWidthDp,
                        )
                    },
                ) { article ->
                    val hasAudio = article.id in state.audioArticleIds
                    val presentation by store.rowPresentationState(article).collectAsState()
                    val presentedArticle = remember(
                        article,
                        presentation.isRead,
                        presentation.isStarred,
                    ) {
                        article.copy(
                            isRead = presentation.isRead,
                            isStarred = presentation.isStarred,
                        )
                    }
                    AndroidArticleSwipeContainer(
                        article = presentedArticle,
                        hasAudio = hasAudio,
                        configuration = loadedArticlePreferences.swipeConfiguration,
                        mediaActionsEnabled = true,
                        mediaState = state.mediaActionStates[article.id],
                        rowWidth = maxWidth,
                        onOpen = { onOpenArticle(presentedArticle) },
                        onSwipeAction = { action -> performSwipeAction(presentedArticle, action) },
                        onContextAction = { action -> performContextAction(presentedArticle, action) },
                    ) {
                        AndroidArticleTimelineRow(
                            article = presentedArticle,
                            hasAudio = hasAudio,
                            preferences = loadedArticlePreferences,
                            publicationReferenceMillis = publicationReferenceMillis,
                            feedIconPng = state.feedIconPngByFeedId[article.feedId],
                            feedIconVariant = feedIconVariant,
                            availableWidth = availableWidth,
                            onRequestFeedIcon = store::ensureFeedIcon,
                        )
                    }
                }

                if (state.loadingNextPage) {
                    item(key = "timeline-loading-more") {
                        Box(
                            Modifier.fillMaxWidth().padding(20.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                } else if (errorMessage != null) {
                    item(key = "timeline-page-error") {
                        TimelineMessage(
                            message = errorMessage,
                            actionLabel = stringResource(R.string.list_retry),
                            onAction = { actionScope.launch { store.loadNextPage() } },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
    }

    val supplementalOverlayVisible = undoState.visible || pendingNewDataForCurrentScope
    SnackbarHost(
        hostState = actionSnackbar,
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .padding(
                start = 16.dp,
                end = 16.dp,
                bottom = bottomOverlayPadding + (if (supplementalOverlayVisible) 88.dp else 20.dp),
            ),
    )

    pendingDownloadChoice?.let { mediaState ->
        AndroidArticleDownloadChooserDialog(
            state = mediaState,
            onSelect = { enclosureId ->
                val articleId = mediaState.audioEnclosures
                    .firstOrNull { it.id == enclosureId }
                    ?.articleId
                    ?: return@AndroidArticleDownloadChooserDialog
                store.requestToggleDownload(articleId, enclosureId)
                pendingDownloadChoice = null
            },
            onDismiss = { pendingDownloadChoice = null },
        )
    }

    if (undoState.visible) {
        Snackbar(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(
                    start = 16.dp,
                    end = 16.dp,
                    top = 20.dp,
                    bottom = bottomOverlayPadding + 20.dp,
                ),
            action = {
                TextButton(
                    onClick = {
                        actionScope.launch {
                            val restoredIds = store.undoScrollover()
                            if (restoredIds.isNotEmpty()) scrolloverTracker.rearm(restoredIds)
                        }
                    },
                ) {
                    Text(stringResource(R.string.action_undo))
                }
            },
        ) {
            val count = undoState.articleIds.size
            Text(
                if (count == 1) "1 article marked as read" else "$count articles marked as read",
            )
        }
    } else if (pendingNewDataForCurrentScope) {
        Button(
            onClick = {
                actionScope.launch {
                    store.adoptPendingNewData(selection, categoryFeedIds)
                }
            },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(
                    start = 16.dp,
                    end = 16.dp,
                    top = 20.dp,
                    bottom = bottomOverlayPadding + 20.dp,
                ),
        ) {
            Text(stringResource(R.string.timeline_new_articles))
        }
    }
    }
}

internal fun View.performFluxConfirmationHaptic() {
    val feedbackConstant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        HapticFeedbackConstants.CONFIRM
    } else {
        HapticFeedbackConstants.VIRTUAL_KEY
    }
    performHapticFeedback(feedbackConstant)
}

internal fun View.performFluxSelectionHaptic() {
    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
}

@Composable
private fun TimelineMessage(
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                message,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (actionLabel != null && onAction != null) {
                Button(onClick = onAction) {
                    Text(actionLabel)
                }
            }
        }
    }
}
