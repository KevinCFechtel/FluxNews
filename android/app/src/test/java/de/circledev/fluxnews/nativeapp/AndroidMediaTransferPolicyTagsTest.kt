package de.circledev.fluxnews.nativeapp

import androidx.work.NetworkType
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidMediaTransferPolicyTagsTest {
    @Test fun unchangedConstraintsDoNotRescheduleWork() {
        val existing = setOf(AndroidMediaTransferPolicyTags.tag(NetworkType.UNMETERED))
        assertFalse(AndroidMediaTransferPolicyTags.needsUpdate(existing, NetworkType.UNMETERED))
    }

    @Test fun relaxingConstraintsUpdatesExistingWork() {
        val existing = setOf(AndroidMediaTransferPolicyTags.tag(NetworkType.UNMETERED))
        assertTrue(AndroidMediaTransferPolicyTags.needsUpdate(existing, NetworkType.CONNECTED))
    }

    @Test fun tighteningConstraintsUpdatesExistingWork() {
        val existing = setOf(AndroidMediaTransferPolicyTags.tag(NetworkType.CONNECTED))
        assertTrue(AndroidMediaTransferPolicyTags.needsUpdate(existing, NetworkType.UNMETERED))
    }

    @Test fun legacyUntaggedWorkIsUpdatedOnce() {
        assertTrue(AndroidMediaTransferPolicyTags.needsUpdate(emptySet(), NetworkType.CONNECTED))
        assertFalse(
            AndroidMediaTransferPolicyTags.needsUpdate(
                setOf(AndroidMediaTransferPolicyTags.tag(NetworkType.CONNECTED)),
                NetworkType.CONNECTED,
            ),
        )
    }
}
