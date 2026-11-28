package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import java.text.NumberFormat

internal data class AndroidArticleTagLayout(
    val visibleCount: Int = 0,
    val firstTagMaxWidth: Int = 0,
    val showsOverflow: Boolean = false,
    val showsIcon: Boolean = false,
)

internal object AndroidArticleTagPolicy {
    fun labels(tags: List<String>): List<String> =
        tags.map { it.replace(Regex("\\s+"), " ").trim() }.filter { it.isNotEmpty() }.distinct()

    /** Only residual publication width is offered here; never take space from the date. */
    fun layout(
        firstTagWidth: Int,
        minimumTagWidth: Int,
        totalCount: Int,
        availableWidth: Int,
        spacing: Int,
        iconWidth: Int,
        overflowWidth: (Int) -> Int,
    ): AndroidArticleTagLayout {
        if (totalCount == 0 || availableWidth <= 0) return AndroidArticleTagLayout()
        val leading = iconWidth + spacing
        val trailing = if (totalCount > 1) spacing + overflowWidth(totalCount - 1) else 0
        val remaining = availableWidth - leading - trailing
        if (remaining >= minOf(firstTagWidth, minimumTagWidth)) {
            return AndroidArticleTagLayout(
                visibleCount = 1,
                firstTagMaxWidth = minOf(firstTagWidth, remaining),
                showsOverflow = totalCount > 1,
                showsIcon = true,
            )
        }
        // A counter alone still needs a tag symbol to disambiguate it.
        return if (iconWidth + spacing + overflowWidth(totalCount) <= availableWidth) {
            AndroidArticleTagLayout(showsOverflow = true, showsIcon = true)
        } else AndroidArticleTagLayout()
    }
}

@Composable
internal fun ArticleTagsRow(labels: List<String>, isRead: Boolean) {
    if (labels.isEmpty()) return
    val locale = LocalConfiguration.current.locales[0]
    val numberFormat = remember(locale) { NumberFormat.getIntegerInstance(locale) }
    val overflowLabels = (0..1).associateWith {
        stringResource(R.string.article_tags_more, numberFormat.format(labels.size - it))
    }
    val style = MaterialTheme.typography.labelSmall
    val color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (isRead) 0.75f else 1f)
    val background = MaterialTheme.colorScheme.surfaceContainerHigh
    val iconSide = with(LocalDensity.current) { style.fontSize.toDp() }
    val textMeasurer = rememberTextMeasurer()
    val labelModifier = Modifier
        .clip(RoundedCornerShape(3.dp)).background(background).padding(horizontal = 3.dp)
    // Full topic accessibility belongs to the publication group, even if no tag fits.
    SubcomposeLayout(modifier = Modifier.clearAndSetSemantics {}) { constraints ->
        val width = constraints.maxWidth
        val gap = 4.dp.roundToPx()
        val childConstraints = Constraints(maxWidth = width)
        fun label(available: Int, key: String) = subcompose(key) {
            Text(
                labels.first(), modifier = labelModifier, style = style, color = color,
                maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
            )
        }.single().measure(Constraints(maxWidth = available))
        val horizontalPadding = 6.dp.roundToPx()
        val icon = subcompose("icon") {
            Icon(painterResource(R.drawable.ic_tag), contentDescription = null, tint = color, modifier = Modifier.size(iconSide))
        }.single().measure(childConstraints)
        val counters = (0..1).associateWith { visible ->
            subcompose("overflow:$visible") {
                Text(
                    overflowLabels.getValue(visible), style = style, color = color,
                    maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
                )
            }.single().measure(childConstraints)
        }
        val fit = AndroidArticleTagPolicy.layout(
            firstTagWidth = textMeasurer.measure(
                AnnotatedString(labels.first()), style, softWrap = false, maxLines = 1,
            ).size.width + horizontalPadding,
            minimumTagWidth = textMeasurer.measure(AnnotatedString("MM…"), style).size.width + horizontalPadding,
            totalCount = labels.size, availableWidth = width, spacing = gap,
            iconWidth = icon.width,
            // Require the full counter, rather than its constrained/ellipsized width.
            overflowWidth = { hidden ->
                textMeasurer.measure(AnnotatedString(overflowLabels.getValue(labels.size - hidden)), style).size.width
            },
        )
        val shownLabel = if (fit.visibleCount == 1) label(fit.firstTagMaxWidth, "fitted") else null
        val counter = if (fit.showsOverflow) counters.getValue(fit.visibleCount) else null
        val children = listOfNotNull(if (fit.showsIcon) icon else null, shownLabel, counter)
        val usedWidth = children.sumOf { it.width } + gap * (children.size - 1).coerceAtLeast(0)
        val height = children.maxOfOrNull { it.height } ?: 0
        layout(usedWidth, height) {
            var x = 0
            children.forEach {
                it.placeRelative(x, (height - it.height) / 2)
                x += it.width + gap
            }
        }
    }
}
