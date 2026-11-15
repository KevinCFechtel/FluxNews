package de.circledev.fluxnews.nativeapp

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import java.net.URI
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.ArticleSummary
import uniffi.flux_uniffi.DownloadState

internal enum class AndroidSaveToServiceOutcome {
    Saved,
    NoIntegrationConfigured,
}

internal enum class AndroidArticleContextAction {
    ReadUnread,
    StarUnstar,
    OpenOriginal,
    Reader,
    OpenMiniflux,
    Comments,
    CopyLink,
    Share,
    SaveToService,
    ListeningList,
    DownloadAudio,
}

internal data class AndroidResolvedSwipeSide(
    val additional: AndroidArticleSwipeAction?,
    val full: AndroidArticleSwipeAction?,
) {
    val visibleActions: List<AndroidArticleSwipeAction>
        get() = listOfNotNull(additional, full)
}

internal object AndroidArticleActionPolicy {
    fun validWebUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        (uri.scheme.equals("http", ignoreCase = true) || uri.scheme.equals("https", ignoreCase = true)) &&
            !uri.host.isNullOrBlank()
    }.getOrDefault(false)

    fun isSwipeActionAvailable(
        action: AndroidArticleSwipeAction,
        article: ArticleSummary,
        hasAudio: Boolean,
        mediaActionsEnabled: Boolean = false,
    ): Boolean = when (action) {
        AndroidArticleSwipeAction.ReadUnread,
        AndroidArticleSwipeAction.StarUnstar,
        AndroidArticleSwipeAction.OpenMiniflux,
        AndroidArticleSwipeAction.SaveToService,
        -> true

        AndroidArticleSwipeAction.OpenOriginal,
        AndroidArticleSwipeAction.Share,
        -> validWebUrl(article.url)

        AndroidArticleSwipeAction.Comments -> validWebUrl(article.commentsUrl)

        AndroidArticleSwipeAction.ListeningList -> mediaActionsEnabled && hasAudio
        AndroidArticleSwipeAction.DownloadAudio -> mediaActionsEnabled && hasAudio
    }

    fun resolveSwipeSide(
        configuration: AndroidArticleSwipeConfiguration,
        side: AndroidArticleSwipeSide,
        article: ArticleSummary,
        hasAudio: Boolean,
        mediaActionsEnabled: Boolean = false,
    ): AndroidResolvedSwipeSide {
        fun AndroidArticleSwipeAction?.available(): AndroidArticleSwipeAction? =
            this?.takeIf {
                isSwipeActionAvailable(
                    action = it,
                    article = article,
                    hasAudio = hasAudio,
                    mediaActionsEnabled = mediaActionsEnabled,
                )
            }

        return AndroidResolvedSwipeSide(
            additional = configuration.additionalAction(side).available(),
            full = configuration.fullSwipeAction(side).available(),
        )
    }

    fun contextActions(article: ArticleSummary, mediaState: AndroidArticleMediaActionState? = null): List<AndroidArticleContextAction> = buildList {
        add(AndroidArticleContextAction.StarUnstar)
        add(AndroidArticleContextAction.ReadUnread)
        if (validWebUrl(article.url)) add(AndroidArticleContextAction.OpenOriginal)
        add(AndroidArticleContextAction.Reader)
        add(AndroidArticleContextAction.OpenMiniflux)
        if (validWebUrl(article.commentsUrl)) add(AndroidArticleContextAction.Comments)
        if (validWebUrl(article.url)) {
            add(AndroidArticleContextAction.CopyLink)
            add(AndroidArticleContextAction.Share)
        }
        add(AndroidArticleContextAction.SaveToService)
        if (mediaState?.audioEnclosures?.isNotEmpty() == true) {
            add(AndroidArticleContextAction.ListeningList)
            add(AndroidArticleContextAction.DownloadAudio)
        }
    }

    fun swipeLabel(action: AndroidArticleSwipeAction, article: ArticleSummary): String = when (action) {
        AndroidArticleSwipeAction.ReadUnread -> if (article.isRead) "Unread" else "Read"
        AndroidArticleSwipeAction.StarUnstar -> if (article.isStarred) "Unstar" else "Star"
        AndroidArticleSwipeAction.OpenOriginal -> "Original"
        AndroidArticleSwipeAction.OpenMiniflux -> "Miniflux"
        AndroidArticleSwipeAction.Comments -> "Comments"
        AndroidArticleSwipeAction.Share -> "Share"
        AndroidArticleSwipeAction.SaveToService -> "Save"
        AndroidArticleSwipeAction.ListeningList -> "Listening"
        AndroidArticleSwipeAction.DownloadAudio -> "Download"
    }

    fun contextLabel(action: AndroidArticleContextAction, article: ArticleSummary): String = when (action) {
        AndroidArticleContextAction.ReadUnread -> if (article.isRead) "Mark as unread" else "Mark as read"
        AndroidArticleContextAction.StarUnstar -> if (article.isStarred) "Unstar" else "Star"
        AndroidArticleContextAction.OpenOriginal -> "Open original"
        AndroidArticleContextAction.Reader -> "Open in Reader"
        AndroidArticleContextAction.OpenMiniflux -> "Open in Miniflux"
        AndroidArticleContextAction.Comments -> "Open comments"
        AndroidArticleContextAction.CopyLink -> "Copy link"
        AndroidArticleContextAction.Share -> "Share"
        AndroidArticleContextAction.SaveToService -> "Save to third-party service"
        AndroidArticleContextAction.ListeningList -> "Listening list"
        AndroidArticleContextAction.DownloadAudio -> "Download audio"
    }
}

@Composable
private fun localizedDownloadActionLabel(state: DownloadState?): String = when (state) {
    null, DownloadState.NOT_DOWNLOADED -> stringResource(R.string.audit_download)
    DownloadState.REQUESTED -> stringResource(R.string.audit_download_cancel)
    DownloadState.DOWNLOADED -> stringResource(R.string.audit_download_delete)
    DownloadState.FAILED -> stringResource(R.string.audit_download_retry)
    DownloadState.DELETE_REQUESTED -> stringResource(R.string.audit_download_deleting)
}

@Composable
private fun localizedContextActionLabel(action: AndroidArticleContextAction, article: ArticleSummary, mediaState: AndroidArticleMediaActionState?): String = when (action) {
    AndroidArticleContextAction.ReadUnread -> stringResource(if (article.isRead) R.string.audit_mark_unread else R.string.audit_mark_read)
    AndroidArticleContextAction.StarUnstar -> stringResource(if (article.isStarred) R.string.audit_unstar else R.string.audit_star)
    AndroidArticleContextAction.OpenOriginal -> stringResource(R.string.audit_open_original)
    AndroidArticleContextAction.Reader -> stringResource(R.string.audit_open_reader)
    AndroidArticleContextAction.OpenMiniflux -> stringResource(R.string.feed_open_miniflux)
    AndroidArticleContextAction.Comments -> stringResource(R.string.audit_open_comments)
    AndroidArticleContextAction.CopyLink -> stringResource(R.string.audit_copy_link)
    AndroidArticleContextAction.Share -> stringResource(R.string.audit_share)
    AndroidArticleContextAction.SaveToService -> stringResource(R.string.audit_save_service)
    AndroidArticleContextAction.ListeningList -> stringResource(if (mediaState?.isInListeningList == true) R.string.audit_listening_remove else R.string.audit_listening_add)
    AndroidArticleContextAction.DownloadAudio -> stringResource(R.string.audit_download)
}

@Composable
private fun localizedSwipeActionLabel(
    action: AndroidArticleSwipeAction,
    article: ArticleSummary,
    mediaState: AndroidArticleMediaActionState?,
): String = when (action) {
    AndroidArticleSwipeAction.ReadUnread -> stringResource(if (article.isRead) R.string.audit_unread else R.string.audit_read)
    AndroidArticleSwipeAction.StarUnstar -> stringResource(if (article.isStarred) R.string.audit_unstar else R.string.audit_star)
    AndroidArticleSwipeAction.OpenOriginal -> stringResource(R.string.audit_original)
    AndroidArticleSwipeAction.OpenMiniflux -> stringResource(R.string.audit_miniflux)
    AndroidArticleSwipeAction.Comments -> stringResource(R.string.article_comments)
    AndroidArticleSwipeAction.Share -> stringResource(R.string.audit_share)
    AndroidArticleSwipeAction.SaveToService -> stringResource(R.string.audit_save)
    AndroidArticleSwipeAction.ListeningList -> stringResource(
        if (mediaState?.isInListeningList == true) R.string.audit_listening_remove else R.string.audit_listening_add,
    )
    AndroidArticleSwipeAction.DownloadAudio -> {
        val enclosure = mediaState?.audioEnclosures?.singleOrNull()
        if (enclosure == null) stringResource(R.string.article_choose_audio)
        else localizedDownloadActionLabel(mediaState.downloads[enclosure.id]?.state)
    }
}

internal fun androidMediaDownloadActionLabel(state: DownloadState?): String = when (state) {
    null, DownloadState.NOT_DOWNLOADED -> "Download"
    DownloadState.REQUESTED -> "Cancel download"
    DownloadState.DOWNLOADED -> "Delete download"
    DownloadState.FAILED -> "Retry download"
    DownloadState.DELETE_REQUESTED -> "Deleting…"
}

@Composable
internal fun AndroidArticleDownloadChooserDialog(
    state: AndroidArticleMediaActionState,
    onSelect: (Long) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.article_choose_audio)) },
        text = {
            Column {
                state.audioEnclosures.forEachIndexed { index, enclosure ->
                    val download = state.downloads[enclosure.id]
                    TextButton(
                        onClick = {
                            if (download?.state != DownloadState.DELETE_REQUESTED) {
                                onSelect(enclosure.id)
                            }
                        },
                        enabled = download?.state != DownloadState.DELETE_REQUESTED,
                    ) {
                        val type = enclosure.mimeType.ifBlank { stringResource(R.string.audit_audio_number, index + 1) }
                        Text(type + " · " + localizedDownloadActionLabel(download?.state))
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        },
    )
}

internal object AndroidWebRoutingPolicy {
    fun dedicatedHandlerPackages(
        specificUrlHandlers: Set<String>,
        genericWebHandlers: Set<String>,
    ): List<String> =
        (specificUrlHandlers - genericWebHandlers).sorted()
}

internal object AndroidArticlePlatformActions {
    fun openUrl(context: Context, value: String): Boolean {
        if (!AndroidArticleActionPolicy.validWebUrl(value)) return false
        val uri = Uri.parse(value)
        return openInDedicatedApp(context, uri) || openInCustomTab(context, uri)
    }

    private fun openInDedicatedApp(context: Context, uri: Uri): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            start(
                context,
                webIntent(uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
                },
            )
        } else {
            openInDedicatedAppBeforeR(context, uri)
        }

    private fun openInDedicatedAppBeforeR(context: Context, uri: Uri): Boolean {
        val packageManager = context.packageManager
        val specificHandlers = packageManager
            .queryIntentActivities(webIntent(uri), PackageManager.MATCH_DEFAULT_ONLY)
            .mapTo(mutableSetOf()) { it.activityInfo.packageName }
        val genericUri = Uri.Builder()
            .scheme(uri.scheme)
            .authority("example.com")
            .path("/")
            .build()
        val genericWebHandlers = packageManager
            .queryIntentActivities(webIntent(genericUri), PackageManager.MATCH_DEFAULT_ONLY)
            .mapTo(mutableSetOf()) { it.activityInfo.packageName }
        val dedicatedPackages = AndroidWebRoutingPolicy.dedicatedHandlerPackages(
            specificUrlHandlers = specificHandlers,
            genericWebHandlers = genericWebHandlers,
        )
        val targetPackage = dedicatedPackages.firstOrNull() ?: return false
        return start(context, webIntent(uri).setPackage(targetPackage))
    }

    private fun openInCustomTab(context: Context, uri: Uri): Boolean = try {
        val customTab = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
        if (context !is Activity) {
            customTab.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        customTab.launchUrl(context, uri)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    private fun webIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }

    fun copyLink(context: Context, article: ArticleSummary): Boolean {
        if (!AndroidArticleActionPolicy.validWebUrl(article.url)) return false
        context.getSystemService(ClipboardManager::class.java)
            ?.setPrimaryClip(ClipData.newPlainText("Article link", article.url))
            ?: return false
        return true
    }

    fun share(context: Context, article: ArticleSummary): Boolean {
        if (!AndroidArticleActionPolicy.validWebUrl(article.url)) return false
        val share = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "${article.title}\n${article.url}")
        }
        return start(context, Intent.createChooser(share, null))
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }
}

private const val ANDROID_ARTICLE_SWIPE_FULL_THRESHOLD = 0.58f

internal object AndroidSwipePresentationPolicy {
    fun isFullSwipeArmed(
        offsetPx: Float,
        rowWidthPx: Float,
        hasFullAction: Boolean,
    ): Boolean =
        hasFullAction &&
            rowWidthPx > 0f &&
            abs(offsetPx) >= rowWidthPx * ANDROID_ARTICLE_SWIPE_FULL_THRESHOLD

    fun presentationActions(
        side: AndroidArticleSwipeSide,
        resolved: AndroidResolvedSwipeSide,
        fullSwipeArmed: Boolean,
    ): List<AndroidArticleSwipeAction> {
        if (fullSwipeArmed && resolved.full != null) return listOf(resolved.full)
        return if (side == AndroidArticleSwipeSide.Leading) {
            resolved.visibleActions.reversed()
        } else {
            resolved.visibleActions
        }
    }
}

/**
 * Android-native gesture adapter for the shared semantic swipe contract.
 *
 * A partial drag only reveals actions. Tapping a revealed action executes it; a full swipe executes
 * only the configured outer/full slot. If a contextual outer action is unavailable, the inner slot
 * is deliberately not promoted. A gesture that starts while the opposite side is open can only
 * return to neutral; crossing through neutral requires a new gesture.
 */
@Composable
internal fun AndroidArticleSwipeContainer(
    article: ArticleSummary,
    hasAudio: Boolean,
    configuration: AndroidArticleSwipeConfiguration,
    mediaActionsEnabled: Boolean = false,
    mediaState: AndroidArticleMediaActionState? = null,
    rowWidth: Dp,
    onOpen: () -> Unit = {},
    onSwipeAction: (AndroidArticleSwipeAction) -> Unit,
    onContextAction: (AndroidArticleContextAction) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val currentOnSwipeAction by rememberUpdatedState(onSwipeAction)
    val currentOnOpen by rememberUpdatedState(onOpen)
    val leading = remember(configuration, article, hasAudio, mediaActionsEnabled) {
        AndroidArticleActionPolicy.resolveSwipeSide(
            configuration = configuration,
            side = AndroidArticleSwipeSide.Leading,
            article = article,
            hasAudio = hasAudio,
            mediaActionsEnabled = mediaActionsEnabled,
        )
    }
    val trailing = remember(configuration, article, hasAudio, mediaActionsEnabled) {
        AndroidArticleActionPolicy.resolveSwipeSide(
            configuration = configuration,
            side = AndroidArticleSwipeSide.Trailing,
            article = article,
            hasAudio = hasAudio,
            mediaActionsEnabled = mediaActionsEnabled,
        )
    }
    val currentLeading by rememberUpdatedState(leading)
    val currentTrailing by rememberUpdatedState(trailing)
    var offsetPx by remember(article.id) { mutableFloatStateOf(0f) }
    var gestureSide by remember(article.id) { mutableStateOf<AndroidArticleSwipeSide?>(null) }
    var gestureStartOffset by remember(article.id) { mutableFloatStateOf(0f) }
    var contextExpanded by remember(article.id) { mutableStateOf(false) }
    var fullSwipeArmed by remember(article.id) { mutableStateOf(false) }
    var rowHeightPx by remember(article.id) { mutableIntStateOf(0) }
    val actionWidth = 80.dp
    val actionWidthPx = with(density) { actionWidth.toPx() }

    suspend fun animateOffset(target: Float) {
        val animation = Animatable(offsetPx)
        animation.animateTo(target, animationSpec = tween(durationMillis = 150)) {
            offsetPx = value
        }
        offsetPx = target
    }

    val rowWidthPx = with(density) { rowWidth.toPx() }.coerceAtLeast(1f)
    Box(
        modifier
            .fillMaxWidth()
            .onSizeChanged { size ->
                if (rowHeightPx != size.height) rowHeightPx = size.height
            },
    ) {

        val visibleSide = when {
            offsetPx > 0f -> AndroidArticleSwipeSide.Leading
            offsetPx < 0f -> AndroidArticleSwipeSide.Trailing
            else -> null
        }
        if (visibleSide != null) {
            val visibleResolved = if (visibleSide == AndroidArticleSwipeSide.Leading) leading else trailing
            val revealWidthPx =
                (actionWidthPx * visibleResolved.visibleActions.size).coerceAtLeast(1f)
            SwipeActionBackground(
                side = visibleSide,
                resolved = visibleResolved,
                article = article,
                mediaState = mediaState,
                fullSwipeArmed = fullSwipeArmed,
                revealProgress = (abs(offsetPx) / revealWidthPx).coerceIn(0f, 1f),
                actionWidth = actionWidth,
                onAction = { action ->
                    scope.launch {
                        fullSwipeArmed = false
                        animateOffset(0f)
                        currentOnSwipeAction(action)
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(with(density) { rowHeightPx.toDp() }),
            )
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .offset { IntOffset(offsetPx.roundToInt(), 0) }
                .background(MaterialTheme.colorScheme.background)
                .pointerInput(article.id, rowWidthPx) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            gestureStartOffset = offsetPx
                            gestureSide = when {
                                offsetPx > 0f -> AndroidArticleSwipeSide.Leading
                                offsetPx < 0f -> AndroidArticleSwipeSide.Trailing
                                else -> null
                            }
                        },
                        onHorizontalDrag = { change, dragAmount ->
                            if (gestureSide == null && dragAmount != 0f) {
                                gestureSide = if (dragAmount > 0f) {
                                    AndroidArticleSwipeSide.Leading
                                } else {
                                    AndroidArticleSwipeSide.Trailing
                                }
                            }
                            val side = gestureSide ?: return@detectHorizontalDragGestures
                            val resolved = if (side == AndroidArticleSwipeSide.Leading) currentLeading else currentTrailing
                            if (resolved.visibleActions.isEmpty()) {
                                offsetPx = 0f
                                return@detectHorizontalDragGestures
                            }
                            val revealWidth = actionWidthPx * resolved.visibleActions.size
                            val maximum = if (resolved.full != null) rowWidthPx else revealWidth
                            offsetPx = if (side == AndroidArticleSwipeSide.Leading) {
                                (offsetPx + dragAmount).coerceIn(0f, maximum)
                            } else {
                                (offsetPx + dragAmount).coerceIn(-maximum, 0f)
                            }
                            val armed = AndroidSwipePresentationPolicy.isFullSwipeArmed(
                                offsetPx = offsetPx,
                                rowWidthPx = rowWidthPx,
                                hasFullAction = resolved.full != null,
                            )
                            if (armed && !fullSwipeArmed) {
                                view.performFluxSelectionHaptic()
                            }
                            fullSwipeArmed = armed
                        },
                        onDragCancel = {
                            val target = gestureStartOffset
                            gestureSide = null
                            fullSwipeArmed = false
                            scope.launch { animateOffset(target) }
                        },
                        onDragEnd = {
                            val side = gestureSide
                            gestureSide = null
                            if (side == null) return@detectHorizontalDragGestures
                            val resolved = if (side == AndroidArticleSwipeSide.Leading) currentLeading else currentTrailing
                            val direction = if (side == AndroidArticleSwipeSide.Leading) 1f else -1f
                            val fullAction = resolved.full
                            if (
                                fullAction != null &&
                                AndroidSwipePresentationPolicy.isFullSwipeArmed(
                                    offsetPx = offsetPx,
                                    rowWidthPx = rowWidthPx,
                                    hasFullAction = true,
                                )
                            ) {
                                scope.launch {
                                    animateOffset(direction * rowWidthPx)
                                    currentOnSwipeAction(fullAction)
                                    offsetPx = 0f
                                    fullSwipeArmed = false
                                }
                            } else {
                                fullSwipeArmed = false
                                val revealWidth = actionWidthPx * resolved.visibleActions.size
                                val shouldReveal = revealWidth > 0f && abs(offsetPx) >= actionWidthPx * 0.4f
                                scope.launch {
                                    animateOffset(if (shouldReveal) direction * revealWidth else 0f)
                                }
                            }
                        },
                    )
                }
                .pointerInput(article.id) {
                    detectTapGestures(
                        onTap = { currentOnOpen() },
                        onLongPress = { contextExpanded = true },
                    )
                }
                .semantics {
                    customActions = listOf(
                        CustomAccessibilityAction("Article actions") {
                            contextExpanded = true
                            true
                        },
                    )
                },
        ) {
            content()
        }

        DropdownMenu(
            expanded = contextExpanded,
            onDismissRequest = { contextExpanded = false },
        ) {
            var previousGroup: Int? = null
            AndroidArticleActionPolicy.contextActions(article, mediaState).forEach { action ->
                val group = contextActionGroup(action)
                if (previousGroup != null && previousGroup != group) {
                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                    )
                }
                previousGroup = group
                DropdownMenuItem(
                    leadingIcon = {
                        Icon(
                            painter = painterResource(contextActionIcon(action, article)),
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                        )
                    },
                    text = {
                        Text(localizedContextActionLabel(action, article, mediaState))
                    },
                    onClick = {
                        contextExpanded = false
                        offsetPx = 0f
                        onContextAction(action)
                    },
                )
            }
        }
    }
}

private fun contextActionGroup(action: AndroidArticleContextAction): Int = when (action) {
    AndroidArticleContextAction.ReadUnread,
    AndroidArticleContextAction.StarUnstar,
    -> 0

    AndroidArticleContextAction.OpenOriginal,
    AndroidArticleContextAction.Reader,
    AndroidArticleContextAction.OpenMiniflux,
    AndroidArticleContextAction.Comments,
    -> 1

    AndroidArticleContextAction.CopyLink,
    AndroidArticleContextAction.Share,
    AndroidArticleContextAction.SaveToService,
    -> 2

    AndroidArticleContextAction.ListeningList,
    AndroidArticleContextAction.DownloadAudio,
    -> 3
}

private fun contextActionIcon(
    action: AndroidArticleContextAction,
    article: ArticleSummary,
): Int = when (action) {
    AndroidArticleContextAction.ReadUnread ->
        if (article.isRead) R.drawable.ic_mark_unread else R.drawable.ic_mark_read
    AndroidArticleContextAction.StarUnstar ->
        if (article.isStarred) R.drawable.ic_unstar else R.drawable.ic_star
    AndroidArticleContextAction.OpenOriginal,
    AndroidArticleContextAction.OpenMiniflux,
    -> R.drawable.ic_open_external
    AndroidArticleContextAction.Reader -> R.drawable.ic_reader
    AndroidArticleContextAction.Comments -> R.drawable.ic_comment
    AndroidArticleContextAction.CopyLink -> R.drawable.ic_copy
    AndroidArticleContextAction.Share -> R.drawable.ic_share
    AndroidArticleContextAction.SaveToService -> R.drawable.ic_save
    AndroidArticleContextAction.ListeningList -> R.drawable.ic_headphones
    AndroidArticleContextAction.DownloadAudio -> R.drawable.ic_download
}

@Composable
private fun SwipeActionBackground(
    side: AndroidArticleSwipeSide,
    resolved: AndroidResolvedSwipeSide,
    article: ArticleSummary,
    mediaState: AndroidArticleMediaActionState?,
    fullSwipeArmed: Boolean,
    revealProgress: Float,
    actionWidth: androidx.compose.ui.unit.Dp,
    onAction: (AndroidArticleSwipeAction) -> Unit,
    modifier: Modifier = Modifier,
) {
    val displayedActions = AndroidSwipePresentationPolicy.presentationActions(
        side = side,
        resolved = resolved,
        fullSwipeArmed = fullSwipeArmed,
    )
    if (displayedActions.isEmpty()) return

    val dominantAction = resolved.full ?: displayedActions.first()
    val dominantColors = swipeActionColors(dominantAction)
    val backgroundColor by animateColorAsState(
        // Keep the area behind partially revealed buttons neutral. Otherwise the Full Swipe
        // color bleeds under the second action and makes both buttons look identical.
        targetValue = if (fullSwipeArmed) dominantColors.container else MaterialTheme.colorScheme.surface,
        label = "article-swipe-background",
    )
    val density = LocalDensity.current
    val travelPx = with(density) { 8.dp.toPx() }
    val direction = if (side == AndroidArticleSwipeSide.Leading) -1f else 1f
    val iconTranslation = direction * travelPx * (1f - revealProgress)
    val iconAlpha = 0.55f + (0.45f * revealProgress)

    Box(
        modifier = modifier.background(backgroundColor),
    ) {
        Row(
            modifier = Modifier
                .align(
                    if (side == AndroidArticleSwipeSide.Leading) {
                        Alignment.CenterStart
                    } else {
                        Alignment.CenterEnd
                    },
                )
                .fillMaxHeight(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            displayedActions.forEach { action ->
                val colors = swipeActionColors(action)
                Box(
                    modifier = Modifier
                        .width(actionWidth)
                        .fillMaxHeight()
                        .background(
                            if (fullSwipeArmed) {
                                Color.Transparent
                            } else {
                                colors.container
                            },
                        )
                        .clickable { onAction(action) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painter = painterResource(swipeActionIcon(action, article, mediaState)),
                        contentDescription = localizedSwipeActionLabel(action, article, mediaState),
                        tint = if (fullSwipeArmed) dominantColors.content else colors.content,
                        modifier = Modifier
                            .size(if (fullSwipeArmed) 30.dp else 28.dp)
                            .graphicsLayer {
                                alpha = if (fullSwipeArmed) 1f else iconAlpha
                                translationX = if (fullSwipeArmed) 0f else iconTranslation
                            },
                    )
                }
            }
        }
    }
}

private data class AndroidSwipeActionColors(
    val container: Color,
    val content: Color,
)

// Distinct semantic hues, shared across both swipe directions. The Material color scheme
// controls the light/dark tone, foreground contrast and a subtle dynamic-color harmonization.
internal fun swipeActionHue(action: AndroidArticleSwipeAction): Float = when (action) {
    AndroidArticleSwipeAction.ReadUnread -> 210f       // blue
    AndroidArticleSwipeAction.StarUnstar -> 43f        // amber
    AndroidArticleSwipeAction.OpenOriginal -> 186f     // teal
    AndroidArticleSwipeAction.OpenMiniflux -> 278f     // violet
    AndroidArticleSwipeAction.Comments -> 121f         // green
    AndroidArticleSwipeAction.Share -> 333f           // pink
    AndroidArticleSwipeAction.SaveToService -> 20f     // orange
    AndroidArticleSwipeAction.ListeningList -> 240f    // indigo
    AndroidArticleSwipeAction.DownloadAudio -> 159f   // sea green
}

@Composable
private fun swipeActionColors(action: AndroidArticleSwipeAction): AndroidSwipeActionColors {
    val scheme = MaterialTheme.colorScheme
    val dark = scheme.background.luminance() < 0.5f
    val semanticColor = Color.hsv(
        swipeActionHue(action),
        saturation = if (dark) 0.58f else 0.49f,
        value = if (dark) 0.44f else 0.89f,
    )
    return AndroidSwipeActionColors(
        container = lerp(semanticColor, scheme.primaryContainer, 0.1f),
        content = scheme.onSurface,
    )
}

internal fun swipeDownloadActionIcon(state: DownloadState?): Int = when (state) {
    null, DownloadState.NOT_DOWNLOADED -> R.drawable.ic_download
    DownloadState.REQUESTED -> R.drawable.ic_close
    DownloadState.DOWNLOADED -> R.drawable.ic_delete
    DownloadState.FAILED -> R.drawable.ic_refresh
    DownloadState.DELETE_REQUESTED -> R.drawable.ic_hourglass
}

internal fun swipeActionIcon(
    action: AndroidArticleSwipeAction,
    article: ArticleSummary,
    mediaState: AndroidArticleMediaActionState? = null,
): Int = when (action) {
    AndroidArticleSwipeAction.ReadUnread ->
        if (article.isRead) R.drawable.ic_mark_unread else R.drawable.ic_mark_read
    AndroidArticleSwipeAction.StarUnstar ->
        if (article.isStarred) R.drawable.ic_unstar else R.drawable.ic_star
    AndroidArticleSwipeAction.OpenOriginal,
    AndroidArticleSwipeAction.OpenMiniflux,
    -> R.drawable.ic_open_external
    AndroidArticleSwipeAction.Comments -> R.drawable.ic_comment
    AndroidArticleSwipeAction.Share -> R.drawable.ic_share
    AndroidArticleSwipeAction.SaveToService -> R.drawable.ic_save
    AndroidArticleSwipeAction.ListeningList ->
        if (mediaState?.isInListeningList == true) R.drawable.ic_headphones_remove else R.drawable.ic_headphones
    AndroidArticleSwipeAction.DownloadAudio -> {
        val downloadState = mediaState?.let { state ->
            state.audioEnclosures.singleOrNull()?.let { enclosure -> state.downloads[enclosure.id]?.state }
        }
        swipeDownloadActionIcon(downloadState)
    }
}
