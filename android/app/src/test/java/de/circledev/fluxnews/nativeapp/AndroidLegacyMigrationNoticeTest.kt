package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidLegacyMigrationNoticeTest {
    @Test
    fun freshInstallNeverShowsMigration() {
        assertFalse(AndroidLegacyMigrationNotice().appliesTo("https://example.test"))
    }

    @Test
    fun migratedAccountShowsPendingStepsWithoutSecrets() {
        val state = AndroidLegacyMigrationNotice(importedServer = "https://example.test")
        assertTrue(state.appliesTo("https://example.test"))
        assertFalse(state.appliesTo("https://another.example.test"))
        assertFalse(state.complete)
        assertEquals(1, state.completedSteps)
        assertEquals(6, state.steps.size)
        assertFalse(state.steps.first { it.title == "Downloads" }.complete)
    }

    @Test
    fun allStagesCompleteOnlyWhenEveryStageMarkerIsSet() {
        val complete = AndroidLegacyMigrationNotice(
            importedServer = "https://example.test",
            settingsComplete = true,
            localComplete = true,
            feedsComplete = true,
            startupComplete = true,
            playbackComplete = true,
            downloadsComplete = true,
            widgetsComplete = true,
        )
        assertTrue(complete.complete)
        assertEquals(6, complete.completedSteps)
        assertTrue(complete.appliesTo("https://example.test"))
        assertFalse(complete.copy(acknowledged = true).appliesTo("https://example.test"))
        assertFalse(complete.copy(feedsComplete = false).complete)
    }
    @Test
    fun pendingStepsShowSpecificRetryReasonsWithoutMarkingComplete() {
        val state = AndroidLegacyMigrationNotice(
            importedServer = "https://example.test",
            playbackStatus = "2 missing article(s)",
            downloadsStatus = "1 missing audio attachment(s)",
        )
        assertFalse(state.complete)
        assertEquals("2 missing article(s)", state.steps.first { it.title == "Playback progress" }.description)
        assertEquals("1 missing audio attachment(s)", state.steps.first { it.title == "Downloads" }.description)
    }
    @Test
    fun partialFinishRequiresCompletedSettingsAndMediaImportResults() {
        val base = AndroidLegacyMigrationNotice(
            importedServer = "https://example.test",
            settingsComplete = true,
            localComplete = true,
            feedsComplete = true,
            startupComplete = true,
            widgetsComplete = true,
            playbackStatus = "1 missing article(s)",
            downloadsStatus = "2 missing audio attachment(s)",
        )
        assertTrue(base.canFinishPartial)
        assertFalse(base.copy(downloadsStatus = "").canFinishPartial)
        assertFalse(base.copy(feedsComplete = false).canFinishPartial)
        assertFalse(base.copy(playbackComplete = true, downloadsComplete = true).canFinishPartial)
    }
    @Test
    fun manuallySkippedMediaRemainsDistinguishableFromVerifiedCompletion() {
        val skipped = AndroidLegacyMigrationNotice(
            importedServer = "https://example.test",
            acknowledged = true,
            settingsComplete = true,
            localComplete = true,
            feedsComplete = true,
            startupComplete = true,
            widgetsComplete = true,
            playbackComplete = true,
            downloadsComplete = true,
            completionKind = "completed_with_skipped_items",
            skippedPlaybackDetails = "79 missing article(s)",
        )
        assertTrue(skipped.complete)
        assertTrue(skipped.completedWithSkippedItems)
        assertEquals(
            "Completed with skipped items: 79 missing article(s)",
            skipped.steps.first { it.title == "Playback progress" }.description,
        )
        assertFalse(skipped.appliesTo("https://example.test"))
        assertFalse(skipped.copy(completionKind = "completed", skippedPlaybackDetails = "").completedWithSkippedItems)
    }

    @Test
    fun discardedOldPlaybackCanBeGreenWhileExplainingWhatWasDropped() {
        val state = AndroidLegacyMigrationNotice(
            importedServer = "https://example.test",
            settingsComplete = true,
            localComplete = true,
            feedsComplete = true,
            startupComplete = true,
            playbackComplete = true,
            downloadsComplete = true,
            widgetsComplete = true,
            playbackStatus = "53 old playback positions discarded: no local download and no longer available on the server.",
        )

        val playback = state.steps.first { it.title == "Playback progress" }
        assertTrue(state.complete)
        assertTrue(playback.complete)
        assertEquals(
            "53 old playback positions discarded: no local download and no longer available on the server.",
            playback.description,
        )
    }

}
