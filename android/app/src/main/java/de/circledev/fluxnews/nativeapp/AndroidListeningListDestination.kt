package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.FiberManualRecord
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.DownloadState
import uniffi.flux_uniffi.FeedIconVariant
import uniffi.flux_uniffi.ListeningListEnclosure
import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.ListeningListSort
import uniffi.flux_uniffi.PlaybackStatus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AndroidListeningListDestination(
    store: AndroidListeningListStore,
    playbackCoordinator: AndroidMediaPlaybackCoordinator,
    transferCoordinator: AndroidMediaTransferCoordinator,
    sessionGeneration: Long?,
    onBack: () -> Unit,
    onToggleSidebar: (() -> Unit)? = null,
    sidebarExpanded: Boolean = false,
) {
    val state by store.state.collectAsState()
    val playback by playbackCoordinator.state.collectAsState()
    val transferProgress by transferCoordinator.progress.collectAsState()
    val mediaRevision by transferCoordinator.revision.collectAsState()
    val coroutineScope = rememberCoroutineScope()
    val feedIconVariant = if (isSystemInDarkTheme()) {
        FeedIconVariant.DARK
    } else {
        FeedIconVariant.NORMAL
    }
    var feedMenuOpen by remember { mutableStateOf(false) }
    var sortMenuOpen by remember { mutableStateOf(false) }
    var playerArticleId by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(sessionGeneration) {
        store.activateSession(sessionGeneration)
        if (sessionGeneration != null) store.reload()
    }
    LaunchedEffect(state.items, feedIconVariant, sessionGeneration) {
        if (sessionGeneration != null) {
            store.ensureFeedIcons(
                state.items.map { it.feedId },
                feedIconVariant,
            )
        }
    }
    LaunchedEffect(mediaRevision, sessionGeneration) {
        if (sessionGeneration != null) store.reload()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.nav_listening_list)) },
                navigationIcon = {
                    if (!sidebarExpanded) IconButton(onClick = onToggleSidebar ?: onBack) {
                        if (onToggleSidebar != null) {
                            Icon(
                                painter = painterResource(R.drawable.ic_sidebar_toggle),
                                contentDescription = stringResource(R.string.nav_toggle),
                            )
                        } else {
                            Icon(
                                Icons.AutoMirrored.Rounded.ArrowBack,
                                contentDescription = stringResource(R.string.list_back),
                            )
                        }
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { feedMenuOpen = true }) {
                            Icon(Icons.Rounded.FilterList, contentDescription = stringResource(R.string.list_filter_feed))
                        }
                        DropdownMenu(
                            expanded = feedMenuOpen,
                            onDismissRequest = { feedMenuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.list_all_feeds)) },
                                onClick = {
                                    feedMenuOpen = false
                                    coroutineScope.launch { store.setFeedId(null) }
                                },
                            )
                            state.feeds.forEach { feed ->
                                DropdownMenuItem(
                                    text = { Text(feed.feedTitle.ifBlank { stringResource(R.string.audit_unknown_feed) }) },
                                    onClick = {
                                        feedMenuOpen = false
                                        coroutineScope.launch { store.setFeedId(feed.feedId) }
                                    },
                                )
                            }
                        }
                    }
                    Box {
                        IconButton(onClick = { sortMenuOpen = true }) {
                            Icon(Icons.AutoMirrored.Rounded.Sort, contentDescription = stringResource(R.string.list_sort))
                        }
                        DropdownMenu(
                            expanded = sortMenuOpen,
                            onDismissRequest = { sortMenuOpen = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.list_recently_added)) },
                                onClick = {
                                    sortMenuOpen = false
                                    coroutineScope.launch {
                                        store.setSort(ListeningListSort.RECENTLY_ADDED)
                                    }
                                },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.list_publication_date)) },
                                onClick = {
                                    sortMenuOpen = false
                                    coroutineScope.launch {
                                        store.setSort(ListeningListSort.PUBLICATION_DATE)
                                    }
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading && state.items.isEmpty() -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }

            state.errorMessage != null && state.items.isEmpty() -> Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    Icons.Rounded.Headphones,
                    contentDescription = null,
                    modifier = Modifier.size(52.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(16.dp))
                Text(
                    state.errorMessage.orEmpty().let(LocalContext.current::localizedLegacyUiMessage),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(12.dp))
                Button(onClick = { coroutineScope.launch { store.reload() } }) {
                    Text(stringResource(R.string.list_retry))
                }
            }

            state.items.isEmpty() -> Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    Icons.Rounded.Headphones,
                    contentDescription = null,
                    modifier = Modifier.size(80.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(16.dp))
                Text(
                    stringResource(R.string.l10n_list_empty),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.size(6.dp))
                Text(
                    stringResource(R.string.l10n_list_empty_hint),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            else -> LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                items(state.items, key = { it.articleId }) { item ->
                    AndroidListeningListRow(
                        item = item,
                        playback = playback,
                        transferProgress = transferProgress,
                        feedIconVariant = feedIconVariant,
                        feedIconPngData = state.feedIconPngByFeedId[item.feedId],
                        playbackCoordinator = playbackCoordinator,
                        onRequestFeedIcon = { feedId, variant ->
                            store.ensureFeedIcons(listOf(feedId), variant)
                        },
                        artwork = selectedListeningListArtwork(
                            item = item,
                            playback = playback,
                            artworkByEnclosureId = state.artworkByEnclosureId,
                        ),
                        onPlay = { enclosureId ->
                            coroutineScope.launch { playbackCoordinator.play(enclosureId) }
                        },
                        onPause = {
                            coroutineScope.launch { playbackCoordinator.pause() }
                        },
                        onOpenPlayer = {
                            playerArticleId = item.articleId
                        },
                        onRemove = {
                            coroutineScope.launch {
                                store.removeFromListeningList(item.articleId)
                            }
                        },
                        onRequestDownload = { enclosureId ->
                            coroutineScope.launch { store.requestDownload(enclosureId) }
                        },
                        onCancelDownload = { enclosureId ->
                            coroutineScope.launch { store.cancelDownload(enclosureId) }
                        },
                        onRetryDownload = { enclosureId ->
                            coroutineScope.launch { store.retryDownload(enclosureId) }
                        },
                        onDeleteDownload = { enclosureId ->
                            coroutineScope.launch { store.deleteDownload(enclosureId) }
                        },
                    )
                    HorizontalDivider()
                }
            }
        }
    }

    playerArticleId
        ?.let { articleId -> state.items.firstOrNull { it.articleId == articleId } }
        ?.let { item ->
            AndroidMediaPlayerSheet(
                coordinator = playbackCoordinator,
                previewItem = item,
                mediaRevision = mediaRevision,
                onDismiss = { playerArticleId = null },
            )
        }
}

@Composable
private fun AndroidListeningListRow(
    item: ListeningListItem,
    playback: AndroidMediaPlaybackState,
    transferProgress: Map<Long, AndroidMediaTransferProgress>,
    feedIconVariant: FeedIconVariant,
    feedIconPngData: ByteArray?,
    playbackCoordinator: AndroidMediaPlaybackCoordinator,
    onRequestFeedIcon: suspend (Long, FeedIconVariant) -> Unit,
    artwork: AndroidListeningListArtwork?,
    onPlay: (Long) -> Unit,
    onPause: () -> Unit,
    onOpenPlayer: () -> Unit,
    onRemove: () -> Unit,
    onRequestDownload: (Long) -> Unit,
    onCancelDownload: (Long) -> Unit,
    onRetryDownload: (Long) -> Unit,
    onDeleteDownload: (Long) -> Unit,
) {
    var actionsOpen by remember { mutableStateOf(false) }
    val nowPlayingEnclosure = playback.enclosureId?.let { loadedId ->
        item.audioEnclosures.firstOrNull { it.enclosure.id == loadedId }
    }
    val selected = nowPlayingEnclosure
        ?: item.audioEnclosures.firstOrNull { it.enclosure.id == item.activeEnclosureId }
        ?: item.audioEnclosures.firstOrNull()
    val selectedId = selected?.enclosure?.id
    val isNowPlaying = nowPlayingEnclosure != null &&
        playback.status != AndroidMediaPlaybackPresentationStatus.Stopped
    val isPlaying = isNowPlaying &&
        playback.status == AndroidMediaPlaybackPresentationStatus.Playing
    val persistedStatus = selected?.playbackState?.status ?: PlaybackStatus.NOT_STARTED
    val displayedStatus = if (selectedId != null && playback.enclosureId == selectedId) {
        when (playback.status) {
            AndroidMediaPlaybackPresentationStatus.Completed -> PlaybackStatus.COMPLETED
            AndroidMediaPlaybackPresentationStatus.Playing -> PlaybackStatus.IN_PROGRESS
            AndroidMediaPlaybackPresentationStatus.Paused,
            AndroidMediaPlaybackPresentationStatus.Stopped,
            AndroidMediaPlaybackPresentationStatus.Idle -> persistedStatus
        }
    } else {
        persistedStatus
    }
    val isCompleted = displayedStatus == PlaybackStatus.COMPLETED
    val isUnplayed = !isCompleted &&
        isUnplayedListeningListItem(item) &&
        (nowPlayingEnclosure == null ||
            (playback.status != AndroidMediaPlaybackPresentationStatus.Playing &&
                playback.positionMs == 0L))

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = selectedId != null, onClick = onOpenPlayer)
            .padding(horizontal = 18.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AndroidListeningListArtwork(
                artwork = artwork,
                playbackCoordinator = playbackCoordinator,
                modifier = Modifier.size(88.dp),
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        item.title.ifBlank { stringResource(R.string.audit_untitled_news) },
                        modifier = Modifier.weight(1f, fill = false),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (isCompleted) {
                        Icon(
                            Icons.Rounded.CheckCircle,
                            contentDescription = stringResource(R.string.audit_playback_completed),
                            tint = MaterialTheme.colorScheme.tertiary,
                            modifier = Modifier.size(18.dp),
                        )
                    } else if (isUnplayed) {
                        Icon(
                            Icons.Rounded.FiberManualRecord,
                            contentDescription = stringResource(R.string.audit_playback_not_started),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(12.dp),
                        )
                    }
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    FeedIcon(
                        feedId = item.feedId,
                        title = item.feedTitle,
                        pngData = feedIconPngData,
                        variant = feedIconVariant,
                        onRequest = onRequestFeedIcon,
                        size = 16.dp,
                    )
                    Text(
                        item.feedTitle.ifBlank { stringResource(R.string.audit_unknown_feed) },
                        modifier = Modifier.weight(1f, fill = false),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                androidListeningListPublicationDate(item.publishedAt)?.let { date ->
                    Text(
                        date,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (isNowPlaying) {
                    Text(
                        stringResource(R.string.l10n_now_playing),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        selected?.playbackState?.let { progress ->
            AndroidListeningListProgress(
                positionMs = if (playback.enclosureId == selectedId) {
                    playback.positionMs
                } else {
                    progress.positionMs.toLong()
                },
                durationMs = if (playback.enclosureId == selectedId) {
                    playback.durationMs ?: progress.durationMs?.toLong()
                } else {
                    progress.durationMs?.toLong()
                },
                status = displayedStatus,
            )
        }

        selectedId?.let { enclosureId ->
            transferProgress[enclosureId]?.let { progress ->
                AndroidListeningListTransferProgress(progress)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier.weight(1f),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AndroidMediaMetric(
                    icon = {
                        Icon(
                            Icons.Rounded.Headphones,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                    },
                    text = if (item.audioEnclosures.size == 1) {
                        "1 audio"
                    } else {
                        item.audioEnclosures.size.toString() + " audio"
                    },
                )
                selected?.download?.state?.let { state ->
                    when (state) {
                        DownloadState.DOWNLOADED -> AndroidMediaMetric(
                            icon = {
                                Icon(
                                    Icons.Rounded.Download,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                            },
                            text = stringResource(R.string.l10n_downloaded),
                        )
                        DownloadState.REQUESTED -> AndroidMediaMetric(
                            icon = {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(14.dp),
                                    strokeWidth = 2.dp,
                                )
                            },
                            text = stringResource(R.string.l10n_pending),
                        )
                        DownloadState.FAILED -> AndroidMediaMetric(
                            icon = {
                                Icon(
                                    Icons.Rounded.RestartAlt,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                            },
                            text = stringResource(R.string.l10n_retry),
                        )
                        else -> Unit
                    }
                }
            }

            FilledIconButton(
                onClick = {
                    if (selectedId != null) {
                        if (isPlaying) onPause() else onPlay(selectedId)
                    }
                },
                enabled = selectedId != null,
            ) {
                Icon(
                    if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = stringResource(if (isPlaying) R.string.l10n_pause else R.string.l10n_play),
                )
            }

            Box {
                IconButton(onClick = { actionsOpen = true }) {
                    Icon(Icons.Rounded.MoreVert, contentDescription = stringResource(R.string.list_actions))
                }
                AndroidListeningListItemMenu(
                    expanded = actionsOpen,
                    item = item,
                    playback = playback,
                    onDismiss = { actionsOpen = false },
                    onPlay = onPlay,
                    onPause = onPause,
                    onRequestDownload = onRequestDownload,
                    onCancelDownload = onCancelDownload,
                    onRetryDownload = onRetryDownload,
                    onDeleteDownload = onDeleteDownload,
                    onRemove = onRemove,
                )
            }
        }
    }
}

private fun selectedListeningListArtwork(
    item: ListeningListItem,
    playback: AndroidMediaPlaybackState,
    artworkByEnclosureId: Map<Long, AndroidListeningListArtwork>,
): AndroidListeningListArtwork? {
    val enclosureId = playback.enclosureId
        ?.takeIf { loadedId ->
            item.audioEnclosures.any { it.enclosure.id == loadedId }
        }
        ?: item.activeEnclosureId
        ?: item.audioEnclosures.firstOrNull()?.enclosure?.id
    return enclosureId?.let(artworkByEnclosureId::get)
}

@Composable
private fun AndroidListeningListArtwork(
    artwork: AndroidListeningListArtwork?,
    playbackCoordinator: AndroidMediaPlaybackCoordinator,
    modifier: Modifier = Modifier,
) {
    val localBytes by androidx.compose.runtime.produceState<ByteArray?>(
        initialValue = null,
        key1 = artwork,
    ) {
        value = when (artwork) {
            is AndroidListeningListArtwork.LocalReference ->
                playbackCoordinator.artworkBytes(artwork.reference)
            else -> null
        }
    }
    val model = when (artwork) {
        is AndroidListeningListArtwork.LocalReference -> localBytes
        is AndroidListeningListArtwork.RemoteUrl -> artwork.url
        null -> null
    }
    val clipped = modifier.clip(RoundedCornerShape(10.dp))
    if (model != null) {
        AsyncImage(
            model = model,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = clipped,
            error = painterResource(R.drawable.fallback_artwork),
            fallback = painterResource(R.drawable.fallback_artwork),
        )
    } else {
        Image(
            painter = painterResource(R.drawable.fallback_artwork),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = clipped,
        )
    }
}

@Composable
private fun AndroidListeningListItemMenu(
    expanded: Boolean,
    item: ListeningListItem,
    playback: AndroidMediaPlaybackState,
    onDismiss: () -> Unit,
    onPlay: (Long) -> Unit,
    onPause: () -> Unit,
    onRequestDownload: (Long) -> Unit,
    onCancelDownload: (Long) -> Unit,
    onRetryDownload: (Long) -> Unit,
    onDeleteDownload: (Long) -> Unit,
    onRemove: () -> Unit,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
    ) {
        item.audioEnclosures.forEachIndexed { index, enclosure ->
            val id = enclosure.enclosure.id
            val active = playback.enclosureId == id &&
                playback.status == AndroidMediaPlaybackPresentationStatus.Playing
            val label = enclosure.enclosure.mimeType.ifBlank {
                "Audio " + (index + 1)
            }

            DropdownMenuItem(
                text = {
                    Text(
                        (if (active) "Pause · " else "Play · ") + label,
                    )
                },
                leadingIcon = {
                    Icon(
                        if (active) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                        contentDescription = null,
                    )
                },
                onClick = {
                    onDismiss()
                    if (active) onPause() else onPlay(id)
                },
            )

            AndroidListeningListDownloadMenuItem(
                enclosure = enclosure,
                onDismiss = onDismiss,
                onRequestDownload = onRequestDownload,
                onCancelDownload = onCancelDownload,
                onRetryDownload = onRetryDownload,
                onDeleteDownload = onDeleteDownload,
            )

            if (index != item.audioEnclosures.lastIndex) {
                HorizontalDivider()
            }
        }

        if (item.audioEnclosures.isNotEmpty()) {
            HorizontalDivider()
        }
        DropdownMenuItem(
            text = { Text(stringResource(R.string.list_remove)) },
            leadingIcon = {
                Icon(Icons.Rounded.Close, contentDescription = null)
            },
            onClick = {
                onDismiss()
                onRemove()
            },
        )
    }
}

@Composable
private fun AndroidListeningListDownloadMenuItem(
    enclosure: ListeningListEnclosure,
    onDismiss: () -> Unit,
    onRequestDownload: (Long) -> Unit,
    onCancelDownload: (Long) -> Unit,
    onRetryDownload: (Long) -> Unit,
    onDeleteDownload: (Long) -> Unit,
) {
    val id = enclosure.enclosure.id
    when (enclosure.download?.state ?: DownloadState.NOT_DOWNLOADED) {
        DownloadState.NOT_DOWNLOADED -> DropdownMenuItem(
            text = { Text(stringResource(R.string.list_download)) },
            leadingIcon = { Icon(Icons.Rounded.Download, contentDescription = null) },
            onClick = {
                onDismiss()
                onRequestDownload(id)
            },
        )
        DownloadState.REQUESTED -> DropdownMenuItem(
            text = { Text(stringResource(R.string.list_cancel_download)) },
            leadingIcon = { Icon(Icons.Rounded.Close, contentDescription = null) },
            onClick = {
                onDismiss()
                onCancelDownload(id)
            },
        )
        DownloadState.DOWNLOADED -> DropdownMenuItem(
            text = { Text(stringResource(R.string.list_delete_download)) },
            leadingIcon = { Icon(Icons.Rounded.Delete, contentDescription = null) },
            onClick = {
                onDismiss()
                onDeleteDownload(id)
            },
        )
        DownloadState.FAILED -> DropdownMenuItem(
            text = { Text(stringResource(R.string.list_retry_download)) },
            leadingIcon = { Icon(Icons.Rounded.RestartAlt, contentDescription = null) },
            onClick = {
                onDismiss()
                onRetryDownload(id)
            },
        )
        DownloadState.DELETE_REQUESTED -> DropdownMenuItem(
            text = { Text(stringResource(R.string.list_deletion_pending)) },
            enabled = false,
            onClick = {},
        )
    }
}

@Composable
private fun AndroidListeningListProgress(
    positionMs: Long,
    durationMs: Long?,
    status: PlaybackStatus,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (status == PlaybackStatus.COMPLETED) {
            LinearProgressIndicator(
                progress = { 1f },
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.tertiary,
            )
        } else if (durationMs != null && durationMs > 0L) {
            LinearProgressIndicator(
                progress = {
                    (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
                },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        val durationLabel = durationMs?.let { " / " + androidMediaTime(it) }.orEmpty()
        val statusLabel = when (status) {
            PlaybackStatus.NOT_STARTED -> stringResource(R.string.audit_playback_not_started)
            PlaybackStatus.IN_PROGRESS -> stringResource(R.string.audit_playback_in_progress)
            PlaybackStatus.COMPLETED -> stringResource(R.string.audit_playback_completed)
        }
        Text(
            androidMediaTime(positionMs) + durationLabel + " · " + statusLabel,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun AndroidListeningListTransferProgress(
    progress: AndroidMediaTransferProgress,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        progress.fraction?.let { fraction ->
            LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth(),
            )
        } ?: LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        Text(
            buildString {
                append("Downloading · ")
                append(androidMediaBytes(progress.bytesDownloaded))
                progress.totalBytes?.let { total ->
                    append(" / ")
                    append(androidMediaBytes(total))
                }
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun AndroidMediaMetric(
    icon: @Composable () -> Unit,
    text: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon()
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun androidListeningListPublicationDate(value: String): String? =
    runCatching {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
            .withLocale(Locale.getDefault())
            .format(Instant.parse(value).atZone(java.time.ZoneId.systemDefault()))
    }.getOrNull()

private fun androidMediaBytes(bytes: Long): String {
    val safe = bytes.coerceAtLeast(0L).toDouble()
    return when {
        safe >= 1024.0 * 1024.0 * 1024.0 ->
            "%.1f GB".format(safe / (1024.0 * 1024.0 * 1024.0))
        safe >= 1024.0 * 1024.0 ->
            "%.1f MB".format(safe / (1024.0 * 1024.0))
        safe >= 1024.0 ->
            "%.1f KB".format(safe / 1024.0)
        else -> safe.toLong().toString() + " B"
    }
}

private fun androidMediaTime(milliseconds: Long): String {
    val totalSeconds = milliseconds.coerceAtLeast(0L) / 1_000L
    val hours = totalSeconds / 3_600L
    val minutes = (totalSeconds % 3_600L) / 60L
    val seconds = totalSeconds % 60L
    return if (hours > 0L) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}
