package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import uniffi.flux_uniffi.BackupAccount
import uniffi.flux_uniffi.BackupPlatform
import uniffi.flux_uniffi.ConfigBackupRestoreModel
import uniffi.flux_uniffi.ConfigurationSnapshot
import uniffi.flux_uniffi.CoreSettings
import uniffi.flux_uniffi.DeliveryMode
import uniffi.flux_uniffi.DownloadNetworkPolicy
import uniffi.flux_uniffi.DownloadRetention
import uniffi.flux_uniffi.PlatformSettingsPayload
import uniffi.flux_uniffi.ReadArticleRetention

class AndroidConfigurationBackupTest {
    private fun settings(headers: List<StoredCredentialHeader> = listOf(StoredCredentialHeader("X-Account", "private"))) = AndroidBackupSettingsV1(
        hideEmptyNavigationEntries = true,
        startupScope = AndroidStartupScopePreference.Feed.storedValue,
        startupCategoryId = null,
        startupFeedId = 42,
        openArticle = AndroidArticleOpenPreference.Reader.storedValue,
        presentationMode = AndroidArticlePresentationMode.Compact.storedValue,
        previewLines = AndroidArticlePreviewLines.Extended.lineCount,
        showArticleCount = false,
        showRelativePublicationTime = true,
        removeArticlesWhenRead = true,
        markReadOnScrollover = false,
        leadingSwipeFull = AndroidArticleSwipeAction.ReadUnread.storedValue,
        leadingSwipeAdditional = AndroidArticleSwipeAction.Share.storedValue,
        trailingSwipeFull = AndroidArticleSwipeAction.DownloadAudio.storedValue,
        trailingSwipeAdditional = AndroidArticleSwipeAction.ListeningList.storedValue,
        actionBarActions = listOf(AndroidActionBarAction.Search.storedValue, AndroidActionBarAction.FilterAndSort.storedValue),
        customHeaders = headers,
    )

    @Test fun payloadRoundTripPreservesNavigationSwipeAndActionOrder() {
        val restored = AndroidBackupSettingsV1.decode(settings().encode())
        assertEquals(settings(), restored)
        assertEquals(42L, restored.startupFeedId)
        assertEquals(listOf("search", "filterAndSort"), restored.actionBarActions)
    }

    @Test fun nonSelectedStartupTargetIsDiscarded() {
        val restored = settings().copy(startupScope = AndroidStartupScopePreference.AllNews.storedValue).validated()
        assertNull(restored.startupCategoryId)
        assertNull(restored.startupFeedId)
    }

    @Test(expected = AndroidConfigurationBackupException.InvalidPlatformSettings::class)
    fun rejectsUnknownSchemaVersion() { AndroidBackupSettingsV1.decode(settings().encode().replace("\"version\":1", "\"version\":2")) }

    @Test(expected = AndroidConfigurationBackupException.InvalidPlatformSettings::class)
    fun rejectsInvalidStoredEnum() { AndroidBackupSettingsV1.decode(settings().copy(openArticle = "invalid").encode()) }

    @Test(expected = AndroidConfigurationBackupException.InvalidPlatformSettings::class)
    fun rejectsAdditionalSwipeWithoutFullSwipe() { AndroidBackupSettingsV1.decode(settings().copy(leadingSwipeFull = null).encode()) }

    @Test(expected = AndroidConfigurationBackupException.InvalidPlatformSettings::class)
    fun rejectsDuplicateActionBarActions() { AndroidBackupSettingsV1.decode(settings().copy(actionBarActions = listOf("search", "search")).encode()) }

    @Test fun existingAccountRestoreCommitsAllStateInsideLock() = runBlocking {
        val oldCredentials = credentials("old", "old-key")
        val fake = FakeRestoreBoundary(oldCredentials, snapshot("https://old.example"), settings(oldCredentials.customHeaders))
        AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings())

        assertEquals("https://new.example", fake.coreBase)
        assertEquals("new-key", fake.credentialsState?.apiKey)
        assertEquals(settings(), fake.platformState)
        assertEquals("new-key", fake.runtimeCredentials?.apiKey)
        assertEquals("new-key", fake.readyCredentials?.apiKey)
        assertFalse(fake.recoveryPublished)
        assertTrue(fake.allMutationsInsideLock)
        assertEquals(listOf("lock.enter", "capturePlatform", "snapshot", "lifecycle.prepare", "replaceCore", "writeCredentials", "applyPlatform", "replaceRuntime", "publishReady", "lifecycle.resume", "lock.exit"), fake.calls)
    }

    @Test fun freshInstallRestoreCommitsAllState() = runBlocking {
        val initialPlatform = settings(emptyList()).copy(hideEmptyNavigationEntries = false)
        val fake = FakeRestoreBoundary(null, null, initialPlatform)
        AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings())

        assertEquals("https://new.example", fake.coreBase)
        assertEquals("new-key", fake.credentialsState?.apiKey)
        assertEquals(settings(), fake.platformState)
        assertEquals("new-key", fake.runtimeCredentials?.apiKey)
        assertEquals("new-key", fake.readyCredentials?.apiKey)
        assertEquals(listOf("lock.enter", "capturePlatform", "snapshot", "lifecycle.prepare", "openFresh", "replaceCore", "writeCredentials", "applyPlatform", "replaceRuntime", "publishReady", "lifecycle.resume", "lock.exit"), fake.calls)
    }

    @Test fun existingAccountFailureAfterCoreReplacementRestoresEverything() = runBlocking {
        assertExistingRollback(FailurePoint.WriteCredentials)
    }

    @Test fun existingAccountFailureAfterCredentialReplacementRestoresEverything() = runBlocking {
        assertExistingRollback(FailurePoint.ApplyPlatform)
    }

    @Test fun existingAccountPartialPlatformFailureRestoresEverything() = runBlocking {
        assertExistingRollback(FailurePoint.ApplyPlatformPartial)
    }

    @Test fun existingAccountRuntimeFailureRestoresEverything() = runBlocking {
        assertExistingRollback(FailurePoint.ReplaceRuntime)
    }

    @Test fun freshInstallFailureAfterCoreMutationResetsEverything() = runBlocking {
        val initialPlatform = settings(emptyList()).copy(hideEmptyNavigationEntries = false)
        val fake = FakeRestoreBoundary(null, null, initialPlatform, FailurePoint.WriteCredentials)
        expectInjectedFailure { AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings()) }

        assertNull(fake.coreBase)
        assertNull(fake.credentialsState)
        assertEquals(initialPlatform, fake.platformState)
        assertNull(fake.runtimeCredentials)
        assertNull(fake.readyCredentials)
        assertOrder(fake.calls, "resetFreshCore", "applyPlatform", "closeRuntime", "clearCredentials")
    }

    @Test fun freshInstallPartialPlatformFailureRestoresPreviousPreferences() = runBlocking {
        val initialPlatform = settings(emptyList()).copy(hideEmptyNavigationEntries = false, showArticleCount = true)
        val fake = FakeRestoreBoundary(null, null, initialPlatform, FailurePoint.ApplyPlatformPartial)
        expectInjectedFailure { AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings()) }

        assertNull(fake.coreBase)
        assertNull(fake.credentialsState)
        assertEquals(initialPlatform, fake.platformState)
        assertNull(fake.runtimeCredentials)
        assertOrder(fake.calls, "resetFreshCore", "applyPlatform", "closeRuntime", "clearCredentials")
    }

    @Test fun rollbackFailurePublishesRecoverableError() = runBlocking {
        val oldCredentials = credentials("old", "old-key")
        val fake = FakeRestoreBoundary(oldCredentials, snapshot("https://old.example"), settings(oldCredentials.customHeaders), FailurePoint.ReplaceRuntime, FailurePoint.RestoreCore)
        try {
            AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings())
            fail("Expected RollbackFailed")
        } catch (error: AndroidConfigurationBackupException.RollbackFailed) {
            // expected
        }
        assertTrue(fake.recoveryPublished)
        assertNull(fake.readyCredentials)
        assertEquals(1, fake.calls.count { it == "publishRecoveryError" })
    }

    @Test fun failureBeforeMutationChangesNothing() = runBlocking {
        val oldCredentials = credentials("old", "old-key")
        val oldPlatform = settings(oldCredentials.customHeaders).copy(showArticleCount = true)
        val fake = FakeRestoreBoundary(oldCredentials, snapshot("https://old.example"), oldPlatform, FailurePoint.CapturePlatform)
        expectInjectedFailure { AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings()) }

        assertEquals("https://old.example", fake.coreBase)
        assertEquals(oldCredentials, fake.credentialsState)
        assertEquals(oldPlatform, fake.platformState)
        assertEquals(oldCredentials, fake.runtimeCredentials)
        assertFalse(fake.calls.contains("replaceCore"))
        assertFalse(fake.recoveryPublished)
    }

    private suspend fun assertExistingRollback(failure: FailurePoint) {
        val oldCredentials = credentials("old", "old-key")
        val oldPlatform = settings(oldCredentials.customHeaders).copy(showArticleCount = true)
        val fake = FakeRestoreBoundary(oldCredentials, snapshot("https://old.example"), oldPlatform, failure)
        expectInjectedFailure { AndroidConfigurationRestoreTransaction(fake).restore(restoredModel(), settings()) }

        assertEquals("https://old.example", fake.coreBase)
        assertEquals(oldCredentials, fake.credentialsState)
        assertEquals(oldPlatform, fake.platformState)
        assertEquals(oldCredentials, fake.runtimeCredentials)
        assertEquals(oldCredentials, fake.readyCredentials)
        assertFalse(fake.recoveryPublished)
        assertTrue(fake.allMutationsInsideLock)
    }

    private suspend fun expectInjectedFailure(block: suspend () -> Unit) {
        try { block(); fail("Expected injected failure") } catch (error: InjectedFailure) { /* expected */ }
    }

    private fun assertOrder(calls: List<String>, vararg expected: String) {
        var position = -1
        expected.forEach { call ->
            val next = calls.indices.firstOrNull { it > position && calls[it] == call } ?: -1
            assertTrue("Missing/out-of-order call $call in $calls", next > position)
            position = next
        }
    }

    private fun credentials(label: String, key: String) = StoredAccountCredentials("https://$label.example", key, listOf(StoredCredentialHeader("X-$label", "$label-value")))

    private fun coreSettings() = CoreSettings(
        retention = ReadArticleRetention.DAYS30,
        deliveryMode = DeliveryMode.DEFERRED,
        backgroundSyncEnabled = true,
        detailCharacterLimit = 10_000u,
        downloadNetworkPolicy = DownloadNetworkPolicy.ANY_NETWORK,
        downloadRetention = DownloadRetention.Forever,
        deleteAfterPlayback = false,
        autoDownloadListeningList = false,
        removeCompletedListeningList = false,
    )

    private fun snapshot(base: String) = ConfigurationSnapshot(base, coreSettings(), emptyList())

    private fun restoredModel() = ConfigBackupRestoreModel(
        BackupPlatform.ANDROID,
        BackupAccount("https://new.example", "new-key"),
        coreSettings(),
        emptyList(),
        PlatformSettingsPayload(AndroidBackupSettingsV1.VERSION, settings().encode()),
    )

    private enum class FailurePoint { CapturePlatform, WriteCredentials, ApplyPlatform, ApplyPlatformPartial, ReplaceRuntime, RestoreCore }
    private class InjectedFailure : Exception()

    private inner class FakeRestoreBoundary(
        initialCredentials: StoredAccountCredentials?,
        private val initialSnapshot: ConfigurationSnapshot?,
        initialPlatform: AndroidBackupSettingsV1,
        private val failure: FailurePoint? = null,
        private val rollbackFailure: FailurePoint? = null,
    ) : AndroidConfigurationRestoreBoundary {
        val calls = mutableListOf<String>()
        var credentialsState = initialCredentials
        var platformState = initialPlatform
        var coreBase: String? = initialSnapshot?.installationBase
        var runtimeCredentials: StoredAccountCredentials? = initialCredentials
        var readyCredentials: StoredAccountCredentials? = null
        var recoveryPublished = false
        var allMutationsInsideLock = true
        private var inLock = false
        private var primaryFailureConsumed = false

        override suspend fun <T> withLock(block: suspend () -> T): T {
            check(!inLock)
            calls += "lock.enter"
            inLock = true
            return try { block() } finally { inLock = false; calls += "lock.exit" }
        }

        override fun credentials(): StoredAccountCredentials? = credentialsState
        override suspend fun snapshot(): ConfigurationSnapshot? { calls += "snapshot"; return initialSnapshot }

        override suspend fun replaceCore(model: ConfigBackupRestoreModel) {
            mutation("replaceCore")
            coreBase = model.account.installationBase
        }

        override suspend fun restoreCore(snapshot: ConfigurationSnapshot) {
            mutation("restoreCore")
            if (rollbackFailure == FailurePoint.RestoreCore) throw InjectedFailure()
            coreBase = snapshot.installationBase
        }

        override suspend fun openFresh(credentials: StoredAccountCredentials) { mutation("openFresh"); runtimeCredentials = credentials; coreBase = credentials.serverUrl }
        override suspend fun resetFreshCore() { mutation("resetFreshCore"); coreBase = null }
        override suspend fun replaceRuntime(credentials: StoredAccountCredentials) { mutation("replaceRuntime"); failPrimary(FailurePoint.ReplaceRuntime); runtimeCredentials = credentials }
        override suspend fun closeRuntime() { mutation("closeRuntime"); runtimeCredentials = null }

        override fun writeCredentials(credentials: StoredAccountCredentials) {
            mutation("writeCredentials")
            failPrimary(FailurePoint.WriteCredentials)
            credentialsState = credentials
        }
        override fun clearCredentials() { mutation("clearCredentials"); credentialsState = null }

        override suspend fun capturePlatform(headers: List<StoredCredentialHeader>): AndroidBackupSettingsV1 {
            calls += "capturePlatform"
            if (failure == FailurePoint.CapturePlatform) throw InjectedFailure()
            return platformState.copy(customHeaders = headers)
        }

        override suspend fun prepareForLifecycleChange() { mutation("lifecycle.prepare") }
        override suspend fun resumeAfterLifecycleChange() { mutation("lifecycle.resume") }

        override suspend fun applyPlatform(settings: AndroidBackupSettingsV1) {
            mutation("applyPlatform")
            if (failure == FailurePoint.ApplyPlatformPartial && !primaryFailureConsumed) {
                primaryFailureConsumed = true
                platformState = platformState.copy(hideEmptyNavigationEntries = settings.hideEmptyNavigationEntries)
                throw InjectedFailure()
            }
            failPrimary(FailurePoint.ApplyPlatform)
            platformState = settings
        }

        override fun publishReady(credentials: StoredAccountCredentials) { mutation("publishReady"); readyCredentials = credentials }
        override fun publishRecoveryError() { mutation("publishRecoveryError"); recoveryPublished = true; readyCredentials = null }

        private fun mutation(name: String) {
            calls += name
            if (!inLock) allMutationsInsideLock = false
        }
        private fun failPrimary(point: FailurePoint) {
            if (failure == point && !primaryFailureConsumed) { primaryFailureConsumed = true; throw InjectedFailure() }
        }
    }
}
