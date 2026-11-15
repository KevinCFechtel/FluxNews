package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidAppDiagnosticsTest {
    @Test fun recordTextContainsStructuredFields() {
        val entry = AndroidAppLogEntry(
            id = "id",
            timestamp = "2026-10-01T07:00:00Z",
            level = AndroidAppLogLevel.Warning,
            category = "core.sync",
            message = "retry scheduled",
        )
        val text = AndroidAppDiagnostics.recordText(entry)
        assertTrue(text.contains("2026-10-01T07:00:00Z"))
        assertTrue(text.contains("[WARNING]"))
        assertTrue(text.contains("[core.sync]"))
        assertTrue(text.endsWith("retry scheduled"))
    }

    @Test fun logLevelsRemainStableForPersistence() {
        assertEquals(listOf("Trace", "Debug", "Info", "Warning", "Error"), AndroidAppLogLevel.entries.map { it.name })
    }
}
