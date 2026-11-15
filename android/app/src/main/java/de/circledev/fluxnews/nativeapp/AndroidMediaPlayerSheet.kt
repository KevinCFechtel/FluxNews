package de.circledev.fluxnews.nativeapp

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Forward30
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.MediaArtworkSource
import uniffi.flux_uniffi.MediaChapter
import uniffi.flux_uniffi.ReaderDocument

@Composable
internal fun AndroidMediaPlayerSheet(
    coordinator: AndroidMediaPlaybackCoordinator,
    previewItem: ListeningListItem? = null,
    mediaRevision: Long = 0L,
    onDismiss: () -> Unit,
) {
    val playback by coordinator.state.collectAsState()
    val sleepTimer by coordinator.sleepTimer.state.collectAsState()
    val scope = rememberCoroutineScope()
    val audit_show_notes_failText = stringResource(R.string.audit_show_notes_fail)
    val previewEnclosure = remember(previewItem, playback.enclosureId) {
        previewItem?.let { item ->
            item.activeEnclosureId
                ?.let { activeId ->
                    item.audioEnclosures.firstOrNull { it.enclosure.id == activeId }
                }
                ?: item.audioEnclosures.firstOrNull()
        }
    }
    val isPreviewingInactiveItem =
        previewEnclosure != null && previewEnclosure.enclosure.id != playback.enclosureId
    val displayedEnclosureId =
        if (isPreviewingInactiveItem) previewEnclosure.enclosure.id else playback.enclosureId
    val displayedArticleId =
        if (isPreviewingInactiveItem) previewItem?.articleId else playback.articleId
    val displayedTitle =
        if (isPreviewingInactiveItem) previewItem?.title else playback.articleTitle
    val displayedFeedTitle =
        if (isPreviewingInactiveItem) previewItem?.feedTitle else playback.feedTitle
    val displayedPositionMs =
        if (isPreviewingInactiveItem) {
            previewEnclosure.playbackState?.positionMs?.toLong() ?: 0L
        } else {
            playback.positionMs
        }
    val displayedDurationMs =
        if (isPreviewingInactiveItem) {
            previewEnclosure.durationMs?.toLong()
                ?: previewEnclosure.playbackState?.durationMs?.toLong()
        } else {
            playback.durationMs
        }
    var rateMenuOpen by remember { mutableStateOf(false) }
    var sleepMenuOpen by remember { mutableStateOf(false) }
    var overflowOpen by remember { mutableStateOf(false) }
    var chaptersExpanded by remember { mutableStateOf(false) }
    var showNotesExpanded by remember { mutableStateOf(false) }
    var showNotesLoading by remember { mutableStateOf(false) }
    var showNotesError by remember { mutableStateOf<String?>(null) }
    var showNotesDocument by remember { mutableStateOf<ReaderDocument?>(null) }
    var showNotesRequestGeneration by remember { mutableLongStateOf(0L) }
    var seeking by remember { mutableStateOf(false) }
    var seekValue by remember(displayedEnclosureId) {
        mutableFloatStateOf(displayedPositionMs.toFloat())
    }

    LaunchedEffect(displayedPositionMs, seeking) {
        if (!seeking) seekValue = displayedPositionMs.toFloat()
    }
    LaunchedEffect(displayedArticleId) {
        showNotesRequestGeneration += 1L
        showNotesExpanded = false
        showNotesLoading = false
        showNotesError = null
        showNotesDocument = null
    }

    val artworkRefreshKey = listOf(
        displayedEnclosureId,
        isPreviewingInactiveItem,
        playback.artworkSource,
        mediaRevision,
    )
    val displayedArtworkSource by produceState<MediaArtworkSource?>(
        initialValue = if (isPreviewingInactiveItem) null else playback.artworkSource,
        key1 = artworkRefreshKey,
    ) {
        value = if (isPreviewingInactiveItem) {
            displayedEnclosureId?.let { coordinator.artworkSource(it) }
        } else {
            playback.artworkSource
        }
    }
    val chapterRefreshKey = listOf(
        displayedEnclosureId,
        isPreviewingInactiveItem,
        playback.chapters,
        mediaRevision,
    )
    val displayedChapters by produceState(
        initialValue = if (isPreviewingInactiveItem) emptyList() else playback.chapters,
        key1 = chapterRefreshKey,
    ) {
        value = if (isPreviewingInactiveItem) {
            displayedEnclosureId?.let { coordinator.chapters(it) }.orEmpty()
        } else {
            playback.chapters
        }
    }
    val artworkModel by produceState<Any?>(
        initialValue = null,
        key1 = displayedArtworkSource,
        key2 = displayedEnclosureId,
    ) {
        value = when (val source = displayedArtworkSource) {
            is MediaArtworkSource.LocalReference -> coordinator.artworkBytes(source.reference)
            is MediaArtworkSource.RemoteUrl -> source.url
            null -> null
        }
    }

    fun requestShowNotes(articleId: Long) {
        val requestGeneration = showNotesRequestGeneration + 1L
        showNotesRequestGeneration = requestGeneration
        showNotesLoading = true
        showNotesError = null
        scope.launch {
            coordinator.showNotes(articleId).fold(
                onSuccess = { document ->
                    if (showNotesRequestGeneration == requestGeneration) {
                        showNotesDocument = document
                        showNotesLoading = false
                    }
                },
                onFailure = {
                    if (showNotesRequestGeneration == requestGeneration) {
                        showNotesError = audit_show_notes_failText
                        showNotesLoading = false
                    }
                },
            )
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.97f)
                .fillMaxHeight(0.94f),
            shape = RoundedCornerShape(28.dp),
            tonalElevation = 6.dp,
            shadowElevation = 10.dp,
        ) {
            Column(Modifier.fillMaxSize()) {
                AndroidMediaPlayerTopBar(
                    completed = !isPreviewingInactiveItem &&
                        playback.status == AndroidMediaPlaybackPresentationStatus.Completed,
                    onRestart = {
                        playback.enclosureId?.let { id ->
                            scope.launch { coordinator.restart(id) }
                        }
                    },
                    onDismiss = onDismiss,
                    overflowOpen = overflowOpen,
                    onOverflowChange = { overflowOpen = it },
                )
                HorizontalDivider()

                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                ) {
                    val sideBySide = maxWidth >= 720.dp || maxWidth > maxHeight * 1.25f
                    if (sideBySide) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(28.dp),
                            horizontalArrangement = Arrangement.spacedBy(32.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            AndroidMediaArtwork(
                                model = artworkModel,
                                loading = !isPreviewingInactiveItem &&
                                    (playback.isLoading || playback.isBuffering),
                                modifier = Modifier
                                    .weight(0.9f)
                                    .widthIn(max = 360.dp),
                            )
                            AndroidMediaPlayerControls(
                                coordinator = coordinator,
                                playback = playback,
                                previewingInactiveItem = isPreviewingInactiveItem,
                                displayedEnclosureId = displayedEnclosureId,
                                displayedArticleId = displayedArticleId,
                                displayedTitle = displayedTitle,
                                displayedFeedTitle = displayedFeedTitle,
                                displayedPositionMs = displayedPositionMs,
                                displayedDurationMs = displayedDurationMs,
                                displayedChapters = displayedChapters,
                                sleepTimer = sleepTimer,
                                seeking = seeking,
                                seekValue = seekValue,
                                onSeekingChange = {
                                    seeking = true
                                    seekValue = it
                                },
                                onSeekFinished = {
                                    val target = seekValue.toLong().coerceAtLeast(0L)
                                    seeking = false
                                    scope.launch { coordinator.seekTo(target) }
                                },
                                rateMenuOpen = rateMenuOpen,
                                onRateMenuChange = { rateMenuOpen = it },
                                sleepMenuOpen = sleepMenuOpen,
                                onSleepMenuChange = { sleepMenuOpen = it },
                                chaptersExpanded = chaptersExpanded,
                                onChaptersExpandedChange = { chaptersExpanded = it },
                                showNotesExpanded = showNotesExpanded,
                                showNotesLoading = showNotesLoading,
                                showNotesError = showNotesError,
                                showNotesDocument = showNotesDocument,
                                onShowNotesExpandedChange = { expanded ->
                                    showNotesExpanded = expanded
                                    if (expanded && showNotesDocument == null && !showNotesLoading) {
                                        displayedArticleId?.let { articleId ->
                                            requestShowNotes(articleId)
                                        }
                                    }
                                },
                                onRetryShowNotes = {
                                    displayedArticleId?.let { articleId ->
                                        requestShowNotes(articleId)
                                    }
                                },
                                modifier = Modifier.weight(1.15f),
                            )
                        }
                    } else {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 24.dp, vertical = 22.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(24.dp),
                        ) {
                            AndroidMediaArtwork(
                                model = artworkModel,
                                loading = !isPreviewingInactiveItem &&
                                    (playback.isLoading || playback.isBuffering),
                                modifier = Modifier.widthIn(max = 300.dp),
                            )
                            AndroidMediaPlayerControls(
                                coordinator = coordinator,
                                playback = playback,
                                previewingInactiveItem = isPreviewingInactiveItem,
                                displayedEnclosureId = displayedEnclosureId,
                                displayedArticleId = displayedArticleId,
                                displayedTitle = displayedTitle,
                                displayedFeedTitle = displayedFeedTitle,
                                displayedPositionMs = displayedPositionMs,
                                displayedDurationMs = displayedDurationMs,
                                displayedChapters = displayedChapters,
                                sleepTimer = sleepTimer,
                                seeking = seeking,
                                seekValue = seekValue,
                                onSeekingChange = {
                                    seeking = true
                                    seekValue = it
                                },
                                onSeekFinished = {
                                    val target = seekValue.toLong().coerceAtLeast(0L)
                                    seeking = false
                                    scope.launch { coordinator.seekTo(target) }
                                },
                                rateMenuOpen = rateMenuOpen,
                                onRateMenuChange = { rateMenuOpen = it },
                                sleepMenuOpen = sleepMenuOpen,
                                onSleepMenuChange = { sleepMenuOpen = it },
                                chaptersExpanded = chaptersExpanded,
                                onChaptersExpandedChange = { chaptersExpanded = it },
                                showNotesExpanded = showNotesExpanded,
                                showNotesLoading = showNotesLoading,
                                showNotesError = showNotesError,
                                showNotesDocument = showNotesDocument,
                                onShowNotesExpandedChange = { expanded ->
                                    showNotesExpanded = expanded
                                    if (expanded && showNotesDocument == null && !showNotesLoading) {
                                        displayedArticleId?.let { articleId ->
                                            showNotesLoading = true
                                            showNotesError = null
                                            scope.launch {
                                                coordinator.showNotes(articleId).fold(
                                                    onSuccess = {
                                                        showNotesDocument = it
                                                        showNotesLoading = false
                                                    },
                                                    onFailure = {
                                                        showNotesError = audit_show_notes_failText
                                                        showNotesLoading = false
                                                    },
                                                )
                                            }
                                        }
                                    }
                                },
                                onRetryShowNotes = {
                                    displayedArticleId?.let { articleId ->
                                        showNotesLoading = true
                                        showNotesError = null
                                        scope.launch {
                                            coordinator.showNotes(articleId).fold(
                                                onSuccess = {
                                                    showNotesDocument = it
                                                    showNotesLoading = false
                                                },
                                                onFailure = {
                                                    showNotesError = audit_show_notes_failText
                                                    showNotesLoading = false
                                                },
                                            )
                                        }
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AndroidMediaPlayerTopBar(
    completed: Boolean,
    onRestart: () -> Unit,
    onDismiss: () -> Unit,
    overflowOpen: Boolean,
    onOverflowChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.End,
    ) {
        if (completed) {
            Box {
                IconButton(onClick = { onOverflowChange(true) }) {
                    Icon(Icons.Rounded.MoreVert, contentDescription = stringResource(R.string.player_actions))
                }
                DropdownMenu(
                    expanded = overflowOpen,
                    onDismissRequest = { onOverflowChange(false) },
                ) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.player_restart)) },
                        leadingIcon = {
                            Icon(Icons.Rounded.RestartAlt, contentDescription = null)
                        },
                        onClick = {
                            onOverflowChange(false)
                            onRestart()
                        },
                    )
                }
            }
        }
        IconButton(onClick = onDismiss) {
            Icon(Icons.Rounded.Close, contentDescription = stringResource(R.string.player_close))
        }
    }
}

@Composable
private fun AndroidMediaPlayerControls(
    coordinator: AndroidMediaPlaybackCoordinator,
    playback: AndroidMediaPlaybackState,
    previewingInactiveItem: Boolean,
    displayedEnclosureId: Long?,
    displayedArticleId: Long?,
    displayedTitle: String?,
    displayedFeedTitle: String?,
    displayedPositionMs: Long,
    displayedDurationMs: Long?,
    displayedChapters: List<MediaChapter>,
    sleepTimer: AndroidMediaSleepTimerState,
    seeking: Boolean,
    seekValue: Float,
    onSeekingChange: (Float) -> Unit,
    onSeekFinished: () -> Unit,
    rateMenuOpen: Boolean,
    onRateMenuChange: (Boolean) -> Unit,
    sleepMenuOpen: Boolean,
    onSleepMenuChange: (Boolean) -> Unit,
    chaptersExpanded: Boolean,
    onChaptersExpandedChange: (Boolean) -> Unit,
    showNotesExpanded: Boolean,
    showNotesLoading: Boolean,
    showNotesError: String?,
    showNotesDocument: ReaderDocument?,
    onShowNotesExpandedChange: (Boolean) -> Unit,
    onRetryShowNotes: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()

    Column(
        modifier = modifier.widthIn(max = 560.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                displayedTitle?.ifBlank { stringResource(R.string.article_audio) } ?: stringResource(R.string.article_audio),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            displayedFeedTitle?.takeIf { it.isNotBlank() }?.let { feed ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Rounded.Headphones,
                        contentDescription = null,
                        modifier = Modifier.size(17.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        feed,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        displayedDurationMs?.takeIf { it > 0L }?.let { duration ->
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Slider(
                    value = seekValue.coerceIn(0f, duration.toFloat()),
                    onValueChange = onSeekingChange,
                    onValueChangeFinished = onSeekFinished,
                    enabled = !previewingInactiveItem,
                    valueRange = 0f..duration.toFloat(),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        androidPlayerTime(if (seeking) seekValue.toLong() else displayedPositionMs),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        androidPlayerTime(duration),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        AndroidMediaTransportControls(
            playback = playback,
            previewingInactiveItem = previewingInactiveItem,
            hasDisplayedEnclosure = displayedEnclosureId != null,
            onBack = { scope.launch { coordinator.skipBackward15Seconds() } },
            onPlayPause = {
                displayedEnclosureId?.let { id ->
                    scope.launch {
                        if (
                            !previewingInactiveItem &&
                            playback.status == AndroidMediaPlaybackPresentationStatus.Playing
                        ) {
                            coordinator.pause()
                        } else {
                            coordinator.play(id)
                        }
                    }
                }
            },
            onForward = { scope.launch { coordinator.skipForward30Seconds() } },
            onStop = { scope.launch { coordinator.stop() } },
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(modifier = Modifier.weight(1f)) {
                OutlinedButton(
                    onClick = { onRateMenuChange(true) },
                    enabled = !previewingInactiveItem,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        Icons.Rounded.Speed,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(androidPlaybackRateLabel(playback.playbackRate))
                }
                DropdownMenu(
                    expanded = rateMenuOpen,
                    onDismissRequest = { onRateMenuChange(false) },
                ) {
                    listOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f, 2.5f, 3.0f).forEach { rate ->
                        DropdownMenuItem(
                            text = { Text(androidPlaybackRateLabel(rate)) },
                            onClick = {
                                onRateMenuChange(false)
                                scope.launch { coordinator.setPlaybackRate(rate) }
                            },
                        )
                    }
                }
            }

            Box(modifier = Modifier.weight(1f)) {
                OutlinedButton(
                    onClick = { onSleepMenuChange(true) },
                    enabled = !previewingInactiveItem,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        Icons.Rounded.Bedtime,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(
                        if (sleepTimer.enabled) {
                            sleepTimer.remainingSeconds?.let {
                                androidPlayerTime(it * 1_000L)
                            } ?: stringResource(R.string.l10n_sleep_on)
                        } else {
                            stringResource(R.string.l10n_sleep)
                        },
                    )
                }
                DropdownMenu(
                    expanded = sleepMenuOpen,
                    onDismissRequest = { onSleepMenuChange(false) },
                ) {
                    if (sleepTimer.enabled) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.player_turn_off)) },
                            onClick = {
                                onSleepMenuChange(false)
                                coordinator.sleepTimer.disable()
                            },
                        )
                    }
                    AndroidMediaSleepTimer.SupportedIntervalsMinutes.forEach { minutes ->
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.l10n_duration_minutes, minutes)) },
                            onClick = {
                                onSleepMenuChange(false)
                                coordinator.sleepTimer.setInterval(minutes)
                                coordinator.sleepTimer.setEnabled(true)
                            },
                        )
                    }
                }
            }
        }

        if (displayedChapters.isNotEmpty()) {
            AndroidMediaChapterSection(
                chapters = displayedChapters,
                positionMs = displayedPositionMs,
                expanded = chaptersExpanded,
                onToggle = { onChaptersExpandedChange(!chaptersExpanded) },
                onSelect = { start ->
                    if (!previewingInactiveItem) {
                        scope.launch { coordinator.seekTo(start) }
                    }
                },
            )
        }

        displayedArticleId?.let {
            AndroidMediaShowNotesSection(
                expanded = showNotesExpanded,
                loading = showNotesLoading,
                error = showNotesError,
                document = showNotesDocument,
                onToggle = { onShowNotesExpandedChange(!showNotesExpanded) },
                onRetry = onRetryShowNotes,
            )
        }

        if (!previewingInactiveItem) playback.errorMessage?.let { error ->
            Text(
                LocalContext.current.localizedLegacyUiMessage(error),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun AndroidMediaTransportControls(
    playback: AndroidMediaPlaybackState,
    previewingInactiveItem: Boolean,
    hasDisplayedEnclosure: Boolean,
    onBack: () -> Unit,
    onPlayPause: () -> Unit,
    onForward: () -> Unit,
    onStop: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(
            onClick = onBack,
            enabled = hasDisplayedEnclosure && !previewingInactiveItem,
        ) {
            Icon(
                painter = painterResource(androidx.media3.session.R.drawable.media3_icon_skip_back_15),
                contentDescription = stringResource(R.string.player_back_15),
                modifier = Modifier.size(30.dp),
            )
        }

        Box(
            modifier = Modifier.size(76.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (!previewingInactiveItem && (playback.isLoading || playback.isBuffering)) {
                CircularProgressIndicator(
                    modifier = Modifier.size(72.dp),
                    strokeWidth = 3.dp,
                )
            }
            FilledIconButton(
                onClick = onPlayPause,
                enabled = hasDisplayedEnclosure,
                modifier = Modifier.size(58.dp),
                shape = CircleShape,
            ) {
                Icon(
                    if (
                        !previewingInactiveItem &&
                        playback.status == AndroidMediaPlaybackPresentationStatus.Playing
                    ) {
                        Icons.Rounded.Pause
                    } else {
                        Icons.Rounded.PlayArrow
                    },
                    contentDescription = if (
                        !previewingInactiveItem &&
                        playback.status == AndroidMediaPlaybackPresentationStatus.Playing
                    ) {
                        stringResource(R.string.l10n_pause)
                    } else {
                        stringResource(R.string.l10n_play)
                    },
                    modifier = Modifier.size(34.dp),
                )
            }
        }

        IconButton(
            onClick = onForward,
            enabled = hasDisplayedEnclosure && !previewingInactiveItem,
        ) {
            Icon(
                Icons.Rounded.Forward30,
                contentDescription = stringResource(R.string.player_forward_30),
                modifier = Modifier.size(30.dp),
            )
        }

        IconButton(
            onClick = onStop,
            enabled = hasDisplayedEnclosure && !previewingInactiveItem,
        ) {
            Icon(
                Icons.Rounded.Stop,
                contentDescription = stringResource(R.string.player_stop),
                modifier = Modifier.size(28.dp),
            )
        }
    }
}

@Composable
private fun AndroidMediaArtwork(
    model: Any?,
    loading: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .clip(RoundedCornerShape(20.dp)),
        contentAlignment = Alignment.Center,
    ) {
        if (model != null) {
            AsyncImage(
                model = model,
                contentDescription = stringResource(R.string.player_artwork),
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Image(
                painter = painterResource(R.drawable.fallback_artwork),
                contentDescription = stringResource(R.string.player_fallback_artwork),
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
            )
        }
        if (loading) {
            CircularProgressIndicator()
        }
    }
}

@Composable
private fun AndroidMediaChapterSection(
    chapters: List<MediaChapter>,
    positionMs: Long,
    expanded: Boolean,
    onToggle: () -> Unit,
    onSelect: (Long) -> Unit,
) {
    val activeIndex = androidActiveChapterIndex(positionMs, chapters)
    val active = activeIndex?.let { chapters[it] }
    val summary = active?.title
        ?.takeIf { it.isNotBlank() }
        ?: activeIndex?.let { "Chapter " + (it + 1) }
        ?: chapters.size.toString() + " chapters"

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onToggle),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column {
            Row(
                modifier = Modifier.padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Rounded.List,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        if (activeIndex != null) {
                            stringResource(R.string.l10n_chapter_of, activeIndex + 1, chapters.size)
                        } else {
                            stringResource(R.string.l10n_chapters)
                        },
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        summary,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            if (expanded) {
                HorizontalDivider()
                chapters.forEachIndexed { index, chapter ->
                    val isActive = index == activeIndex
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(
                                color = if (isActive) {
                                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f)
                                } else {
                                    androidx.compose.ui.graphics.Color.Transparent
                                },
                                shape = RoundedCornerShape(10.dp),
                            )
                            .clickable { onSelect(chapter.startMs.toLong()) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                chapter.title.takeIf { it.isNotBlank() }
                                    ?: "Chapter " + (index + 1),
                                fontWeight = if (isActive) {
                                    FontWeight.SemiBold
                                } else {
                                    FontWeight.Normal
                                },
                                color = if (isActive) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                            )
                            Text(
                                androidPlayerTime(chapter.startMs.toLong()),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (isActive) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AndroidMediaShowNotesSection(
    expanded: Boolean,
    loading: Boolean,
    error: String?,
    document: ReaderDocument?,
    onToggle: () -> Unit,
    onRetry: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onToggle)
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Rounded.Article,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.l10n_show_notes),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        if (expanded) stringResource(R.string.l10n_tap_collapse) else stringResource(R.string.l10n_read_while_listening),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (expanded) {
                HorizontalDivider()
                when {
                    loading -> Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(28.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                    error != null -> Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            error,
                            color = MaterialTheme.colorScheme.error,
                            textAlign = TextAlign.Center,
                        )
                        OutlinedButton(onClick = onRetry) {
                            Text(stringResource(R.string.list_retry))
                        }
                    }
                    document != null -> AndroidReaderDocumentContent(
                        document = document,
                        onOpenOriginal = null,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 520.dp),
                    )
                }
            }
        }
    }
}

private fun androidActiveChapterIndex(
    positionMs: Long,
    chapters: List<MediaChapter>,
): Int? {
    if (chapters.isEmpty()) return null
    return chapters.indices.lastOrNull { index ->
        val chapter = chapters[index]
        val end = chapter.endMs?.toLong()
            ?: chapters.getOrNull(index + 1)?.startMs?.toLong()
        positionMs >= chapter.startMs.toLong() &&
            (end == null || positionMs < end)
    }
}

private fun androidPlaybackRateLabel(rate: Float): String =
    "%.2f".format(rate).trimEnd('0').trimEnd('.') + "×"

private fun androidPlayerTime(milliseconds: Long): String {
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
