package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.DownloadState

class AndroidArticleActionsTest {
    @Test
    fun conditionalOuterSwipeActionIsOmittedWithoutPromotingInnerAction() {
        val configuration = AndroidArticleSwipeConfiguration(
            leading = listOf(
                AndroidArticleSwipeAction.ReadUnread,
                AndroidArticleSwipeAction.Comments,
            ),
            trailing = emptyList(),
        )

        val resolved = AndroidArticleActionPolicy.resolveSwipeSide(
            configuration = configuration,
            side = AndroidArticleSwipeSide.Leading,
            article = article(commentsUrl = ""),
            hasAudio = false,
        )

        assertEquals(AndroidArticleSwipeAction.ReadUnread, resolved.additional)
        assertNull(resolved.full)
        assertEquals(listOf(AndroidArticleSwipeAction.ReadUnread), resolved.visibleActions)
    }

    @Test
    fun validOuterSwipeActionKeepsConfiguredFullSwipeMeaning() {
        val configuration = AndroidArticleSwipeConfiguration(
            leading = listOf(
                AndroidArticleSwipeAction.ReadUnread,
                AndroidArticleSwipeAction.Comments,
            ),
            trailing = emptyList(),
        )

        val resolved = AndroidArticleActionPolicy.resolveSwipeSide(
            configuration = configuration,
            side = AndroidArticleSwipeSide.Leading,
            article = article(commentsUrl = "https://example.test/comments"),
            hasAudio = false,
        )

        assertEquals(AndroidArticleSwipeAction.ReadUnread, resolved.additional)
        assertEquals(AndroidArticleSwipeAction.Comments, resolved.full)
    }

    @Test
    fun mediaSwipePolicyEnablesListeningListAndDownloadsOnlyForAudio() {
        val article = article()
        assertFalse(
            AndroidArticleActionPolicy.isSwipeActionAvailable(
                AndroidArticleSwipeAction.ListeningList,
                article,
                hasAudio = true,
            ),
        )
        assertTrue(
            AndroidArticleActionPolicy.isSwipeActionAvailable(
                AndroidArticleSwipeAction.ListeningList,
                article,
                hasAudio = true,
                mediaActionsEnabled = true,
            ),
        )
        assertFalse(
            AndroidArticleActionPolicy.isSwipeActionAvailable(
                AndroidArticleSwipeAction.ListeningList,
                article,
                hasAudio = false,
                mediaActionsEnabled = true,
            ),
        )
        assertTrue(
            AndroidArticleActionPolicy.isSwipeActionAvailable(
                AndroidArticleSwipeAction.DownloadAudio,
                article,
                hasAudio = true,
                mediaActionsEnabled = true,
            ),
        )
        assertFalse(
            AndroidArticleActionPolicy.isSwipeActionAvailable(
                AndroidArticleSwipeAction.DownloadAudio,
                article,
                hasAudio = false,
                mediaActionsEnabled = true,
            ),
        )
        assertTrue(
            AndroidArticleActionPolicy.isSwipeActionAvailable(
                AndroidArticleSwipeAction.StarUnstar,
                article,
                hasAudio = false,
            ),
        )
    }

    @Test
    fun contextActionsOmitInvalidUrlsButKeepCoreBackedActions() {
        val invalid = article(url = "not a url", commentsUrl = "")
        val actions = AndroidArticleActionPolicy.contextActions(invalid)

        assertTrue(AndroidArticleContextAction.ReadUnread in actions)
        assertTrue(AndroidArticleContextAction.StarUnstar in actions)
        assertTrue(AndroidArticleContextAction.Reader in actions)
        assertTrue(AndroidArticleContextAction.OpenMiniflux in actions)
        assertTrue(AndroidArticleContextAction.SaveToService in actions)
        assertFalse(AndroidArticleContextAction.OpenOriginal in actions)
        assertFalse(AndroidArticleContextAction.Comments in actions)
        assertFalse(AndroidArticleContextAction.CopyLink in actions)
        assertFalse(AndroidArticleContextAction.Share in actions)
    }

    @Test
    fun legacyDeepLinkRoutingRemovesGenericBrowserHandlers() {
        assertEquals(
            listOf("com.example.news", "com.example.social"),
            AndroidWebRoutingPolicy.dedicatedHandlerPackages(
                specificUrlHandlers = setOf(
                    "com.example.browser",
                    "com.example.news",
                    "com.example.social",
                ),
                genericWebHandlers = setOf(
                    "com.example.browser",
                    "org.example.otherbrowser",
                ),
            ),
        )
        assertTrue(
            AndroidWebRoutingPolicy.dedicatedHandlerPackages(
                specificUrlHandlers = setOf("com.example.browser"),
                genericWebHandlers = setOf("com.example.browser"),
            ).isEmpty(),
        )
    }

    @Test
    fun materialSwipePresentationArmsOnlyAtTheFullSwipeThreshold() {
        assertFalse(AndroidSwipePresentationPolicy.isFullSwipeArmed(57f, 100f, true))
        assertTrue(AndroidSwipePresentationPolicy.isFullSwipeArmed(58f, 100f, true))
        assertFalse(AndroidSwipePresentationPolicy.isFullSwipeArmed(100f, 100f, false))
    }

    @Test
    fun swipePresentationKeepsTwoFlatActionZonesUntilFullSwipeIsArmed() {
        val resolved = AndroidResolvedSwipeSide(
            additional = AndroidArticleSwipeAction.StarUnstar,
            full = AndroidArticleSwipeAction.ReadUnread,
        )

        assertEquals(
            listOf(
                AndroidArticleSwipeAction.ReadUnread,
                AndroidArticleSwipeAction.StarUnstar,
            ),
            AndroidSwipePresentationPolicy.presentationActions(
                side = AndroidArticleSwipeSide.Leading,
                resolved = resolved,
                fullSwipeArmed = false,
            ),
        )
        assertEquals(
            listOf(AndroidArticleSwipeAction.ReadUnread),
            AndroidSwipePresentationPolicy.presentationActions(
                side = AndroidArticleSwipeSide.Leading,
                resolved = resolved,
                fullSwipeArmed = true,
            ),
        )
        assertEquals(
            listOf(
                AndroidArticleSwipeAction.StarUnstar,
                AndroidArticleSwipeAction.ReadUnread,
            ),
            AndroidSwipePresentationPolicy.presentationActions(
                side = AndroidArticleSwipeSide.Trailing,
                resolved = resolved,
                fullSwipeArmed = false,
            ),
        )
    }

    @Test
    fun everySwipeActionHasAnIndependentSemanticColor() {
        assertEquals(
            AndroidArticleSwipeAction.entries.size,
            AndroidArticleSwipeAction.entries.map(::swipeActionHue).toSet().size,
        )
    }

    @Test
    fun reversibleSwipeActionsUseDifferentIconsForOppositeStates() {
        val article = article()
        assertTrue(
            swipeActionIcon(AndroidArticleSwipeAction.ReadUnread, article) !=
                swipeActionIcon(AndroidArticleSwipeAction.ReadUnread, article.copy(isRead = true)),
        )
        assertTrue(
            swipeActionIcon(AndroidArticleSwipeAction.StarUnstar, article) !=
                swipeActionIcon(AndroidArticleSwipeAction.StarUnstar, article.copy(isStarred = true)),
        )
        assertTrue(
            swipeActionIcon(
                AndroidArticleSwipeAction.ListeningList,
                article,
                AndroidArticleMediaActionState(hasAudio = true, isInListeningList = false),
            ) != swipeActionIcon(
                AndroidArticleSwipeAction.ListeningList,
                article,
                AndroidArticleMediaActionState(hasAudio = true, isInListeningList = true),
            ),
        )
    }

    @Test
    fun downloadSwipeIconsDescribeEachDownloadState() {
        val states = listOf(
            DownloadState.NOT_DOWNLOADED,
            DownloadState.REQUESTED,
            DownloadState.DOWNLOADED,
            DownloadState.FAILED,
            DownloadState.DELETE_REQUESTED,
        )
        assertEquals(states.size, states.map(::swipeDownloadActionIcon).toSet().size)
    }

    @Test
    fun urlValidationAcceptsOnlyHttpAndHttpsWebUrls() {
        assertTrue(AndroidArticleActionPolicy.validWebUrl("https://example.test/article"))
        assertTrue(AndroidArticleActionPolicy.validWebUrl("http://example.test/article"))
        assertFalse(AndroidArticleActionPolicy.validWebUrl("mailto:test@example.test"))
        assertFalse(AndroidArticleActionPolicy.validWebUrl("javascript:alert(1)"))
        assertFalse(AndroidArticleActionPolicy.validWebUrl("not a url"))
    }

    private fun article(
        url: String = "https://example.test/article",
        commentsUrl: String = "",
    ): ArticleSummary = ArticleSummary(
        id = 1L,
        feedId = 10L,
        categoryId = 20L,
        feedTitle = "Feed",
        title = "Article",
        url = url,
        commentsUrl = commentsUrl,
        publishedAt = "2026-10-01T12:00:00Z",
        isRead = false,
        isStarred = false,
        readingTimeMinutes = 3u,
        preview = "Preview",
        imageUrl = null,
    )
}
