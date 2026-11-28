package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import java.text.NumberFormat

internal data class AndroidArticleTagLayout(
    val visibleCount: Int,
    val firstTagMaxWidth: Int? = null,
)

/** Fits complete labels first, truncating only a lone oversized first label. */
internal object AndroidArticleTagPolicy {
    const val MAX_VISIBLE = 3

    fun layout(
        tagWidths: List<Int>,
        totalCount: Int,
        availableWidth: Int,
        spacing: Int,
        overflowWidth: (Int) -> Int,
    ): AndroidArticleTagLayout {
        if (totalCount == 0 || availableWidth <= 0) return AndroidArticleTagLayout(0)
        for (count in minOf(MAX_VISIBLE, totalCount, tagWidths.size) downTo 1) {
            val hidden = totalCount - count
            val trailing = if (hidden > 0) spacing + overflowWidth(hidden) else 0
            if (tagWidths.take(count).sum() + spacing * (count - 1) + trailing <= availableWidth) {
                return AndroidArticleTagLayout(count)
            }
        }
        val hidden = totalCount - 1
        val remaining = availableWidth - if (hidden > 0) spacing + overflowWidth(hidden) else 0
        return if (remaining > 0 && tagWidths.isNotEmpty()) {
            AndroidArticleTagLayout(1, firstTagMaxWidth = remaining)
        } else {
            AndroidArticleTagLayout(0)
        }
    }
}

@Composable
internal fun ArticleTagsRow(tags: List<String>, isRead: Boolean) {
    val labels = remember(tags) {
        tags.map { it.replace(Regex("\\s+"), " ").trim() }.filter { it.isNotEmpty() }.distinct()
    }
    if (labels.isEmpty()) return
    val locale = LocalConfiguration.current.locales[0]
    val numberFormat = remember(locale) { NumberFormat.getIntegerInstance(locale) }
    val accessibilityLabel = stringResource(
        R.string.article_tags_accessibility,
        android.icu.text.ListFormatter.getInstance(locale).format(labels),
    )
    // Only up to three candidates and their possible overflow counts are measured.
    val overflowLabels = (0..minOf(AndroidArticleTagPolicy.MAX_VISIBLE, labels.size)).associateWith {
        stringResource(R.string.article_tags_more, numberFormat.format(labels.size - it))
    }
    val style = MaterialTheme.typography.labelSmall
    val color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (isRead) 0.75f else 1f)
    val background = MaterialTheme.colorScheme.surfaceContainerHigh
    SubcomposeLayout(
        modifier = Modifier.clearAndSetSemantics { contentDescription = accessibilityLabel },
    ) { constraints ->
        val width = constraints.maxWidth
        val gap = 5.dp.roundToPx()
        val childConstraints = Constraints(maxWidth = width)
        val candidates = labels.take(AndroidArticleTagPolicy.MAX_VISIBLE).mapIndexed { index, label ->
            subcompose("tag:$index") {
                Text(
                    label,
                    modifier = Modifier.clip(RoundedCornerShape(4.dp))
                        .background(background).padding(horizontal = 6.dp, vertical = 2.dp),
                    style = style,
                    color = color,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                )
            }.single().measure(childConstraints)
        }
        val overflow = mutableMapOf<Int, androidx.compose.ui.layout.Placeable>()
        fun overflowFor(visible: Int) = overflow.getOrPut(visible) {
            subcompose("overflow:$visible") {
                Text(
                    overflowLabels.getValue(visible),
                    style = style,
                    color = color,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                )
            }.single().measure(childConstraints)
        }
        val fit = AndroidArticleTagPolicy.layout(
            tagWidths = candidates.map { it.width },
            totalCount = labels.size,
            availableWidth = width,
            spacing = gap,
            overflowWidth = { hidden -> overflowFor(labels.size - hidden).width },
        )
        val visible = if (fit.firstTagMaxWidth != null) {
            listOf(subcompose("truncatedFirst") {
                Text(
                    labels.first(),
                    modifier = Modifier.clip(RoundedCornerShape(4.dp))
                        .background(background).padding(horizontal = 6.dp, vertical = 2.dp),
                    style = style,
                    color = color,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                )
            }.single().measure(Constraints(maxWidth = fit.firstTagMaxWidth)))
        } else candidates.take(fit.visibleCount)
        val trailing = if (labels.size > fit.visibleCount) overflowFor(fit.visibleCount) else null
        val height = maxOf(visible.maxOfOrNull { it.height } ?: 0, trailing?.height ?: 0)
        layout(width, height) {
            var x = 0
            visible.forEach {
                it.placeRelative(x, (height - it.height) / 2)
                x += it.width + gap
            }
            trailing?.placeRelative(x, (height - trailing.height) / 2)
        }
    }
}
