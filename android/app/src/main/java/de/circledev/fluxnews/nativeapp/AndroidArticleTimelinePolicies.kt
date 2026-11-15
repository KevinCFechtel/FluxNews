package de.circledev.fluxnews.nativeapp

import androidx.compose.ui.text.font.FontWeight
import java.time.Instant
import java.time.OffsetDateTime
import uniffi.flux_uniffi.ArticleSummary

internal object AndroidArticleStatusPresentationPolicy {
    fun titleFontWeight(@Suppress("UNUSED_PARAMETER") isRead: Boolean): FontWeight =
        FontWeight.SemiBold

    fun titleAlpha(isRead: Boolean): Float = if (isRead) 0.62f else 1f

    fun supportingAlpha(isRead: Boolean): Float = if (isRead) 0.50f else 0.80f
}

internal object AndroidArticleRowPolicy {
    private const val WIDE_LAYOUT_THRESHOLD_DP = 600

    fun accessories(article: ArticleSummary, hasAudio: Boolean): List<AndroidArticleAccessory> = buildList {
        if (!article.isRead) add(AndroidArticleAccessory.Unread)
        if (article.isStarred) add(AndroidArticleAccessory.Star)
        if (article.commentsUrl.isNotBlank()) add(AndroidArticleAccessory.Comments)
        if (hasAudio) add(AndroidArticleAccessory.Audio)
    }

    fun showsImage(mode: AndroidArticlePresentationMode, imageUrl: String?): Boolean =
        mode != AndroidArticlePresentationMode.Compact && !imageUrl.isNullOrBlank()

    fun layoutVariant(
        mode: AndroidArticlePresentationMode,
        imageUrl: String?,
        availableWidthDp: Int,
    ): AndroidArticleRowLayoutVariant {
        val hasImage = showsImage(mode, imageUrl)
        val wide = availableWidthDp > WIDE_LAYOUT_THRESHOLD_DP
        return when (mode) {
            AndroidArticlePresentationMode.Compact -> AndroidArticleRowLayoutVariant.Compact
            AndroidArticlePresentationMode.Visual -> when {
                !hasImage -> AndroidArticleRowLayoutVariant.VisualTextOnly
                wide -> AndroidArticleRowLayoutVariant.VisualLandscape
                else -> AndroidArticleRowLayoutVariant.VisualPortrait
            }
            AndroidArticlePresentationMode.VisualCompact -> when {
                !hasImage -> AndroidArticleRowLayoutVariant.VisualCompactTextOnly
                wide -> AndroidArticleRowLayoutVariant.VisualCompactWide
                else -> AndroidArticleRowLayoutVariant.VisualCompactNarrow
            }
        }
    }
}

/**
 * The preview shares the narrow column only while a new text line can begin
 * above the thumbnail's bottom. It can finish a little below that edge; its
 * successor then starts at full width without an extra paragraph gap.
 *
 * Line coordinates and character indices come from Compose TextMeasurer.
 * This pure policy is shared with unit tests and caps the total preview lines.
 */
internal data class AndroidVisualCompactPreviewBreak(
    val sideLines: Int,
    val splitIndex: Int,
) {
    fun sideText(preview: String, totalLineLimit: Int): String =
        if (sideLines == 0) "" else if (sideLines >= totalLineLimit) preview
        else preview.substring(0, splitIndex).trimEnd()

    fun continuationText(preview: String, totalLineLimit: Int): String =
        if (sideLines >= totalLineLimit) "" else preview.substring(splitIndex).trimStart()

    fun continuationLines(totalLineLimit: Int): Int = (totalLineLimit - sideLines).coerceAtLeast(0)
}

internal object AndroidVisualCompactFlowPolicy {
    fun breakFor(
        textLength: Int,
        maximumLines: Int,
        availableSideHeightPx: Float,
        measuredLineCount: Int,
        lineTopPx: (Int) -> Float,
        lineEnd: (Int) -> Int,
    ): AndroidVisualCompactPreviewBreak {
        if (textLength == 0 || availableSideHeightPx <= 0f || maximumLines <= 0) {
            return AndroidVisualCompactPreviewBreak(sideLines = 0, splitIndex = 0)
        }
        var sideLines = 0
        val limit = minOf(maximumLines, measuredLineCount)
        while (sideLines < limit && lineTopPx(sideLines) < availableSideHeightPx) {
            sideLines++
        }
        val index = if (sideLines == 0) 0
        else lineEnd(sideLines - 1).coerceIn(0, textLength)
        return AndroidVisualCompactPreviewBreak(sideLines, index)
    }

    fun continuationTop(
        imageBottomPx: Int,
        publicationBottomPx: Int,
        sidePreviewBottomPx: Int?,
        textSpacingPx: Int,
    ): Int = if (sidePreviewBottomPx == null) {
        maxOf(imageBottomPx, publicationBottomPx) + textSpacingPx
    } else {
        maxOf(imageBottomPx, sidePreviewBottomPx)
    }
}

internal fun parseArticlePublishedAtMillis(value: String): Long? =
    runCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }
        .recoverCatching { Instant.parse(value).toEpochMilli() }
        .getOrNull()
