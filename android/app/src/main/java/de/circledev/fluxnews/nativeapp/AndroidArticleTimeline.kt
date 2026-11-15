package de.circledev.fluxnews.nativeapp

import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.ArticleCursor
import uniffi.flux_uniffi.ArticlePage
import uniffi.flux_uniffi.ArticleQuery
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.CoreEvent
import uniffi.flux_uniffi.DownloadOrigin
import uniffi.flux_uniffi.DownloadState
import uniffi.flux_uniffi.Enclosure
import uniffi.flux_uniffi.FeedIconVariant
import uniffi.flux_uniffi.MediaDownload
import uniffi.flux_uniffi.MediaKind
import uniffi.flux_uniffi.SaveToServiceResult
import uniffi.flux_uniffi.SyncReason

private const val ANDROID_FEED_ICON_RETRY_DELAY_MILLIS = 1_000L
private const val ANDROID_FEED_ICON_MAX_ATTEMPTS = 3
private const val ANDROID_SCROLL_OVER_UNDO_INACTIVITY_MILLIS = 4_000L
private const val ANDROID_SCROLL_OVER_UNDO_MAX_LIFETIME_MILLIS = 15_000L
private const val ANDROID_SCROLL_OVER_UNDO_QUALIFICATION_MILLIS = 1_000L
private const val ANDROID_SCROLL_OVER_UNDO_MIN_READS = 3
private const val ANDROID_SCROLL_OVER_MUTATION_BATCH_SIZE = 32

internal enum class AndroidTimelineHaptic {
    Confirmation,
    Selection,
}

internal sealed interface AndroidScrolloverMutationRequest {
    data class MarkRead(
        val articleIds: List<Long>,
        val queryGeneration: Long? = null,
    ) : AndroidScrolloverMutationRequest

    data class CompleteInteraction(
        val queryGeneration: Long? = null,
    ) : AndroidScrolloverMutationRequest
}

internal suspend fun consumeAndroidScrolloverMutationRequests(
    requests: ReceiveChannel<AndroidScrolloverMutationRequest>,
    markRead: suspend (List<Long>) -> List<Long>,
    rearm: (Collection<Long>) -> Unit,
    completeInteraction: () -> Unit,
) {
    for (request in requests) {
        when (request) {
            is AndroidScrolloverMutationRequest.MarkRead -> {
                val failed = markRead(request.articleIds)
                if (failed.isNotEmpty()) rearm(failed)
            }
            is AndroidScrolloverMutationRequest.CompleteInteraction -> completeInteraction()
        }
    }
}

internal data class AndroidScrolloverUndoState(
    val articleIds: List<Long> = emptyList(),
    val revision: Long = 0,
    val expiresAtUptimeMillis: Long? = null,
) {
    val visible: Boolean
        get() = articleIds.size >= ANDROID_SCROLL_OVER_UNDO_MIN_READS
}


internal data class AndroidArticleRowPresentation(
    val isRead: Boolean,
    val isStarred: Boolean,
    val revision: Long = 0L,
)

internal data class AndroidArticleMediaActionState(
    val hasAudio: Boolean,
    val isInListeningList: Boolean,
    val audioEnclosures: List<Enclosure> = emptyList(),
    val downloads: Map<Long, MediaDownload> = emptyMap(),
)

internal data class AndroidArticleTimelineContentState(
    val selection: AndroidArticleTimelineSelection? = null,
    val articles: List<ArticleSummary> = emptyList(),
    val audioArticleIds: Set<Long> = emptySet(),
    val mediaActionStates: Map<Long, AndroidArticleMediaActionState> = emptyMap(),
    val feedIconVariant: FeedIconVariant? = null,
    val feedIconPngByFeedId: Map<Long, ByteArray> = emptyMap(),
    val nextCursor: ArticleCursor? = null,
    val initialLoading: Boolean = false,
    val loadingNextPage: Boolean = false,
    val errorMessage: String? = null,
    val queryGeneration: Long = 0,
    val sessionGeneration: Long? = null,
    val pendingNewFeedIds: Set<Long> = emptySet(),
    val hasUnscopedNewDataSignal: Boolean = false,
) {
    val empty: Boolean
        get() = !initialLoading && articles.isEmpty() && errorMessage == null
}

internal data class AndroidArticleTimelineState(
    val selection: AndroidArticleTimelineSelection? = null,
    val articles: List<ArticleSummary> = emptyList(),
    val audioArticleIds: Set<Long> = emptySet(),
    val mediaActionStates: Map<Long, AndroidArticleMediaActionState> = emptyMap(),
    val feedIconVariant: FeedIconVariant? = null,
    val feedIconPngByFeedId: Map<Long, ByteArray> = emptyMap(),
    val total: ULong? = null,
    val nextCursor: ArticleCursor? = null,
    val initialLoading: Boolean = false,
    val loadingNextPage: Boolean = false,
    val errorMessage: String? = null,
    val queryGeneration: Long = 0,
    val sessionGeneration: Long? = null,
    val pendingNewFeedIds: Set<Long> = emptySet(),
    val hasUnscopedNewDataSignal: Boolean = false,
) {
    val empty: Boolean
        get() = !initialLoading && articles.isEmpty() && errorMessage == null

    fun contentState(): AndroidArticleTimelineContentState =
        AndroidArticleTimelineContentState(
            selection = selection,
            articles = articles,
            audioArticleIds = audioArticleIds,
            mediaActionStates = mediaActionStates,
            feedIconVariant = feedIconVariant,
            feedIconPngByFeedId = feedIconPngByFeedId,
            nextCursor = nextCursor,
            initialLoading = initialLoading,
            loadingNextPage = loadingNextPage,
            errorMessage = errorMessage,
            queryGeneration = queryGeneration,
            sessionGeneration = sessionGeneration,
            pendingNewFeedIds = pendingNewFeedIds,
            hasUnscopedNewDataSignal = hasUnscopedNewDataSignal,
        )
}

/**
 * Owns only the visible Timeline snapshot/paging lifecycle. Article records remain Core read models
 * and all synchronous Core work runs through AndroidCoreRuntime's bounded local lane.
 */
internal class AndroidArticleTimelineStore private constructor(
    private val pageLoader: suspend (ArticleQuery, Boolean) -> ArticlePage,
    private val mediaActionStatesLoader: suspend (List<Long>) -> Map<Long, AndroidArticleMediaActionState>,
    private val selectionCountLoader: suspend (ArticleQuery) -> ULong,
    private val feedIconLoader: suspend (List<Long>, FeedIconVariant) -> Map<Long, ByteArray>,
    private val scrolloverReadWriter: suspend (Long, List<Long>) -> Unit,
    private val scrolloverUnreadWriter: suspend (Long, List<Long>) -> Unit,
    private val explicitReadWriter: suspend (Long, Long, Boolean) -> Unit,
    private val explicitStarredWriter: suspend (Long, Long, Boolean) -> Unit,
    private val scopeUnreadIdsLoader: suspend (Long, ArticleQuery) -> List<Long>,
    private val scopeReadWriter: suspend (Long, List<Long>) -> Unit,
    private val minifluxEntryUrlLoader: suspend (Long, Long) -> String,
    private val saveToServiceWriter: suspend (Long, Long) -> AndroidSaveToServiceOutcome,
    private val listeningListWriter: suspend (Long, Long, Boolean) -> Unit,
    private val mediaDownloadWriter: suspend (Long, Long, DownloadState?) -> Unit,
    private val transferReconciler: suspend (Long) -> Unit,
    private val transferRevision: StateFlow<Long>?,
    private val activeSessionGeneration: () -> Long?,
    private val monotonicMillis: () -> Long,
) {
    internal constructor(
        coreRuntime: AndroidCoreRuntime,
        transferCoordinator: AndroidMediaTransferCoordinator? = null,
    ) : this(
        pageLoader = { query, includeTotal ->
            coreRuntime.local { core -> core.articlePage(query, includeTotal) }
        },
        mediaActionStatesLoader = { articleIds ->
            if (articleIds.isEmpty()) {
                emptyMap()
            } else {
                coreRuntime.local { core ->
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
            }
        },
        selectionCountLoader = { query ->
            coreRuntime.local { core -> core.countArticles(query) }
        },
        feedIconLoader = { feedIds, variant ->
            coreRuntime.remote { core ->
                feedIds.distinct().mapNotNull { feedId ->
                    core.feedIcon(feedId = feedId, variant = variant)
                        ?.pngData
                        ?.let { png -> feedId to png }
                }.toMap()
            }
        },
        scrolloverReadWriter = { generation, articleIds ->
            coreRuntime.localForGeneration(generation) { core ->
                core.setReadStateBulk(articleIds = articleIds, read = true)
            }
            Unit
        },
        scrolloverUnreadWriter = { generation, articleIds ->
            coreRuntime.localForGeneration(generation) { core ->
                core.setReadStateBulk(articleIds = articleIds, read = false)
            }
            Unit
        },
        explicitReadWriter = { generation, articleId, read ->
            coreRuntime.localForGeneration(generation) { core ->
                core.setReadState(articleId = articleId, read = read)
            }
            Unit
        },
        explicitStarredWriter = { generation, articleId, starred ->
            coreRuntime.localForGeneration(generation) { core ->
                core.setStarredState(articleId = articleId, starred = starred)
            }
            Unit
        },
        scopeUnreadIdsLoader = { generation, query ->
            coreRuntime.localForGeneration(generation) { core ->
                core.queryArticles(query).map { it.id }
            }
        },
        scopeReadWriter = { generation, articleIds ->
            coreRuntime.localForGeneration(generation) { core ->
                core.setReadStateBulk(articleIds = articleIds, read = true)
            }
            Unit
        },
        minifluxEntryUrlLoader = { generation, articleId ->
            coreRuntime.localForGeneration(generation) { core ->
                core.minifluxEntryUrl(articleId = articleId)
            }
        },
        saveToServiceWriter = { generation, articleId ->
            when (
                coreRuntime.remoteForGeneration(generation) { core ->
                    core.saveToService(articleId = articleId)
                }
            ) {
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
        monotonicMillis = SystemClock::elapsedRealtime,
    )

    internal constructor(
        pageLoader: suspend (ArticleQuery, Boolean) -> ArticlePage,
        activeSessionGeneration: () -> Long?,
        audioArticleIdsLoader: suspend (List<Long>) -> Set<Long> = { emptySet() },
        mediaActionStatesLoader: suspend (List<Long>) -> Map<Long, AndroidArticleMediaActionState> = { ids ->
            audioArticleIdsLoader(ids).associateWith {
                AndroidArticleMediaActionState(hasAudio = true, isInListeningList = false)
            }
        },
        selectionCountLoader: suspend (ArticleQuery) -> ULong = { 0uL },
        feedIconLoader: suspend (List<Long>, FeedIconVariant) -> Map<Long, ByteArray> = { _, _ -> emptyMap() },
        scrolloverReadWriter: suspend (Long, List<Long>) -> Unit = { _, _ -> },
        scrolloverUnreadWriter: suspend (Long, List<Long>) -> Unit = { _, _ -> },
        explicitReadWriter: suspend (Long, Long, Boolean) -> Unit = { _, _, _ -> },
        explicitStarredWriter: suspend (Long, Long, Boolean) -> Unit = { _, _, _ -> },
        scopeUnreadIdsLoader: suspend (Long, ArticleQuery) -> List<Long> = { _, _ -> emptyList() },
        scopeReadWriter: suspend (Long, List<Long>) -> Unit = { _, _ -> },
        minifluxEntryUrlLoader: suspend (Long, Long) -> String = { _, articleId ->
            "https://example.test/miniflux/entry/$articleId"
        },
        saveToServiceWriter: suspend (Long, Long) -> AndroidSaveToServiceOutcome = { _, _ ->
            AndroidSaveToServiceOutcome.Saved
        },
        listeningListWriter: suspend (Long, Long, Boolean) -> Unit = { _, _, _ -> },
        mediaDownloadWriter: suspend (Long, Long, DownloadState?) -> Unit = { _, _, _ -> },
        transferReconciler: suspend (Long) -> Unit = { _ -> },
        transferRevision: StateFlow<Long>? = null,
        monotonicMillis: () -> Long = { System.nanoTime() / 1_000_000L },
        @Suppress("UNUSED_PARAMETER") testOnly: Unit,
    ) : this(
        pageLoader,
        mediaActionStatesLoader,
        selectionCountLoader,
        feedIconLoader,
        scrolloverReadWriter,
        scrolloverUnreadWriter,
        explicitReadWriter,
        explicitStarredWriter,
        scopeUnreadIdsLoader,
        scopeReadWriter,
        minifluxEntryUrlLoader,
        saveToServiceWriter,
        listeningListWriter,
        mediaDownloadWriter,
        transferReconciler,
        transferRevision,
        activeSessionGeneration,
        monotonicMillis,
    )

    private val mutableState = MutableStateFlow(AndroidArticleTimelineState())
    private val mutableFeedback = MutableSharedFlow<AndroidTimelineHaptic>(extraBufferCapacity = 8)
    private val mutableActionMessages = MutableSharedFlow<String>(extraBufferCapacity = 8)
    private val mutableScrollResetRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private val mutableScrolloverRearmRequests = MutableSharedFlow<List<Long>>(extraBufferCapacity = 8)
    private val mutableUndoState = MutableStateFlow(AndroidScrolloverUndoState())
    private val explicitActionScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val scrolloverMutationScope = CoroutineScope(
        SupervisorJob() + Dispatchers.Default.limitedParallelism(1),
    )
    private val scrolloverMutationRequests = Channel<AndroidScrolloverMutationRequest>(capacity = Channel.UNLIMITED)
    private val articleIndexById = ConcurrentHashMap<Long, Int>()
    private val rowPresentationById = ConcurrentHashMap<Long, MutableStateFlow<AndroidArticleRowPresentation>>()
    private val explicitMutationMutex = Mutex()
    private val nextExplicitMutationToken = AtomicLong(0)
    private val explicitReadMutationTokens = ConcurrentHashMap<Long, Long>()
    private val explicitStarredMutationTokens = ConcurrentHashMap<Long, Long>()
    private val expectedReadEvents = ConcurrentHashMap<Long, ConcurrentLinkedQueue<Boolean>>()
    private val expectedStarredEvents = ConcurrentHashMap<Long, ConcurrentLinkedQueue<Boolean>>()
    private val expectedBulkReadEventIds = ConcurrentHashMap.newKeySet<Long>()
    private val scrolloverRetainedReadIds = ConcurrentHashMap.newKeySet<Long>()
    private val undoFeedbackSuppressedUnreadIds = ConcurrentHashMap.newKeySet<Long>()
    private val pendingSuccessfulScrolloverUndoIds = mutableListOf<Long>()
    private val recentSuccessfulScrolloverReads = mutableListOf<Pair<Long, Long>>()
    private var scrolloverUndoOpenedAtUptimeMillis: Long? = null
    private var scrolloverUndoLastSuccessAtUptimeMillis: Long? = null
    private var scrolloverConfirmationPending = false
    private val feedIconCacheByVariant = mutableMapOf<FeedIconVariant, MutableMap<Long, ByteArray>>()
    private val unavailableFeedIconsByVariant = mutableMapOf<FeedIconVariant, MutableSet<Long>>()
    private val feedIconRequestsInFlight = mutableSetOf<Pair<Long, FeedIconVariant>>()
    private var requestGeneration = 0L

    init {
        transferRevision?.let { revisions ->
            explicitActionScope.launch {
                revisions.collect {
                    refreshVisibleMediaActions()
                }
            }
        }
        scrolloverMutationScope.launch {
            for (request in scrolloverMutationRequests) {
                when (request) {
                    is AndroidScrolloverMutationRequest.MarkRead -> {
                        val currentGeneration = mutableState.value.queryGeneration
                        if (
                            request.queryGeneration != null &&
                            request.queryGeneration != currentGeneration
                        ) {
                            continue
                        }

                        val combined = linkedSetOf<Long>()
                        combined.addAll(request.articleIds)
                        var completeInteraction = false
                        while (combined.size < ANDROID_SCROLL_OVER_MUTATION_BATCH_SIZE) {
                            val next = scrolloverMutationRequests.tryReceive().getOrNull() ?: break
                            when (next) {
                                is AndroidScrolloverMutationRequest.MarkRead -> {
                                    if (
                                        next.queryGeneration == null ||
                                        next.queryGeneration == currentGeneration
                                    ) {
                                        combined.addAll(next.articleIds)
                                    }
                                }
                                is AndroidScrolloverMutationRequest.CompleteInteraction -> {
                                    if (
                                        next.queryGeneration == null ||
                                        next.queryGeneration == currentGeneration
                                    ) {
                                        completeInteraction = true
                                    }
                                    break
                                }
                            }
                        }

                        val failed = markReadFromScrollover(combined.toList())
                        if (failed.isNotEmpty()) mutableScrolloverRearmRequests.tryEmit(failed)
                        if (completeInteraction) completeScrolloverInteraction()
                    }
                    is AndroidScrolloverMutationRequest.CompleteInteraction -> {
                        if (
                            request.queryGeneration == null ||
                            request.queryGeneration == mutableState.value.queryGeneration
                        ) {
                            completeScrolloverInteraction()
                        }
                    }
                }
            }
        }
    }

    val state = mutableState.asStateFlow()
    val contentState: StateFlow<AndroidArticleTimelineContentState> =
        mutableState
            .map(AndroidArticleTimelineState::contentState)
            .stateIn(
                scope = explicitActionScope,
                started = SharingStarted.Eagerly,
                initialValue = mutableState.value.contentState(),
            )
    val feedback = mutableFeedback.asSharedFlow()
    val actionMessages = mutableActionMessages.asSharedFlow()
    val scrollResetRequests = mutableScrollResetRequests.asSharedFlow()
    val scrolloverRearmRequests = mutableScrolloverRearmRequests.asSharedFlow()
    val undoState = mutableUndoState.asStateFlow()

    fun rowPresentationState(article: ArticleSummary): StateFlow<AndroidArticleRowPresentation> =
        rowPresentationById.computeIfAbsent(article.id) {
            MutableStateFlow(
                AndroidArticleRowPresentation(
                    isRead = article.isRead,
                    isStarred = article.isStarred,
                ),
            )
        }

    internal fun rowPresentationForTesting(articleId: Long): AndroidArticleRowPresentation? =
        rowPresentationById[articleId]?.value

    fun enqueueScrolloverCandidates(articleIds: List<Long>) {
        if (articleIds.isEmpty()) return
        scrolloverMutationRequests.trySend(
            AndroidScrolloverMutationRequest.MarkRead(
                articleIds = articleIds,
                queryGeneration = mutableState.value.queryGeneration,
            ),
        )
    }

    fun enqueueScrolloverInteractionComplete() {
        scrolloverMutationRequests.trySend(
            AndroidScrolloverMutationRequest.CompleteInteraction(
                queryGeneration = mutableState.value.queryGeneration,
            ),
        )
    }

    fun retainedSelectionForSession(sessionGeneration: Long?): AndroidArticleTimelineSelection? =
        mutableState.value
            .takeIf { it.sessionGeneration == sessionGeneration }
            ?.selection

    fun requestSetRead(
        articleId: Long,
        read: Boolean,
        removeWhenRead: Boolean,
        providesFeedback: Boolean = true,
    ) {
        explicitActionScope.launch {
            setReadExplicit(
                articleId = articleId,
                read = read,
                removeWhenRead = removeWhenRead,
                providesFeedback = providesFeedback,
            )
        }
    }

    internal suspend fun setReadExplicit(
        articleId: Long,
        read: Boolean,
        removeWhenRead: Boolean,
        providesFeedback: Boolean = true,
    ): Boolean {
        val current = mutableState.value
        val selection = current.selection ?: return false
        val sessionGeneration = current.sessionGeneration ?: return false
        if (activeSessionGeneration() != sessionGeneration) return false
        val articleIndex = articleIndexById[articleId] ?: return false
        if (current.articles.getOrNull(articleIndex)?.id != articleId) return false
        val previous = rowPresentationById[articleId]?.value?.isRead ?: return false
        if (previous == read) return true

        val token = nextExplicitMutationToken.incrementAndGet()
        explicitReadMutationTokens[articleId] = token
        expectedReadEvents.computeIfAbsent(articleId) { ConcurrentLinkedQueue() }.add(read)
        val generation = current.queryGeneration
        setRowRead(articleId, read)
        if (selection.readFilter == AndroidArticleReadFilter.Unread) {
            mutableState.update { state ->
                if (
                    state.queryGeneration != generation ||
                    state.selection != selection ||
                    state.sessionGeneration != sessionGeneration
                ) {
                    return@update state
                }
                val adjustedTotal = adjustedReadTotal(
                    total = state.total,
                    selection = selection,
                    previous = previous,
                    requested = read,
                )
                if (adjustedTotal == state.total) state else state.copy(total = adjustedTotal)
            }
        }

        val result = runCatching {
            explicitMutationMutex.withLock {
                explicitReadWriter(sessionGeneration, articleId, read)
            }
        }
        if (result.isFailure) {
            discardExpectedEvent(expectedReadEvents, articleId, read)
        }
        if (activeSessionGeneration() != sessionGeneration) return result.isSuccess
        if (explicitReadMutationTokens[articleId] != token) return result.isSuccess
        explicitReadMutationTokens.remove(articleId, token)
        if (!owns(generation, selection, sessionGeneration)) return result.isSuccess

        if (result.isSuccess) {
            if (
                read &&
                removeWhenRead &&
                selection.readFilter == AndroidArticleReadFilter.Unread
            ) {
                removeArticleFromVisibleState(
                    articleId = articleId,
                    selection = selection,
                    generation = generation,
                    sessionGeneration = sessionGeneration,
                )
            }
            refreshSelectionTotal(selection, generation, sessionGeneration)
            if (previous && !read) {
                mutableScrolloverRearmRequests.tryEmit(listOf(articleId))
            }
            if (providesFeedback && !previous && read) {
                mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            }
            return true
        }

        if (owns(generation, selection, sessionGeneration)) {
            val presentation = rowPresentationById[articleId]?.value
            if (presentation?.isRead == read) setRowRead(articleId, previous)
        }
        refreshSelectionTotal(selection, generation, sessionGeneration)
        mutableActionMessages.emit(
            if (read) "Article could not be marked as read." else "Article could not be marked as unread.",
        )
        return false
    }

    fun requestSetStarred(articleId: Long, starred: Boolean) {
        explicitActionScope.launch { setStarredExplicit(articleId, starred) }
    }

    internal suspend fun setStarredExplicit(articleId: Long, starred: Boolean): Boolean {
        val current = mutableState.value
        val selection = current.selection ?: return false
        val sessionGeneration = current.sessionGeneration ?: return false
        if (activeSessionGeneration() != sessionGeneration) return false
        val articleIndex = articleIndexById[articleId] ?: return false
        if (current.articles.getOrNull(articleIndex)?.id != articleId) return false
        val previous = rowPresentationById[articleId]?.value?.isStarred ?: return false
        if (previous == starred) return true

        val token = nextExplicitMutationToken.incrementAndGet()
        explicitStarredMutationTokens[articleId] = token
        expectedStarredEvents.computeIfAbsent(articleId) { ConcurrentLinkedQueue() }.add(starred)
        val generation = current.queryGeneration
        setRowStarred(articleId, starred)
        mutableState.update { state ->
            if (
                state.queryGeneration != generation ||
                state.selection != selection ||
                state.sessionGeneration != sessionGeneration
            ) {
                return@update state
            }
            state.copy(
                total = adjustedStarredTotal(
                    total = state.total,
                    selection = selection,
                    previous = previous,
                    requested = starred,
                ),
            )
        }

        val result = runCatching {
            explicitMutationMutex.withLock {
                explicitStarredWriter(sessionGeneration, articleId, starred)
            }
        }
        if (result.isFailure) {
            discardExpectedEvent(expectedStarredEvents, articleId, starred)
        }
        if (activeSessionGeneration() != sessionGeneration) return result.isSuccess
        if (explicitStarredMutationTokens[articleId] != token) return result.isSuccess
        explicitStarredMutationTokens.remove(articleId, token)
        if (!owns(generation, selection, sessionGeneration)) return result.isSuccess

        if (result.isSuccess) {
            if (!starred && selection.scope == AndroidNewsScope.Starred) {
                removeArticleFromVisibleState(
                    articleId = articleId,
                    selection = selection,
                    generation = generation,
                    sessionGeneration = sessionGeneration,
                )
            }
            if (selection.scope == AndroidNewsScope.Starred) {
                refreshSelectionTotal(selection, generation, sessionGeneration)
            }
            mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            return true
        }

        if (owns(generation, selection, sessionGeneration)) {
            val presentation = rowPresentationById[articleId]?.value
            if (presentation?.isStarred == starred) setRowStarred(articleId, previous)
        }
        if (selection.scope == AndroidNewsScope.Starred) {
            refreshSelectionTotal(selection, generation, sessionGeneration)
        }
        mutableActionMessages.emit(
            if (starred) "Article could not be starred." else "Article could not be unstarred.",
        )
        return false
    }

    suspend fun markCurrentScopeAsRead(reloadCurrentScope: Boolean = true): Boolean {
        val current = mutableState.value
        val selection = current.selection ?: return false
        if (
            selection.scope != AndroidNewsScope.All &&
            selection.scope !is AndroidNewsScope.Category &&
            selection.scope !is AndroidNewsScope.Feed
        ) {
            return false
        }
        val sessionGeneration = current.sessionGeneration ?: return false
        if (activeSessionGeneration() != sessionGeneration) return false
        val generation = current.queryGeneration

        val ids = try {
            scopeUnreadIdsLoader(sessionGeneration, selection.markAllReadQuery()).distinct()
        } catch (_: Exception) {
            if (owns(generation, selection, sessionGeneration)) {
                mutableActionMessages.emit("Unread articles could not be loaded.")
            }
            return false
        }
        if (!owns(generation, selection, sessionGeneration)) return false
        if (ids.isEmpty()) return true

        expectedBulkReadEventIds.addAll(ids)
        val mutation = runCatching {
            explicitMutationMutex.withLock {
                scopeReadWriter(sessionGeneration, ids)
            }
        }
        if (mutation.isFailure) {
            expectedBulkReadEventIds.removeAll(ids.toSet())
        }
        if (!owns(generation, selection, sessionGeneration)) return false

        if (mutation.isFailure) {
            mutableActionMessages.emit("Articles could not be marked as read.")
            return false
        }

        if (reloadCurrentScope) {
            reset(selection)
            mutableScrollResetRequests.tryEmit(Unit)
        }
        mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
        mutableActionMessages.emit("All unread articles in this scope were marked as read.")
        return true
    }

    suspend fun resolveMinifluxEntryUrl(articleId: Long): String? {
        val generation = activeSessionGeneration() ?: return null
        val result = runCatching { minifluxEntryUrlLoader(generation, articleId) }.getOrNull()
        return result?.takeIf { activeSessionGeneration() == generation }
    }

    fun requestSaveToService(articleId: Long) {
        val generation = activeSessionGeneration() ?: return
        explicitActionScope.launch {
            val result = runCatching { saveToServiceWriter(generation, articleId) }
            if (activeSessionGeneration() != generation) return@launch
            result.fold(
                onSuccess = { outcome ->
                    when (outcome) {
                        AndroidSaveToServiceOutcome.Saved -> {
                            mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
                            mutableActionMessages.emit("Saved to third-party service.")
                        }
                        AndroidSaveToServiceOutcome.NoIntegrationConfigured -> {
                            mutableActionMessages.emit("No third-party integration is configured.")
                        }
                    }
                },
                onFailure = {
                    mutableActionMessages.emit("Article could not be saved to the third-party service.")
                },
            )
        }
    }


    fun requestSetListeningList(articleId: Long, enabled: Boolean) {
        val generation = activeSessionGeneration() ?: return
        explicitActionScope.launch {
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
        explicitActionScope.launch {
            val result = runCatching {
                mediaDownloadWriter(generation, enclosureId, downloadState)
            }
            if (activeSessionGeneration() != generation) return@launch
            if (result.isSuccess) {
                runCatching { transferReconciler(generation) }
                val refreshed = runCatching {
                    mediaActionStatesLoader(listOf(articleId))[articleId]
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

    private fun consumeExpectedEvent(
        events: ConcurrentHashMap<Long, ConcurrentLinkedQueue<Boolean>>,
        articleId: Long,
        value: Boolean,
    ): Boolean {
        val queue = events[articleId] ?: return false
        val expected = queue.peek() ?: return false
        if (expected != value) return false
        queue.poll()
        if (queue.isEmpty()) events.remove(articleId, queue)
        return true
    }

    private fun discardExpectedEvent(
        events: ConcurrentHashMap<Long, ConcurrentLinkedQueue<Boolean>>,
        articleId: Long,
        value: Boolean,
    ) {
        val queue = events[articleId] ?: return
        queue.remove(value)
        if (queue.isEmpty()) events.remove(articleId, queue)
    }

    private fun adjustedReadTotal(
        total: ULong?,
        selection: AndroidArticleTimelineSelection,
        previous: Boolean,
        requested: Boolean,
    ): ULong? {
        if (total == null || selection.readFilter != AndroidArticleReadFilter.Unread || previous == requested) {
            return total
        }
        return if (!previous && requested) {
            total - 1uL.coerceAtMost(total)
        } else {
            total + 1uL
        }
    }

    private fun adjustedStarredTotal(
        total: ULong?,
        selection: AndroidArticleTimelineSelection,
        previous: Boolean,
        requested: Boolean,
    ): ULong? {
        if (total == null || selection.scope != AndroidNewsScope.Starred || previous == requested) {
            return total
        }
        return if (previous && !requested) {
            total - 1uL.coerceAtMost(total)
        } else {
            total + 1uL
        }
    }

    suspend fun reset(selection: AndroidArticleTimelineSelection) {
        explicitReadMutationTokens.clear()
        explicitStarredMutationTokens.clear()
        expectedReadEvents.clear()
        expectedStarredEvents.clear()
        scrolloverRetainedReadIds.clear()
        undoFeedbackSuppressedUnreadIds.clear()
        pendingSuccessfulScrolloverUndoIds.clear()
        recentSuccessfulScrolloverReads.clear()
        clearScrolloverUndoGroup()
        scrolloverConfirmationPending = false
        articleIndexById.clear()
        rowPresentationById.clear()
        while (scrolloverMutationRequests.tryReceive().isSuccess) {
            // A semantic Timeline reset starts a new Scrollover generation.
        }
        val generation = ++requestGeneration
        val sessionGeneration = activeSessionGeneration()
        val previous = mutableState.value
        val sameSession = previous.sessionGeneration == null || previous.sessionGeneration == sessionGeneration
        if (!sameSession) {
            expectedBulkReadEventIds.clear()
            feedIconCacheByVariant.clear()
            unavailableFeedIconsByVariant.clear()
            feedIconRequestsInFlight.clear()
        }
        mutableState.value = AndroidArticleTimelineState(
            selection = selection,
            feedIconVariant = previous.feedIconVariant.takeIf { sameSession },
            feedIconPngByFeedId = previous.feedIconPngByFeedId.takeIf { sameSession }.orEmpty(),
            pendingNewFeedIds = previous.pendingNewFeedIds.takeIf { sameSession }.orEmpty(),
            hasUnscopedNewDataSignal = sameSession && previous.hasUnscopedNewDataSignal,
            initialLoading = true,
            queryGeneration = generation,
            sessionGeneration = sessionGeneration,
        )

        if (sessionGeneration == null) {
            failInitialIfOwned(generation, selection, null)
            return
        }

        val page = try {
            pageLoader(selection.coreQuery(), true)
        } catch (_: Exception) {
            failInitialIfOwned(generation, selection, sessionGeneration)
            return
        }

        if (!owns(generation, selection, sessionGeneration)) return
        val articles = page.articles.distinctBy { it.id }
        val mediaActionStates = loadMediaActionStates(articles.map { it.id })
        val audioArticleIds = mediaActionStates.filterValues { it.hasAudio }.keys

        if (!owns(generation, selection, sessionGeneration)) return
        rebuildArticleIndex(articles)
        reconcileRowPresentations(articles, replace = true)
        val iconState = mutableState.value
        mutableState.value = AndroidArticleTimelineState(
            selection = selection,
            articles = articles,
            audioArticleIds = audioArticleIds,
            mediaActionStates = mediaActionStates,
            feedIconVariant = iconState.feedIconVariant,
            feedIconPngByFeedId = iconState.feedIconPngByFeedId,
            pendingNewFeedIds = iconState.pendingNewFeedIds,
            hasUnscopedNewDataSignal = iconState.hasUnscopedNewDataSignal,
            total = page.total,
            nextCursor = page.nextCursor.takeIf { articles.isNotEmpty() },
            initialLoading = false,
            queryGeneration = generation,
            sessionGeneration = sessionGeneration,
        )
    }

    fun hasPendingNewDataForScope(
        scope: AndroidNewsScope,
        categoryFeedIds: Set<Long> = emptySet(),
    ): Boolean {
        val current = mutableState.value
        if (current.hasUnscopedNewDataSignal) return true
        return when (scope) {
            AndroidNewsScope.All,
            AndroidNewsScope.Starred,
            -> current.pendingNewFeedIds.isNotEmpty()
            is AndroidNewsScope.Category -> current.pendingNewFeedIds.any { it in categoryFeedIds }
            is AndroidNewsScope.Feed -> scope.id in current.pendingNewFeedIds
        }
    }

    fun acknowledgePendingNewDataForScope(
        scope: AndroidNewsScope,
        categoryFeedIds: Set<Long> = emptySet(),
    ) {
        mutableState.update { state ->
            val remainingFeedIds = when (scope) {
                AndroidNewsScope.All,
                AndroidNewsScope.Starred,
                -> emptySet()
                is AndroidNewsScope.Category -> state.pendingNewFeedIds - categoryFeedIds
                is AndroidNewsScope.Feed -> state.pendingNewFeedIds - scope.id
            }
            state.copy(
                pendingNewFeedIds = remainingFeedIds,
                hasUnscopedNewDataSignal = false,
            )
        }
    }

    suspend fun adoptPendingNewData(
        selection: AndroidArticleTimelineSelection,
        categoryFeedIds: Set<Long> = emptySet(),
    ) {
        acknowledgePendingNewDataForScope(selection.scope, categoryFeedIds)
        reset(selection)
        mutableScrollResetRequests.tryEmit(Unit)
    }

    private fun clearPendingNewData() {
        mutableState.update {
            it.copy(
                pendingNewFeedIds = emptySet(),
                hasUnscopedNewDataSignal = false,
            )
        }
    }

    suspend fun handleCoreEvent(runtimeEvent: AndroidCoreRuntimeEvent) {
        val current = mutableState.value
        val selection = current.selection ?: return
        if (runtimeEvent.generation != current.sessionGeneration || runtimeEvent.generation != activeSessionGeneration()) {
            return
        }

        when (val event = runtimeEvent.event) {
            is CoreEvent.ArticleReadStateChanged -> {
                if (event.read && expectedBulkReadEventIds.remove(event.articleId)) return
                if (consumeExpectedEvent(expectedReadEvents, event.articleId, event.read)) return
                val suppressFeedback =
                    !event.read && undoFeedbackSuppressedUnreadIds.remove(event.articleId)
                applyReadStateChanged(selection, event.articleId, event.read)
                if (!event.read) {
                    mutableScrolloverRearmRequests.tryEmit(listOf(event.articleId))
                }
                if (!suppressFeedback) mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            }
            is CoreEvent.ArticleStarredStateChanged -> {
                if (consumeExpectedEvent(expectedStarredEvents, event.articleId, event.starred)) return
                applyStarredStateChanged(selection, event.articleId, event.starred)
                mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
            }
            is CoreEvent.SyncDidComplete -> {
                val metadata = event.metadata
                if (metadata.navigationChanged) {
                    unavailableFeedIconsByVariant.clear()
                }

                if (metadata.reason == SyncReason.MANUAL) {
                    clearPendingNewData()
                    reset(selection)
                    mutableScrollResetRequests.tryEmit(Unit)
                } else if (metadata.dataChanged) {
                    val newFeedIds = metadata.newArticlesByFeed
                        .asSequence()
                        .filter { it.count > 0u }
                        .mapTo(mutableSetOf()) { it.feedId }
                    mutableState.update { state ->
                        state.copy(
                            pendingNewFeedIds = state.pendingNewFeedIds + newFeedIds,
                            hasUnscopedNewDataSignal =
                                state.hasUnscopedNewDataSignal || newFeedIds.isEmpty(),
                        )
                    }
                    refreshSelectionTotal(
                        selection = selection,
                        generation = current.queryGeneration,
                        sessionGeneration = current.sessionGeneration,
                    )
                }
            }
            else -> Unit
        }
    }

    private suspend fun applyReadStateChanged(
        selection: AndroidArticleTimelineSelection,
        articleId: Long,
        read: Boolean,
    ) {
        if (!read) scrolloverRetainedReadIds.remove(articleId)

        val current = mutableState.value
        val index = articleIndexById[articleId] ?: -1
        val retainScrolloverRow = read && articleId in scrolloverRetainedReadIds

        if (selection.readFilter == AndroidArticleReadFilter.Unread && !read && index < 0) {
            reset(selection)
            return
        }

        if (index >= 0) {
            val currentIndex = articleIndexById[articleId]
            if (
                currentIndex != null &&
                currentIndex in current.articles.indices &&
                current.articles[currentIndex].id == articleId
            ) {
                if (selection.readFilter == AndroidArticleReadFilter.Unread && read && !retainScrolloverRow) {
                    removeArticleFromVisibleState(
                        articleId = articleId,
                        selection = selection,
                        generation = current.queryGeneration,
                        sessionGeneration = current.sessionGeneration,
                    )
                } else {
                    setRowRead(articleId, read)
                }
            }
        }

        if (
            selection.readFilter == AndroidArticleReadFilter.Unread &&
            read &&
            !retainScrolloverRow
        ) {
            refreshSelectionTotal(selection, current.queryGeneration, current.sessionGeneration)
        }
    }

    suspend fun markReadFromScrollover(articleIds: List<Long>): List<Long> {
        if (articleIds.isEmpty()) return emptyList()

        val current = mutableState.value
        val selection = current.selection ?: return emptyList()
        val sessionGeneration = current.sessionGeneration ?: return emptyList()
        if (activeSessionGeneration() != sessionGeneration) return emptyList()

        val accepted = articleIds.asSequence()
            .distinct()
            .filter { id ->
                val index = articleIndexById[id] ?: return@filter false
                current.articles.getOrNull(index)?.takeIf { it.id == id } ?: return@filter false
                rowPresentationById[id]?.value?.isRead == false
            }
            .toList()
        if (accepted.isEmpty()) return emptyList()

        scrolloverRetainedReadIds.addAll(accepted)
        expectedBulkReadEventIds.addAll(accepted)
        accepted.forEach { setRowRead(it, true) }

        return try {
            scrolloverReadWriter(sessionGeneration, accepted)
            if (!owns(current.queryGeneration, selection, sessionGeneration)) return emptyList()
            pendingSuccessfulScrolloverUndoIds += accepted
            scrolloverConfirmationPending = true
            emptyList()
        } catch (_: Exception) {
            expectedBulkReadEventIds.removeAll(accepted.toSet())
            scrolloverRetainedReadIds.removeAll(accepted.toSet())
            if (owns(current.queryGeneration, selection, sessionGeneration)) {
                accepted.forEach { id ->
                    if (rowPresentationById[id]?.value?.isRead == true) setRowRead(id, false)
                }
            }
            accepted
        }
    }

    fun completeScrolloverInteraction() {
        if (pendingSuccessfulScrolloverUndoIds.isNotEmpty()) {
            val completedIds = pendingSuccessfulScrolloverUndoIds.distinct()
            val current = mutableState.value
            if (current.selection?.readFilter == AndroidArticleReadFilter.Unread) {
                mutableState.update { state ->
                    if (
                        state.queryGeneration != current.queryGeneration ||
                        state.selection != current.selection ||
                        state.sessionGeneration != current.sessionGeneration
                    ) {
                        return@update state
                    }
                    state.copy(
                        total = state.total?.let { total ->
                            val delta = completedIds.size.toULong().coerceAtMost(total)
                            total - delta
                        },
                    )
                }
            }
            recordSuccessfulScrolloverUndo(
                completedIds,
                monotonicMillis(),
            )
            pendingSuccessfulScrolloverUndoIds.clear()
        }
        if (!scrolloverConfirmationPending) return
        scrolloverConfirmationPending = false
        mutableFeedback.tryEmit(AndroidTimelineHaptic.Confirmation)
    }

    fun expireScrolloverUndo(revision: Long) {
        val current = mutableUndoState.value
        if (current.revision != revision || !current.visible) return
        val expiresAt = current.expiresAtUptimeMillis ?: return
        if (monotonicMillis() >= expiresAt) clearScrolloverUndoGroup()
    }

    suspend fun undoScrollover(): List<Long> {
        val currentUndo = mutableUndoState.value
        val ids = currentUndo.articleIds.distinct()
        if (!currentUndo.visible || ids.isEmpty()) return emptyList()

        val current = mutableState.value
        val selection = current.selection ?: return emptyList()
        val sessionGeneration = current.sessionGeneration ?: return emptyList()
        if (activeSessionGeneration() != sessionGeneration) {
            clearScrolloverUndoGroup()
            return emptyList()
        }

        undoFeedbackSuppressedUnreadIds.addAll(ids)
        return try {
            scrolloverUnreadWriter(sessionGeneration, ids)
            scrolloverRetainedReadIds.removeAll(ids.toSet())
            val restoredCount = ids.count { rowPresentationById[it]?.value?.isRead == true }
            ids.forEach { setRowRead(it, false) }
            mutableState.update { state ->
                if (
                    state.selection != selection ||
                    state.sessionGeneration != sessionGeneration
                ) {
                    return@update state
                }
                state.copy(
                    total = if (selection.readFilter == AndroidArticleReadFilter.Unread) {
                        state.total?.plus(restoredCount.toULong())
                    } else {
                        state.total
                    },
                    errorMessage = null,
                )
            }
            refreshSelectionTotal(selection, current.queryGeneration, sessionGeneration)
            clearScrolloverUndoGroup()
            mutableFeedback.tryEmit(AndroidTimelineHaptic.Selection)
            ids
        } catch (_: Exception) {
            undoFeedbackSuppressedUnreadIds.removeAll(ids.toSet())
            mutableState.update { state ->
                if (state.selection == selection && state.sessionGeneration == sessionGeneration) {
                    state.copy(errorMessage = "Articles could not be marked unread.")
                } else {
                    state
                }
            }
            emptyList()
        }
    }

    private fun recordSuccessfulScrolloverUndo(ids: List<Long>, now: Long) {
        if (ids.isEmpty()) return

        val currentUndo = mutableUndoState.value
        val openedAt = scrolloverUndoOpenedAtUptimeMillis
        val lastSuccessAt = scrolloverUndoLastSuccessAtUptimeMillis
        val existingGroupExpired =
            openedAt != null &&
                lastSuccessAt != null &&
                (now - lastSuccessAt >= ANDROID_SCROLL_OVER_UNDO_INACTIVITY_MILLIS ||
                    now - openedAt >= ANDROID_SCROLL_OVER_UNDO_MAX_LIFETIME_MILLIS)

        if (existingGroupExpired) clearScrolloverUndoGroup()

        if (mutableUndoState.value.visible) {
            appendScrolloverUndo(ids, now)
            return
        }

        recentSuccessfulScrolloverReads += ids.map { it to now }
        recentSuccessfulScrolloverReads.removeAll {
            now - it.second > ANDROID_SCROLL_OVER_UNDO_QUALIFICATION_MILLIS
        }
        val burstIds = recentSuccessfulScrolloverReads.map { it.first }.distinct()
        if (burstIds.size < ANDROID_SCROLL_OVER_UNDO_MIN_READS) return

        recentSuccessfulScrolloverReads.clear()
        scrolloverUndoOpenedAtUptimeMillis = now
        appendScrolloverUndo(burstIds, now)
    }

    private fun appendScrolloverUndo(ids: List<Long>, now: Long) {
        val existing = mutableUndoState.value.articleIds.toMutableList()
        val seen = existing.toMutableSet()
        ids.forEach { if (seen.add(it)) existing += it }
        if (existing.isEmpty()) return

        if (scrolloverUndoOpenedAtUptimeMillis == null) {
            scrolloverUndoOpenedAtUptimeMillis = now
        }
        scrolloverUndoLastSuccessAtUptimeMillis = now
        val openedAt = scrolloverUndoOpenedAtUptimeMillis ?: now
        val expiresAt = minOf(
            now + ANDROID_SCROLL_OVER_UNDO_INACTIVITY_MILLIS,
            openedAt + ANDROID_SCROLL_OVER_UNDO_MAX_LIFETIME_MILLIS,
        )
        val previous = mutableUndoState.value
        mutableUndoState.value = AndroidScrolloverUndoState(
            articleIds = existing,
            revision = previous.revision + 1,
            expiresAtUptimeMillis = expiresAt,
        )
    }

    private fun clearScrolloverUndoGroup() {
        val previous = mutableUndoState.value
        if (previous.articleIds.isNotEmpty() || previous.expiresAtUptimeMillis != null) {
            mutableUndoState.value = AndroidScrolloverUndoState(revision = previous.revision + 1)
        }
        scrolloverUndoOpenedAtUptimeMillis = null
        scrolloverUndoLastSuccessAtUptimeMillis = null
        recentSuccessfulScrolloverReads.clear()
    }

    private suspend fun applyStarredStateChanged(
        selection: AndroidArticleTimelineSelection,
        articleId: Long,
        starred: Boolean,
    ) {
        val current = mutableState.value
        val index = articleIndexById[articleId] ?: -1
        val starredScope = selection.scope == AndroidNewsScope.Starred

        if (starredScope && starred && index < 0) {
            reset(selection)
            return
        }

        if (index >= 0) {
            val currentIndex = articleIndexById[articleId]
            if (
                currentIndex != null &&
                currentIndex in current.articles.indices &&
                current.articles[currentIndex].id == articleId
            ) {
                if (starredScope && !starred) {
                    removeArticleFromVisibleState(
                        articleId = articleId,
                        selection = selection,
                        generation = current.queryGeneration,
                        sessionGeneration = current.sessionGeneration,
                    )
                } else {
                    setRowStarred(articleId, starred)
                }
            }
        }

        if (starredScope && !starred) {
            refreshSelectionTotal(selection, current.queryGeneration, current.sessionGeneration)
        }
    }

    private suspend fun refreshSelectionTotal(
        selection: AndroidArticleTimelineSelection,
        generation: Long,
        sessionGeneration: Long?,
    ) {
        val ownedSession = sessionGeneration ?: return
        val total = try {
            selectionCountLoader(selection.coreQuery())
        } catch (_: Exception) {
            return
        }
        if (!owns(generation, selection, ownedSession)) return
        mutableState.update { state ->
            if (
                state.queryGeneration == generation &&
                state.selection == selection &&
                state.sessionGeneration == ownedSession
            ) {
                if (state.total == total) state else state.copy(total = total)
            } else {
                state
            }
        }
    }

    suspend fun ensureFeedIcon(feedId: Long, variant: FeedIconVariant) {
        ensureFeedIcons(listOf(feedId), variant)
    }

    suspend fun ensureFeedIcons(feedIds: List<Long>, variant: FeedIconVariant) {
        if (feedIds.isEmpty()) return

        val current = mutableState.value
        val selection = current.selection ?: return
        val sessionGeneration = current.sessionGeneration ?: return
        if (activeSessionGeneration() != sessionGeneration) return

        val cache = feedIconCacheByVariant.getOrPut(variant) { mutableMapOf() }
        val unavailable = unavailableFeedIconsByVariant.getOrPut(variant) { mutableSetOf() }
        val requested = feedIds.asSequence()
            .distinct()
            .filterNot { it in cache || it in unavailable }
            .filter { feedIconRequestsInFlight.add(it to variant) }
            .toList()

        if (requested.isEmpty()) {
            if (cache.isNotEmpty()) {
                publishFeedIconCache(
                    generation = current.queryGeneration,
                    selection = selection,
                    sessionGeneration = sessionGeneration,
                    variant = variant,
                    cache = cache,
                )
            }
            return
        }

        try {
            repeat(ANDROID_FEED_ICON_MAX_ATTEMPTS) { attempt ->
                val loaded = try {
                    feedIconLoader(requested, variant)
                } catch (_: Exception) {
                    if (attempt + 1 < ANDROID_FEED_ICON_MAX_ATTEMPTS) {
                        delay(ANDROID_FEED_ICON_RETRY_DELAY_MILLIS * (attempt + 1))
                    }
                    return@repeat
                }

                if (!owns(current.queryGeneration, selection, sessionGeneration)) return

                requested.forEach { feedId ->
                    val png = loaded[feedId]
                    if (png == null) {
                        unavailable += feedId
                    } else {
                        cache[feedId] = png
                    }
                }
                publishFeedIconCache(
                    generation = current.queryGeneration,
                    selection = selection,
                    sessionGeneration = sessionGeneration,
                    variant = variant,
                    cache = cache,
                )
                return
            }
        } finally {
            requested.forEach { feedIconRequestsInFlight.remove(it to variant) }
        }
    }

    private fun publishFeedIconCache(
        generation: Long,
        selection: AndroidArticleTimelineSelection,
        sessionGeneration: Long,
        variant: FeedIconVariant,
        cache: Map<Long, ByteArray>,
    ) {
        mutableState.update { state ->
            if (
                state.queryGeneration != generation ||
                state.selection != selection ||
                state.sessionGeneration != sessionGeneration
            ) {
                return@update state
            }
            state.copy(
                feedIconVariant = variant,
                feedIconPngByFeedId = cache.toMap(),
            )
        }
    }

    suspend fun loadNextPage() {
        val current = mutableState.value
        val selection = current.selection ?: return
        val cursor = current.nextCursor ?: return
        if (current.initialLoading || current.loadingNextPage) return

        val currentSessionGeneration = activeSessionGeneration()
        if (currentSessionGeneration == null || currentSessionGeneration != current.sessionGeneration) {
            reset(selection)
            return
        }

        val generation = current.queryGeneration
        mutableState.update { state ->
            if (state.queryGeneration == generation && state.selection == selection) {
                state.copy(loadingNextPage = true, errorMessage = null)
            } else {
                state
            }
        }

        val page = try {
            pageLoader(selection.coreQuery(cursor), false)
        } catch (_: Exception) {
            if (owns(generation, selection, currentSessionGeneration)) {
                mutableState.update { state ->
                    if (state.queryGeneration == generation && state.selection == selection) {
                        state.copy(loadingNextPage = false, errorMessage = "More articles could not be loaded.")
                    } else {
                        state
                    }
                }
            }
            return
        }

        if (!owns(generation, selection, currentSessionGeneration)) return
        val appended = page.articles.filter { !articleIndexById.containsKey(it.id) }
        val appendedMediaActionStates = loadMediaActionStates(appended.map { it.id })
        val appendedAudioArticleIds = appendedMediaActionStates.filterValues { it.hasAudio }.keys

        if (!owns(generation, selection, currentSessionGeneration)) return
        val appendBase = mutableState.value
        if (appendBase.queryGeneration != generation || appendBase.selection != selection) return
        val currentAppend = appended.filter { article ->
            appendBase.articles.none { it.id == article.id }
        }
        val madeProgress = currentAppend.isNotEmpty()
        val nextCursor = page.nextCursor.takeIf { madeProgress && it != cursor }
        val updatedArticles = appendBase.articles + currentAppend
        mutableState.value = appendBase.copy(
            articles = updatedArticles,
            audioArticleIds = appendBase.audioArticleIds + appendedAudioArticleIds,
            mediaActionStates = appendBase.mediaActionStates + appendedMediaActionStates,
            nextCursor = nextCursor,
            loadingNextPage = false,
            errorMessage = null,
        )
        rebuildArticleIndex(updatedArticles)
        reconcileRowPresentations(currentAppend, replace = false)
    }

    private fun removeArticleFromVisibleState(
        articleId: Long,
        selection: AndroidArticleTimelineSelection,
        generation: Long,
        sessionGeneration: Long?,
    ): Boolean {
        val state = mutableState.value
        if (
            state.queryGeneration != generation ||
            state.selection != selection ||
            state.sessionGeneration != sessionGeneration
        ) {
            return false
        }
        val filtered = state.articles.filterNot { it.id == articleId }
        if (filtered.size == state.articles.size) return false

        mutableState.value = state.copy(
            articles = filtered,
            audioArticleIds = state.audioArticleIds - articleId,
            mediaActionStates = state.mediaActionStates - articleId,
        )
        rebuildArticleIndex(filtered)
        rowPresentationById.remove(articleId)
        return true
    }

    private fun rebuildArticleIndex(articles: List<ArticleSummary>) {
        articleIndexById.clear()
        articles.forEachIndexed { index, article -> articleIndexById[article.id] = index }
    }

    private fun reconcileRowPresentations(
        articles: List<ArticleSummary>,
        replace: Boolean,
    ) {
        if (replace) {
            val retainedIds = articles.asSequence().map { it.id }.toHashSet()
            rowPresentationById.keys
                .filter { it !in retainedIds }
                .forEach(rowPresentationById::remove)
        }
        articles.forEach { article ->
            val state = rowPresentationById[article.id]
            if (state == null) {
                rowPresentationById[article.id] = MutableStateFlow(
                    AndroidArticleRowPresentation(
                        isRead = article.isRead,
                        isStarred = article.isStarred,
                    ),
                )
            } else {
                val current = state.value
                if (current.isRead != article.isRead || current.isStarred != article.isStarred) {
                    state.value = current.copy(
                        isRead = article.isRead,
                        isStarred = article.isStarred,
                        revision = current.revision + 1L,
                    )
                }
            }
        }
    }

    private fun setRowRead(articleId: Long, read: Boolean): Boolean {
        val state = rowPresentationById[articleId] ?: return false
        val current = state.value
        if (current.isRead == read) return false
        state.value = current.copy(isRead = read, revision = current.revision + 1L)
        return true
    }

    private fun setRowStarred(articleId: Long, starred: Boolean): Boolean {
        val state = rowPresentationById[articleId] ?: return false
        val current = state.value
        if (current.isStarred == starred) return false
        state.value = current.copy(isStarred = starred, revision = current.revision + 1L)
        return true
    }

    private suspend fun refreshVisibleMediaActions() {
        val current = mutableState.value
        val sessionGeneration = current.sessionGeneration ?: return
        if (activeSessionGeneration() != sessionGeneration || current.articles.isEmpty()) return
        val generation = current.queryGeneration
        val refreshed = runCatching {
            mediaActionStatesLoader(current.articles.map { it.id })
        }.getOrNull() ?: return
        if (activeSessionGeneration() != sessionGeneration) return
        mutableState.update { state ->
            if (
                state.sessionGeneration != sessionGeneration ||
                state.queryGeneration != generation
            ) {
                return@update state
            }
            state.copy(
                mediaActionStates = refreshed,
                audioArticleIds = refreshed.filterValues { it.hasAudio }.keys,
            )
        }
    }

    private suspend fun loadMediaActionStates(articleIds: List<Long>): Map<Long, AndroidArticleMediaActionState> =
        try {
            mediaActionStatesLoader(articleIds)
        } catch (_: Exception) {
            emptyMap()
        }

    private fun owns(
        generation: Long,
        selection: AndroidArticleTimelineSelection,
        sessionGeneration: Long,
    ): Boolean =
        requestGeneration == generation &&
            mutableState.value.selection == selection &&
            activeSessionGeneration() == sessionGeneration

    private fun failInitialIfOwned(
        generation: Long,
        selection: AndroidArticleTimelineSelection,
        sessionGeneration: Long?,
    ) {
        if (
            requestGeneration != generation ||
            mutableState.value.selection != selection ||
            activeSessionGeneration() != sessionGeneration
        ) {
            return
        }
        val current = mutableState.value
        mutableState.value = AndroidArticleTimelineState(
            selection = selection,
            initialLoading = false,
            errorMessage = "Articles could not be loaded.",
            queryGeneration = generation,
            sessionGeneration = sessionGeneration,
            pendingNewFeedIds = current.pendingNewFeedIds,
            hasUnscopedNewDataSignal = current.hasUnscopedNewDataSignal,
        )
    }
}
