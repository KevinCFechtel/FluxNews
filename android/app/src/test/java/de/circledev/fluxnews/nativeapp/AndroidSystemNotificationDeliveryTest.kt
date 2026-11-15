package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.SystemNotificationCandidate

class AndroidSystemNotificationDeliveryTest {
    @Test
    fun acknowledgesOnlyAfterSuccessfulPlatformHandoff() = runBlocking {
        val events = mutableListOf<String>()
        val delivery = AndroidSystemNotificationDelivery(
            activeSessionGeneration = { 7L },
            handoff = {
                events += "handoff:${it.candidateId}"
                true
            },
            acknowledge = { generation, candidateId ->
                events += "ack:$generation:$candidateId"
                true
            },
        )

        delivery.deliver(7L, listOf(candidate(41L)))

        assertEquals(listOf("handoff:41", "ack:7:41"), events)
    }

    @Test
    fun failedPlatformHandoffIsNeverAcknowledged() = runBlocking {
        var acknowledged = false
        val delivery = AndroidSystemNotificationDelivery(
            activeSessionGeneration = { 9L },
            handoff = { false },
            acknowledge = { _, _ -> acknowledged = true; true },
        )

        delivery.deliver(9L, listOf(candidate(42L)))

        assertTrue(!acknowledged)
    }

    @Test
    fun staleSessionDoesNotDeliverOrAcknowledge() = runBlocking {
        var delivered = false
        var acknowledged = false
        val delivery = AndroidSystemNotificationDelivery(
            activeSessionGeneration = { 12L },
            handoff = { delivered = true; true },
            acknowledge = { _, _ -> acknowledged = true; true },
        )

        delivery.deliver(11L, listOf(candidate(43L)))

        assertTrue(!delivered)
        assertTrue(!acknowledged)
    }

    @Test
    fun sessionReplacementAfterHandoffSuppressesAcknowledgement() = runBlocking {
        var activeGeneration = 20L
        var acknowledged = false
        val delivery = AndroidSystemNotificationDelivery(
            activeSessionGeneration = { activeGeneration },
            handoff = {
                activeGeneration = 21L
                true
            },
            acknowledge = { _, _ -> acknowledged = true; true },
        )

        delivery.deliver(20L, listOf(candidate(44L)))

        assertTrue(!acknowledged)
    }

    private fun candidate(id: Long) = SystemNotificationCandidate(
        candidateId = id,
        feedId = 3L,
        feedTitle = "Feed",
        newCount = 2u,
    )
}
