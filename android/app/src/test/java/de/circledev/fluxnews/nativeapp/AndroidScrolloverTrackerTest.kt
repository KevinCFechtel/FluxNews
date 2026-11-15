package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidScrolloverTrackerTest {
    @Test
    fun firstArticleCommitsAtScrollEnd() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(0)

        assertTrue(tracker.observe(sample(1), scrolling = true, enabled = true).isEmpty())
        assertEquals(
            listOf(1L),
            tracker.observe(sample(1), scrolling = false, enabled = true),
        )
    }

    @Test
    fun forwardBackwardForwardUsesHighestReachedIndex() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L, 4L))
        tracker.synchronizeIdlePosition(0)

        assertTrue(tracker.observe(sample(1), scrolling = true, enabled = true).isEmpty())
        assertTrue(tracker.observe(sample(0), scrolling = true, enabled = true).isEmpty())
        assertTrue(tracker.observe(sample(2), scrolling = true, enabled = true).isEmpty())

        assertEquals(
            listOf(1L, 2L),
            tracker.observe(sample(1), scrolling = false, enabled = true),
        )
    }

    @Test
    fun reachingDatasetEndCommitsRemainingArticlesIncludingLastOne() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L, 4L))
        tracker.synchronizeIdlePosition(1)

        assertTrue(
            tracker.observe(
                AndroidScrolloverPositionSample(
                    firstVisibleIndex = 2,
                    atDatasetEnd = true,
                ),
                scrolling = true,
                enabled = true,
            ).isEmpty(),
        )

        assertEquals(
            listOf(2L, 3L, 4L),
            tracker.observe(
                AndroidScrolloverPositionSample(
                    firstVisibleIndex = 2,
                    atDatasetEnd = true,
                ),
                scrolling = false,
                enabled = true,
            ),
        )
    }

    @Test
    fun temporaryPagingEndDoesNotCommitPastHighestReachedIndex() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L, 4L))
        tracker.synchronizeIdlePosition(1)

        tracker.observe(
            AndroidScrolloverPositionSample(
                firstVisibleIndex = 2,
                atDatasetEnd = false,
            ),
            scrolling = true,
            enabled = true,
        )

        assertEquals(
            listOf(2L),
            tracker.observe(
                AndroidScrolloverPositionSample(
                    firstVisibleIndex = 2,
                    atDatasetEnd = false,
                ),
                scrolling = false,
                enabled = true,
            ),
        )
    }

    @Test
    fun noForwardProgressCommitsNothing() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(1)

        tracker.observe(sample(0), scrolling = true, enabled = true)

        assertTrue(tracker.observe(sample(0), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun programmaticScrollNeverCommitsCandidates() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(2)

        tracker.beginProgrammaticScroll(2)
        tracker.observe(sample(0), scrolling = true, enabled = true)
        tracker.observe(sample(0), scrolling = false, enabled = true)
        tracker.endProgrammaticScroll(0)

        assertTrue(tracker.observe(sample(0), scrolling = false, enabled = true).isEmpty())

        tracker.observe(sample(1), scrolling = true, enabled = true)
        assertEquals(
            listOf(1L),
            tracker.observe(sample(1), scrolling = false, enabled = true),
        )
    }

    @Test
    fun disabledTrackingSynchronizesIdleWithoutCommitting() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(0)

        tracker.observe(sample(2), scrolling = true, enabled = false)
        tracker.observe(sample(2), scrolling = false, enabled = false)

        tracker.observe(sample(2), scrolling = true, enabled = true)
        assertTrue(tracker.observe(sample(2), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun rearmedArticleCanCommitAgain() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(0)

        tracker.observe(sample(1), scrolling = true, enabled = true)
        assertEquals(listOf(1L), tracker.observe(sample(1), scrolling = false, enabled = true))

        tracker.rearm(listOf(1L))
        tracker.synchronizeIdlePosition(0)
        tracker.observe(sample(1), scrolling = true, enabled = true)

        assertEquals(listOf(1L), tracker.observe(sample(1), scrolling = false, enabled = true))
    }

    @Test
    fun appendOnlySnapshotKeepsActiveScrollProgress() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(0)

        tracker.observe(sample(1), scrolling = true, enabled = true)
        tracker.updateSnapshot(listOf(1L, 2L, 3L, 4L, 5L))
        tracker.observe(sample(2), scrolling = true, enabled = true)

        assertEquals(
            listOf(1L, 2L),
            tracker.observe(sample(2), scrolling = false, enabled = true),
        )
    }

    @Test
    fun structuralSnapshotResetDropsActiveScrollProgress() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(0)
        tracker.observe(sample(2), scrolling = true, enabled = true)

        tracker.updateSnapshot(listOf(10L, 11L, 12L))

        assertTrue(tracker.observe(sample(2), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun repeatedInteractionDoesNotReemitAlreadyReadCandidates() {
        val tracker = AndroidScrolloverTracker()
        tracker.updateSnapshot(listOf(1L, 2L, 3L))
        tracker.synchronizeIdlePosition(0)

        tracker.observe(sample(2), scrolling = true, enabled = true)
        assertEquals(
            listOf(1L, 2L),
            tracker.observe(sample(2), scrolling = false, enabled = true),
        )

        tracker.synchronizeIdlePosition(0)
        tracker.observe(sample(2), scrolling = true, enabled = true)

        assertTrue(tracker.observe(sample(2), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun slowReadWriterDoesNotBlockLaterScrolloverCandidates() = runBlocking {
        val firstWriteStarted = CompletableDeferred<Unit>()
        val releaseFirstWrite = CompletableDeferred<Unit>()
        val writes = mutableListOf<List<Long>>()
        val requests = Channel<AndroidScrolloverMutationRequest>(Channel.UNLIMITED)

        val consumer = launch {
            consumeAndroidScrolloverMutationRequests(
                requests = requests,
                markRead = { ids ->
                    writes += ids
                    if (writes.size == 1) {
                        firstWriteStarted.complete(Unit)
                        releaseFirstWrite.await()
                    }
                    emptyList()
                },
                rearm = {},
                completeInteraction = {},
            )
        }

        requests.send(AndroidScrolloverMutationRequest.MarkRead(listOf(1L)))
        firstWriteStarted.await()
        requests.send(AndroidScrolloverMutationRequest.MarkRead(listOf(2L)))
        releaseFirstWrite.complete(Unit)
        requests.close()
        consumer.join()

        assertEquals(listOf(listOf(1L), listOf(2L)), writes)
    }

    private fun sample(firstVisibleIndex: Int) =
        AndroidScrolloverPositionSample(firstVisibleIndex = firstVisibleIndex)
}
