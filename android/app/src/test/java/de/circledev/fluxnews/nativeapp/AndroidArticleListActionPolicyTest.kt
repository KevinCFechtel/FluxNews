package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidArticleListActionPolicyTest {
    @Test
    fun markAllAvailabilityMatchesSharedScopeSemantics() {
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllRead,
                AndroidNewsScope.All,
                hasNextScope = false,
            ),
        )
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllRead,
                AndroidNewsScope.Category(1, "Category"),
                hasNextScope = false,
            ),
        )
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllRead,
                AndroidNewsScope.Feed(2, 1, "Feed"),
                hasNextScope = false,
            ),
        )
        assertFalse(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllRead,
                AndroidNewsScope.Starred,
                hasNextScope = false,
            ),
        )
    }

    @Test
    fun markAllAndNextRequiresCategoryOrFeedWithNextSibling() {
        assertFalse(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllReadAndNext,
                AndroidNewsScope.All,
                hasNextScope = true,
            ),
        )
        assertFalse(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllReadAndNext,
                AndroidNewsScope.Starred,
                hasNextScope = true,
            ),
        )
        assertFalse(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllReadAndNext,
                AndroidNewsScope.Feed(2, 1, "Feed"),
                hasNextScope = false,
            ),
        )
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllReadAndNext,
                AndroidNewsScope.Feed(2, 1, "Feed"),
                hasNextScope = true,
            ),
        )
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                AndroidActionBarAction.MarkAllReadAndNext,
                AndroidNewsScope.Category(1, "Category"),
                hasNextScope = true,
            ),
        )
    }

    @Test
    fun configuredPriorityFillsDirectSlotsAndOverflowKeepsAllOtherAvailableActions() {
        val configured = listOf(
            AndroidActionBarAction.Search,
            AndroidActionBarAction.MarkAllRead,
            AndroidActionBarAction.FilterAndSort,
        )

        val resolved = AndroidArticleListActionPolicy.resolvedActions(
            configuredActions = configured,
            directCapacity = 2,
            scope = AndroidNewsScope.All,
            hasNextScope = false,
        )

        assertEquals(
            listOf(AndroidActionBarAction.Search, AndroidActionBarAction.MarkAllRead),
            resolved.direct,
        )
        assertEquals(AndroidActionBarAction.FilterAndSort, resolved.overflow.first())
        assertTrue(AndroidActionBarAction.ToggleReadFilter in resolved.overflow)
        assertTrue(AndroidActionBarAction.ToggleSortOrder in resolved.overflow)
        assertTrue(AndroidActionBarAction.ListeningList in resolved.overflow)
        assertTrue(AndroidActionBarAction.Settings in resolved.overflow)
        assertFalse(AndroidActionBarAction.MarkAllReadAndNext in resolved.overflow)
    }

    @Test
    fun contextFilteringNeverMutatesConfiguredMeaning() {
        val configured = listOf(
            AndroidActionBarAction.MarkAllReadAndNext,
            AndroidActionBarAction.Search,
            AndroidActionBarAction.MarkAllReadAndNext,
        )

        val resolved = AndroidArticleListActionPolicy.resolvedActions(
            configuredActions = configured,
            directCapacity = 1,
            scope = AndroidNewsScope.Starred,
            hasNextScope = true,
        )

        assertEquals(listOf(AndroidActionBarAction.Search), resolved.direct)
        assertFalse(AndroidActionBarAction.MarkAllReadAndNext in resolved.overflow)
        assertEquals(
            listOf(
                AndroidActionBarAction.MarkAllReadAndNext,
                AndroidActionBarAction.Search,
                AndroidActionBarAction.MarkAllReadAndNext,
            ),
            configured,
        )
    }
}
