package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.ArticleCursor
import uniffi.flux_uniffi.ArticlePage
import uniffi.flux_uniffi.ArticleQuery
import uniffi.flux_uniffi.ArticleScope
import uniffi.flux_uniffi.ArticleSort
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.CoreEvent
import uniffi.flux_uniffi.FeedIconVariant
import uniffi.flux_uniffi.NewArticlesByFeed
import uniffi.flux_uniffi.ReadFilter
import uniffi.flux_uniffi.StarredFilter
import uniffi.flux_uniffi.SyncCompleted
import uniffi.flux_uniffi.SyncReason

class AndroidArticleTimelineTest {
    @Test
    fun visualCompactFlowStartsBesideImageAndContinuesWithoutParagraphGap() {
        val input = "The preview uses the free space beside the thumbnail and continues underneath"
        val lines = listOf(0f, 18f, 36f, 54f, 72f)
        val lineEnds = listOf(12, 26, 43, 58, input.length)
        val split = AndroidVisualCompactFlowPolicy.breakFor(
            textLength = input.length,
            maximumLines = 5,
            availableSideHeightPx = 40f,
            measuredLineCount = lines.size,
            lineTopPx = { lines[it] },
            lineEnd = { lineEnds[it] },
        )
        assertEquals(3, split.sideLines)
        assertEquals(43, split.splitIndex)
        assertEquals(2, split.continuationLines(5))
        assertEquals(input.substring(0, 43).trimEnd(), split.sideText(input, 5))
        assertEquals(input.substring(43).trimStart(), split.continuationText(input, 5))
        assertEquals(
            104,
            AndroidVisualCompactFlowPolicy.continuationTop(
                imageBottomPx = 100,
                publicationBottomPx = 60,
                sidePreviewBottomPx = 104,
                textSpacingPx = 7,
            ),
        )
    }

    @Test
    fun visualCompactFlowWithoutSideRoomOrImageKeepsTextAndSpacing() {
        val input = "A short article preview"
        val emptySide = AndroidVisualCompactFlowPolicy.breakFor(
            textLength = input.length,
            maximumLines = 3,
            availableSideHeightPx = 0f,
            measuredLineCount = 2,
            lineTopPx = { it * 18f },
            lineEnd = { input.length },
        )
        assertEquals(0, emptySide.sideLines)
        assertEquals("", emptySide.sideText(input, 3))
        assertEquals(input, emptySide.continuationText(input, 3))
        assertEquals(
            110,
            AndroidVisualCompactFlowPolicy.continuationTop(
                imageBottomPx = 100,
                publicationBottomPx = 85,
                sidePreviewBottomPx = null,
                textSpacingPx = 10,
            ),
        )
        val allSide = AndroidVisualCompactPreviewBreak(sideLines = 3, splitIndex = 9)
        assertEquals("", allSide.continuationText(input, 3))
        assertEquals(0, allSide.continuationLines(3))
    }
    @Test
    fun readPresentationKeepsHeadlineGeometryStable() {
        assertEquals(
            AndroidArticleStatusPresentationPolicy.titleFontWeight(isRead = false),
            AndroidArticleStatusPresentationPolicy.titleFontWeight(isRead = true),
        )
        assertTrue(
            AndroidArticleStatusPresentationPolicy.supportingAlpha(isRead = true) <
                AndroidArticleStatusPresentationPolicy.supportingAlpha(isRead = false),
        )
    }

    @Test
    fun allFilterReadMutationKeepsStructuralContentStateStable() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 1L },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.All,
            readFilter = AndroidArticleReadFilter.All,
        )
        store.reset(selection)
        val structuralArticles = store.state.value.articles
        val contentBefore = store.state.value.contentState()

        assertTrue(
            store.setReadExplicit(
                articleId = 1L,
                read = true,
                removeWhenRead = false,
            ),
        )

        assertSame(structuralArticles, store.state.value.articles)
        assertEquals(contentBefore, store.state.value.contentState())
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
    }

    @Test
    fun selectionMapsScopesFiltersSortAndBoundedPageSize() {
        val all = AndroidArticleTimelineSelection(AndroidNewsScope.All).coreQuery()
        assertEquals(ArticleScope.All, all.scope)
        assertEquals(ReadFilter.UNREAD, all.readFilter)
        assertEquals(StarredFilter.ALL, all.starredFilter)
        assertEquals(ArticleSort.OLDEST_FIRST, all.sort)
        assertEquals(64u, all.limit)
        assertNull(all.cursor)

        val starred = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.Starred,
            readFilter = AndroidArticleReadFilter.All,
            sort = AndroidArticleSortOrder.NewestFirst,
        ).coreQuery()
        assertEquals(ArticleScope.All, starred.scope)
        assertEquals(ReadFilter.ALL, starred.readFilter)
        assertEquals(StarredFilter.STARRED, starred.starredFilter)
        assertEquals(ArticleSort.NEWEST_FIRST, starred.sort)

        val category = AndroidArticleTimelineSelection(
            AndroidNewsScope.Category(7, "Category"),
        ).coreQuery()
        assertEquals(ArticleScope.Category(id = 7), category.scope)

        val cursor = ArticleCursor(
            publishedAt = "2026-10-01T12:00:00Z",
            articleId = 99,
        )
        val feed = AndroidArticleTimelineSelection(
            AndroidNewsScope.Feed(42, 7, "Feed"),
        ).coreQuery(cursor)
        assertEquals(ArticleScope.Feed(id = 42), feed.scope)
        assertEquals(cursor, feed.cursor)
    }

    @Test
    fun starredScopeAlwaysQueriesAllStarredArticlesRegardlessOfReadFilter() {
        val staleUnreadSelection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.Starred,
            readFilter = AndroidArticleReadFilter.Unread,
            sort = AndroidArticleSortOrder.NewestFirst,
        )
        val query = staleUnreadSelection.coreQuery()

        assertEquals(ArticleScope.All, query.scope)
        assertEquals(ReadFilter.ALL, query.readFilter)
        assertEquals(StarredFilter.STARRED, query.starredFilter)

        val selectedFromUnread = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.All,
            readFilter = AndroidArticleReadFilter.Unread,
        ).selectingScope(AndroidNewsScope.Starred)
        assertEquals(AndroidArticleReadFilter.Unread, selectedFromUnread.readFilter)
        assertEquals(ReadFilter.ALL, selectedFromUnread.coreQuery().readFilter)
        assertEquals(
            AndroidArticleReadFilter.Unread,
            selectedFromUnread.togglingReadFilter().readFilter,
        )
        assertEquals(
            AndroidArticleReadFilter.Unread,
            selectedFromUnread
                .selectingScope(AndroidNewsScope.All)
                .readFilter,
        )
    }

    @Test
    fun markAllQueryUsesExactUnreadUnboundedNewestScopeSemantics() {
        val query = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.Feed(42, 7, "Feed"),
            readFilter = AndroidArticleReadFilter.All,
            sort = AndroidArticleSortOrder.OldestFirst,
        ).markAllReadQuery()

        assertEquals(ArticleScope.Feed(id = 42), query.scope)
        assertEquals(ReadFilter.UNREAD, query.readFilter)
        assertEquals(StarredFilter.ALL, query.starredFilter)
        assertEquals(ArticleSort.NEWEST_FIRST, query.sort)
        assertEquals(0u, query.limit)
        assertNull(query.cursor)
    }

    @Test
    fun semanticSelectionTransitionsPreserveTransientFilterAndSortAcrossScopeChanges() {
        val original = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.All,
            readFilter = AndroidArticleReadFilter.All,
            sort = AndroidArticleSortOrder.NewestFirst,
        )

        val starred = original.selectingScope(AndroidNewsScope.Starred)
        assertEquals(AndroidNewsScope.Starred, starred.scope)
        assertEquals(AndroidArticleReadFilter.All, starred.readFilter)

        val feed = starred.selectingScope(AndroidNewsScope.Feed(42, 7, "Feed"))
        assertEquals(AndroidNewsScope.Feed(42, 7, "Feed"), feed.scope)
        assertEquals(AndroidArticleReadFilter.All, feed.readFilter)
        assertEquals(AndroidArticleSortOrder.NewestFirst, feed.sort)

        val unread = feed.togglingReadFilter()
        assertEquals(AndroidArticleReadFilter.Unread, unread.readFilter)
        assertEquals(AndroidArticleSortOrder.NewestFirst, unread.sort)

        val oldest = unread.togglingSortOrder()
        assertEquals(AndroidArticleReadFilter.Unread, oldest.readFilter)
        assertEquals(AndroidArticleSortOrder.OldestFirst, oldest.sort)

        assertEquals(AndroidArticleReadFilter.All, original.readFilter)
        assertEquals(AndroidArticleSortOrder.NewestFirst, original.sort)
    }

    @Test
    fun firstPageOwnsTotalAndFollowingPageAppendsOnlyNewStableIds() = runBlocking {
        var sessionGeneration: Long? = 4
        val calls = mutableListOf<Pair<Boolean, ArticleCursor?>>()
        val cursor = ArticleCursor(
            publishedAt = "2026-10-01T10:00:00Z",
            articleId = 2,
        )
        val store = AndroidArticleTimelineStore(
            pageLoader = { query, includeTotal ->
                calls += includeTotal to query.cursor
                if (includeTotal) {
                    ArticlePage(
                        articles = listOf(article(1), article(2)),
                        total = 3uL,
                        nextCursor = cursor,
                    )
                } else {
                    ArticlePage(
                        articles = listOf(article(2), article(3)),
                        total = null,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { sessionGeneration },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)

        store.reset(selection)

        assertEquals(listOf(1L, 2L), store.state.value.articles.map { it.id })
        assertEquals(3uL, store.state.value.total)
        assertEquals(cursor, store.state.value.nextCursor)
        assertFalse(store.state.value.initialLoading)

        store.loadNextPage()

        assertEquals(listOf(1L, 2L, 3L), store.state.value.articles.map { it.id })
        assertEquals(3uL, store.state.value.total)
        assertNull(store.state.value.nextCursor)
        assertEquals(listOf(true to null, false to cursor), calls)
        sessionGeneration = null
    }

    @Test
    fun staleFirstPageCannotPublishAfterNewerSelectionReset() = runBlocking {
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        var call = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                call += 1
                if (call == 1) {
                    firstStarted.complete(Unit)
                    releaseFirst.await()
                    ArticlePage(
                        articles = listOf(article(1)),
                        total = 1uL,
                        nextCursor = null,
                    )
                } else {
                    ArticlePage(
                        articles = listOf(article(2)),
                        total = 1uL,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { 9L },
            testOnly = Unit,
        )

        val oldRequest = async {
            store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))
        }
        firstStarted.await()

        store.reset(
            AndroidArticleTimelineSelection(
                AndroidNewsScope.Feed(22, 7, "Current"),
            ),
        )
        releaseFirst.complete(Unit)
        oldRequest.await()

        assertEquals(listOf(2L), store.state.value.articles.map { it.id })
        assertEquals(
            AndroidNewsScope.Feed(22, 7, "Current"),
            store.state.value.selection?.scope,
        )
        assertEquals(2L, store.state.value.queryGeneration)
    }

    @Test
    fun pageCompletionFromRetiredCoreSessionCannotOverwriteNewSessionSnapshot() = runBlocking {
        var sessionGeneration: Long? = 3
        val pageStarted = CompletableDeferred<Unit>()
        val releasePage = CompletableDeferred<Unit>()
        var call = 0
        val cursor = ArticleCursor(
            publishedAt = "2026-10-01T10:00:00Z",
            articleId = 1,
        )
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, includeTotal ->
                call += 1
                when (call) {
                    1 -> ArticlePage(
                        articles = listOf(article(1)),
                        total = 2uL,
                        nextCursor = cursor,
                    )
                    2 -> {
                        assertFalse(includeTotal)
                        pageStarted.complete(Unit)
                        releasePage.await()
                        ArticlePage(
                            articles = listOf(article(2)),
                            total = null,
                            nextCursor = null,
                        )
                    }
                    else -> ArticlePage(
                        articles = listOf(article(9)),
                        total = 1uL,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { sessionGeneration },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)

        store.reset(selection)
        val staleAppend = async { store.loadNextPage() }
        pageStarted.await()

        sessionGeneration = 4
        store.reset(selection)
        releasePage.complete(Unit)
        staleAppend.await()

        assertEquals(3, call)
        assertEquals(listOf(9L), store.state.value.articles.map { it.id })
        assertEquals(1uL, store.state.value.total)
        assertNull(store.state.value.nextCursor)
        assertFalse(store.state.value.loadingNextPage)
        assertEquals(2L, store.state.value.queryGeneration)
    }

    @Test
    fun repeatedCursorOrDuplicateOnlyPageStopsPagination() = runBlocking {
        val cursor = ArticleCursor(
            publishedAt = "2026-10-01T10:00:00Z",
            articleId = 1,
        )
        var call = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, includeTotal ->
                call += 1
                if (includeTotal) {
                    ArticlePage(
                        articles = listOf(article(1)),
                        total = 2uL,
                        nextCursor = cursor,
                    )
                } else {
                    ArticlePage(
                        articles = listOf(article(1)),
                        total = null,
                        nextCursor = cursor,
                    )
                }
            },
            activeSessionGeneration = { 1L },
            testOnly = Unit,
        )

        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))
        store.loadNextPage()
        store.loadNextPage()

        assertEquals(2, call)
        assertEquals(listOf(1L), store.state.value.articles.map { it.id })
        assertNull(store.state.value.nextCursor)
        assertTrue(store.state.value.errorMessage == null)
    }


    @Test
    fun readEventsPatchVisibleRowsAndIgnoreRetiredSessions() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2)),
                    total = 2uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 7L },
            selectionCountLoader = { 1uL },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 6L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 1L, read = true),
            ),
        )
        assertEquals(listOf(1L, 2L), store.state.value.articles.map { it.id })

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 7L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 1L, read = true),
            ),
        )

        assertEquals(listOf(2L), store.state.value.articles.map { it.id })
        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun unloadedUnreadRemovalRefreshesOnlySelectionTotal() = runBlocking {
        var pageCalls = 0
        var countCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 2uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 8L },
            selectionCountLoader = {
                countCalls += 1
                1uL
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 8L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 2L, read = true),
            ),
        )

        assertEquals(1, pageCalls)
        assertEquals(1, countCalls)
        assertEquals(listOf(1L), store.state.value.articles.map { it.id })
        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun allFilterStatusEventsPatchRowsWithoutReloadingTimeline() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 3L },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.All,
            readFilter = AndroidArticleReadFilter.All,
        )
        store.reset(selection)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 3L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 1L, read = true),
            ),
        )
        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 3L,
                event = CoreEvent.ArticleStarredStateChanged(articleId = 1L, starred = true),
            ),
        )

        assertEquals(1, pageCalls)
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
        assertTrue(store.rowPresentationForTesting(1L)!!.isStarred)
        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun filteredReadReentryTriggersOneSnapshotRefresh() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                if (pageCalls == 1) {
                    ArticlePage(
                        articles = listOf(article(1)),
                        total = 1uL,
                        nextCursor = null,
                    )
                } else {
                    ArticlePage(
                        articles = listOf(article(1), article(2)),
                        total = 2uL,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { 4L },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 4L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 2L, read = false),
            ),
        )

        assertEquals(2, pageCalls)
        assertEquals(listOf(1L, 2L), store.state.value.articles.map { it.id })
        assertEquals(2uL, store.state.value.total)
    }

    @Test
    fun starredScopeRemovesVisibleRowsAndRefreshesForReentry() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                if (pageCalls == 1) {
                    ArticlePage(
                        articles = listOf(article(1, starred = true)),
                        total = 1uL,
                        nextCursor = null,
                    )
                } else {
                    ArticlePage(
                        articles = listOf(article(2, starred = true)),
                        total = 1uL,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { 5L },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.Starred,
            readFilter = AndroidArticleReadFilter.All,
        )
        store.reset(selection)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 5L,
                event = CoreEvent.ArticleStarredStateChanged(articleId = 1L, starred = false),
            ),
        )
        assertTrue(store.state.value.articles.isEmpty())
        assertEquals(0uL, store.state.value.total)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 5L,
                event = CoreEvent.ArticleStarredStateChanged(articleId = 2L, starred = true),
            ),
        )

        assertEquals(2, pageCalls)
        assertEquals(listOf(2L), store.state.value.articles.map { it.id })
        assertEquals(1uL, store.state.value.total)
    }


    @Test
    fun scrolloverWritesOnlyUnreadVisibleRowsAndKeepsUnreadSnapshotStable() = runBlocking {
        val writes = mutableListOf<Pair<Long, List<Long>>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2, read = true), article(3)),
                    total = 3uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 11L },
            scrolloverReadWriter = { generation, ids -> writes += generation to ids },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)
        val structuralSnapshot = store.state.value.articles

        val failed = store.markReadFromScrollover(listOf(1L, 2L, 1L, 99L, 3L))

        assertTrue(failed.isEmpty())
        assertSame(structuralSnapshot, store.state.value.articles)
        assertEquals(listOf(11L to listOf(1L, 3L)), writes)
        assertEquals(listOf(1L, 2L, 3L), store.state.value.articles.map { it.id })
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
        assertTrue(store.rowPresentationForTesting(3L)!!.isRead)
        assertEquals(3uL, store.state.value.total)

        store.completeScrolloverInteraction()

        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun storeOwnedScrolloverQueuePersistsCandidatesWithoutComposableOwnership() = runBlocking {
        val persisted = CompletableDeferred<List<Long>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2)),
                    total = 2uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 20L },
            scrolloverReadWriter = { _, ids -> persisted.complete(ids) },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        store.enqueueScrolloverCandidates(listOf(1L, 2L))

        assertEquals(listOf(1L, 2L), withTimeout(1_000) { persisted.await() })
        withTimeout(1_000) {
            while (
                store.rowPresentationForTesting(1L)?.isRead != true ||
                store.rowPresentationForTesting(2L)?.isRead != true
            ) {
                kotlinx.coroutines.yield()
            }
        }
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
        assertTrue(store.rowPresentationForTesting(2L)!!.isRead)
    }

    @Test
    fun scrolloverPublishesOneConfirmationOnlyAfterInteractionCompletes() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2)),
                    total = 2uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 21L },
            scrolloverReadWriter = { _, _ -> },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))
        val feedback = async(start = CoroutineStart.UNDISPATCHED) { store.feedback.first() }

        assertTrue(store.markReadFromScrollover(listOf(1L)).isEmpty())
        assertTrue(store.markReadFromScrollover(listOf(2L)).isEmpty())
        assertFalse(feedback.isCompleted)

        store.completeScrolloverInteraction()

        assertEquals(
            AndroidTimelineHaptic.Confirmation,
            withTimeout(1_000) { feedback.await() },
        )
    }

    @Test
    fun failedScrolloverDoesNotPublishConfirmation() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 22L },
            scrolloverReadWriter = { _, _ -> error("write failed") },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        assertEquals(listOf(1L), store.markReadFromScrollover(listOf(1L)))
        store.completeScrolloverInteraction()

        assertNull(withTimeoutOrNull(100) { store.feedback.first() })
    }

    @Test
    fun scrolloverUndoAppearsAfterQualifiedBurstAndRestoresUnreadState() = runBlocking {
        var now = 1_000L
        val unreadWrites = mutableListOf<Pair<Long, List<Long>>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2), article(3)),
                    total = 3uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 31L },
            selectionCountLoader = { 3uL },
            scrolloverReadWriter = { _, _ -> },
            scrolloverUnreadWriter = { generation, ids -> unreadWrites += generation to ids },
            monotonicMillis = { now },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        assertTrue(store.markReadFromScrollover(listOf(1L, 2L, 3L)).isEmpty())
        store.completeScrolloverInteraction()

        assertTrue(store.undoState.value.visible)
        assertEquals(listOf(1L, 2L, 3L), store.undoState.value.articleIds)
        assertEquals(0uL, store.state.value.total)

        val feedback = async(start = CoroutineStart.UNDISPATCHED) { store.feedback.first() }
        val restored = store.undoScrollover()

        assertEquals(listOf(1L, 2L, 3L), restored)
        assertEquals(listOf(31L to listOf(1L, 2L, 3L)), unreadWrites)
        assertTrue(listOf(1L, 2L, 3L).none { store.rowPresentationForTesting(it)!!.isRead })
        assertEquals(3uL, store.state.value.total)
        assertFalse(store.undoState.value.visible)
        assertEquals(
            AndroidTimelineHaptic.Selection,
            withTimeout(1_000) { feedback.await() },
        )
    }

    @Test
    fun scrolloverUndoDoesNotAppearForSmallBurstAndExpiresAfterInactivity() = runBlocking {
        var now = 2_000L
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2), article(3)),
                    total = 3uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 32L },
            scrolloverReadWriter = { _, _ -> },
            monotonicMillis = { now },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        store.markReadFromScrollover(listOf(1L, 2L))
        store.completeScrolloverInteraction()
        assertFalse(store.undoState.value.visible)

        now += 500L
        store.markReadFromScrollover(listOf(3L))
        store.completeScrolloverInteraction()
        assertTrue(store.undoState.value.visible)
        val revision = store.undoState.value.revision

        now = store.undoState.value.expiresAtUptimeMillis!! + 1L
        store.expireScrolloverUndo(revision)

        assertFalse(store.undoState.value.visible)
        assertTrue(store.undoState.value.articleIds.isEmpty())
    }

    @Test
    fun scrolloverUndoIsRejectedAfterSessionReplacement() = runBlocking {
        var generation: Long? = 41L
        var unreadWrites = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2), article(3)),
                    total = 3uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { generation },
            scrolloverReadWriter = { _, _ -> },
            scrolloverUnreadWriter = { _, _ -> unreadWrites += 1 },
            monotonicMillis = { 3_000L },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))
        store.markReadFromScrollover(listOf(1L, 2L, 3L))
        store.completeScrolloverInteraction()
        assertTrue(store.undoState.value.visible)

        generation = 42L
        val restored = store.undoScrollover()

        assertTrue(restored.isEmpty())
        assertEquals(0, unreadWrites)
        assertFalse(store.undoState.value.visible)
    }

    @Test
    fun scrolloverWriteFailureRollsBackOptimisticReadStateAndCount() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2)),
                    total = 2uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 12L },
            scrolloverReadWriter = { _, _ -> error("write failed") },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)

        val failed = store.markReadFromScrollover(listOf(1L))

        assertEquals(listOf(1L), failed)
        assertFalse(store.rowPresentationForTesting(1L)!!.isRead)
        assertEquals(2uL, store.state.value.total)
    }

    @Test
    fun scrolloverWriteIsRejectedWhenSessionGenerationChanged() = runBlocking {
        var generation: Long? = 13L
        var writes = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { generation },
            scrolloverReadWriter = { _, _ -> writes += 1 },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)
        generation = 14L

        val failed = store.markReadFromScrollover(listOf(1L))

        assertTrue(failed.isEmpty())
        assertEquals(0, writes)
        assertFalse(store.rowPresentationForTesting(1L)!!.isRead)
        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun explicitReadMutationIsOptimisticAndRollsBackOnFailure() = runBlocking {
        val writerStarted = CompletableDeferred<Unit>()
        val releaseWriter = CompletableDeferred<Unit>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 51L },
            selectionCountLoader = { 1uL },
            explicitReadWriter = { _, _, _ ->
                writerStarted.complete(Unit)
                releaseWriter.await()
                error("expected write failure")
            },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        val mutation = async {
            store.setReadExplicit(
                articleId = 1L,
                read = true,
                removeWhenRead = false,
            )
        }
        writerStarted.await()

        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
        assertEquals(0uL, store.state.value.total)

        releaseWriter.complete(Unit)
        assertFalse(mutation.await())
        assertFalse(store.rowPresentationForTesting(1L)!!.isRead)
        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun successfulExplicitReadRemovesOnlyWhenPreferenceRequestsIt() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1), article(2)),
                    total = 2uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 52L },
            selectionCountLoader = { 1uL },
            explicitReadWriter = { _, _, _ -> },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        assertTrue(
            store.setReadExplicit(
                articleId = 1L,
                read = true,
                removeWhenRead = true,
            ),
        )

        assertEquals(listOf(2L), store.state.value.articles.map { it.id })
        assertEquals(1uL, store.state.value.total)
    }

    @Test
    fun failedSupersededReadDoesNotLeaveAStaleExpectedEvent() = runBlocking {
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        var call = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 55L },
            selectionCountLoader = { 1uL },
            explicitReadWriter = { _, _, _ ->
                call += 1
                if (call == 1) {
                    firstStarted.complete(Unit)
                    releaseFirst.await()
                    error("superseded write failed")
                }
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.All,
            readFilter = AndroidArticleReadFilter.All,
        )
        store.reset(selection)

        val first = async {
            store.setReadExplicit(1L, read = true, removeWhenRead = false)
        }
        firstStarted.await()
        val second = async {
            store.setReadExplicit(1L, read = false, removeWhenRead = false)
        }
        releaseFirst.complete(Unit)
        assertFalse(first.await())
        assertTrue(second.await())

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 55L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 1L, read = true),
            ),
        )

        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
    }

    @Test
    fun ownDelayedReadEventDoesNotOverrideRemoveWhenReadPreference() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 54L },
            selectionCountLoader = { 0uL },
            explicitReadWriter = { _, _, _ -> },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)

        assertTrue(
            store.setReadExplicit(
                articleId = 1L,
                read = true,
                removeWhenRead = false,
            ),
        )
        assertEquals(listOf(1L), store.state.value.articles.map { it.id })

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 54L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 1L, read = true),
            ),
        )

        assertEquals(listOf(1L), store.state.value.articles.map { it.id })
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
    }

    @Test
    fun successfulExplicitUnreadRearmsScrolloverOnlyAfterWriteSucceeds() = runBlocking {
        val writerStarted = CompletableDeferred<Unit>()
        val releaseWriter = CompletableDeferred<Unit>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1, read = true)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 56L },
            selectionCountLoader = { 1uL },
            explicitReadWriter = { _, _, _ ->
                writerStarted.complete(Unit)
                releaseWriter.await()
            },
            testOnly = Unit,
        )
        store.reset(
            AndroidArticleTimelineSelection(
                scope = AndroidNewsScope.All,
                readFilter = AndroidArticleReadFilter.All,
            ),
        )
        val rearm = async(start = CoroutineStart.UNDISPATCHED) {
            store.scrolloverRearmRequests.first()
        }

        val mutation = async {
            store.setReadExplicit(
                articleId = 1L,
                read = false,
                removeWhenRead = false,
            )
        }
        writerStarted.await()
        assertFalse(rearm.isCompleted)

        releaseWriter.complete(Unit)
        assertTrue(mutation.await())
        assertEquals(listOf(1L), withTimeout(1_000) { rearm.await() })
    }

    @Test
    fun failedExplicitUnreadDoesNotRearmScrollover() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1, read = true)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 57L },
            selectionCountLoader = { 1uL },
            explicitReadWriter = { _, _, _ -> error("expected") },
            testOnly = Unit,
        )
        store.reset(
            AndroidArticleTimelineSelection(
                scope = AndroidNewsScope.All,
                readFilter = AndroidArticleReadFilter.All,
            ),
        )

        assertFalse(
            store.setReadExplicit(
                articleId = 1L,
                read = false,
                removeWhenRead = false,
            ),
        )
        assertNull(withTimeoutOrNull(100) { store.scrolloverRearmRequests.first() })
    }

    @Test
    fun externalUnreadCoreEventRequestsScrolloverRearm() = runBlocking {
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1, read = true)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 58L },
            testOnly = Unit,
        )
        store.reset(
            AndroidArticleTimelineSelection(
                scope = AndroidNewsScope.All,
                readFilter = AndroidArticleReadFilter.All,
            ),
        )
        val rearm = async(start = CoroutineStart.UNDISPATCHED) {
            store.scrolloverRearmRequests.first()
        }

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 58L,
                event = CoreEvent.ArticleReadStateChanged(articleId = 1L, read = false),
            ),
        )

        assertEquals(listOf(1L), withTimeout(1_000) { rearm.await() })
    }

    @Test
    fun explicitStarMutationRollsBackAndStarredRemovalWaitsForSuccess() = runBlocking {
        var shouldFail = true
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1, starred = true)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 53L },
            selectionCountLoader = { if (shouldFail) 1uL else 0uL },
            explicitStarredWriter = { _, _, _ ->
                if (shouldFail) error("expected write failure")
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.Starred,
            readFilter = AndroidArticleReadFilter.All,
        )
        store.reset(selection)

        assertFalse(store.setStarredExplicit(articleId = 1L, starred = false))
        assertTrue(store.rowPresentationForTesting(1L)!!.isStarred)
        assertEquals(1uL, store.state.value.total)

        shouldFail = false
        assertTrue(store.setStarredExplicit(articleId = 1L, starred = false))
        assertTrue(store.state.value.articles.isEmpty())
        assertEquals(0uL, store.state.value.total)
    }

    @Test
    fun staleExplicitMutationCompletionCannotOverwriteReplacementSession() = runBlocking {
        var sessionGeneration: Long? = 61L
        val writerStarted = CompletableDeferred<Unit>()
        val releaseWriter = CompletableDeferred<Unit>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1, read = sessionGeneration == 62L)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { sessionGeneration },
            selectionCountLoader = { 1uL },
            explicitReadWriter = { _, _, _ ->
                writerStarted.complete(Unit)
                releaseWriter.await()
                error("retired session failure")
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.All,
            readFilter = AndroidArticleReadFilter.All,
        )
        store.reset(selection)

        val staleMutation = async {
            store.setReadExplicit(
                articleId = 1L,
                read = true,
                removeWhenRead = false,
            )
        }
        writerStarted.await()

        sessionGeneration = 62L
        store.reset(selection)
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)

        releaseWriter.complete(Unit)
        assertFalse(staleMutation.await())
        assertTrue(store.rowPresentationForTesting(1L)!!.isRead)
        assertEquals(62L, store.state.value.sessionGeneration)
    }

    @Test
    fun markCurrentScopeReadPassesExactQueriedIdsAndReloadsOnlyAfterSuccess() = runBlocking {
        val queries = mutableListOf<ArticleQuery>()
        val writes = mutableListOf<Pair<Long, List<Long>>>()
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                if (pageCalls == 1) {
                    ArticlePage(
                        articles = listOf(article(1), article(2)),
                        total = 2uL,
                        nextCursor = null,
                    )
                } else {
                    ArticlePage(
                        articles = emptyList(),
                        total = 0uL,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { 71L },
            scopeUnreadIdsLoader = { _, query ->
                queries += query
                listOf(2L, 1L, 2L)
            },
            scopeReadWriter = { generation, ids ->
                writes += generation to ids
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(
            scope = AndroidNewsScope.Category(7, "Category"),
            readFilter = AndroidArticleReadFilter.All,
            sort = AndroidArticleSortOrder.OldestFirst,
        )
        store.reset(selection)

        assertTrue(store.markCurrentScopeAsRead())

        assertEquals(2, pageCalls)
        assertEquals(1, queries.size)
        assertEquals(ReadFilter.UNREAD, queries.single().readFilter)
        assertEquals(ArticleSort.NEWEST_FIRST, queries.single().sort)
        assertEquals(0u, queries.single().limit)
        assertEquals(listOf(71L to listOf(2L, 1L)), writes)
        assertTrue(store.state.value.articles.isEmpty())
        assertEquals(0uL, store.state.value.total)
    }

    @Test
    fun markReadAndNextCanSkipReloadingTheOldScope() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 74L },
            scopeUnreadIdsLoader = { _, _ -> listOf(1L) },
            scopeReadWriter = { _, _ -> },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.Feed(1, 7, "Current")))

        assertTrue(store.markCurrentScopeAsRead(reloadCurrentScope = false))

        assertEquals(1, pageCalls)
        assertEquals(AndroidNewsScope.Feed(1, 7, "Current"), store.state.value.selection?.scope)
    }

    @Test
    fun markCurrentScopeReadFailureDoesNotReloadOrPretendSuccess() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 72L },
            scopeUnreadIdsLoader = { _, _ -> listOf(1L) },
            scopeReadWriter = { _, _ -> error("expected bulk failure") },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        assertFalse(store.markCurrentScopeAsRead())
        assertEquals(1, pageCalls)
        assertEquals(listOf(1L), store.state.value.articles.map { it.id })
    }

    @Test
    fun markCurrentScopeReadNeverWritesAfterSelectionWasSuperseded() = runBlocking {
        val loaderStarted = CompletableDeferred<Unit>()
        val releaseLoader = CompletableDeferred<Unit>()
        var writes = 0
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = listOf(article(pageCalls.toLong())),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 73L },
            scopeUnreadIdsLoader = { _, _ ->
                loaderStarted.complete(Unit)
                releaseLoader.await()
                listOf(1L)
            },
            scopeReadWriter = { _, _ -> writes += 1 },
            testOnly = Unit,
        )
        val original = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(original)

        val markAll = async { store.markCurrentScopeAsRead() }
        loaderStarted.await()
        store.reset(
            AndroidArticleTimelineSelection(
                AndroidNewsScope.Feed(9, 4, "Other"),
            ),
        )
        releaseLoader.complete(Unit)

        assertFalse(markAll.await())
        assertEquals(0, writes)
        assertEquals(AndroidNewsScope.Feed(9, 4, "Other"), store.state.value.selection?.scope)
    }

    @Test
    fun rowPolicyPreservesSemanticAccessoryOrderAndImageModes() {
        val article = article(
            id = 7,
            read = false,
            starred = true,
            commentsUrl = "https://example.test/comments",
            imageUrl = "https://example.test/image.jpg",
        )

        assertEquals(
            listOf(
                AndroidArticleAccessory.Unread,
                AndroidArticleAccessory.Star,
                AndroidArticleAccessory.Comments,
                AndroidArticleAccessory.Audio,
            ),
            AndroidArticleRowPolicy.accessories(article, hasAudio = true),
        )
        assertFalse(
            AndroidArticleRowPolicy.showsImage(
                AndroidArticlePresentationMode.Compact,
                article.imageUrl,
            ),
        )
        assertTrue(
            AndroidArticleRowPolicy.showsImage(
                AndroidArticlePresentationMode.Visual,
                article.imageUrl,
            ),
        )
        assertTrue(
            AndroidArticleRowPolicy.showsImage(
                AndroidArticlePresentationMode.VisualCompact,
                article.imageUrl,
            ),
        )
        assertFalse(
            AndroidArticleRowPolicy.showsImage(
                AndroidArticlePresentationMode.Visual,
                null,
            ),
        )
    }

    @Test
    fun rowLayoutVariantsMatchCurrentSharedPresentationSemantics() {
        val image = "https://example.test/image.jpg"

        assertEquals(
            AndroidArticleRowLayoutVariant.Compact,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.Compact,
                image,
                390,
            ),
        )
        assertEquals(
            AndroidArticleRowLayoutVariant.VisualPortrait,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.Visual,
                image,
                390,
            ),
        )
        assertEquals(
            AndroidArticleRowLayoutVariant.VisualLandscape,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.Visual,
                image,
                700,
            ),
        )
        assertEquals(
            AndroidArticleRowLayoutVariant.VisualCompactNarrow,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.VisualCompact,
                image,
                390,
            ),
        )
        assertEquals(
            AndroidArticleRowLayoutVariant.VisualCompactWide,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.VisualCompact,
                image,
                700,
            ),
        )
        assertEquals(
            AndroidArticleRowLayoutVariant.VisualTextOnly,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.Visual,
                null,
                390,
            ),
        )
        assertEquals(
            AndroidArticleRowLayoutVariant.VisualCompactTextOnly,
            AndroidArticleRowPolicy.layoutVariant(
                AndroidArticlePresentationMode.VisualCompact,
                null,
                390,
            ),
        )
    }

    @Test
    fun feedIconsLoadOncePerUniqueFeedAndThemeVariant() = runBlocking {
        val calls = mutableListOf<Pair<List<Long>, FeedIconVariant>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(
                        article(1),
                        article(2).copy(feedId = 10),
                        article(3).copy(feedId = 11),
                    ),
                    total = 3uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 21L },
            feedIconLoader = { ids, variant ->
                calls += ids to variant
                ids.associateWith { byteArrayOf(it.toByte()) }
            },
            testOnly = Unit,
        )
        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))

        store.ensureFeedIcon(10L, FeedIconVariant.NORMAL)
        store.ensureFeedIcon(11L, FeedIconVariant.NORMAL)
        store.ensureFeedIcon(10L, FeedIconVariant.NORMAL)
        store.ensureFeedIcon(11L, FeedIconVariant.NORMAL)
        store.ensureFeedIcon(10L, FeedIconVariant.DARK)
        store.ensureFeedIcon(11L, FeedIconVariant.DARK)

        assertEquals(
            listOf(
                listOf(10L) to FeedIconVariant.NORMAL,
                listOf(11L) to FeedIconVariant.NORMAL,
                listOf(10L) to FeedIconVariant.DARK,
                listOf(11L) to FeedIconVariant.DARK,
            ),
            calls,
        )
        assertEquals(FeedIconVariant.DARK, store.state.value.feedIconVariant)
        assertEquals(setOf(10L, 11L), store.state.value.feedIconPngByFeedId.keys)
    }

    @Test
    fun feedIconCacheSurvivesTimelineResetWithinSameSession() = runBlocking {
        val calls = mutableListOf<Pair<List<Long>, FeedIconVariant>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1).copy(feedId = 10)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 31L },
            feedIconLoader = { ids, variant ->
                calls += ids to variant
                ids.associateWith { byteArrayOf(it.toByte()) }
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)

        store.reset(selection)
        store.ensureFeedIcon(10L, FeedIconVariant.NORMAL)
        store.reset(selection)
        store.ensureFeedIcon(10L, FeedIconVariant.NORMAL)

        assertEquals(
            listOf(listOf(10L) to FeedIconVariant.NORMAL),
            calls,
        )
        assertEquals(setOf(10L), store.state.value.feedIconPngByFeedId.keys)
    }

    @Test
    fun feedIconCacheIsClearedWhenCoreSessionChanges() = runBlocking {
        var generation: Long? = 41L
        val calls = mutableListOf<Pair<List<Long>, FeedIconVariant>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                ArticlePage(
                    articles = listOf(article(1).copy(feedId = 10)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { generation },
            feedIconLoader = { ids, variant ->
                calls += ids to variant
                ids.associateWith { byteArrayOf(it.toByte()) }
            },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)

        store.reset(selection)
        store.ensureFeedIcon(10L, FeedIconVariant.NORMAL)

        generation = 42L
        store.reset(selection)
        store.ensureFeedIcon(10L, FeedIconVariant.NORMAL)

        assertEquals(
            listOf(
                listOf(10L) to FeedIconVariant.NORMAL,
                listOf(10L) to FeedIconVariant.NORMAL,
            ),
            calls,
        )
    }

    @Test
    fun audioProjectionIsBatchedOncePerLoadedPage() = runBlocking {
        val cursor = ArticleCursor(
            publishedAt = "2026-10-01T10:00:00Z",
            articleId = 2,
        )
        val audioCalls = mutableListOf<List<Long>>()
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, includeTotal ->
                if (includeTotal) {
                    ArticlePage(
                        articles = listOf(article(1), article(2)),
                        total = 3uL,
                        nextCursor = cursor,
                    )
                } else {
                    ArticlePage(
                        articles = listOf(article(2), article(3)),
                        total = null,
                        nextCursor = null,
                    )
                }
            },
            activeSessionGeneration = { 12L },
            audioArticleIdsLoader = { ids ->
                audioCalls += ids
                ids.filterTo(mutableSetOf()) { it % 2L == 1L }
            },
            testOnly = Unit,
        )

        store.reset(AndroidArticleTimelineSelection(AndroidNewsScope.All))
        store.loadNextPage()

        assertEquals(listOf(listOf(1L, 2L), listOf(3L)), audioCalls)
        assertEquals(setOf(1L, 3L), store.state.value.audioArticleIds)
    }

    @Test
    fun manualSyncReplacesSnapshotAndRequestsScrollReset() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = if (pageCalls == 1) listOf(article(1)) else listOf(article(2)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 12L },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)
        val resetRequest = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(1_000) { store.scrollResetRequests.first() }
        }

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 12L,
                event = CoreEvent.SyncDidComplete(
                    metadata = syncCompleted(
                        reason = SyncReason.MANUAL,
                        dataChanged = true,
                        feedIds = listOf(10L),
                    ),
                ),
            ),
        )

        resetRequest.await()
        assertEquals(2, pageCalls)
        assertEquals(listOf(2L), store.state.value.articles.map { it.id })
        assertFalse(store.hasPendingNewDataForScope(AndroidNewsScope.All))
    }

    @Test
    fun nonManualSyncPreservesSnapshotAndSignalsPendingNewArticles() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = listOf(article(1)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 13L },
            selectionCountLoader = { 2uL },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)

        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 13L,
                event = CoreEvent.SyncDidComplete(
                    metadata = syncCompleted(
                        reason = SyncReason.APP_START,
                        dataChanged = true,
                        feedIds = listOf(10L),
                    ),
                ),
            ),
        )

        assertEquals(1, pageCalls)
        assertEquals(listOf(1L), store.state.value.articles.map { it.id })
        assertEquals(2uL, store.state.value.total)
        assertTrue(store.hasPendingNewDataForScope(AndroidNewsScope.All))
        assertTrue(
            store.hasPendingNewDataForScope(
                scope = AndroidNewsScope.Category(20L, "Category"),
                categoryFeedIds = setOf(10L),
            ),
        )
        assertFalse(store.hasPendingNewDataForScope(AndroidNewsScope.Feed(99L, 20L, "Other")))
    }

    @Test
    fun adoptingPendingNewArticlesReloadsSnapshotAndRequestsScrollReset() = runBlocking {
        var pageCalls = 0
        val store = AndroidArticleTimelineStore(
            pageLoader = { _, _ ->
                pageCalls += 1
                ArticlePage(
                    articles = if (pageCalls == 1) listOf(article(1)) else listOf(article(2)),
                    total = 1uL,
                    nextCursor = null,
                )
            },
            activeSessionGeneration = { 14L },
            selectionCountLoader = { 2uL },
            testOnly = Unit,
        )
        val selection = AndroidArticleTimelineSelection(AndroidNewsScope.All)
        store.reset(selection)
        store.handleCoreEvent(
            AndroidCoreRuntimeEvent(
                generation = 14L,
                event = CoreEvent.SyncDidComplete(
                    metadata = syncCompleted(
                        reason = SyncReason.BACKGROUND,
                        dataChanged = true,
                        feedIds = listOf(10L),
                    ),
                ),
            ),
        )
        val resetRequest = async(start = CoroutineStart.UNDISPATCHED) {
            withTimeout(1_000) { store.scrollResetRequests.first() }
        }

        store.adoptPendingNewData(selection)

        resetRequest.await()
        assertEquals(2, pageCalls)
        assertEquals(listOf(2L), store.state.value.articles.map { it.id })
        assertFalse(store.hasPendingNewDataForScope(AndroidNewsScope.All))
    }

    @Test
    fun publishedAtParserAcceptsRfc3339Offsets() {
        assertEquals(
            1_759_320_000_000L,
            parseArticlePublishedAtMillis("2025-10-01T12:00:00Z"),
        )
        assertEquals(
            parseArticlePublishedAtMillis("2025-10-01T12:00:00Z"),
            parseArticlePublishedAtMillis("2025-10-01T14:00:00+02:00"),
        )
        assertNull(parseArticlePublishedAtMillis("not-a-date"))
    }

    private fun syncCompleted(
        reason: SyncReason,
        dataChanged: Boolean,
        feedIds: List<Long> = emptyList(),
    ): SyncCompleted = SyncCompleted(
        reason = reason,
        newArticles = feedIds.size.toUInt(),
        updatedArticles = 0u,
        mutationsDelivered = 0u,
        dataChanged = dataChanged,
        navigationChanged = dataChanged,
        newArticlesByFeed = feedIds.map { feedId ->
            NewArticlesByFeed(feedId = feedId, count = 1u)
        },
        systemNotificationCandidates = emptyList(),
    )

    private fun article(
        id: Long,
        read: Boolean = false,
        starred: Boolean = false,
        commentsUrl: String = "",
        imageUrl: String? = null,
    ): ArticleSummary = ArticleSummary(
        id = id,
        feedId = 10,
        categoryId = 20,
        feedTitle = "Feed",
        title = "Article $id",
        url = "https://example.test/$id",
        commentsUrl = commentsUrl,
        publishedAt = "2026-10-01T12:00:00Z",
        isRead = read,
        isStarred = starred,
        readingTimeMinutes = 3u,
        preview = "Preview",
        imageUrl = imageUrl,
    )
}
