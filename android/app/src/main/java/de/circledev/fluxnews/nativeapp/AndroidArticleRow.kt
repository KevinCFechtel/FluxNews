package de.circledev.fluxnews.nativeapp

import android.text.format.DateFormat
import android.text.format.DateUtils
import android.text.format.DateUtils.FORMAT_ABBREV_RELATIVE
import android.text.format.DateUtils.MINUTE_IN_MILLIS
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import kotlin.math.roundToInt
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import java.util.Date
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.FeedIconVariant

@Composable
internal fun AndroidArticleTimelineRow(
    article: ArticleSummary,
    hasAudio: Boolean,
    preferences: AndroidArticlePreferenceState,
    publicationReferenceMillis: Long,
    feedIconPng: ByteArray?,
    feedIconVariant: FeedIconVariant,
    availableWidth: Dp,
    onRequestFeedIcon: suspend (Long, FeedIconVariant) -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        val layoutVariant = AndroidArticleRowPolicy.layoutVariant(
            mode = preferences.presentationMode,
            imageUrl = article.imageUrl,
            availableWidthDp = availableWidth.value.toInt(),
        )
        val metadata: @Composable () -> Unit = {
            ArticleMetadataRow(
                article = article,
                hasAudio = hasAudio,
                feedIconPng = feedIconPng,
                feedIconVariant = feedIconVariant,
                onRequestFeedIcon = onRequestFeedIcon,
                requestIfMissing = false,
            )
        }
        val title: @Composable () -> Unit = {
            ArticleTitle(article)
        }
        val publication: @Composable () -> Unit = {
            ArticlePublicationRow(
                article = article,
                hasAudio = hasAudio,
                preferences = preferences,
                publicationReferenceMillis = publicationReferenceMillis,
            )
        }
        val preview: @Composable () -> Unit = {
            ArticlePreview(article = article, preferences = preferences)
        }

        when (layoutVariant) {
            AndroidArticleRowLayoutVariant.Compact,
            AndroidArticleRowLayoutVariant.VisualTextOnly,
            AndroidArticleRowLayoutVariant.VisualCompactTextOnly,
            -> {
                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    metadata()
                    title()
                    publication()
                    preview()
                }
            }

            AndroidArticleRowLayoutVariant.VisualPortrait -> {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ArticleImage(
                        imageUrl = article.imageUrl!!,
                                        modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f),
                    )
                    metadata()
                    title()
                    publication()
                    preview()
                }
            }

            AndroidArticleRowLayoutVariant.VisualLandscape -> {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    ArticleImage(
                        imageUrl = article.imageUrl!!,
                                        modifier = Modifier.weight(0.48f).aspectRatio(16f / 9f),
                    )
                    Column(
                        modifier = Modifier.weight(0.52f),
                        verticalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        metadata()
                        title()
                        publication()
                        preview()
                    }
                }
            }

            AndroidArticleRowLayoutVariant.VisualCompactNarrow,
            AndroidArticleRowLayoutVariant.VisualCompactWide,
            -> {
                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    metadata()
                    AndroidVisualCompactFlowBody(
                        article = article,
                        hasAudio = hasAudio,
                        preferences = preferences,
                        publicationReferenceMillis = publicationReferenceMillis,
                    )
                }
            }
        }
    }
}

/**
 * Visual Compact keeps the feed/status row full width. Inside this body the
 * preview uses real Compose text line breaks beside the trailing 4:3 image,
 * then continues at full width below it without inserting a new paragraph.
 *
 * The measured layout belongs to the visible LazyColumn item; an image load
 * does not change any of its dimensions.
 */
@Composable
private fun AndroidVisualCompactFlowBody(
    article: ArticleSummary,
    hasAudio: Boolean,
    preferences: AndroidArticlePreferenceState,
    publicationReferenceMillis: Long,
) {
    val previewText = article.preview.trim()
    val previewStyle = MaterialTheme.typography.bodyMedium
    val previewColor = MaterialTheme.colorScheme.onSurface.copy(
        alpha = AndroidArticleStatusPresentationPolicy.supportingAlpha(article.isRead),
    )
    val textMeasurer = rememberTextMeasurer()
    val imageUrl = article.imageUrl ?: return
    val gap = 7.dp
    val imageGap = 12.dp
    val maxPreviewLines = preferences.previewLines.lineCount

    SubcomposeLayout(modifier = Modifier.fillMaxWidth()) { constraints ->
        val width = constraints.maxWidth
        val imageWidth = (width * 0.32f).roundToInt().coerceIn(1, width)
        val imageHeight = (imageWidth * 3f / 4f).roundToInt()
        val gapPx = gap.roundToPx()
        val imageGapPx = imageGap.roundToPx()
        val columnWidth = (width - imageWidth - imageGapPx).coerceAtLeast(1)
        val textConstraints = Constraints(maxWidth = columnWidth)
        val fullConstraints = Constraints(maxWidth = width)

        val titlePlaceable = subcompose("title") { ArticleTitle(article) }
            .first().measure(textConstraints)
        val publicationPlaceable = subcompose("publication") {
            ArticlePublicationRow(
                article = article,
                hasAudio = hasAudio,
                preferences = preferences,
                publicationReferenceMillis = publicationReferenceMillis,
            )
        }.first().measure(textConstraints)
        val imagePlaceable = subcompose("image") {
            ArticleImage(
                imageUrl = imageUrl,
                modifier = Modifier.size(imageWidth.toDp(), imageHeight.toDp()),
            )
        }.first().measure(Constraints.fixed(imageWidth, imageHeight))

        val publicationTop = titlePlaceable.height + gapPx
        val publicationBottom = publicationTop + publicationPlaceable.height
        val previewTop = publicationBottom + if (previewText.isNotEmpty()) gapPx else 0

        val lineBreak = if (previewText.isNotEmpty() && previewTop < imageHeight) {
            val measured = textMeasurer.measure(
                text = AnnotatedString(previewText),
                style = previewStyle,
                constraints = textConstraints,
                maxLines = maxPreviewLines,
                overflow = TextOverflow.Ellipsis,
            )
            AndroidVisualCompactFlowPolicy.breakFor(
                textLength = previewText.length,
                maximumLines = maxPreviewLines,
                availableSideHeightPx = (imageHeight - previewTop).toFloat(),
                measuredLineCount = measured.lineCount,
                lineTopPx = { line -> measured.getLineTop(line) },
                lineEnd = { line -> measured.getLineEnd(line, visibleEnd = false) },
            )
        } else {
            AndroidVisualCompactPreviewBreak(sideLines = 0, splitIndex = 0)
        }
        val sideText = lineBreak.sideText(previewText, maxPreviewLines)
        val continuationText = lineBreak.continuationText(previewText, maxPreviewLines)
        val sidePlaceable = if (sideText.isNotEmpty()) {
            subcompose("previewSide") {
                Text(
                    text = sideText,
                    style = previewStyle,
                    color = previewColor,
                    maxLines = lineBreak.sideLines,
                    overflow = TextOverflow.Ellipsis,
                )
            }.first().measure(textConstraints)
        } else null
        val sideBottom = sidePlaceable?.let { previewTop + it.height }
        val continuationTop = AndroidVisualCompactFlowPolicy.continuationTop(
            imageBottomPx = imageHeight,
            publicationBottomPx = publicationBottom,
            sidePreviewBottomPx = sideBottom,
            textSpacingPx = gapPx,
        )
        val continuationPlaceable = if (continuationText.isNotEmpty() &&
            lineBreak.continuationLines(maxPreviewLines) > 0) {
            subcompose("previewContinuation") {
                Text(
                    text = continuationText,
                    style = previewStyle,
                    color = previewColor,
                    maxLines = lineBreak.continuationLines(maxPreviewLines),
                    overflow = TextOverflow.Ellipsis,
                )
            }.first().measure(fullConstraints)
        } else null
        val height = maxOf(
            imagePlaceable.height,
            publicationBottom,
            sideBottom ?: 0,
            continuationPlaceable?.let { continuationTop + it.height } ?: 0,
        )
        layout(width, height) {
            titlePlaceable.placeRelative(0, 0)
            publicationPlaceable.placeRelative(0, publicationTop)
            sidePlaceable?.placeRelative(0, previewTop)
            continuationPlaceable?.placeRelative(0, continuationTop)
            imagePlaceable.placeRelative(width - imageWidth, 0)
        }
    }
}

@Composable
private fun ArticleMetadataRow(
    article: ArticleSummary,
    hasAudio: Boolean,
    feedIconPng: ByteArray?,
    feedIconVariant: FeedIconVariant,
    onRequestFeedIcon: suspend (Long, FeedIconVariant) -> Unit,
    requestIfMissing: Boolean = true,
) {
    val supportingColor = MaterialTheme.colorScheme.onSurface.copy(
        alpha = AndroidArticleStatusPresentationPolicy.supportingAlpha(article.isRead),
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        FeedIcon(
            feedId = article.feedId,
            title = article.feedTitle,
            pngData = feedIconPng,
            variant = feedIconVariant,
            onRequest = onRequestFeedIcon,
            requestIfMissing = requestIfMissing,
        )
        Text(
            article.feedTitle,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = supportingColor,
        )
        ArticleAccessories(
            article = article,
            hasAudio = hasAudio,
        )
    }
}

@Composable
internal fun FeedIcon(
    feedId: Long,
    title: String,
    pngData: ByteArray?,
    variant: FeedIconVariant,
    onRequest: suspend (Long, FeedIconVariant) -> Unit,
    requestIfMissing: Boolean = true,
    size: Dp = 22.dp,
) {
    LaunchedEffect(feedId, variant, pngData == null, requestIfMissing) {
        if (requestIfMissing && pngData == null) onRequest(feedId, variant)
    }
    val context = LocalContext.current
    val imageRequest = remember(context, feedId, variant, pngData) {
        pngData?.let { bytes ->
            ImageRequest.Builder(context)
                .data(bytes)
                .memoryCacheKey("feed-icon:$feedId:$variant:${pngData.contentHashCode()}")
                .build()
        }
    }
    if (imageRequest != null) {
        AsyncImage(
            model = imageRequest,
            contentDescription = null,
            modifier = Modifier.size(size).clip(CircleShape),
        )
    } else {
        Box(
            modifier = Modifier
                .size(size)
                .clearAndSetSemantics { }
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                title.trim().firstOrNull()?.uppercase() ?: "•",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onPrimary,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun ArticleTitle(article: ArticleSummary) {
    Text(
        article.title,
        style = MaterialTheme.typography.titleMedium,
        // Keep typography geometry stable across read-state changes. iOS uses the
        // same headline font for read and unread rows and changes colour only.
        fontWeight = AndroidArticleStatusPresentationPolicy.titleFontWeight(article.isRead),
        color = MaterialTheme.colorScheme.onSurface.copy(
            alpha = AndroidArticleStatusPresentationPolicy.titleAlpha(article.isRead),
        ),
    )
}

@Composable
private fun ArticlePublicationRow(
    article: ArticleSummary,
    hasAudio: Boolean,
    preferences: AndroidArticlePreferenceState,
    publicationReferenceMillis: Long,
) {
    val supportingColor = MaterialTheme.colorScheme.onSurface.copy(
        alpha = AndroidArticleStatusPresentationPolicy.supportingAlpha(article.isRead),
    )
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (preferences.showRelativePublicationTime) {
            Icon(
                painter = painterResource(R.drawable.ic_relative_time),
                contentDescription = null,
                modifier = Modifier.size(13.dp),
                tint = supportingColor,
            )
        }
        Text(
            publicationLabel(
                article = article,
                relative = preferences.showRelativePublicationTime,
                referenceMillis = publicationReferenceMillis,
            ),
            style = MaterialTheme.typography.labelSmall,
            color = supportingColor,
        )
        if (article.readingTimeMinutes > 0u) {
            Text(
                "·",
                style = MaterialTheme.typography.labelSmall,
                color = supportingColor,
            )
            Icon(
                painter = painterResource(
                    if (hasAudio) R.drawable.ic_headphones else R.drawable.ic_reading_time,
                ),
                contentDescription = stringResource(if (hasAudio) R.string.l10n_audio_duration else R.string.l10n_reading_time),
                modifier = Modifier.size(13.dp),
                tint = supportingColor,
            )
            Text(
                stringResource(R.string.l10n_duration_minutes_short, article.readingTimeMinutes.toInt()),
                style = MaterialTheme.typography.labelSmall,
                color = supportingColor,
            )
        }
    }
}

@Composable
private fun ArticlePreview(
    article: ArticleSummary,
    preferences: AndroidArticlePreferenceState,
) {
    val preview = article.preview.trim()
    if (preview.isEmpty()) return
    Text(
        preview,
        maxLines = preferences.previewLines.lineCount,
        overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurface.copy(
            alpha = AndroidArticleStatusPresentationPolicy.supportingAlpha(article.isRead),
        ),
    )
}

@Composable
private fun publicationLabel(
    article: ArticleSummary,
    relative: Boolean,
    referenceMillis: Long,
): String {
    val context = LocalContext.current
    val locales = LocalConfiguration.current.locales
    val publishedMillis = remember(article.publishedAt) {
        parseArticlePublishedAtMillis(article.publishedAt)
    }
    val publication = remember(article.publishedAt, publishedMillis, relative, referenceMillis, locales) {
        if (publishedMillis == null) {
            article.publishedAt
        } else if (relative) {
            DateUtils.getRelativeTimeSpanString(
                publishedMillis,
                referenceMillis,
                MINUTE_IN_MILLIS,
                FORMAT_ABBREV_RELATIVE,
            ).toString()
        } else {
            val published = Date(publishedMillis)
            val date = DateFormat.getMediumDateFormat(context).format(published)
            val time = DateFormat.getTimeFormat(context).format(published)
            "$date · $time"
        }
    }
    return publication
}

@Composable
private fun ArticleImage(
    imageUrl: String,
    modifier: Modifier = Modifier,
) {
    var failed by remember(imageUrl) { mutableStateOf(false) }

    Box(
        modifier = modifier
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            model = imageUrl,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            onError = { failed = true },
            modifier = Modifier.fillMaxSize(),
        )
        if (failed) {
            Icon(
                painter = painterResource(R.drawable.ic_image_unavailable),
                contentDescription = stringResource(R.string.article_image_unavailable),
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ArticleAccessories(
    article: ArticleSummary,
    hasAudio: Boolean,
) {
    val supportingColor = MaterialTheme.colorScheme.onSurface.copy(
        alpha = AndroidArticleStatusPresentationPolicy.supportingAlpha(article.isRead),
    )
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (hasAudio) {
            Icon(
                painter = painterResource(R.drawable.ic_headphones),
                contentDescription = stringResource(R.string.article_audio),
                modifier = Modifier.size(16.dp),
                tint = supportingColor,
            )
        }
        if (article.commentsUrl.isNotBlank()) {
            Icon(
                painter = painterResource(R.drawable.ic_comment),
                contentDescription = stringResource(R.string.article_comments),
                modifier = Modifier.size(16.dp),
                tint = supportingColor,
            )
        }

        // Star and unread keep fixed slots so status-only mutations do not move
        // the feed title or the immutable comments/audio accessories.
        Box(Modifier.size(16.dp), contentAlignment = Alignment.Center) {
            if (article.isStarred) {
                Icon(
                    painter = painterResource(R.drawable.ic_star),
                    contentDescription = stringResource(R.string.article_starred),
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
        val unreadDescription = stringResource(R.string.article_unread)
        Box(Modifier.size(16.dp), contentAlignment = Alignment.Center) {
            if (!article.isRead) {
                Box(
                    Modifier
                        .size(8.dp)
                        .semantics { contentDescription = unreadDescription }
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary),
                )
            }
        }
    }
}
