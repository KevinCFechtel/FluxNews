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
    fun firstVisibleArticleQualifiesOnlyAfterObservedForwardCrossing() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)

        assertTrue(tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true).isEmpty())
        assertEquals(listOf(1L), tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true))
    }

    @Test
    fun fastFlingDoesNotMarkSkippedAndUnobservedRows() {
        val tracker = trackerWith(1L, 2L, 3L, 4L, 5L)
        tracker.observe(sample(0, 0), scrolling = false, enabled = true)

        // The LazyList jumped directly from the first article to the fifth.
        tracker.observe(sample(4, 4), scrolling = true, enabled = true)

        assertEquals(listOf(1L), tracker.observe(sample(4, 4), scrolling = false, enabled = true))
    }

    @Test
    fun crossingWithoutPriorViewportExposureNeverQualifies() {
        val tracker = trackerWith(1L, 2L, 3L, 4L)
        tracker.synchronizeIdlePosition(0)

        tracker.observe(sample(2, 2, 3), scrolling = true, enabled = true)
        assertTrue(tracker.observe(sample(2, 2, 3), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun partialScrollDoesNotQualifyUntilRowCrossesTop() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)

        tracker.observe(sample(0, 0, 1, firstVisibleOffset = 60), scrolling = true, enabled = true)
        assertTrue(
            tracker.observe(
                sample(0, 0, 1, firstVisibleOffset = 60),
                scrolling = false,
                enabled = true,
            ).isEmpty(),
        )

        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        assertEquals(listOf(1L), tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true))
    }

    @Test
    fun forwardBackwardForwardOnlyMarksPreviouslySeenForwardCrossings() {
        val tracker = trackerWith(1L, 2L, 3L, 4L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)

        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        tracker.observe(sample(0, 0, 1), scrolling = true, enabled = true)
        tracker.observe(sample(2, 2, 3), scrolling = true, enabled = true)

        assertEquals(
            listOf(1L, 2L),
            tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true),
        )
    }

    @Test
    fun reverseMovementAloneDoesNotMarkRead() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true)
        tracker.observe(sample(0, 0, 1), scrolling = true, enabled = true)

        assertTrue(tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun genuineForwardArrivalAtEndCompletesOnlyObservedTrailingRows() {
        val tracker = trackerWith(1L, 2L, 3L, 4L)
        tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true)

        tracker.observe(sample(2, 2, 3, atDatasetEnd = true), scrolling = true, enabled = true)
        assertEquals(
            listOf(2L, 3L, 4L),
            tracker.observe(sample(2, 2, 3, atDatasetEnd = true), scrolling = false, enabled = true),
        )
    }

    @Test
    fun jumpingToDatasetEndNeverMarksUnseenMiddleRows() {
        val tracker = trackerWith(1L, 2L, 3L, 4L, 5L)
        tracker.observe(sample(0, 0), scrolling = false, enabled = true)

        tracker.observe(sample(4, 4, atDatasetEnd = true), scrolling = true, enabled = true)
        assertEquals(
            listOf(1L, 5L),
            tracker.observe(sample(4, 4, atDatasetEnd = true), scrolling = false, enabled = true),
        )
    }

    @Test
    fun scrollingWhileAlreadyAtEndDoesNotCommitVisibleRows() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(2, 2, atDatasetEnd = true), scrolling = false, enabled = true)

        tracker.observe(
            sample(2, 2, firstVisibleOffset = 12, atDatasetEnd = true),
            scrolling = true,
            enabled = true,
        )
        assertTrue(
            tracker.observe(
                sample(2, 2, firstVisibleOffset = 12, atDatasetEnd = true),
                scrolling = false,
                enabled = true,
            ).isEmpty(),
        )
    }

    @Test
    fun temporaryPagingEndDoesNotCompleteTrailingRows() {
        val tracker = trackerWith(1L, 2L, 3L, 4L)
        tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true)

        tracker.observe(sample(2, 2, 3, atDatasetEnd = false), scrolling = true, enabled = true)
        assertEquals(
            listOf(2L),
            tracker.observe(sample(2, 2, 3, atDatasetEnd = false), scrolling = false, enabled = true),
        )
    }

    @Test
    fun programmaticScrollNeverCommitsCandidates() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(2, 2), scrolling = false, enabled = true)

        tracker.beginProgrammaticScroll(2)
        tracker.observe(sample(0, 0, 1), scrolling = true, enabled = true)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.endProgrammaticScroll(0)

        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        assertEquals(listOf(1L), tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true))
    }

    @Test
    fun disabledTrackingSynchronizesIdleWithoutCommitting() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)

        tracker.observe(sample(2, 2), scrolling = true, enabled = false)
        tracker.observe(sample(2, 2), scrolling = false, enabled = false)

        tracker.observe(sample(2, 2), scrolling = true, enabled = true)
        assertTrue(tracker.observe(sample(2, 2), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun rearmedArticleCanCommitAgain() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        assertEquals(listOf(1L), tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true))

        tracker.rearm(listOf(1L))
        tracker.synchronizeIdlePosition(0)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        assertEquals(listOf(1L), tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true))
    }

    @Test
    fun appendOnlySnapshotKeepsActiveVisibleCrossings() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        tracker.updateSnapshot(listOf(1L, 2L, 3L, 4L, 5L))
        tracker.observe(sample(2, 2, 3), scrolling = true, enabled = true)

        assertEquals(
            listOf(1L, 2L),
            tracker.observe(sample(2, 2, 3), scrolling = false, enabled = true),
        )
    }

    @Test
    fun structuralSnapshotResetDropsActiveScrollProgress() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(2, 2), scrolling = true, enabled = true)

        tracker.updateSnapshot(listOf(10L, 11L, 12L))
        assertTrue(tracker.observe(sample(2, 2), scrolling = false, enabled = true).isEmpty())
    }

    @Test
    fun repeatedInteractionDoesNotReemitAlreadyReadCandidates() {
        val tracker = trackerWith(1L, 2L, 3L)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        assertEquals(listOf(1L), tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true))

        tracker.synchronizeIdlePosition(0)
        tracker.observe(sample(0, 0, 1), scrolling = false, enabled = true)
        tracker.observe(sample(1, 1, 2), scrolling = true, enabled = true)
        assertTrue(tracker.observe(sample(1, 1, 2), scrolling = false, enabled = true).isEmpty())
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


    private fun trackerWith(vararg ids: Long): AndroidScrolloverTracker =
        AndroidScrolloverTracker().also { it.updateSnapshot(ids.toList()) }

    private fun sample(
        firstVisibleIndex: Int,
        vararg visibleIndices: Int,
        firstVisibleOffset: Int = 0,
        atDatasetEnd: Boolean = false,
    ) = AndroidScrolloverPositionSample(
        firstVisibleIndex = firstVisibleIndex,
        firstVisibleOffset = firstVisibleOffset,
        visibleArticleIndices = visibleIndices.toList(),
        atDatasetEnd = atDatasetEnd,
    )
}
