package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.SyncCompleted
import uniffi.flux_uniffi.SyncReason

class AndroidSyncCoordinatorTest {
    @Test
    fun onlyOneForegroundSyncRunsAtATime() = runBlocking {
        val release = CompletableDeferred<Unit>()
        val coordinator = coordinator { _, _ -> release.await() }

        assertTrue(coordinator.requestSync(SyncReason.APP_START))
        assertFalse(coordinator.requestSync(SyncReason.MANUAL))
        release.complete(Unit)
        awaitTerminal(coordinator)

        assertTrue(coordinator.state.value is AndroidSyncCoordinator.State.Succeeded)
        assertTrue(coordinator.requestSync(SyncReason.MANUAL))
    }

    @Test
    fun cancellationUsesRunScopedHandleAndPublishesCancelled() = runBlocking {
        val release = CompletableDeferred<Unit>()
        var observedHandle: FakeCancellation? = null
        val coordinator = AndroidSyncCoordinator(
            scope = this,
            cancellationFactory = { FakeCancellation().also { observedHandle = it } },
            syncRunner = { _, _ -> release.await() },
            testOnly = Unit,
        )

        assertTrue(coordinator.requestSync(SyncReason.MANUAL))
        assertTrue(coordinator.cancelActiveSync())
        assertTrue(observedHandle?.isCancelled() == true)
        release.complete(Unit)
        awaitTerminal(coordinator)

        assertTrue(coordinator.state.value is AndroidSyncCoordinator.State.Cancelled)
    }

    @Test
    fun userCancellationOnlyCancelsManualRuns() = runBlocking {
        val startupRelease = CompletableDeferred<Unit>()
        var startupHandle: FakeCancellation? = null
        val coordinator = AndroidSyncCoordinator(
            scope = this,
            cancellationFactory = { FakeCancellation().also { startupHandle = it } },
            syncRunner = { _, _ -> startupRelease.await() },
            testOnly = Unit,
        )

        assertTrue(coordinator.requestSync(SyncReason.APP_START))
        assertFalse(coordinator.cancelManualSync())
        assertFalse(startupHandle?.isCancelled() == true)
        startupRelease.complete(Unit)
        awaitTerminal(coordinator)

        val manualRelease = CompletableDeferred<Unit>()
        val manualCoordinator = AndroidSyncCoordinator(
            scope = this,
            cancellationFactory = { FakeCancellation() },
            syncRunner = { _, _ -> manualRelease.await() },
            testOnly = Unit,
        )
        assertTrue(manualCoordinator.requestSync(SyncReason.MANUAL))
        assertTrue(manualCoordinator.cancelManualSync())
        manualRelease.complete(Unit)
        awaitTerminal(manualCoordinator)
        assertTrue(manualCoordinator.state.value is AndroidSyncCoordinator.State.Cancelled)
    }

    @Test
    fun requestIsRejectedWithoutAnActiveCoreSession() {
        val coordinator = AndroidSyncCoordinator(
            scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined),
            cancellationFactory = { FakeCancellation() },
            sessionGeneration = { null },
            syncRunner = { _, _ -> },
            testOnly = Unit,
        )

        assertFalse(coordinator.requestSync(SyncReason.RESUME))
        assertTrue(coordinator.state.value is AndroidSyncCoordinator.State.Idle)
    }

    @Test
    fun successfulSyncPublishesPostSyncMetadataForItsSessionGeneration() = runBlocking {
        val metadata = syncMetadata(SyncReason.MANUAL)
        val published = mutableListOf<Pair<Long, SyncCompleted>>()
        val coordinator = AndroidSyncCoordinator(
            scope = this,
            cancellationFactory = { FakeCancellation() },
            sessionGeneration = { 41L },
            syncRunner = { _, _ -> },
            syncMetadata = metadata,
            postSync = { generation, completed -> published += generation to completed },
            testOnly = Unit,
        )

        assertTrue(coordinator.requestSync(SyncReason.MANUAL))
        awaitTerminal(coordinator)

        assertEquals(listOf(41L to metadata), published)
    }

    @Test
    fun replacedCoreSessionSuppressesStalePostSyncEffects() = runBlocking {
        val release = CompletableDeferred<Unit>()
        var activeGeneration: Long? = 51L
        val published = mutableListOf<Pair<Long, SyncCompleted>>()
        val coordinator = AndroidSyncCoordinator(
            scope = this,
            cancellationFactory = { FakeCancellation() },
            sessionGeneration = { activeGeneration },
            syncRunner = { _, _ -> release.await() },
            syncMetadata = syncMetadata(SyncReason.APP_START),
            postSync = { generation, completed -> published += generation to completed },
            testOnly = Unit,
        )

        assertTrue(coordinator.requestSync(SyncReason.APP_START))
        activeGeneration = 52L
        release.complete(Unit)
        awaitTerminal(coordinator)

        assertTrue(published.isEmpty())
    }

    @Test
    fun successPresentationIsImmediateAndOnlyDismissesAfterItsGenerationExpires() {
        assertFalse(
            AndroidSyncPresentationPolicy.successVisible(
                state = AndroidSyncCoordinator.State.Syncing(
                    generation = 7L,
                    reason = SyncReason.MANUAL,
                ),
                dismissedGeneration = null,
            ),
        )
        assertTrue(
            AndroidSyncPresentationPolicy.successVisible(
                state = AndroidSyncCoordinator.State.Succeeded(
                    generation = 7L,
                    reason = SyncReason.MANUAL,
                ),
                dismissedGeneration = null,
            ),
        )
        assertFalse(
            AndroidSyncPresentationPolicy.successVisible(
                state = AndroidSyncCoordinator.State.Succeeded(
                    generation = 7L,
                    reason = SyncReason.MANUAL,
                ),
                dismissedGeneration = 7L,
            ),
        )
        assertFalse(
            AndroidSyncPresentationPolicy.successVisible(
                state = AndroidSyncCoordinator.State.Succeeded(
                    generation = 7L,
                    reason = SyncReason.APP_START,
                ),
                dismissedGeneration = null,
            ),
        )
    }

    @Test
    fun failureKeepsARecoverableLocalDataMessage() = runBlocking {
        val coordinator = coordinator { _, _ -> error("token=must-not-leak") }

        assertTrue(coordinator.requestSync(SyncReason.APP_START))
        awaitTerminal(coordinator)

        val state = coordinator.state.value as AndroidSyncCoordinator.State.Failed
        assertEquals("Sync failed. Showing locally stored data.", state.message)
        assertFalse(state.message.contains("must-not-leak"))
    }

    private fun syncMetadata(reason: SyncReason) = SyncCompleted(
        reason = reason,
        newArticles = 0u,
        updatedArticles = 0u,
        mutationsDelivered = 0u,
        dataChanged = false,
        navigationChanged = false,
        newArticlesByFeed = emptyList(),
        systemNotificationCandidates = emptyList(),
    )

    private fun kotlinx.coroutines.CoroutineScope.coordinator(
        runner: suspend (SyncReason, AndroidSyncCancellationHandle) -> Unit,
    ) = AndroidSyncCoordinator(
        scope = this,
        cancellationFactory = { FakeCancellation() },
        syncRunner = runner,
        testOnly = Unit,
    )

    private suspend fun awaitTerminal(coordinator: AndroidSyncCoordinator) {
        repeat(100) {
            if (coordinator.state.value !is AndroidSyncCoordinator.State.Syncing) return
            yield()
        }
        error("Sync did not reach a terminal state")
    }

    private class FakeCancellation : AndroidSyncCancellationHandle {
        private var cancelled = false

        override fun cancel() {
            cancelled = true
        }

        override fun isCancelled(): Boolean = cancelled
    }
}
