package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.Enclosure
import uniffi.flux_uniffi.ListeningListEnclosure
import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.MediaKind
import uniffi.flux_uniffi.PlaybackState
import uniffi.flux_uniffi.PlaybackStatus

class AndroidListeningListStatusTest {
    @Test
    fun unplayedOnlyWhenAllAudioHasNeverStarted() {
        val unplayed = audio(1L, null)
        val started = audio(2L, PlaybackStatus.IN_PROGRESS)
        val completed = audio(3L, PlaybackStatus.COMPLETED)

        assertTrue(isUnplayedListeningListItem(item(listOf(unplayed))))
        assertTrue(isUnplayedListeningListItem(item(listOf(unplayed, audio(4L, PlaybackStatus.NOT_STARTED)))))
        assertFalse(isUnplayedListeningListItem(item(listOf(unplayed, started))))
        assertFalse(isUnplayedListeningListItem(item(listOf(completed))))
        assertFalse(isUnplayedListeningListItem(item(emptyList())))
        assertFalse(isUnplayedListeningListItem(item(listOf(audio(5L, null, remoteSeconds = 20uL)))))
    }

    private fun audio(id: Long, status: PlaybackStatus?, remoteSeconds: ULong = 0uL) =
        ListeningListEnclosure(
            enclosure = Enclosure(
                id = id,
                articleId = 7L,
                url = "https://example.test/$id.mp3",
                mimeType = "audio/mpeg",
                sizeBytes = null,
                remoteMediaProgressionSeconds = remoteSeconds,
                mediaKind = MediaKind.AUDIO,
            ),
            remotePresent = true,
            playbackState = status?.let {
                PlaybackState(
                    enclosureId = id,
                    positionMs = if (it == PlaybackStatus.NOT_STARTED) 0uL else 1000uL,
                    durationMs = 60_000uL,
                    status = it,
                    updatedAt = null,
                )
            },
            download = null,
            durationMs = 60_000uL,
        )

    private fun item(audio: List<ListeningListEnclosure>) = ListeningListItem(
        articleId = 7L,
        feedId = 9L,
        title = "Episode",
        feedTitle = "Feed",
        publishedAt = "2026-10-07T10:00:00Z",
        addedAt = "2026-10-07T11:00:00Z",
        remotePresent = true,
        audioEnclosures = audio,
        activeEnclosureId = null,
    )
}
