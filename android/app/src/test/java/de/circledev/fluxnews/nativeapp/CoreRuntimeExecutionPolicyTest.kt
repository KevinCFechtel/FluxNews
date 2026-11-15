package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class CoreRuntimeExecutionPolicyTest {
    @Test
    fun executionWorkerPolicyRemainsSmallAndBounded() {
        assertEquals(2, CoreRuntimeExecutionPolicy.LOCAL_WORKERS)
        assertEquals(1, CoreRuntimeExecutionPolicy.REMOTE_WORKERS)
    }
}
