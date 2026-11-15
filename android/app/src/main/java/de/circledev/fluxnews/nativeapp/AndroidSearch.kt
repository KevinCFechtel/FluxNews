package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.FeedIconVariant
import uniffi.flux_uniffi.DownloadOrigin
import uniffi.flux_uniffi.DownloadState
import uniffi.flux_uniffi.Enclosure
import uniffi.flux_uniffi.MediaDownload
import uniffi.flux_uniffi.MediaKind
import uniffi.flux_uniffi.SaveToServiceResult
import uniffi.flux_uniffi.SearchArticlesRequest
import uniffi.flux_uniffi.SearchArticlesResult

private const val ANDROID_SEARCH_PAGE_SIZE = 50
private const val ANDROID_SEARCH_PREFETCH_DISTANCE = 8

internal object AndroidSearchPaginationPolicy {
    fun nextOffset(resultCount: Int, total: Long): Long? =
        resultCount.toLong().takeIf { it < total }

    fun deduplicated(articles: List<ArticleSummary>): List<ArticleSummary> {
        val seen = mutableSetOf<Long>()
        return articles.filter { seen.add(it.id) }
    }
}

internal data class AndroidSearchState(
    val query: String = "",
    val submittedQuery: String = "",
    val results: List<ArticleSummary> = emptyList(),
    val total: Long = 0,
    val hasSearched: Boolean = false,
    val searching: Boolean = false,
    val loadingMore: Boolean = false,
    val errorMessage: String? = null,
    val audioArticleIds: Set<Long> = emptySet(),
    val mediaActionStates: Map<Long, AndroidArticleMediaActionState> = emptyMap(),
    val feedIconVariant: FeedIconVariant? = null,
    val feedIconPngByFeedId: Map<Long, ByteArray> = emptyMap(),
    val requestGeneration: Long = 0,
    val sessionGeneration: Long? = null,
) {
    val canLoadMore: Boolean
        get() = hasSearched && !searching && !loadingMore && errorMessage == null &&
            AndroidSearchPaginationPolicy.nextOffset(results.size, total) != null
}

internal class AndroidSearchStore private constructor(
    private val searchLoader: suspend (Long, SearchArticlesRequest) -> SearchArticlesResult,
    private val readWriter: suspend (Long, Long, Boolean) -> Unit,
    private val starredWriter: suspend (Long, Long, Boolean) -> Unit,
    private val mediaActionStatesLoader: suspend (Long, List<Long>) -> Map<Long, AndroidArticleMediaActionState>,
    private val feedIconLoader: suspend (Long, List<Long>, FeedIconVariant) -> Map<Long, ByteArray>,
    private val minifluxEntryUrlLoader: suspend (Long, Long) -> String,
    private val saveToServiceWriter: suspend (Long, Long) -> AndroidSaveToServiceOutcome,
    private val listeningListWriter: suspend (Long, Long, Boolean) -> Unit,
    private val mediaDownloadWriter: suspend (Long, Long, DownloadState?) -> Unit,
    private val transferReconciler: suspend (Long) -> Unit,
    private val transferRevision: kotlinx.coroutines.flow.StateFlow<Long>?,
    private val activeSessionGeneration: () -> Long?,
) {
    internal constructor(
        coreRuntime: AndroidCoreRuntime,
        transferCoordinator: AndroidMediaTransferCoordinator? = null,
    ) : this(
        searchLoader = { generation, request ->
            coreRuntime.remoteForGeneration(generation) { core -> core.searchArticles(request = request) }
        },
        readWriter = { generation, articleId, read ->
            coreRuntime.remoteForGeneration(generation) { core ->
                core.searchSetReadState(articleId = articleId, read = read)
            }
            Unit
        },
        starredWriter = { generation, articleId, starred ->
            coreRuntime.remoteForGeneration(generation) { core ->
                core.searchSetStarredState(articleId = articleId, starred = starred)
            }
            Unit
        },
        mediaActionStatesLoader = { generation, articleIds ->
            if (articleIds.isEmpty()) emptyMap() else coreRuntime.localForGeneration(generation) { core ->
                core.articleAudioActionStates(articleIds).associate { projection ->
                    val audioEnclosures = projection.enclosures.filter { enclosure ->
                        enclosure.mediaKind == MediaKind.AUDIO
                    }
                    projection.articleId to AndroidArticleMediaActionState(
                        hasAudio = audioEnclosures.isNotEmpty(),
                        isInListeningList = projection.isInListeningList,
                        audioEnclosures = audioEnclosures,
                        downloads = projection.downloads.associateBy { it.enclosureId },
                    )
                }
            }
        },
        feedIconLoader = { generation, feedIds, variant ->
            coreRuntime.remoteForGeneration(generation) { core ->
                feedIds.distinct().mapNotNull { feedId ->
                    core.feedIcon(feedId = feedId, variant = variant)?.pngData?.let { feedId to it }
                }.toMap()
            }
        },
        minifluxEntryUrlLoader = { generation, articleId ->
            coreRuntime.localForGeneration(generation) { core -> core.minifluxEntryUrl(articleId = articleId) }
        },
        saveToServiceWriter = { generation, articleId ->
            when (coreRuntime.remoteForGeneration(generation) { core -> core.saveToService(articleId = articleId) }) {
                SaveToServiceResult.SAVED -> AndroidSaveToServiceOutcome.Saved
                SaveToServiceResult.NO_INTEGRATION_CONFIGURED -> AndroidSaveToServiceOutcome.NoIntegrationConfigured
            }
        },
        listeningListWriter = { generation, articleId, enabled ->
            coreRuntime.localForGeneration(generation) { core ->
                if (enabled) core.addToListeningList(articleId = articleId)
                else core.removeFromListeningList(articleId = articleId)
            }
            if (enabled) {
                transferCoordinator?.requestArtworkProbe(generation, articleId)
            }
            Unit
        },
        mediaDownloadWriter = { generation, enclosureId, state ->
            coreRuntime.localForGeneration(generation) { core ->
                when (state) {
                    null, DownloadState.NOT_DOWNLOADED ->
                        core.requestDownload(enclosureId = enclosureId, origin = DownloadOrigin.MANUAL)
                    DownloadState.REQUESTED ->
                        core.cancelDownload(enclosureId = enclosureId)
                    DownloadState.DOWNLOADED ->
                        core.requestDownloadDeletion(enclosureId = enclosureId)
                    DownloadState.FAILED ->
                        core.retryDownload(enclosureId = enclosureId)
                    DownloadState.DELETE_REQUESTED -> Unit
                }
            }
            Unit
        },
        transferReconciler = { generation ->
            transferCoordinator?.reconcileAndSignal(generation)
        },
        transferRevision = transferCoordinator?.revision,
        activeSessionGeneration = coreRuntime::activeSessionGeneration,
    )

    internal constructor(
        searchLoader: suspend (Long, SearchArticlesRequest) -> SearchArticlesResult,
        readWriter: suspend (Long, Long, Boolean) -> Unit = { _, _, _ -> },
        starredWriter: suspend (Long, Long, Boolean) -> Unit = { _, _, _ -> },
        audioLoader: suspend (Long, List<Long>) -> Set<Long> = { _, _ -> emptySet() },
        mediaActionStatesLoader: suspend (Long, List<Long>) -> Map<Long, AndroidArticleMediaActionState> = { generation, ids ->
            audioLoader(generation, ids).associateWith {
                AndroidArticleMediaActionState(hasAudio = true, isInListeningList = false)
            }
        },
        feedIconLoader: suspend (Long, List<Long>, FeedIconVariant) -> Map<Long, ByteArray> = { _, _, _ -> emptyMap() },
        minifluxEntryUrlLoader: suspend (Long, Long) -> String = { _, id -> "https://example.test/entry/$id" },
        saveToServiceWriter: suspend (Long, Long) -> AndroidSaveToServiceOutcome = { _, _ -> AndroidSaveToServiceOutcome.Saved },
        listeningListWriter: suspend (Long, Long, Boolean) -> Unit = { _, _, _ -> },
        mediaDownloadWriter: suspend (Long, Long, DownloadState?) -> Unit = { _, _, _ -> },
        transferReconciler: suspend (Long) -> Unit = { _ -> },
        transferRevision: kotlinx.coroutines.flow.StateFlow<Long>? = null,
        activeSessionGeneration: () -> Long?,
        @Suppress("UNUSED_PARAMETER") testOnly: Unit,
    ) : this(
        searchLoader,
        readWriter,
        starredWriter,
        mediaActionStatesLoader,
        feedIconLoader,
        minifluxEntryUrlLoader,
        saveToServiceWriter,
        listeningListWriter,
        mediaDownloadWriter,
        transferReconciler,
        transferRevision,
        activeSessionGeneration,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mutationMutex = Mutex()
    private val nextRequestGeneration = AtomicLong(0)
    private val nextMutationToken = AtomicLong(0)
    private val readTokens = ConcurrentHashMap<Long, Long>()
    private val starredTokens = ConcurrentHashMap<Long, Long>()
    private val mutableState = MutableStateFlow(AndroidSearchState())
    private val mutableFeedback = MutableSharedFlow<AndroidTimelineHaptic>(extraBufferCapacity = 8)
    private val mutableActionMessages = MutableSharedFlow<String>(extraBufferCapacity = 8)

    val state = mutableState.asStateFlow()
    val feedback = mutableFeedback.asSharedFlow()
    val actionMessages = mutableActionMessages.asSharedFlow()

    init {
        transferRevision?.let { revisions ->
            scope.launch {
                revisions.collect {
                    refreshVisibleMediaActions()
                }
            }
        }
    }

    fun activateSession(sessionGeneration: Long?) {
        val current = mutableState.value
        if (current.sessionGeneration != null && current.sessionGeneration != sessionGeneration) clear()
        else if (current.sessionGeneration == null && sessionGeneration != null) {
            mutableState.update { it.copy(sessionGeneration = sessionGeneration) }
        }
    }

    fun setQuery(value: String) = mutableState.update { it.copy(query = value) }

    fun clear() {
        val request = nextRequestGeneration.incrementAndGet()
        readTokens.clear()
        starredTokens.clear()
        mutableState.value = AndroidSearchState(requestGeneration = request, sessionGeneration = activeSessionGeneration())
    }

    fun submit(): Job? {
        val query = mutableState.value.query.trim()
        val sessionGeneration = activeSessionGeneration() ?: return null
        if (query.isEmpty()) return null
        val request = nextRequestGeneration.incrementAndGet()
        mutableState.value = AndroidSearchState(
            query = query,
            submittedQuery = query,
            hasSearched = true,
            searching = true,
            requestGeneration = request,
            sessionGeneration = sessionGeneration,
        )
        return scope.launch {
            val result = runCatching {
                searchLoader(sessionGeneration, SearchArticlesRequest(query = query, offset = 0, limit = ANDROID_SEARCH_PAGE_SIZE.toUInt()))
            }
            if (!owns(request, sessionGeneration, query)) return@launch
            result.fold(
                onSuccess = { page ->
                    val results = AndroidSearchPaginationPolicy.deduplicated(page.articles)
                    mutableState.update { state ->
                        if (ownsState(state, request, sessionGeneration, query)) {
                            state.copy(results = results, total = page.total, searching = false, errorMessage = null)
                        } else state
                    }
                    loadMediaActions(request, sessionGeneration, query, results.map { it.id })
                },
                onFailure = {
                    mutableState.update { state ->
                        if (ownsState(state, request, sessionGeneration, query)) state.copy(searching = false, errorMessage = "Search could not be completed.") else state
                    }
                },
            )
        }
    }

    fun retry() {
        val submitted = mutableState.value.submittedQuery
        if (submitted.isBlank()) return
        mutableState.update { it.copy(query = submitted) }
        submit()
    }

    fun retryLoadMore() {
        val current = mutableState.value
        if (current.submittedQuery.isBlank() || current.searching || current.loadingMore) return
        mutableState.update { state ->
            if (
                state.requestGeneration == current.requestGeneration &&
                state.sessionGeneration == current.sessionGeneration &&
                state.submittedQuery == current.submittedQuery
            ) {
                state.copy(errorMessage = null)
            } else {
                state
            }
        }
        loadMore()
    }

    fun loadMore() {
        val current = mutableState.value
        val sessionGeneration = current.sessionGeneration ?: return
        val offset = AndroidSearchPaginationPolicy.nextOffset(current.results.size, current.total) ?: return
        if (!current.canLoadMore || activeSessionGeneration() != sessionGeneration) return
        val request = current.requestGeneration
        val query = current.submittedQuery
        mutableState.update { if (ownsState(it, request, sessionGeneration, query)) it.copy(loadingMore = true) else it }
        scope.launch {
            val result = runCatching {
                searchLoader(sessionGeneration, SearchArticlesRequest(query = query, offset = offset, limit = ANDROID_SEARCH_PAGE_SIZE.toUInt()))
            }
            if (!owns(request, sessionGeneration, query)) return@launch
            result.fold(
                onSuccess = { page ->
                    var appended = emptyList<Long>()
                    mutableState.update { state ->
                        if (!ownsState(state, request, sessionGeneration, query)) return@update state
                        val updated = AndroidSearchPaginationPolicy.deduplicated(state.results + page.articles)
                        appended = updated.drop(state.results.size).map { it.id }
                        state.copy(results = updated, total = page.total, loadingMore = false, errorMessage = null)
                    }
                    loadMediaActions(request, sessionGeneration, query, appended)
                },
                onFailure = {
                    mutableState.update { state ->
                        if (ownsState(state, request, sessionGeneration, query)) state.copy(loadingMore = false, errorMessage = "More search results could not be loaded.") else state
                    }
                },
            )
        }
    }

    fun ensureFeedIcons(variant: FeedIconVariant) {
        val current = mutableState.value
        val sessionGeneration = current.sessionGeneration ?: return
        val request = current.requestGeneration
        val query = current.submittedQuery
        val feedIds = current.results.map { it.feedId }.distinct()
        if (feedIds.isEmpty()) return
        scope.launch {
            val icons = runCatching { feedIconLoader(sessionGeneration, feedIds, variant) }.getOrNull() ?: return@launch
            if (!owns(request, sessionGeneration, query)) return@launch
            mutableState.update { state ->
                if (ownsState(state, request, sessionGeneration, query)) state.copy(feedIconVariant = variant, feedIconPngByFeedId = icons) else state
            }
        }
    }

    fun requestSetRead(articleId: Long, read: Boolean, providesFeedback: Boolean = true) {
        scope.launch { setReadExplicit(articleId, read, providesFeedback) }
    }

    fun requestSetStarred(articleId: Long, starred: Boolean) {
        scope.launch { mutateStarred(articleId, starred) }
    }

    internal suspend fun setReadExplicit(articleId: Long, read: Boolean, providesFeedback: Boolean = true): Boolean {
        val current = mutableState.value
        val article = current.results.firstOrNull { it.id == articleId } ?: return false
        val sessionGeneration = current.sessionGeneration ?: return false
        if (activeSessionGeneration() != sessionGeneration || article.isRead == read) return true
        val request = current.requestGeneration
        val query = current.submittedQuery
        val token = nextMutationToken.incrementAndGet()
        readTokens[articleId] = token
        mutableState.update { state ->
            if (ownsState(state, request, sessionGeneration, query)) state.copy(results = state.results.map { if (it.id == articleId) it.copy(isRead = read) else it }) else state
        }
        val result = runCatching { mutationMutex.withLock { readWriter(sessionGeneration, articleId, read) } }
        if (readTokens[articleId] != token) return result.isSuccess
        readTokens.remove(articleId, token)
        if (!owns(request, sessionGeneration, query)) return result.isSuccess
        if (result.isSuccess) {
            if (providesFeedback && read) mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            return true
        }
        mutableState.update { state ->
            if (!ownsState(state, request, sessionGeneration, query)) return@update state
            state.copy(results = state.results.map { if (it.id == articleId && it.isRead == read) it.copy(isRead = article.isRead) else it })
        }
        mutableActionMessages.emit(if (read) "Article could not be marked as read." else "Article could not be marked as unread.")
        return false
    }

    private suspend fun mutateStarred(articleId: Long, starred: Boolean) {
        val current = mutableState.value
        val article = current.results.firstOrNull { it.id == articleId } ?: return
        val sessionGeneration = current.sessionGeneration ?: return
        if (activeSessionGeneration() != sessionGeneration || article.isStarred == starred) return
        val request = current.requestGeneration
        val query = current.submittedQuery
        val token = nextMutationToken.incrementAndGet()
        starredTokens[articleId] = token
        mutableState.update { state ->
            if (ownsState(state, request, sessionGeneration, query)) state.copy(results = state.results.map { if (it.id == articleId) it.copy(isStarred = starred) else it }) else state
        }
        val result = runCatching { mutationMutex.withLock { starredWriter(sessionGeneration, articleId, starred) } }
        if (starredTokens[articleId] != token) return
        starredTokens.remove(articleId, token)
        if (!owns(request, sessionGeneration, query)) return
        if (result.isSuccess) {
            mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            return
        }
        mutableState.update { state ->
            if (!ownsState(state, request, sessionGeneration, query)) return@update state
            state.copy(results = state.results.map { if (it.id == articleId && it.isStarred == starred) it.copy(isStarred = article.isStarred) else it })
        }
        mutableActionMessages.emit(if (starred) "Article could not be starred." else "Article could not be unstarred.")
    }

    suspend fun resolveMinifluxEntryUrl(articleId: Long): String? {
        val generation = activeSessionGeneration() ?: return null
        return runCatching { minifluxEntryUrlLoader(generation, articleId) }.getOrNull()
            ?.takeIf { activeSessionGeneration() == generation }
    }

    fun requestSaveToService(articleId: Long) {
        val generation = activeSessionGeneration() ?: return
        scope.launch {
            val result = runCatching { saveToServiceWriter(generation, articleId) }
            if (activeSessionGeneration() != generation) return@launch
            result.fold(
                onSuccess = { outcome ->
                    if (outcome == AndroidSaveToServiceOutcome.Saved) {
                        mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
                        mutableActionMessages.emit("Saved to third-party service.")
                    } else mutableActionMessages.emit("No third-party integration is configured.")
                },
                onFailure = { mutableActionMessages.emit("Article could not be saved to the third-party service.") },
            )
        }
    }

    fun requestSetListeningList(articleId: Long, enabled: Boolean) {
        val generation = activeSessionGeneration() ?: return
        scope.launch {
            val result = runCatching {
                listeningListWriter(generation, articleId, enabled)
            }
            if (activeSessionGeneration() != generation) return@launch
            if (result.isSuccess) {
                runCatching { transferReconciler(generation) }
                mutableState.update { state ->
                    val current = state.mediaActionStates[articleId] ?: return@update state
                    state.copy(
                        mediaActionStates = state.mediaActionStates + (
                            articleId to current.copy(isInListeningList = enabled)
                        ),
                    )
                }
                mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
                mutableActionMessages.emit(
                    if (enabled) "Added to Listening List." else "Removed from Listening List.",
                )
            } else {
                mutableActionMessages.emit("Listening List could not be updated.")
            }
        }
    }

    fun requestToggleDownload(articleId: Long, enclosureId: Long) {
        val generation = activeSessionGeneration() ?: return
        val current = mutableState.value.mediaActionStates[articleId] ?: return
        val downloadState = current.downloads[enclosureId]?.state
        scope.launch {
            val result = runCatching {
                mediaDownloadWriter(generation, enclosureId, downloadState)
            }
            if (activeSessionGeneration() != generation) return@launch
            if (result.isSuccess) {
                runCatching { transferReconciler(generation) }
                val refreshed = runCatching {
                    mediaActionStatesLoader(generation, listOf(articleId))[articleId]
                }.getOrNull()
                if (activeSessionGeneration() != generation) return@launch
                if (refreshed != null) {
                    mutableState.update { state ->
                        if (state.sessionGeneration != generation) return@update state
                        state.copy(
                            mediaActionStates = state.mediaActionStates + (articleId to refreshed),
                            audioArticleIds = if (refreshed.hasAudio) {
                                state.audioArticleIds + articleId
                            } else {
                                state.audioArticleIds - articleId
                            },
                        )
                    }
                }
                mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            } else {
                mutableActionMessages.emit("Download action could not be completed.")
            }
        }
    }

    private suspend fun refreshVisibleMediaActions() {
        val current = mutableState.value
        val sessionGeneration = current.sessionGeneration ?: return
        if (
            activeSessionGeneration() != sessionGeneration ||
            current.results.isEmpty() ||
            current.submittedQuery.isBlank()
        ) {
            return
        }
        val request = current.requestGeneration
        val query = current.submittedQuery
        val refreshed = runCatching {
            mediaActionStatesLoader(sessionGeneration, current.results.map { it.id })
        }.getOrNull() ?: return
        if (!owns(request, sessionGeneration, query)) return
        mutableState.update { state ->
            if (!ownsState(state, request, sessionGeneration, query)) return@update state
            state.copy(
                mediaActionStates = refreshed,
                audioArticleIds = refreshed.filterValues { it.hasAudio }.keys,
            )
        }
    }

    private fun loadMediaActions(request: Long, sessionGeneration: Long, query: String, articleIds: List<Long>) {
        if (articleIds.isEmpty()) return
        scope.launch {
            val mediaStates = runCatching {
                mediaActionStatesLoader(sessionGeneration, articleIds)
            }.getOrNull() ?: return@launch
            if (!owns(request, sessionGeneration, query)) return@launch
            mutableState.update { state ->
                if (!ownsState(state, request, sessionGeneration, query)) return@update state
                state.copy(
                    audioArticleIds = state.audioArticleIds + mediaStates.filterValues { it.hasAudio }.keys,
                    mediaActionStates = state.mediaActionStates + mediaStates,
                )
            }
        }
    }

    private fun owns(request: Long, sessionGeneration: Long, query: String): Boolean =
        activeSessionGeneration() == sessionGeneration && ownsState(mutableState.value, request, sessionGeneration, query)

    private fun ownsState(state: AndroidSearchState, request: Long, sessionGeneration: Long, query: String): Boolean =
        state.requestGeneration == request && state.sessionGeneration == sessionGeneration && state.submittedQuery == query
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AndroidSearchDestination(
    store: AndroidSearchStore,
    readerStore: AndroidReaderStore,
    openResolver: AndroidArticleOpenResolver,
    sessionGeneration: Long?,
    onBack: () -> Unit,
    onToggleSidebar: (() -> Unit)? = null,
    sidebarExpanded: Boolean = false,
) {
    val state by store.state.collectAsState()
    val preferences by LocalAndroidArticlePreferences.current.state.collectAsState(initial = AndroidArticlePreferenceState())
    val listState = rememberLazyListState()
    val snackbar = remember { SnackbarHostState() }
    val actionScope = rememberCoroutineScope()
    val context = LocalContext.current
    // Resolve translated UI copy during composition, not through LocalContext in event handlers.
    val badArticleUrlMessage = stringResource(R.string.search_bad_article_url)
    val articleOpenError = stringResource(R.string.audit_article_open)
    val minifluxUrlError = stringResource(R.string.audit_miniflux_url)
    val badCommentsUrlMessage = stringResource(R.string.search_bad_comments_url)
    val shareFailedMessage = stringResource(R.string.search_share_failed)
    val linkCopiedMessage = stringResource(R.string.search_link_copied)
    val view = LocalView.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val searchFocusRequester = remember { FocusRequester() }
    val feedIconVariant = if (isSystemInDarkTheme()) FeedIconVariant.DARK else FeedIconVariant.NORMAL
    val referenceMillis = remember(state.requestGeneration) { System.currentTimeMillis() }
    var pendingDownloadChoice by remember {
        androidx.compose.runtime.mutableStateOf<AndroidArticleMediaActionState?>(null)
    }

    LaunchedEffect(sessionGeneration) { store.activateSession(sessionGeneration) }
    LaunchedEffect(Unit) { searchFocusRequester.requestFocus() }
    LaunchedEffect(state.results.map { it.feedId }, feedIconVariant) { store.ensureFeedIcons(feedIconVariant) }
    LaunchedEffect(store, snackbar, context) { store.actionMessages.collect { snackbar.showSnackbar(context.localizedLegacyUiMessage(it)) } }
    LaunchedEffect(store, view) {
        store.feedback.collect {
            when (it) {
                AndroidTimelineHaptic.Confirmation -> view.performFluxConfirmationHaptic()
                AndroidTimelineHaptic.Selection -> view.performFluxSelectionHaptic()
            }
        }
    }
    LaunchedEffect(listState, state.requestGeneration, state.results.size, state.canLoadMore) {
        if (!state.canLoadMore) return@LaunchedEffect
        snapshotFlow {
            val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1
            last >= (state.results.lastIndex - ANDROID_SEARCH_PREFETCH_DISTANCE).coerceAtLeast(0)
        }.distinctUntilChanged().collect { if (it) store.loadMore() }
    }

    fun submitSearch() {
        if (state.query.isBlank() || state.searching) return
        store.submit()
        keyboardController?.hide()
    }
    fun showMessage(message: String) { actionScope.launch { snackbar.showSnackbar(message) } }
    fun openReader(article: ArticleSummary) {
        store.requestSetRead(article.id, true, providesFeedback = false)
        readerStore.open(article, AndroidReaderSource.Search)
    }
    fun openNormal(article: ArticleSummary) {
        store.requestSetRead(article.id, true, providesFeedback = false)
        if (preferences.openArticle == AndroidArticleOpenPreference.Reader) {
            readerStore.open(article, AndroidReaderSource.Search)
            return
        }
        actionScope.launch {
            when (val destination = openResolver.resolve(article, preferences.openArticle)) {
                AndroidNormalOpenDestination.Reader -> readerStore.open(article, AndroidReaderSource.Search)
                is AndroidNormalOpenDestination.Web -> if (!AndroidArticlePlatformActions.openUrl(context, destination.url)) snackbar.showSnackbar(badArticleUrlMessage)
                null -> snackbar.showSnackbar(articleOpenError)
            }
        }
    }
    fun performSwipe(article: ArticleSummary, action: AndroidArticleSwipeAction) {
        when (action) {
            AndroidArticleSwipeAction.ReadUnread -> store.requestSetRead(article.id, !article.isRead)
            AndroidArticleSwipeAction.StarUnstar -> store.requestSetStarred(article.id, !article.isStarred)
            AndroidArticleSwipeAction.OpenOriginal -> {
                store.requestSetRead(article.id, true, providesFeedback = false)
                if (!AndroidArticlePlatformActions.openUrl(context, article.url)) showMessage(badArticleUrlMessage)
            }
            AndroidArticleSwipeAction.OpenMiniflux -> {
                store.requestSetRead(article.id, true, providesFeedback = false)
                actionScope.launch {
                    val url = store.resolveMinifluxEntryUrl(article.id)
                    if (url == null || !AndroidArticlePlatformActions.openUrl(context, url)) snackbar.showSnackbar(minifluxUrlError)
                }
            }
            AndroidArticleSwipeAction.Comments -> if (!AndroidArticlePlatformActions.openUrl(context, article.commentsUrl)) showMessage(badCommentsUrlMessage)
            AndroidArticleSwipeAction.Share -> if (!AndroidArticlePlatformActions.share(context, article)) showMessage(shareFailedMessage)
            AndroidArticleSwipeAction.SaveToService -> store.requestSaveToService(article.id)
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
    fun performContext(article: ArticleSummary, action: AndroidArticleContextAction) {
        when (action) {
            AndroidArticleContextAction.ReadUnread -> performSwipe(article, AndroidArticleSwipeAction.ReadUnread)
            AndroidArticleContextAction.StarUnstar -> performSwipe(article, AndroidArticleSwipeAction.StarUnstar)
            AndroidArticleContextAction.OpenOriginal -> performSwipe(article, AndroidArticleSwipeAction.OpenOriginal)
            AndroidArticleContextAction.Reader -> openReader(article)
            AndroidArticleContextAction.OpenMiniflux -> performSwipe(article, AndroidArticleSwipeAction.OpenMiniflux)
            AndroidArticleContextAction.Comments -> performSwipe(article, AndroidArticleSwipeAction.Comments)
            AndroidArticleContextAction.CopyLink -> if (AndroidArticlePlatformActions.copyLink(context, article)) showMessage(linkCopiedMessage) else showMessage(badArticleUrlMessage)
            AndroidArticleContextAction.Share -> performSwipe(article, AndroidArticleSwipeAction.Share)
            AndroidArticleContextAction.SaveToService -> performSwipe(article, AndroidArticleSwipeAction.SaveToService)
            AndroidArticleContextAction.ListeningList -> performSwipe(article, AndroidArticleSwipeAction.ListeningList)
            AndroidArticleContextAction.DownloadAudio -> performSwipe(article, AndroidArticleSwipeAction.DownloadAudio)
        }
    }

    Box(Modifier.fillMaxSize()) {
        Scaffold(
            snackbarHost = { SnackbarHost(snackbar) },
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.nav_search)) },
                    navigationIcon = {
                        if (!sidebarExpanded) IconButton(onClick = onToggleSidebar ?: onBack) {
                            Icon(
                                painter = painterResource(if (onToggleSidebar != null) R.drawable.ic_sidebar_toggle else R.drawable.ic_arrow_back),
                                contentDescription = if (onToggleSidebar != null) stringResource(R.string.nav_toggle) else stringResource(R.string.search_back_news),
                            )
                        }
                    },
                )
            },
        ) { padding ->
            AndroidCenteredContent(
                maxWidth = AndroidSecondaryContentMaxWidth,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) { contentModifier ->
            Column(contentModifier) {
                TextField(
                    value = state.query,
                    onValueChange = store::setQuery,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .focusRequester(searchFocusRequester),
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.search_articles_hint)) },
                    leadingIcon = {
                        IconButton(
                            onClick = ::submitSearch,
                            enabled = state.query.isNotBlank() && !state.searching,
                        ) {
                            Icon(
                                painter = painterResource(R.drawable.ic_search),
                                contentDescription = stringResource(R.string.nav_search),
                            )
                        }
                    },
                    trailingIcon = {
                        when {
                            state.searching -> CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                            )
                            state.query.isNotBlank() -> IconButton(
                                onClick = store::clear,
                            ) {
                                Icon(
                                    painter = painterResource(R.drawable.ic_close),
                                    contentDescription = stringResource(R.string.search_clear),
                                )
                            }
                        }
                    },
                    shape = RoundedCornerShape(18.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.52f),
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent,
                        errorIndicatorColor = Color.Transparent,
                    ),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { submitSearch() }),
                )
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val availableWidth = (maxWidth - 32.dp).coerceAtLeast(0.dp)
                    val availableWidthDp = availableWidth.value.toInt()
                    when {
                        !state.hasSearched -> SearchMessage(
                            title = stringResource(R.string.search_articles_hint),
                            message = stringResource(R.string.search_intro),
                            modifier = Modifier.fillMaxSize(),
                            showSearchIcon = true,
                        )
                        state.searching && state.results.isEmpty() -> Box(
                            Modifier.fillMaxSize(),
                        )
                        state.errorMessage != null && state.results.isEmpty() -> SearchMessage(
                            title = stringResource(R.string.search_unavailable),
                            message = state.errorMessage?.let(context::localizedLegacyUiMessage) ?: stringResource(R.string.search_failed),
                            modifier = Modifier.fillMaxSize(),
                            actionLabel = stringResource(R.string.list_retry),
                            onAction = store::retry,
                        )
                        state.results.isEmpty() -> SearchMessage(
                            title = stringResource(R.string.search_no_results),
                            message = stringResource(R.string.search_try_different),
                            modifier = Modifier.fillMaxSize(),
                            showSearchIcon = true,
                        )
                        else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                            items(
                                items = state.results,
                                key = { it.id },
                                contentType = { article -> AndroidArticleRowPolicy.layoutVariant(preferences.presentationMode, article.imageUrl, availableWidthDp) },
                            ) { article ->
                                val hasAudio = article.id in state.audioArticleIds
                                AndroidArticleSwipeContainer(
                                    article = article,
                                    hasAudio = hasAudio,
                                    configuration = preferences.swipeConfiguration,
                                    mediaActionsEnabled = true,
                                    mediaState = state.mediaActionStates[article.id],
                                    rowWidth = maxWidth,
                                    onOpen = { openNormal(article) },
                                    onSwipeAction = { performSwipe(article, it) },
                                    onContextAction = { performContext(article, it) },
                                ) {
                                    AndroidArticleTimelineRow(
                                        article = article,
                                        hasAudio = hasAudio,
                                        preferences = preferences,
                                        publicationReferenceMillis = referenceMillis,
                                        feedIconPng = state.feedIconPngByFeedId[article.feedId],
                                        feedIconVariant = feedIconVariant,
                                        availableWidth = availableWidth,
                                        onRequestFeedIcon = { _, _ -> store.ensureFeedIcons(feedIconVariant) },
                                    )
                                }
                            }
                            if (state.loadingMore) item("search-loading-more") {
                                Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                            } else if (state.errorMessage != null) item("search-page-error") {
                                SearchMessage(
                                    title = stringResource(R.string.search_more_unavailable),
                                    message = state.errorMessage?.let(context::localizedLegacyUiMessage) ?: stringResource(R.string.audit_search_more_load),
                                    modifier = Modifier.fillMaxWidth(),
                                    actionLabel = stringResource(R.string.list_retry),
                                    onAction = store::retryLoadMore,
                                )
                            }
                        }
                    }
                }
            }
            }
        }
        pendingDownloadChoice?.let { mediaState ->
            AndroidArticleDownloadChooserDialog(
                state = mediaState,
                onSelect = { enclosureId ->
                    val articleId = mediaState.audioEnclosures
                        .firstOrNull { it.id == enclosureId }
                        ?.articleId
                    if (articleId != null) {
                        store.requestToggleDownload(articleId, enclosureId)
                    }
                    pendingDownloadChoice = null
                },
                onDismiss = { pendingDownloadChoice = null },
            )
        }
        AndroidArticleReaderOverlay(
            store = readerStore,
            source = AndroidReaderSource.Search,
            onOpenOriginal = { article ->
                if (!AndroidArticlePlatformActions.openUrl(context, article.url)) showMessage(badArticleUrlMessage)
            },
        )
    }
}

@Composable
private fun SearchMessage(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    showSearchIcon: Boolean = false,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(32.dp),
        ) {
            if (showSearchIcon) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.72f),
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                ) {
                    Box(
                        modifier = Modifier.size(56.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            painter = painterResource(R.drawable.ic_search),
                            contentDescription = null,
                            modifier = Modifier.size(28.dp),
                        )
                    }
                }
            }
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (actionLabel != null && onAction != null) {
                TextButton(onClick = onAction) { Text(actionLabel) }
            }
        }
    }
}
