package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.SyncCompleted
import uniffi.flux_uniffi.SyncReason

class AndroidPostSyncEffectsTest {
    @Test
    fun staleSessionDoesNotRunEffects() = runBlocking {
        var activeGeneration: Long? = 8L
        var calls = 0
        val handoff = AndroidPostSyncEffects(
            activeSessionGeneration = { activeGeneration },
            effects = listOf(AndroidPostSyncEffect { _, _ -> calls += 1 }),
        )

        activeGeneration = 9L
        handoff.handle(8L, metadata())

        assertEquals(0, calls)
    }

    @Test
    fun sessionReplacementStopsRemainingEffects() = runBlocking {
        var activeGeneration: Long? = 11L
        val calls = mutableListOf<String>()
        val handoff = AndroidPostSyncEffects(
            activeSessionGeneration = { activeGeneration },
            effects = listOf(
                AndroidPostSyncEffect { _, _ ->
                    calls += "first"
                    activeGeneration = 12L
                },
                AndroidPostSyncEffect { _, _ -> calls += "second" },
            ),
        )

        handoff.handle(11L, metadata())

        assertEquals(listOf("first"), calls)
    }

    @Test
    fun oneFailingPlatformEffectDoesNotBlockLaterEffects() = runBlocking {
        val calls = mutableListOf<String>()
        val handoff = AndroidPostSyncEffects(
            activeSessionGeneration = { 21L },
            effects = listOf(
                AndroidPostSyncEffect { _, _ -> error("expected") },
                AndroidPostSyncEffect { generation, completed ->
                    calls += "${generation}:${completed.reason}"
                },
            ),
        )

        handoff.handle(21L, metadata())

        assertTrue(calls.single().startsWith("21:"))
    }

    private fun metadata() = SyncCompleted(
        reason = SyncReason.BACKGROUND,
        newArticles = 0u,
        updatedArticles = 0u,
        mutationsDelivered = 0u,
        dataChanged = false,
        navigationChanged = false,
        newArticlesByFeed = emptyList(),
        systemNotificationCandidates = emptyList(),
    )
}
