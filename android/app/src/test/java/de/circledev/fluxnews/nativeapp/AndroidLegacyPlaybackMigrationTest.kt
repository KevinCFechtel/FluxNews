package de.circledev.fluxnews.nativeapp

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidLegacyPlaybackMigrationTest {
    @Test
    fun confirmedRemoteMissWithoutLegacyDownloadIsDiscardable() {
        val downloads = AndroidLegacyPlaybackMigration.downloadedArticleIdsOrNull(
            LegacyAndroidDownloadReadResult.Found(emptyList()),
        )

        assertEquals(emptySet<Long>(), downloads)
        assertTrue(AndroidLegacyPlaybackMigration.shouldDiscardRemoteMiss(53L, downloads))
        assertEquals(
            "1 old playback position discarded: no local download and no longer available on the server.",
            AndroidLegacyPlaybackMigration.discardedDescription(1),
        )
    }

    @Test
    fun confirmedRemoteMissWithLegacyDownloadRemainsRetryable() {
        val downloads = AndroidLegacyPlaybackMigration.downloadedArticleIdsOrNull(
            LegacyAndroidDownloadReadResult.Found(
                listOf(
                    LegacyAndroidDownloadImport(
                        enclosureId = 5300L,
                        sourceFile = File("/legacy/audio_5300_1.mp3"),
                        articleId = 53L,
                    ),
                ),
            ),
        )

        assertEquals(setOf(53L), downloads)
        assertFalse(AndroidLegacyPlaybackMigration.shouldDiscardRemoteMiss(53L, downloads))
    }

    @Test
    fun incompleteLegacyDownloadEvidenceNeverAllowsAutomaticDiscard() {
        assertNull(
            AndroidLegacyPlaybackMigration.downloadedArticleIdsOrNull(
                LegacyAndroidDownloadReadResult.Unavailable,
            ),
        )
        val unresolved = AndroidLegacyPlaybackMigration.downloadedArticleIdsOrNull(
            LegacyAndroidDownloadReadResult.Found(
                listOf(
                    LegacyAndroidDownloadImport(
                        enclosureId = 99L,
                        sourceFile = File("/legacy/audio_99_1.mp3"),
                        articleId = null,
                    ),
                ),
            ),
        )
        assertNull(unresolved)
        assertFalse(AndroidLegacyPlaybackMigration.shouldDiscardRemoteMiss(53L, unresolved))
    }

    @Test
    fun discardedArticleIdsAreDurableAndCanonical() {
        val encoded = AndroidLegacyPlaybackMigration.encodeDiscardedArticleIds(
            setOf(53L, 10L, 53L),
        )
        assertEquals("10,53", encoded)
        assertEquals(
            setOf(10L, 53L),
            AndroidLegacyPlaybackMigration.parseDiscardedArticleIds(encoded),
        )
    }

    @Test
    fun v2ReopensOnlyPlaybackThatWasPreviouslyManuallySkipped() {
        assertTrue(
            AndroidLegacyPlaybackMigration.shouldReopenManualPlaybackSkip(
                playbackDone = true,
                verificationV2Done = false,
                completionKind = "completed_with_skipped_items",
                skippedPlaybackDetails = "53 missing article(s)",
            ),
        )
        assertFalse(
            AndroidLegacyPlaybackMigration.shouldReopenManualPlaybackSkip(
                playbackDone = true,
                verificationV2Done = false,
                completionKind = "completed",
                skippedPlaybackDetails = "",
            ),
        )
        assertFalse(
            AndroidLegacyPlaybackMigration.shouldReopenManualPlaybackSkip(
                playbackDone = true,
                verificationV2Done = false,
                completionKind = "completed_with_skipped_items",
                skippedPlaybackDetails = "",
            ),
        )
        assertFalse(
            AndroidLegacyPlaybackMigration.shouldReopenManualPlaybackSkip(
                playbackDone = true,
                verificationV2Done = true,
                completionKind = "completed_with_skipped_items",
                skippedPlaybackDetails = "53 missing article(s)",
            ),
        )
    }

}
