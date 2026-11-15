package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LegacyAndroidImportParsingTest {
    @Test
    fun accountRequiresBothCredentialFields() {
        assertNull(LegacyAndroidImportParsing.account(mapOf("minifluxURL" to "https://example.test")))
        assertNull(LegacyAndroidImportParsing.account(mapOf("minifluxAPIKey" to "secret")))
        assertNull(
            LegacyAndroidImportParsing.account(
                mapOf("minifluxURL" to "  ", "minifluxAPIKey" to "secret"),
            ),
        )
    }

    @Test
    fun accountTrimsCredentialsAndImportsOnlyCompleteHeadersInIndexOrder() {
        val parsed = LegacyAndroidImportParsing.account(
            mapOf(
                "minifluxURL" to " https://example.test/ ",
                "minifluxAPIKey" to " secret ",
                "customHeadersKey_2" to " X-Second ",
                "customHeadersValue_2" to "two",
                "customHeadersKey_0" to "X-First",
                "customHeadersValue_0" to "one",
                "customHeadersKey_1" to "X-Incomplete",
            ),
        )

        requireNotNull(parsed)
        assertEquals("https://example.test/", parsed.serverUrl)
        assertEquals("secret", parsed.apiKey)
        assertEquals(
            listOf(
                LegacyAndroidHeaderImport("X-First", "one"),
                LegacyAndroidHeaderImport("X-Second", "two"),
            ),
            parsed.customHeaders,
        )
    }
    @Test
    fun settingsPreserveExplicitFalseAndOnlyPositiveFeedOverride() {
        val settings = LegacyAndroidImportParsing.settings(
            mapOf(
                "backgroundSyncIntervalMinutes" to "0",
                "autoDownloadAudioAfterSync" to "false",
                "downloadAudioOnlyOnWifi" to "true",
                "audioDownloadRetentionDays" to "30",
                "feedSettingsOverrides" to """{"42":{"openMinifluxEntry":1},"43":{"openMinifluxEntry":0},"44":{"openMinifluxEntry":true}}""",
            ),
        )
        assertEquals(false, settings.backgroundSyncEnabled)
        assertEquals(false, settings.autoDownloadListeningList)
        assertEquals(true, settings.unmeteredDownloadsOnly)
        assertEquals(30, settings.retentionDays)
        assertEquals(listOf(42L), settings.openInMinifluxFeedIds)
    }

    @Test
    fun sharedPlaybackWinsAndZeroDoesNotBecomeResumableProgress() {
        val parsed = LegacyAndroidImportParsing.playback(
            sharedPreferences = mapOf(
                "audio_progress_20" to "1500",
                "audio_progress_21" to "0",
                "audio_progress_bad" to "100",
            ),
            legacySecure = mapOf(
                "audio_progress_20" to "800",
                "audio_progress_22" to "2000",
                "audio_progress_21" to "3000",
            ),
        )
        assertEquals(
            listOf(
                LegacyAndroidPlaybackProgressImport(20L, 1500uL),
                LegacyAndroidPlaybackProgressImport(22L, 2000uL),
            ),
            parsed,
        )
    }
    @Test
    fun downloadDiscoveryRequiresVerifiedLegacyFileAndEnclosureIdentity() {
        val root = kotlin.io.path.createTempDirectory("legacy-audio-test").toFile()
        try {
            val valid = java.io.File(root, "audio_42.mp3").apply { writeText("media") }
            java.io.File(root, "audio_43.mp3").apply { writeText("other") }
            val imports = LegacyAndroidImportParsing.downloads(
                secure = mapOf(
                    "audio_download_path_42" to valid.absolutePath,
                    "audio_download_path_43" to java.io.File(root, "audio_43.mp3").absolutePath,
                    "audio_download_path_url_https://example.test/media" to valid.absolutePath,
                ),
                audioRoot = root,
                knownLegacyEnclosureIds = setOf(42L),
            )
            assertEquals(listOf(LegacyAndroidDownloadImport(42L, valid.canonicalFile)), imports)
        } finally {
            root.deleteRecursively()
        }
    }
    @Test
    fun downloadDiscoveryRetainsReadOnlyArticleAssociation() {
        val root = kotlin.io.path.createTempDirectory("legacy-audio-mapping").toFile()
        try {
            val file = java.io.File(root, "audio_99.mp3").apply { writeText("media") }
            val imports = LegacyAndroidImportParsing.downloads(
                secure = mapOf("audio_download_path_99" to file.absolutePath),
                audioRoot = root,
                knownLegacyEnclosureIds = setOf(99L),
                articleIdsByEnclosureId = mapOf(99L to 42L),
            )
            assertEquals(listOf(LegacyAndroidDownloadImport(99L, file.canonicalFile, 42L)), imports)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun downloadDiscoveryFallsBackToValidatedAudioCacheFileWhenStoredPathIsMissing() {
        val root = kotlin.io.path.createTempDirectory("legacy-audio-cache-fallback").toFile()
        try {
            val cached = java.io.File(root, "audio_77_1790000000.mp3").apply {
                writeText("cached-media")
            }
            val imports = LegacyAndroidImportParsing.downloads(
                secure = emptyMap(),
                audioRoot = root,
                knownLegacyEnclosureIds = setOf(77L),
                articleIdsByEnclosureId = mapOf(77L to 700L),
            )

            assertEquals(
                listOf(LegacyAndroidDownloadImport(77L, cached.canonicalFile, 700L)),
                imports,
            )
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun localAndWidgetSettingsOnlyMapSupportedValues() {
        val parsed = LegacyAndroidImportParsing.settings(
            mapOf(
                "markAsReadOnScrollOver" to "false",
                "removeNewsFromListWhenRead" to "true",
                "startupCategorie" to "3",
                "startupFeedSelection" to "77",
                "androidFloatingToolbarActions" to """["settings","search","podcasts"]""",
                "androidFloatingToolbarActionOrder" to """["search","settings","podcasts"]""",
                "widgetNewsStatus" to "bookmarked",
                "widgetSortOrder" to "Oldest first",
            ),
        )
        assertEquals(false, parsed.local.markReadOnScrollover)
        assertEquals(true, parsed.local.removeWhenRead)
        assertEquals(3, parsed.local.startupMode)
        assertEquals(77L, parsed.local.startupFeedId)
        assertEquals(listOf("search", "settings", "listeningList"), parsed.local.actionBar)
        assertEquals("bookmarks", parsed.widget?.scope)
        assertEquals(false, parsed.widget?.unreadOnly)
        assertEquals(true, parsed.widget?.oldestFirst)
    }
}
