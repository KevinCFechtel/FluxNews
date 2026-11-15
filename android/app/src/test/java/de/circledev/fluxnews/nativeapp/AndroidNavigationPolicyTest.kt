package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidNavigationPolicyTest {
    private val categories = listOf(
        AndroidNavigationCategoryRef(10, "Tech"),
        AndroidNavigationCategoryRef(20, "World"),
    )
    private val feeds = listOf(
        AndroidNavigationFeedRef(1, 10, "One"),
        AndroidNavigationFeedRef(2, 10, "Two"),
        AndroidNavigationFeedRef(3, 20, "Three"),
        AndroidNavigationFeedRef(4, 999, "Orphan"),
    )

    @Test
    fun startupScopeMatchesIosSemanticsAndFallsBackForMissingTargets() {
        assertEquals(
            AndroidNewsScope.Starred,
            AndroidNavigationPolicy.resolveStartupScope(
                AndroidNavigationPreferenceState(startupScope = AndroidStartupScopePreference.Starred),
                categories,
                feeds,
            ),
        )
        assertEquals(
            AndroidNewsScope.Category(10, "Tech"),
            AndroidNavigationPolicy.resolveStartupScope(
                AndroidNavigationPreferenceState(
                    startupScope = AndroidStartupScopePreference.Category,
                    startupCategoryId = 10,
                ),
                categories,
                feeds,
            ),
        )
        assertEquals(
            AndroidNewsScope.Feed(3, 20, "Three"),
            AndroidNavigationPolicy.resolveStartupScope(
                AndroidNavigationPreferenceState(
                    startupScope = AndroidStartupScopePreference.Feed,
                    startupFeedId = 3,
                ),
                categories,
                feeds,
            ),
        )
        assertEquals(
            AndroidNewsScope.All,
            AndroidNavigationPolicy.resolveStartupScope(
                AndroidNavigationPreferenceState(
                    startupScope = AndroidStartupScopePreference.Feed,
                    startupFeedId = 404,
                ),
                categories,
                feeds,
            ),
        )
    }

    @Test
    fun hideEmptyFiltersFeedsAndCategoriesButKeepsNonEmptyOrphans() {
        val visibleFeeds = AndroidNavigationPolicy.visibleFeedIds(
            hidingEmpty = true,
            feeds = feeds,
            counts = mapOf(1L to 0uL, 2L to 3uL, 3L to 0uL, 4L to 2uL),
        )
        assertEquals(setOf(2L, 4L), visibleFeeds)
        assertEquals(
            setOf(10L),
            AndroidNavigationPolicy.visibleCategoryIds(categories, feeds, visibleFeeds),
        )
    }

    @Test
    fun nextFeedUsesVisibleDrawerOrderSkipsEmptyAndNeverWraps() {
        val extendedCategories = categories + AndroidNavigationCategoryRef(30, "Science")
        val extendedFeeds = feeds + AndroidNavigationFeedRef(5, 30, "Five")
        val counts = mapOf(
            1L to 2uL,
            2L to 0uL,
            3L to 4uL,
            4L to 3uL,
            5L to 1uL,
        )

        assertEquals(
            AndroidNewsScope.Feed(3, 20, "Three"),
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.Feed(1, 10, "One"),
                hidingEmpty = true,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
        assertEquals(
            AndroidNewsScope.Feed(4, 999, "Orphan"),
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.Feed(5, 30, "Five"),
                hidingEmpty = true,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
        assertEquals(
            null,
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.Feed(4, 999, "Orphan"),
                hidingEmpty = true,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
    }

    @Test
    fun nextCategoryUsesVisibleDrawerOrderAndGlobalScopesHaveNoNext() {
        val extendedCategories = categories + AndroidNavigationCategoryRef(30, "Science")
        val extendedFeeds = feeds + AndroidNavigationFeedRef(5, 30, "Five")
        val counts = mapOf(1L to 1uL, 2L to 0uL, 3L to 0uL, 4L to 2uL, 5L to 1uL)

        assertEquals(
            AndroidNewsScope.Category(30, "Science"),
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.Category(10, "Tech"),
                hidingEmpty = true,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
        assertEquals(
            null,
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.Category(30, "Science"),
                hidingEmpty = true,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
        assertEquals(
            null,
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.All,
                hidingEmpty = false,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
        assertEquals(
            null,
            AndroidNavigationPolicy.nextScope(
                after = AndroidNewsScope.Starred,
                hidingEmpty = false,
                categories = extendedCategories,
                feeds = extendedFeeds,
                counts = counts,
            ),
        )
    }

    @Test
    fun disablingHideEmptyKeepsEveryFeed() {
        assertEquals(
            setOf(1L, 2L, 3L, 4L),
            AndroidNavigationPolicy.visibleFeedIds(
                hidingEmpty = false,
                feeds = feeds,
                counts = emptyMap(),
            ),
        )
    }
}
