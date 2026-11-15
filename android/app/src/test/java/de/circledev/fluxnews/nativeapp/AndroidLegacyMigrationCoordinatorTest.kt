package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidLegacyMigrationCoordinatorTest {
    private val legacy = LegacyAndroidAccountImport(
        serverUrl = "https://example.test/",
        apiKey = "secret",
        customHeaders = listOf(LegacyAndroidHeaderImport("X-Test", "value")),
    )

    @Test
    fun nativeAccountWinsWithoutReadingLegacyState() = runBlocking {
        var legacyRead = false
        var written: StoredAccountCredentials? = null
        val existing = StoredAccountCredentials("https://native.test/", "native", emptyList())
        val coordinator = AndroidLegacyMigrationCoordinator(
            nativeCredentialReader = { existing },
            nativeCredentialWriter = { written = it },
            legacyAccountReader = {
                legacyRead = true
                LegacyAndroidAccountReadResult.Found(legacy)
            },
            testOnly = Unit,
        )

        coordinator.prepareAccountForRestore()

        assertFalse(legacyRead)
        assertEquals(null, written)
    }

    @Test
    fun legacyAccountWritesProvenanceBeforeNativeCredentials() = runBlocking {
        val calls = mutableListOf<String>()
        var stored: StoredAccountCredentials? = null
        val coordinator = AndroidLegacyMigrationCoordinator(
            nativeCredentialReader = { stored },
            nativeCredentialWriter = {
                calls += "credentials"
                stored = it
            },
            legacyAccountReader = { LegacyAndroidAccountReadResult.Found(legacy) },
            importedAccountMarkerWriter = { calls += "marker:$it" },
            onCredentialsImported = { calls += "redaction" },
            testOnly = Unit,
        )

        coordinator.prepareAccountForRestore()

        assertEquals(
            listOf("marker:https://example.test/", "credentials", "redaction"),
            calls,
        )
        assertEquals("secret", stored?.apiKey)
        assertEquals(listOf(StoredCredentialHeader("X-Test", "value")), stored?.customHeaders)
    }

    @Test
    fun unavailableLegacyStorageIsRetryableAndDoesNotWriteNativeState() = runBlocking {
        var wroteCredentials = false
        val coordinator = AndroidLegacyMigrationCoordinator(
            nativeCredentialReader = { null },
            nativeCredentialWriter = { wroteCredentials = true },
            legacyAccountReader = { LegacyAndroidAccountReadResult.Unavailable },
            testOnly = Unit,
        )

        val failure = runCatching { coordinator.prepareAccountForRestore() }.exceptionOrNull()

        assertTrue(failure is AndroidLegacyMigrationException)
        assertFalse(wroteCredentials)
    }

    @Test
    fun failedCredentialCopyClearsProvenanceAndPartialNativeState() = runBlocking {
        val calls = mutableListOf<String>()
        val coordinator = AndroidLegacyMigrationCoordinator(
            nativeCredentialReader = { null },
            nativeCredentialWriter = {
                calls += "credentials"
                error("write failed")
            },
            nativeCredentialClearer = { calls += "clear-credentials" },
            legacyAccountReader = { LegacyAndroidAccountReadResult.Found(legacy) },
            importedAccountMarkerWriter = { calls += "marker" },
            importedAccountMarkerClearer = { calls += "clear-marker" },
            testOnly = Unit,
        )

        val failure = runCatching { coordinator.prepareAccountForRestore() }.exceptionOrNull()

        assertTrue(failure is AndroidLegacyMigrationException)
        assertEquals(
            listOf("marker", "credentials", "clear-marker", "clear-credentials"),
            calls,
        )
    }
}
