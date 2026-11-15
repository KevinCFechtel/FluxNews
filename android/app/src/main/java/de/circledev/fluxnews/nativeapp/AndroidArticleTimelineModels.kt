package de.circledev.fluxnews.nativeapp

import uniffi.flux_uniffi.ArticleCursor
import uniffi.flux_uniffi.ArticleQuery
import uniffi.flux_uniffi.ArticleScope
import uniffi.flux_uniffi.ArticleSort
import uniffi.flux_uniffi.ReadFilter
import uniffi.flux_uniffi.StarredFilter

private const val ANDROID_ARTICLE_TIMELINE_PAGE_SIZE = 64

internal enum class AndroidArticleReadFilter {
    Unread,
    All,
}

internal enum class AndroidArticleSortOrder {
    OldestFirst,
    NewestFirst,
}

internal enum class AndroidArticleAccessory {
    Unread,
    Star,
    Comments,
    Audio,
}

internal enum class AndroidArticleRowLayoutVariant {
    Compact,
    VisualTextOnly,
    VisualPortrait,
    VisualLandscape,
    VisualCompactTextOnly,
    VisualCompactNarrow,
    VisualCompactWide,
}

/**
 * Transient Article List selection. Scope comes from the app shell while read/sort remain
 * presentation controls; none of this state is persisted as a second domain truth.
 */
internal data class AndroidArticleTimelineSelection(
    val scope: AndroidNewsScope,
    val readFilter: AndroidArticleReadFilter = AndroidArticleReadFilter.Unread,
    val sort: AndroidArticleSortOrder = AndroidArticleSortOrder.OldestFirst,
) {
    fun selectingScope(scope: AndroidNewsScope): AndroidArticleTimelineSelection =
        copy(scope = scope)

    fun togglingReadFilter(): AndroidArticleTimelineSelection =
        if (scope == AndroidNewsScope.Starred) {
            this
        } else {
            copy(
                readFilter = when (readFilter) {
                    AndroidArticleReadFilter.Unread -> AndroidArticleReadFilter.All
                    AndroidArticleReadFilter.All -> AndroidArticleReadFilter.Unread
                },
            )
        }

    fun togglingSortOrder(): AndroidArticleTimelineSelection =
        copy(
            sort = when (sort) {
                AndroidArticleSortOrder.OldestFirst -> AndroidArticleSortOrder.NewestFirst
                AndroidArticleSortOrder.NewestFirst -> AndroidArticleSortOrder.OldestFirst
            },
        )

    fun markAllReadQuery(): ArticleQuery {
        val base = coreQuery()
        return ArticleQuery(
            scope = base.scope,
            readFilter = ReadFilter.UNREAD,
            starredFilter = StarredFilter.ALL,
            sort = ArticleSort.NEWEST_FIRST,
            limit = 0u,
            cursor = null,
        )
    }

    fun coreQuery(cursor: ArticleCursor? = null): ArticleQuery {
        val coreScope = when (scope) {
            AndroidNewsScope.All,
            AndroidNewsScope.Starred,
            -> ArticleScope.All
            is AndroidNewsScope.Category -> ArticleScope.Category(id = scope.id)
            is AndroidNewsScope.Feed -> ArticleScope.Feed(id = scope.id)
        }
        return ArticleQuery(
            scope = coreScope,
            readFilter = if (scope == AndroidNewsScope.Starred) {
                ReadFilter.ALL
            } else {
                when (readFilter) {
                    AndroidArticleReadFilter.Unread -> ReadFilter.UNREAD
                    AndroidArticleReadFilter.All -> ReadFilter.ALL
                }
            },
            starredFilter = if (scope == AndroidNewsScope.Starred) StarredFilter.STARRED else StarredFilter.ALL,
            sort = when (sort) {
                AndroidArticleSortOrder.OldestFirst -> ArticleSort.OLDEST_FIRST
                AndroidArticleSortOrder.NewestFirst -> ArticleSort.NEWEST_FIRST
            },
            limit = ANDROID_ARTICLE_TIMELINE_PAGE_SIZE.toUInt(),
            cursor = cursor,
        )
    }
}
