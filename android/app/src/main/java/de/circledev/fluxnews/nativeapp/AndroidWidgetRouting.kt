package de.circledev.fluxnews.nativeapp

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal class AndroidWidgetRouting {
    private val mutablePendingArticleId = MutableStateFlow<Long?>(null)
    val pendingArticleId: StateFlow<Long?> = mutablePendingArticleId.asStateFlow()

    fun routeIntent(intent: Intent?): Boolean {
        if (intent?.action != ACTION_OPEN_ARTICLE) return false
        val articleId = intent.getLongExtra(EXTRA_ARTICLE_ID, INVALID_ARTICLE_ID)
        if (articleId == INVALID_ARTICLE_ID) return false
        mutablePendingArticleId.value = articleId
        return true
    }

    fun consumeArticle(articleId: Long) {
        mutablePendingArticleId.compareAndSet(articleId, null)
    }

    companion object {
        const val ACTION_OPEN_ARTICLE = "de.circle_dev.flux_news.action.OPEN_WIDGET_ARTICLE"
        const val EXTRA_ARTICLE_ID = "flux.widget.articleId"
        private const val INVALID_ARTICLE_ID = Long.MIN_VALUE
    }
}
