package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidListeningListReloadPolicyTest {
    @Test
    fun onlyLatestReloadForActiveSessionMayPublish() {
        assertTrue(
            androidListeningListReloadIsCurrent(
                activeSessionGeneration = 7L,
                latestReloadGeneration = 12L,
                expectedSessionGeneration = 7L,
                expectedReloadGeneration = 12L,
            ),
        )
        assertFalse(
            androidListeningListReloadIsCurrent(
                activeSessionGeneration = 7L,
                latestReloadGeneration = 13L,
                expectedSessionGeneration = 7L,
                expectedReloadGeneration = 12L,
            ),
        )
        assertFalse(
            androidListeningListReloadIsCurrent(
                activeSessionGeneration = 8L,
                latestReloadGeneration = 12L,
                expectedSessionGeneration = 7L,
                expectedReloadGeneration = 12L,
            ),
        )
    }
}
