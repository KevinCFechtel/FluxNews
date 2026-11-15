package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.PlaybackState
import uniffi.flux_uniffi.PlaybackStatus

class AndroidMediaPlaybackSyncPolicyTest {
    @Test
    fun onlyIdlePlaybackAdoptsRemoteSyncProgress() {
        assertFalse(
            AndroidMediaPlaybackSyncPolicy.shouldAdopt(
                AndroidMediaPlaybackPresentationStatus.Playing,
            ),
        )
        assertTrue(
            AndroidMediaPlaybackSyncPolicy.shouldAdopt(
                AndroidMediaPlaybackPresentationStatus.Paused,
            ),
        )
        assertTrue(
            AndroidMediaPlaybackSyncPolicy.shouldAdopt(
                AndroidMediaPlaybackPresentationStatus.Stopped,
            ),
        )
    }

    @Test
    fun completedPlaybackUsesKnownDurationAsTargetPosition() {
        assertEquals(
            90_000L,
            AndroidMediaPlaybackSyncPolicy.targetPositionMs(
                PlaybackState(
                    enclosureId = 42L,
                    positionMs = 81_000uL,
                    durationMs = 90_000uL,
                    status = PlaybackStatus.COMPLETED,
                    updatedAt = null,
                ),
            ),
        )
    }

    @Test
    fun inProgressPlaybackUsesCorePosition() {
        assertEquals(
            42_000L,
            AndroidMediaPlaybackSyncPolicy.targetPositionMs(
                PlaybackState(
                    enclosureId = 42L,
                    positionMs = 42_000uL,
                    durationMs = 90_000uL,
                    status = PlaybackStatus.IN_PROGRESS,
                    updatedAt = null,
                ),
            ),
        )
    }
}
