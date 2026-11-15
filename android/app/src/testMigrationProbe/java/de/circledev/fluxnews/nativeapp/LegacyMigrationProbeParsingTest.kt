package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LegacyMigrationProbeParsingTest {
    @Test
    fun recognizesLegacyPlaybackAndDownloadIdentifiers() {
        assertTrue(LegacyKeyParsing.isPlaybackKey("audio_progress_42"))
        assertFalse(LegacyKeyParsing.isPlaybackKey("audio_progress_invalid"))
        assertEquals(42L, LegacyKeyParsing.attachmentIdFromAudioFile("audio_42_123.mp3"))
        assertEquals(42L, LegacyKeyParsing.downloadMetadataAttachmentId("audio_download_path_42"))
        assertEquals(null, LegacyKeyParsing.downloadMetadataAttachmentId("audio_download_path_url_YQ"))
    }

    @Test
    fun pairsOnlyCompleteCustomHeaderValues() {
        val headers = legacyCustomHeaders(
            mapOf(
                "customHeadersKey_0" to "Authorization",
                "customHeadersValue_0" to "secret",
                "customHeadersKey_1" to "Incomplete",
            ),
        )
        assertEquals(1, headers.size)
        assertEquals("Authorization", headers.getValue(0).first)
    }
}
