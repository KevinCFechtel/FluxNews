package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged

internal enum class AndroidStartupScopePreference(
    val storedValue: String,
    val displayName: String,
) {
    AllNews("allNews", "All News"),
    Starred("starred", "Starred"),
    Category("category", "Category"),
    Feed("feed", "Feed"),
    ;

    companion object {
        fun fromStoredValue(value: String): AndroidStartupScopePreference =
            entries.firstOrNull { it.storedValue == value } ?: AllNews
    }
}

internal data class AndroidNavigationPreferenceState(
    val hideEmptyNavigationEntries: Boolean = false,
    val startupScope: AndroidStartupScopePreference = AndroidStartupScopePreference.AllNews,
    val startupCategoryId: Long? = null,
    val startupFeedId: Long? = null,
)

internal data class AndroidNavigationCategoryRef(
    val id: Long,
    val title: String,
)

internal data class AndroidNavigationFeedRef(
    val id: Long,
    val categoryId: Long,
    val title: String,
)

/** Product-level news scopes shared by the Android navigation shell and the E3 timeline. */
internal sealed interface AndroidNewsScope {
    data object All : AndroidNewsScope
    data object Starred : AndroidNewsScope
    data class Category(val id: Long, val title: String) : AndroidNewsScope
    data class Feed(val id: Long, val categoryId: Long, val title: String) : AndroidNewsScope
}

/**
 * Pure presentation policy matching the completed iOS Navigation settings semantics.
 * Invalid persisted category/feed startup targets safely fall back to All News.
 */
internal object AndroidNavigationPolicy {
    fun resolveStartupScope(
        preferences: AndroidNavigationPreferenceState,
        categories: List<AndroidNavigationCategoryRef>,
        feeds: List<AndroidNavigationFeedRef>,
    ): AndroidNewsScope = when (preferences.startupScope) {
        AndroidStartupScopePreference.AllNews -> AndroidNewsScope.All
        AndroidStartupScopePreference.Starred -> AndroidNewsScope.Starred
        AndroidStartupScopePreference.Category -> {
            categories.firstOrNull { it.id == preferences.startupCategoryId }
                ?.let { AndroidNewsScope.Category(it.id, it.title) }
                ?: AndroidNewsScope.All
        }
        AndroidStartupScopePreference.Feed -> {
            feeds.firstOrNull { it.id == preferences.startupFeedId }
                ?.let { AndroidNewsScope.Feed(it.id, it.categoryId, it.title) }
                ?: AndroidNewsScope.All
        }
    }

    fun visibleFeedIds(
        hidingEmpty: Boolean,
        feeds: List<AndroidNavigationFeedRef>,
        counts: Map<Long, ULong>,
    ): Set<Long> = feeds
        .asSequence()
        .filter { !hidingEmpty || (counts[it.id] ?: 0uL) > 0uL }
        .mapTo(mutableSetOf()) { it.id }

    fun visibleCategoryIds(
        categories: List<AndroidNavigationCategoryRef>,
        feeds: List<AndroidNavigationFeedRef>,
        visibleFeedIds: Set<Long>,
    ): Set<Long> {
        val knownCategoryIds = categories.mapTo(mutableSetOf()) { it.id }
        return feeds
            .asSequence()
            .filter { it.id in visibleFeedIds && it.categoryId in knownCategoryIds }
            .mapTo(mutableSetOf()) { it.categoryId }
    }

    /**
     * Mark All & Next follows the same order the news drawer presents. There is no wrap-around and
     * global scopes never invent a sibling target.
     */
    fun nextScope(
        after: AndroidNewsScope,
        hidingEmpty: Boolean,
        categories: List<AndroidNavigationCategoryRef>,
        feeds: List<AndroidNavigationFeedRef>,
        counts: Map<Long, ULong>,
    ): AndroidNewsScope? {
        val visibleFeedIds = visibleFeedIds(
            hidingEmpty = hidingEmpty,
            feeds = feeds,
            counts = counts,
        )
        val visibleCategoryIds = if (hidingEmpty) {
            visibleCategoryIds(categories, feeds, visibleFeedIds)
        } else {
            categories.mapTo(mutableSetOf()) { it.id }
        }

        return when (after) {
            is AndroidNewsScope.Feed -> {
                val knownCategoryIds = categories.mapTo(mutableSetOf()) { it.id }
                val orderedFeeds = buildList {
                    categories
                        .filter { it.id in visibleCategoryIds }
                        .forEach { category ->
                            addAll(
                                feeds.filter {
                                    it.categoryId == category.id && it.id in visibleFeedIds
                                },
                            )
                        }
                    addAll(
                        feeds.filter {
                            it.categoryId !in knownCategoryIds && it.id in visibleFeedIds
                        },
                    )
                }
                val index = orderedFeeds.indexOfFirst { it.id == after.id }
                orderedFeeds
                    .getOrNull(index + 1)
                    ?.takeIf { index >= 0 }
                    ?.let { AndroidNewsScope.Feed(it.id, it.categoryId, it.title) }
            }

            is AndroidNewsScope.Category -> {
                val orderedCategories = categories.filter { it.id in visibleCategoryIds }
                val index = orderedCategories.indexOfFirst { it.id == after.id }
                orderedCategories
                    .getOrNull(index + 1)
                    ?.takeIf { index >= 0 }
                    ?.let { AndroidNewsScope.Category(it.id, it.title) }
            }

            AndroidNewsScope.All,
            AndroidNewsScope.Starred,
            -> null
        }
    }
}

/** Platform-local E2 navigation preferences. No shared Core state is duplicated here. */
internal class AndroidNavigationPreferences(
    private val store: AndroidPreferenceStore,
) {
    private val hideEmptyKey = AndroidPreferenceKey.boolean("navigation-hide-empty")
    private val startupScopeKey = AndroidPreferenceKey.string("navigation-startup-scope")
    private val startupCategoryKey = AndroidPreferenceKey.long("navigation-startup-category")
    private val startupFeedKey = AndroidPreferenceKey.long("navigation-startup-feed")

    val state: Flow<AndroidNavigationPreferenceState> = combine(
        store.observe(hideEmptyKey, false),
        store.observe(startupScopeKey, AndroidStartupScopePreference.AllNews.storedValue),
        store.observe(startupCategoryKey, NO_SELECTION),
        store.observe(startupFeedKey, NO_SELECTION),
    ) { hideEmpty, startupScope, startupCategory, startupFeed ->
        AndroidNavigationPreferenceState(
            hideEmptyNavigationEntries = hideEmpty,
            startupScope = AndroidStartupScopePreference.fromStoredValue(startupScope),
            startupCategoryId = startupCategory.takeUnless { it == NO_SELECTION },
            startupFeedId = startupFeed.takeUnless { it == NO_SELECTION },
        )
    }.distinctUntilChanged()

    suspend fun setHideEmptyNavigationEntries(value: Boolean) {
        store.write(hideEmptyKey, value)
    }

    suspend fun setStartupScope(value: AndroidStartupScopePreference) {
        store.write(startupScopeKey, value.storedValue)
    }

    suspend fun setStartupCategoryId(value: Long?) {
        if (value == null) store.remove(startupCategoryKey) else store.write(startupCategoryKey, value)
    }

    suspend fun setStartupFeedId(value: Long?) {
        if (value == null) store.remove(startupFeedKey) else store.write(startupFeedKey, value)
    }

    private companion object {
        const val NO_SELECTION = Long.MIN_VALUE
    }
}
