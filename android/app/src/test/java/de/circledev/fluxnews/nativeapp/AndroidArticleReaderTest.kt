package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.ReaderDocument

class AndroidArticleReaderTest {
    @Test
    fun normalOpenPolicyKeepsReaderIndependentFromFeedMinifluxPreference() {
        assertEquals(
            AndroidNormalOpenDestination.Reader,
            AndroidArticleOpenPolicy.destination(
                AndroidArticleOpenPreference.Reader,
                true,
                "https://example.test/original",
                "https://example.test/miniflux",
            ),
        )
        assertEquals(
            AndroidNormalOpenDestination.Web("https://example.test/miniflux"),
            AndroidArticleOpenPolicy.destination(
                AndroidArticleOpenPreference.OriginalLink,
                true,
                "https://example.test/original",
                "https://example.test/miniflux",
            ),
        )
        assertEquals(
            AndroidNormalOpenDestination.Web("https://example.test/original"),
            AndroidArticleOpenPolicy.destination(
                AndroidArticleOpenPreference.OriginalLink,
                false,
                "https://example.test/original",
                "https://example.test/miniflux",
            ),
        )
    }

    @Test
    fun staleReaderCompletionCannotReplaceNewerArticle() = runBlocking {
        val firstRelease = CompletableDeferred<Unit>()
        val first = ReaderDocument(emptyList(), false, false)
        val second = ReaderDocument(emptyList(), true, false)
        val store = AndroidReaderStore(
            timelineLoader = { _, articleId ->
                if (articleId == 1L) {
                    firstRelease.await()
                    first
                } else {
                    second
                }
            },
            searchLoader = { _, _ -> second },
            activeSessionGeneration = { 7L },
            testOnly = Unit,
        )

        val firstJob = store.open(article(1), AndroidReaderSource.Timeline)!!
        val secondJob = store.open(article(2), AndroidReaderSource.Timeline)!!

        secondJob.join()
        firstRelease.complete(Unit)
        firstJob.join()

        assertEquals(2L, store.state.value.article?.id)
        assertEquals(second, store.state.value.document)
        assertNull(store.state.value.errorMessage)
    }

    private fun article(id: Long) = ArticleSummary(
        id = id,
        feedId = 10L,
        categoryId = 20L,
        feedTitle = "Feed",
        title = "Article",
        url = "https://example.test/article",
        commentsUrl = "",
        publishedAt = "2026-10-03T00:00:00Z",
        isRead = false,
        isStarred = false,
        readingTimeMinutes = 3u,
        preview = "Preview",
        imageUrl = null,
    )
}
