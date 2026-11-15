package de.circledev.fluxnews.nativeapp

import uniffi.flux_uniffi.ListeningListItem
import uniffi.flux_uniffi.PlaybackStatus

// "Not started" means never played, not necessarily newly published or added.
internal fun isUnplayedListeningListItem(item: ListeningListItem): Boolean =
    item.audioEnclosures.isNotEmpty() && item.audioEnclosures.all { audio ->
        val playback = audio.playbackState
        audio.enclosure.remoteMediaProgressionSeconds == 0uL &&
            (playback == null ||
                (playback.status == PlaybackStatus.NOT_STARTED &&
                    playback.positionMs == 0uL))
    }

