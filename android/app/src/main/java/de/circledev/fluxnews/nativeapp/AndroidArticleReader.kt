package de.circledev.fluxnews.nativeapp

import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.zIndex
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import java.util.Date
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.ReaderBlock
import uniffi.flux_uniffi.ReaderDocument
import uniffi.flux_uniffi.ReaderInline

internal enum class AndroidReaderSource {
    Timeline,
    Search,
}

internal data class AndroidReaderState(
    val article: ArticleSummary? = null,
    val source: AndroidReaderSource? = null,
    val document: ReaderDocument? = null,
    val loading: Boolean = false,
    val errorMessage: String? = null,
    val requestGeneration: Long = 0,
    val sessionGeneration: Long? = null,
)

internal class AndroidReaderStore private constructor(
    private val timelineLoader: suspend (Long, Long) -> ReaderDocument,
    private val searchLoader: suspend (Long, Long) -> ReaderDocument,
    private val activeSessionGeneration: () -> Long?,
) {
    internal constructor(coreRuntime: AndroidCoreRuntime) : this(
        timelineLoader = { generation, articleId ->
            coreRuntime.localForGeneration(generation) { core ->
                core.readerDocument(articleId = articleId)
            }
        },
        searchLoader = { generation, articleId ->
            coreRuntime.remoteForGeneration(generation) { core ->
                core.readerDocumentForSearch(articleId = articleId)
            }
        },
        activeSessionGeneration = coreRuntime::activeSessionGeneration,
    )

    internal constructor(
        timelineLoader: suspend (Long, Long) -> ReaderDocument,
        searchLoader: suspend (Long, Long) -> ReaderDocument,
        activeSessionGeneration: () -> Long?,
        @Suppress("UNUSED_PARAMETER") testOnly: Unit,
    ) : this(timelineLoader, searchLoader, activeSessionGeneration)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val nextRequestGeneration = AtomicLong(0)
    private val mutableState = MutableStateFlow(AndroidReaderState())
    val state = mutableState.asStateFlow()

    fun activateSession(sessionGeneration: Long?) {
        val current = mutableState.value
        if (current.sessionGeneration != null && current.sessionGeneration != sessionGeneration) {
            dismiss()
        }
    }

    fun open(article: ArticleSummary, source: AndroidReaderSource): Job? {
        val sessionGeneration = activeSessionGeneration() ?: return null
        val request = nextRequestGeneration.incrementAndGet()
        mutableState.value = AndroidReaderState(
            article = article,
            source = source,
            loading = true,
            requestGeneration = request,
            sessionGeneration = sessionGeneration,
        )
        return scope.launch {
            val result = runCatching {
                when (source) {
                    AndroidReaderSource.Timeline -> timelineLoader(sessionGeneration, article.id)
                    AndroidReaderSource.Search -> searchLoader(sessionGeneration, article.id)
                }
            }
            val current = mutableState.value
            if (
                current.requestGeneration != request ||
                current.sessionGeneration != sessionGeneration ||
                current.article?.id != article.id ||
                current.source != source ||
                activeSessionGeneration() != sessionGeneration
            ) {
                return@launch
            }
            mutableState.value = if (result.isSuccess) {
                current.copy(
                    document = result.getOrThrow(),
                    loading = false,
                    errorMessage = null,
                )
            } else {
                current.copy(
                    document = null,
                    loading = false,
                    errorMessage = "Article content could not be loaded.",
                )
            }
        }
    }

    fun dismiss() {
        val generation = nextRequestGeneration.incrementAndGet()
        mutableState.value = AndroidReaderState(
            requestGeneration = generation,
            sessionGeneration = activeSessionGeneration(),
        )
    }
}

internal sealed interface AndroidNormalOpenDestination {
    data object Reader : AndroidNormalOpenDestination
    data class Web(val url: String) : AndroidNormalOpenDestination
}

internal object AndroidArticleOpenPolicy {
    fun destination(
        preference: AndroidArticleOpenPreference,
        openInMiniflux: Boolean,
        originalUrl: String,
        minifluxUrl: String,
    ): AndroidNormalOpenDestination = when (preference) {
        AndroidArticleOpenPreference.Reader -> AndroidNormalOpenDestination.Reader
        AndroidArticleOpenPreference.OriginalLink -> AndroidNormalOpenDestination.Web(
            if (openInMiniflux) minifluxUrl else originalUrl,
        )
    }
}

internal class AndroidArticleOpenResolver(
    private val coreRuntime: AndroidCoreRuntime,
) {
    suspend fun resolve(
        article: ArticleSummary,
        preference: AndroidArticleOpenPreference,
    ): AndroidNormalOpenDestination? {
        if (preference == AndroidArticleOpenPreference.Reader) {
            return AndroidNormalOpenDestination.Reader
        }
        val generation = coreRuntime.activeSessionGeneration() ?: return null
        val destination = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                val openInMiniflux = runCatching {
                    core.feedPreferences(feedId = article.feedId).openInMiniflux
                }.getOrDefault(false)
                AndroidArticleOpenPolicy.destination(
                    preference = preference,
                    openInMiniflux = openInMiniflux,
                    originalUrl = article.url,
                    minifluxUrl = core.minifluxEntryUrl(articleId = article.id),
                )
            }
        }.getOrNull()
        return destination?.takeIf { coreRuntime.activeSessionGeneration() == generation }
    }
}

@Composable
internal fun AndroidArticleReaderOverlay(
    store: AndroidReaderStore,
    source: AndroidReaderSource,
    onOpenOriginal: (ArticleSummary) -> Unit,
) {
    val state by store.state.collectAsState()
    val readerPaneTitle = stringResource(R.string.l10n_reader_pane)
    val article = state.article ?: return
    if (state.source != source) return

    var readerVisible by remember(article.id, source) { mutableStateOf(false) }
    val dismissScope = rememberCoroutineScope()

    LaunchedEffect(article.id, source) {
        readerVisible = true
    }

    fun dismissReader() {
        if (!readerVisible) return
        readerVisible = false
        val closingArticleId = article.id
        dismissScope.launch {
            delay(AndroidMotion.ReaderDurationMillis.toLong())
            val current = store.state.value
            if (current.article?.id == closingArticleId && current.source == source) {
                store.dismiss()
            }
        }
    }

    BackHandler(enabled = readerVisible) { dismissReader() }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .zIndex(50f),
    ) {
        val compactPortrait = maxWidth < 600.dp && maxHeight >= maxWidth
        val darkMode = isSystemInDarkTheme()
        val readerContainerColor = if (darkMode) {
            MaterialTheme.colorScheme.surfaceContainer
        } else {
            MaterialTheme.colorScheme.surface
        }

        AnimatedVisibility(
            visible = readerVisible,
            enter = AndroidMotion.readerScrimEnter(),
            exit = AndroidMotion.readerScrimExit(),
            modifier = Modifier.fillMaxSize(),
        ) {
            val interactionSource = remember { MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.38f))
                    .clickable(
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = ::dismissReader,
                    ),
            )
        }

        AnimatedVisibility(
            visible = readerVisible,
            enter = AndroidMotion.readerSurfaceEnter(compactPortrait),
            exit = AndroidMotion.readerSurfaceExit(compactPortrait),
            modifier = Modifier.fillMaxSize(),
        ) {
            Box(Modifier.fillMaxSize()) {
                Surface(
                    modifier = if (compactPortrait) {
                        Modifier
                            .windowInsetsPadding(WindowInsets.safeDrawing)
                            .align(Alignment.BottomCenter)
                            .padding(horizontal = 6.dp, vertical = 6.dp)
                            .fillMaxWidth()
                            .fillMaxHeight(0.94f)
                    } else {
                        Modifier
                            .windowInsetsPadding(WindowInsets.safeDrawing)
                            .align(Alignment.Center)
                            .padding(24.dp)
                            .fillMaxWidth(0.76f)
                            .fillMaxHeight(0.88f)
                            .widthIn(max = 860.dp)
                    }
                        .semantics { paneTitle = readerPaneTitle },
                    shape = RoundedCornerShape(28.dp),
                    color = readerContainerColor,
                    tonalElevation = if (compactPortrait) 0.dp else 8.dp,
                    shadowElevation = if (compactPortrait) 0.dp else 12.dp,
                ) {
                    Column(Modifier.fillMaxSize()) {
                        ReaderHeader(
                            article = article,
                            onClose = ::dismissReader,
                            onOpenOriginal = { onOpenOriginal(article) },
                        )
                        HorizontalDivider()
                        when {
                            state.loading -> {
                                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator()
                                }
                            }
                            state.errorMessage != null -> {
                                Column(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .padding(24.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.Center,
                                ) {
                                    Text(
                                        stringResource(R.string.audit_reader_load_fail),
                                        style = MaterialTheme.typography.bodyLarge,
                                    )
                                    Spacer(Modifier.height(12.dp))
                                    Button(onClick = { onOpenOriginal(article) }) {
                                        Text(stringResource(R.string.reader_open_original))
                                    }
                                }
                            }
                            state.document != null -> {
                                AndroidReaderDocumentContent(
                                    document = state.document!!,
                                    onOpenOriginal = { onOpenOriginal(article) },
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ReaderHeader(
    article: ArticleSummary,
    onClose: () -> Unit,
    onOpenOriginal: () -> Unit,
) {
    val context = LocalContext.current
    val published = remember(article.publishedAt) {
        parseArticlePublishedAtMillis(article.publishedAt)?.let { millis ->
            val date = Date(millis)
            val day = DateFormat.getMediumDateFormat(context).format(date)
            val time = DateFormat.getTimeFormat(context).format(date)
            "$day · $time"
        } ?: article.publishedAt
    }
    Column(
        modifier = Modifier.padding(start = 24.dp, top = 16.dp, end = 12.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                article.feedTitle,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(onClick = onOpenOriginal) {
                Text(stringResource(R.string.reader_original))
            }
            IconButton(onClick = onClose) {
                Icon(
                    painter = painterResource(R.drawable.ic_close),
                    contentDescription = stringResource(R.string.reader_close_article),
                )
            }
        }
        Text(
            article.title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        Text(
            if (article.readingTimeMinutes > 0u) {
                "$published · ${article.readingTimeMinutes} min"
            } else {
                published
            },
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
internal fun AndroidReaderDocumentContent(
    document: ReaderDocument,
    onOpenOriginal: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ReaderBlocks(document.blocks)
        readerNotice(
            simplified = document.hasSimplifiedContent,
            truncated = document.wasTruncated,
        )?.let { notice ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    notice,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (onOpenOriginal != null) {
                    TextButton(onClick = onOpenOriginal) {
                        Text(stringResource(R.string.reader_open_original))
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun ReaderBlocks(blocks: List<ReaderBlock>) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        blocks.forEach { block ->
            when (block) {
                is ReaderBlock.Paragraph -> ReaderInlineText(
                    inlines = block.inlines,
                    style = MaterialTheme.typography.bodyLarge,
                )
                is ReaderBlock.Heading -> {
                    val level = block.level.toInt()
                    ReaderInlineText(
                        inlines = block.inlines,
                        style = when {
                            level <= 1 -> MaterialTheme.typography.headlineSmall
                            level == 2 -> MaterialTheme.typography.titleLarge
                            else -> MaterialTheme.typography.titleMedium
                        }.copy(fontWeight = FontWeight.Bold),
                    )
                }
                is ReaderBlock.Image -> ReaderImageBlock(block)
                is ReaderBlock.ListBlock -> {
                    Column(
                        modifier = Modifier.padding(start = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        block.items.forEachIndexed { index, item ->
                            Row(
                                verticalAlignment = Alignment.Top,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    if (block.ordered) "${index + 1}." else "•",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Box(Modifier.weight(1f)) {
                                    ReaderBlocks(item.blocks)
                                }
                            }
                        }
                    }
                }
                is ReaderBlock.Quote -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            Modifier
                                .width(3.dp)
                                .heightIn(min = 48.dp)
                                .background(MaterialTheme.colorScheme.outlineVariant),
                        )
                        Box(Modifier.weight(1f)) {
                            ReaderBlocks(block.blocks)
                        }
                    }
                }
                is ReaderBlock.CodeBlock -> {
                    Text(
                        block.text,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.medium)
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .padding(12.dp),
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                        ),
                    )
                }
                ReaderBlock.HorizontalRule -> HorizontalDivider()
                is ReaderBlock.ExternalContent -> {
                    val context = LocalContext.current
                    TextButton(
                        onClick = {
                            AndroidArticlePlatformActions.openUrl(context, block.url)
                        },
                    ) {
                        Text(block.label ?: block.url, maxLines = 2)
                    }
                }
            }
        }
    }
}

@Suppress("DEPRECATION")
@Composable
private fun ReaderInlineText(
    inlines: List<ReaderInline>,
    style: androidx.compose.ui.text.TextStyle,
) {
    val linkColor = MaterialTheme.colorScheme.primary
    val text = remember(inlines, linkColor) {
        buildAnnotatedString {
            appendReaderInlines(inlines, linkColor)
        }
    }
    val context = LocalContext.current
    ClickableText(
        text = text,
        style = style.copy(color = MaterialTheme.colorScheme.onSurface),
        onClick = { offset ->
            text.getStringAnnotations("URL", offset, offset)
                .firstOrNull()
                ?.let { AndroidArticlePlatformActions.openUrl(context, it.item) }
        },
    )
}

private fun AnnotatedString.Builder.appendReaderInlines(
    inlines: List<ReaderInline>,
    linkColor: Color,
) {
    inlines.forEach { inline ->
        when (inline) {
            is ReaderInline.Text -> append(inline.text)
            is ReaderInline.Bold -> {
                pushStyle(SpanStyle(fontWeight = FontWeight.Bold))
                appendReaderInlines(inline.inlines, linkColor)
                pop()
            }
            is ReaderInline.Italic -> {
                pushStyle(SpanStyle(fontStyle = FontStyle.Italic))
                appendReaderInlines(inline.inlines, linkColor)
                pop()
            }
            is ReaderInline.Code -> {
                pushStyle(SpanStyle(fontFamily = FontFamily.Monospace))
                append(inline.text)
                pop()
            }
            is ReaderInline.Link -> {
                pushStringAnnotation(tag = "URL", annotation = inline.url)
                pushStyle(
                    SpanStyle(
                        color = linkColor,
                        textDecoration = TextDecoration.Underline,
                    ),
                )
                appendReaderInlines(inline.inlines, linkColor)
                pop()
                pop()
            }
        }
    }
}

@Composable
private fun ReaderImageBlock(block: ReaderBlock.Image) {
    val context = LocalContext.current
    val imageModifier = if (
        block.link != null &&
        AndroidArticleActionPolicy.validWebUrl(block.link)
    ) {
        Modifier.clickable {
            AndroidArticlePlatformActions.openUrl(context, block.link)
        }
    } else {
        Modifier
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        AsyncImage(
            model = block.url,
            contentDescription = block.alt ?: stringResource(R.string.l10n_article_image),
            contentScale = ContentScale.Fit,
            modifier = imageModifier
                .fillMaxWidth()
                .heightIn(min = 120.dp, max = 520.dp)
                .clip(MaterialTheme.shapes.medium)
                .background(MaterialTheme.colorScheme.surfaceVariant),
        )
        if (!block.alt.isNullOrBlank()) {
            Text(
                block.alt,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun readerNotice(simplified: Boolean, truncated: Boolean): String? = when {
    simplified && truncated -> stringResource(R.string.audit_reader_simplified_truncated)
    simplified -> stringResource(R.string.audit_reader_simplified)
    truncated -> stringResource(R.string.audit_reader_truncated)
    else -> null
}
