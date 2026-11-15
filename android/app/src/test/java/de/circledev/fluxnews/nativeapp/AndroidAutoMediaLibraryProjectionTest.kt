package de.circledev.fluxnews.nativeapp

import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.Enclosure
import uniffi.flux_uniffi.ListeningListEnclosure
import uniffi.flux_uniffi.ListeningListFeed
import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.MediaKind
import uniffi.flux_uniffi.PlaybackState
import uniffi.flux_uniffi.PlaybackStatus

class AndroidAutoMediaLibraryProjectionTest {
    @Test
    fun rootRepresentsListeningListAndIsNotPlayable() {
        val root = AndroidAutoMediaLibraryProjection.rootItem()

        assertEquals(AndroidAutoMediaLibraryProjection.ROOT_MEDIA_ID, root.mediaId)
        assertEquals("Listening List", root.mediaMetadata.title?.toString())
        assertTrue(root.mediaMetadata.isBrowsable == true)
        assertFalse(root.mediaMetadata.isPlayable == true)
        assertTrue(root.mediaMetadata.supportedCommands.isEmpty())
    }

    @Test
    fun rootExposesFeedFilterOnlyWhenHostSupportsBrowseActions() {
        val root = AndroidAutoMediaLibraryProjection.rootItem(supportsFeedFilter = true)

        assertEquals(
            listOf(AndroidAutoMediaLibraryProjection.FILTER_COMMAND_ACTION),
            root.mediaMetadata.supportedCommands,
        )
    }

    @Test
    fun directRootChildUsesActiveEnclosureAsCanonicalMediaIdentity() {
        val item = item(
            activeEnclosureId = 22L,
            enclosureIds = listOf(11L, 22L),
        )

        val projected = AndroidAutoMediaLibraryProjection.mediaItem(item)

        assertNotNull(projected)
        assertEquals("22", projected?.mediaId)
        assertEquals("Episode", projected?.mediaMetadata?.title?.toString())
        assertEquals("Feed", projected?.mediaMetadata?.artist?.toString())
        assertTrue(projected?.mediaMetadata?.isPlayable == true)
        assertFalse(projected?.mediaMetadata?.isBrowsable == true)
    }

    @Test
    fun automotiveBrowseTitlesShowVisibleUnplayedAndCompletedMarkers() {
        // Android Auto's completion extras use android.os.Bundle, which requires
        // Android runtime or Robolectric. Test the same pure browse-title policy
        // that mediaItem() calls, without constructing Bundle in a JVM unit test.
        fun browseTitle(item: ListeningListItem): String {
            val selected = requireNotNull(AndroidAutoMediaLibraryProjection.selectedEnclosure(item))
            return AndroidAutoMediaLibraryProjection.automotiveBrowseTitle(item, selected, "Episode")
        }

        val newItem = item(activeEnclosureId = 61L, enclosureIds = listOf(61L))
        assertEquals("● Episode", browseTitle(newItem))

        // Normal media metadata retains the original title and canonical enclosure ID.
        val regular = requireNotNull(AndroidAutoMediaLibraryProjection.mediaItem(newItem))
        assertEquals("Episode", regular.mediaMetadata.title?.toString())
        assertEquals("61", regular.mediaId)

        val completedItem = item(
            activeEnclosureId = 61L,
            enclosureIds = listOf(61L),
            playbackState = PlaybackState(
                enclosureId = 61L,
                positionMs = 60_000uL,
                durationMs = 60_000uL,
                status = PlaybackStatus.COMPLETED,
                updatedAt = null,
            ),
        )
        assertEquals("✓ Episode", browseTitle(completedItem))

        val partiallyPlayedItem = item(
            activeEnclosureId = 61L,
            enclosureIds = listOf(61L),
            playbackState = PlaybackState(
                enclosureId = 61L,
                positionMs = 10_000uL,
                durationMs = 60_000uL,
                status = PlaybackStatus.IN_PROGRESS,
                updatedAt = null,
            ),
        )
        assertEquals("Episode", browseTitle(partiallyPlayedItem))

        // A multi-audio item is not "unplayed" after any enclosure has progressed.
        val mixed = item(
            activeEnclosureId = 62L,
            enclosureIds = listOf(61L, 62L),
            playbackState = PlaybackState(
                enclosureId = 61L,
                positionMs = 10_000uL,
                durationMs = 60_000uL,
                status = PlaybackStatus.IN_PROGRESS,
                updatedAt = null,
            ),
        )
        assertEquals("Episode", browseTitle(mixed))
    }

    @Test
    fun firstEnclosureIsDeterministicFallbackWhenNoActiveEnclosureExists() {
        val item = item(
            activeEnclosureId = null,
            enclosureIds = listOf(31L, 32L),
        )

        assertEquals(
            31L,
            AndroidAutoMediaLibraryProjection.selectedEnclosure(item)?.enclosure?.id,
        )
    }

    @Test
    fun searchMatchesEpisodeTitleAndFeedWithoutCreatingBrowseBranches() {
        val projected = AndroidAutoMediaLibraryProjection.mediaItem(
            item(activeEnclosureId = 22L, enclosureIds = listOf(22L)),
        )
        requireNotNull(projected)

        assertTrue(AndroidAutoMediaLibraryProjection.matchesSearch(projected, "episode"))
        assertTrue(AndroidAutoMediaLibraryProjection.matchesSearch(projected, "feed"))
        assertFalse(AndroidAutoMediaLibraryProjection.matchesSearch(projected, "other"))
        assertFalse(AndroidAutoMediaLibraryProjection.matchesSearch(projected, "   "))
    }

    @Test
    fun requestPolicyPrefersCanonicalMediaIdOverSearchQuery() {
        val first = requireNotNull(
            AndroidAutoMediaLibraryProjection.mediaItem(
                item(activeEnclosureId = 11L, enclosureIds = listOf(11L)),
            ),
        )
        val second = MediaItem.Builder()
            .setMediaId("22")
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle("Other Episode")
                    .setArtist("Other Feed")
                    .setIsPlayable(true)
                    .build(),
            )
            .build()
        val snapshot = AndroidAutoMediaLibrarySnapshot(
            items = listOf(first, second),
            itemsByMediaId = mapOf(first.mediaId to first, second.mediaId to second),
        )

        assertEquals(
            "22",
            AndroidAutoMediaRequestPolicy.resolve(
                snapshot = snapshot,
                mediaId = "22",
                searchQuery = "Episode",
            )?.mediaId,
        )
    }

    @Test
    fun requestPolicyResolvesVoiceSearchInVisibleListeningListOrder() {
        val first = requireNotNull(
            AndroidAutoMediaLibraryProjection.mediaItem(
                item(activeEnclosureId = 31L, enclosureIds = listOf(31L)),
            ),
        )
        val second = first.buildUpon()
            .setMediaId("32")
            .setMediaMetadata(
                first.mediaMetadata.buildUpon()
                    .setTitle("Episode Two")
                    .build(),
            )
            .build()
        val snapshot = AndroidAutoMediaLibrarySnapshot(
            items = listOf(first, second),
            itemsByMediaId = mapOf(first.mediaId to first, second.mediaId to second),
        )

        assertEquals(
            first.mediaId,
            AndroidAutoMediaRequestPolicy.resolve(
                snapshot = snapshot,
                mediaId = "",
                searchQuery = "episode",
            )?.mediaId,
        )
    }

    @Test
    fun feedFilterChoicesStayOutsideTheEpisodeRoot() {
        val episode = requireNotNull(
            AndroidAutoMediaLibraryProjection.mediaItem(
                item(activeEnclosureId = 41L, enclosureIds = listOf(41L)),
            ),
        )
        val snapshot = AndroidAutoMediaLibrarySnapshot(
            selectedFeedId = 9L,
            items = listOf(episode),
            itemsByMediaId = mapOf(episode.mediaId to episode),
            feeds = listOf(
                ListeningListFeed(feedId = 9L, feedTitle = "Feed", itemCount = 3uL),
                ListeningListFeed(feedId = 10L, feedTitle = "Other Feed", itemCount = 2uL),
            ),
        )

        assertEquals(listOf(episode), snapshot.items)

        val filterItems = AndroidAutoMediaLibraryProjection.filterItems(snapshot)
        assertEquals(3, filterItems.size)
        assertEquals(
            AndroidAutoMediaLibraryProjection.FILTER_ALL_MEDIA_ID,
            filterItems.first().mediaId,
        )
        assertTrue(filterItems[1].mediaMetadata.title.toString().startsWith("✓ "))
        assertEquals(9L, AndroidAutoMediaLibraryProjection.filterFeedId(filterItems[1].mediaId))
        assertEquals(null, AndroidAutoMediaLibraryProjection.filterFeedId(filterItems.first().mediaId))
    }

    @Test
    fun partiallyPlayedItemPublishesCompletionPercentage() {
        val selected = requireNotNull(
            AndroidAutoMediaLibraryProjection.selectedEnclosure(
                item(
                    activeEnclosureId = 51L,
                    enclosureIds = listOf(51L),
                    playbackState = PlaybackState(
                        enclosureId = 51L,
                        positionMs = 30_000uL,
                        durationMs = 120_000uL,
                        status = PlaybackStatus.IN_PROGRESS,
                        updatedAt = null,
                    ),
                ),
            ),
        )

        val progress = AndroidAutoMediaLibraryProjection.playbackProgress(selected)
        assertEquals(AndroidAutoPlaybackCompletion.PartiallyPlayed, progress.completion)
        assertEquals(0.25, progress.percentage ?: error("Missing progress percentage"), 0.0001)
    }

    @Test
    fun completedItemPublishesFullyPlayedStatus() {
        val selected = requireNotNull(
            AndroidAutoMediaLibraryProjection.selectedEnclosure(
                item(
                    activeEnclosureId = 52L,
                    enclosureIds = listOf(52L),
                    playbackState = PlaybackState(
                        enclosureId = 52L,
                        positionMs = 120_000uL,
                        durationMs = 120_000uL,
                        status = PlaybackStatus.COMPLETED,
                        updatedAt = null,
                    ),
                ),
            ),
        )

        val progress = AndroidAutoMediaLibraryProjection.playbackProgress(selected)
        assertEquals(AndroidAutoPlaybackCompletion.FullyPlayed, progress.completion)
        assertEquals(1.0, progress.percentage ?: error("Missing completion percentage"), 0.0001)
    }

    @Test
    fun notStartedItemPublishesZeroCompletionPercentage() {
        val selected = requireNotNull(
            AndroidAutoMediaLibraryProjection.selectedEnclosure(
                item(
                    activeEnclosureId = 53L,
                    enclosureIds = listOf(53L),
                ),
            ),
        )

        val progress = AndroidAutoMediaLibraryProjection.playbackProgress(selected)
        assertEquals(AndroidAutoPlaybackCompletion.NotStarted, progress.completion)
        assertEquals(0.0, progress.percentage ?: error("Missing initial percentage"), 0.0001)
    }

    @Test
    fun itemWithoutAudioDoesNotCreateAutomotiveBrowseEntry() {
        val item = item(activeEnclosureId = null, enclosureIds = emptyList())

        assertEquals(null, AndroidAutoMediaLibraryProjection.mediaItem(item))
    }

    private fun item(
        activeEnclosureId: Long?,
        enclosureIds: List<Long>,
        playbackState: PlaybackState? = null,
    ) = ListeningListItem(
        articleId = 7L,
        feedId = 9L,
        title = "Episode",
        feedTitle = "Feed",
        publishedAt = "2026-10-07T10:00:00Z",
        addedAt = "2026-10-07T11:00:00Z",
        remotePresent = true,
        audioEnclosures = enclosureIds.map { id ->
            ListeningListEnclosure(
                enclosure = Enclosure(
                    id = id,
                    articleId = 7L,
                    url = "https://media.example/episode-$id.mp3",
                    mimeType = "audio/mpeg",
                    sizeBytes = null,
                    remoteMediaProgressionSeconds = 0uL,
                    mediaKind = MediaKind.AUDIO,
                ),
                remotePresent = true,
                playbackState = playbackState?.takeIf { it.enclosureId == id },
                download = null,
                durationMs = null,
            )
        },
        activeEnclosureId = activeEnclosureId,
    )
}
