package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaConstants
import java.util.concurrent.atomic.AtomicLong
import uniffi.flux_uniffi.ListeningListEnclosure
import uniffi.flux_uniffi.ListeningListFeed
import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.ListeningListSort
import uniffi.flux_uniffi.PlaybackStatus

internal enum class AndroidAutoPlaybackCompletion {
    NotStarted,
    PartiallyPlayed,
    FullyPlayed,
}

internal data class AndroidAutoPlaybackProgress(
    val completion: AndroidAutoPlaybackCompletion,
    val percentage: Double? = null,
)

/**
 * Android Auto / system-media browse projection over the Core-owned Listening List.
 *
 * The automotive root is the Listening List itself: its direct children are playable episodes.
 * Feeds are retained only as filter metadata for the later E7 filter interaction and never become
 * browse nodes.
 */
internal object AndroidAutoMediaLibraryProjection {
    const val ROOT_MEDIA_ID = "flux:listening-list"
    const val FILTER_ROOT_MEDIA_ID = "flux:listening-list:filter"
    const val FILTER_ALL_MEDIA_ID = "flux:listening-list:filter:all"
    const val FILTER_COMMAND_ACTION = "flux:auto:filter-by-feed"
    private const val FILTER_FEED_PREFIX = "flux:listening-list:filter:feed:"

    @OptIn(UnstableApi::class)
    fun rootItem(
        supportsFeedFilter: Boolean = false,
        context: Context? = null,
    ): MediaItem =
        MediaItem.Builder()
            .setMediaId(ROOT_MEDIA_ID)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(context?.getString(R.string.nav_listening_list) ?: "Listening List")
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_NEWS)
                    .apply {
                        if (supportsFeedFilter) {
                            setSupportedCommands(listOf(FILTER_COMMAND_ACTION))
                        }
                    }
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .build(),
            )
            .build()

    fun filterRootItem(context: Context? = null): MediaItem =
        MediaItem.Builder()
            .setMediaId(FILTER_ROOT_MEDIA_ID)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(context?.getString(R.string.auto_filter_by_feed) ?: "Filter by Feed")
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_NEWS)
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .build(),
            )
            .build()

    fun filterItems(snapshot: AndroidAutoMediaLibrarySnapshot, context: Context? = null): List<MediaItem> =
        buildList {
            add(
                filterChoiceItem(
                    mediaId = FILTER_ALL_MEDIA_ID,
                    title = context?.getString(R.string.list_all_feeds) ?: "All Feeds",
                    selected = snapshot.selectedFeedId == null,
                    count = snapshot.feeds.sumOf { it.itemCount },
                    context = context,
                ),
            )
            snapshot.feeds.forEach { feed ->
                add(
                    filterChoiceItem(
                        mediaId = FILTER_FEED_PREFIX + feed.feedId,
                        title = feed.feedTitle.ifBlank { context?.getString(R.string.auto_unknown_feed) ?: "Unknown Feed" },
                        selected = snapshot.selectedFeedId == feed.feedId,
                        count = feed.itemCount,
                        context = context,
                    ),
                )
            }
        }

    fun filterFeedId(mediaId: String): Long? = when {
        mediaId == FILTER_ALL_MEDIA_ID -> null
        mediaId.startsWith(FILTER_FEED_PREFIX) ->
            mediaId.removePrefix(FILTER_FEED_PREFIX).toLongOrNull()?.takeIf { it > 0L }
        else -> null
    }

    fun isFilterChoice(mediaId: String): Boolean =
        mediaId == FILTER_ALL_MEDIA_ID || mediaId.startsWith(FILTER_FEED_PREFIX)

    fun filterChoiceItem(
        snapshot: AndroidAutoMediaLibrarySnapshot,
        mediaId: String,
        context: Context? = null,
    ): MediaItem? =
        filterItems(snapshot, context).firstOrNull { it.mediaId == mediaId }

    private fun filterChoiceItem(
        mediaId: String,
        title: String,
        selected: Boolean,
        count: ULong,
        context: Context? = null,
    ): MediaItem =
        MediaItem.Builder()
            .setMediaId(mediaId)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(if (selected) "✓ $title" else title)
                    .setSubtitle(
                        context?.resources?.getQuantityString(R.plurals.auto_item_count, count.coerceAtMost(Int.MAX_VALUE.toULong()).toInt(), count.coerceAtMost(Int.MAX_VALUE.toULong()).toInt()) ?: if (count == 1uL) "1 item" else "$count items",
                    )
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_NEWS)
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .build(),
            )
            .build()

    fun selectedEnclosure(item: ListeningListItem): ListeningListEnclosure? =
        item.activeEnclosureId
            ?.let { activeId ->
                item.audioEnclosures.firstOrNull { it.enclosure.id == activeId }
            }
            ?: item.audioEnclosures.firstOrNull()

    fun matchesSearch(item: MediaItem, query: String): Boolean {
        val normalized = query.trim()
        if (normalized.isEmpty()) return false
        return item.mediaMetadata.title
            ?.toString()
            ?.contains(normalized, ignoreCase = true) == true ||
            item.mediaMetadata.artist
                ?.toString()
                ?.contains(normalized, ignoreCase = true) == true
    }

    // Pure title projection: the regular JVM tests can validate car browse indicators
    // without instantiating Android's Bundle (used only by Media3 completion extras).
    internal fun automotiveBrowseTitle(
        item: ListeningListItem,
        selected: ListeningListEnclosure,
        originalTitle: String,
    ): String = when {
        selected.playbackState?.status == PlaybackStatus.COMPLETED -> "✓ $originalTitle"
        isUnplayedListeningListItem(item) -> "● $originalTitle"
        else -> originalTitle
    }

    @OptIn(UnstableApi::class)
    fun mediaItem(
        item: ListeningListItem,
        artworkUri: Uri? = null,
        includeAndroidAutoProgressExtras: Boolean = false,
        context: Context? = null,
    ): MediaItem? {
        val selected = selectedEnclosure(item) ?: return null
        val originalTitle = item.title.ifBlank { context?.getString(R.string.auto_untitled_news) ?: "Untitled News" }
        // Car hosts may ignore the supported completion-status extras. Keep a small,
        // visible mark in the browse title without changing canonical enclosure IDs.
        val browseTitle = if (includeAndroidAutoProgressExtras) {
            automotiveBrowseTitle(item, selected, originalTitle)
        } else {
            originalTitle
        }
        val metadata = MediaMetadata.Builder()
            .setTitle(browseTitle)
            .setArtist(item.feedTitle.ifBlank { context?.getString(R.string.auto_unknown_feed) ?: "Unknown Feed" })
            .setAlbumTitle(item.feedTitle.ifBlank { context?.getString(R.string.auto_unknown_feed) ?: "Unknown Feed" })
            .setMediaType(MediaMetadata.MEDIA_TYPE_NEWS)
            .setArtworkUri(artworkUri)
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .apply {
                if (includeAndroidAutoProgressExtras) {
                    setExtras(playbackProgressExtras(selected))
                }
            }
            .build()

        return MediaItem.Builder()
            // Keep the canonical enclosure ID as Media3 identity. E6 checkpointing already reads
            // this ID from the player, and later E7 playback dispatch can therefore reuse it.
            .setMediaId(selected.enclosure.id.toString())
            .setMediaMetadata(metadata)
            .build()
    }

    fun playbackProgress(
        selected: ListeningListEnclosure,
    ): AndroidAutoPlaybackProgress {
        val playback = selected.playbackState
            ?: return AndroidAutoPlaybackProgress(
                completion = AndroidAutoPlaybackCompletion.NotStarted,
                percentage = 0.0,
            )

        return when (playback.status) {
            PlaybackStatus.NOT_STARTED ->
                AndroidAutoPlaybackProgress(
                    completion = AndroidAutoPlaybackCompletion.NotStarted,
                    percentage = 0.0,
                )
            PlaybackStatus.COMPLETED ->
                AndroidAutoPlaybackProgress(
                    completion = AndroidAutoPlaybackCompletion.FullyPlayed,
                    percentage = 1.0,
                )
            PlaybackStatus.IN_PROGRESS -> {
                val durationMs = playback.durationMs ?: selected.durationMs
                val percentage = durationMs
                    ?.takeIf { it > 0uL }
                    ?.let { duration ->
                        playback.positionMs.toDouble()
                            .div(duration.toDouble())
                            .coerceIn(0.0, 1.0)
                    }
                AndroidAutoPlaybackProgress(
                    completion = AndroidAutoPlaybackCompletion.PartiallyPlayed,
                    percentage = percentage,
                )
            }
        }
    }

    @OptIn(UnstableApi::class)
    private fun playbackProgressExtras(
        selected: ListeningListEnclosure,
    ): Bundle {
        val progress = playbackProgress(selected)
        val status = when (progress.completion) {
            AndroidAutoPlaybackCompletion.NotStarted ->
                MediaConstants.EXTRAS_VALUE_COMPLETION_STATUS_NOT_PLAYED
            AndroidAutoPlaybackCompletion.PartiallyPlayed ->
                MediaConstants.EXTRAS_VALUE_COMPLETION_STATUS_PARTIALLY_PLAYED
            AndroidAutoPlaybackCompletion.FullyPlayed ->
                MediaConstants.EXTRAS_VALUE_COMPLETION_STATUS_FULLY_PLAYED
        }

        return Bundle().apply {
            putInt(MediaConstants.EXTRAS_KEY_COMPLETION_STATUS, status)
            progress.percentage?.let { percentage ->
                putDouble(MediaConstants.EXTRAS_KEY_COMPLETION_PERCENTAGE, percentage)
            }
        }
    }
}

internal object AndroidAutoMediaRequestPolicy {
    fun resolve(
        snapshot: AndroidAutoMediaLibrarySnapshot,
        mediaId: String,
        searchQuery: String?,
    ): MediaItem? =
        mediaId.toLongOrNull()
            ?.takeIf { it > 0L }
            ?.let { snapshot.itemsByMediaId[it.toString()] }
            ?: searchQuery
                ?.trim()
                ?.takeIf(String::isNotEmpty)
                ?.let { query ->
                    snapshot.items.firstOrNull { item ->
                        AndroidAutoMediaLibraryProjection.matchesSearch(item, query)
                    }
                }
}

internal data class AndroidAutoMediaLibrarySnapshot(
    val sessionGeneration: Long? = null,
    val selectedFeedId: Long? = null,
    val items: List<MediaItem> = emptyList(),
    val itemsByMediaId: Map<String, MediaItem> = emptyMap(),
    val feeds: List<ListeningListFeed> = emptyList(),
)

/**
 * Small process-runtime projection for MediaLibrarySession callbacks.
 *
 * MediaLibrary callbacks are deliberately served from an already prepared in-memory snapshot.
 * Synchronous UniFFI/Core reads stay on AndroidCoreRuntime's local dispatcher rather than running
 * on the Media3/application thread. The snapshot is disposable and can always be rebuilt from
 * Core after process death.
 */
internal class AndroidAutoMediaLibraryStore(
    context: Context,
    private val coreRuntime: AndroidCoreRuntime,
    private val diagnostics: AndroidAppDiagnostics,
) {
    private val applicationContext = context.applicationContext
    @Volatile
    private var currentSnapshot = AndroidAutoMediaLibrarySnapshot()
    private val nextRefreshGeneration = AtomicLong(0L)

    fun snapshot(): AndroidAutoMediaLibrarySnapshot = currentSnapshot

    fun clear() {
        nextRefreshGeneration.incrementAndGet()
        currentSnapshot = AndroidAutoMediaLibrarySnapshot()
    }

    suspend fun refresh(
        generation: Long,
        feedId: Long? = null,
    ): AndroidAutoMediaLibrarySnapshot {
        val refreshGeneration = nextRefreshGeneration.incrementAndGet()
        val projected = runCatching {
            coreRuntime.localForGeneration(generation) { core ->
                val feeds = core.listeningListFeeds()
                val validFeedId = feedId?.takeIf { candidate ->
                    feeds.any { it.feedId == candidate }
                }
                val items = core.listeningList(
                    feedId = validFeedId,
                    sort = ListeningListSort.RECENTLY_ADDED,
                )
                val mediaItems = items.mapNotNull { item ->
                    val selected = AndroidAutoMediaLibraryProjection.selectedEnclosure(item)
                        ?: return@mapNotNull null
                    AndroidAutoMediaLibraryProjection.mediaItem(
                        item = item,
                        artworkUri = AndroidAutoArtworkProvider.uri(
                            applicationContext,
                            selected.enclosure.id,
                        ),
                        includeAndroidAutoProgressExtras = true,
                        context = applicationContext,
                    )
                }
                AndroidAutoMediaLibrarySnapshot(
                    sessionGeneration = generation,
                    selectedFeedId = validFeedId,
                    items = mediaItems,
                    itemsByMediaId = mediaItems.associateBy(MediaItem::mediaId),
                    feeds = feeds,
                )
            }
        }.getOrElse { failure ->
            if (
                coreRuntime.activeSessionGeneration() == generation &&
                nextRefreshGeneration.get() == refreshGeneration
            ) {
                diagnostics.record(
                    AndroidAppLogLevel.Warning,
                    "android-auto",
                    "Listening List projection failed: ${failure.javaClass.simpleName}",
                )
            }
            return snapshot()
        }

        if (
            coreRuntime.activeSessionGeneration() != generation ||
            nextRefreshGeneration.get() != refreshGeneration
        ) {
            return snapshot()
        }

        currentSnapshot = projected
        return projected
    }
}
