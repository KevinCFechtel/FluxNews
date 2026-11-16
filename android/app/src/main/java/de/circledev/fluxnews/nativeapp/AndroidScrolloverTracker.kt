package de.circledev.fluxnews.nativeapp

internal data class AndroidScrolloverPositionSample(
    val firstVisibleIndex: Int,
    val firstVisibleOffset: Int = 0,
    /** Actual article rows intersecting the viewport, not prefetched/offscreen LazyList items. */
    val visibleArticleIndices: List<Int> = emptyList(),
    val atDatasetEnd: Boolean = false,
)

/**
 * Tracks exposure before forward crossing, using Compose's observed visible rows.
 *
 * A jump in first-visible index is not proof that intervening articles were seen:
 * only rows actually observed in the viewport may become read candidates.
 * Crossings are accumulated during the gesture and emitted once when it ends.
 */
internal class AndroidScrolloverTracker(
    initialFirstVisibleIndex: Int = 0,
) {
    private val orderedIds = mutableListOf<Long>()
    private val emittedIds = mutableSetOf<Long>()

    private var idleFirstVisibleIndex = initialFirstVisibleIndex.coerceAtLeast(0)
    private var idleFirstVisibleOffset = 0
    private var idleAtDatasetEnd = false
    private val idleObservedIndices = mutableSetOf<Int>()

    private var sessionActive = false
    private var sessionStartedAtDatasetEnd = false
    private var lastFirstVisibleIndex = 0
    private var lastFirstVisibleOffset = 0
    private val sessionObservedIndices = mutableSetOf<Int>()
    private val sessionCrossedIds = mutableSetOf<Long>()
    private var programmaticScrollActive = false

    fun updateSnapshot(ids: List<Long>) {
        if (ids.size == orderedIds.size && ids.indices.all { ids[it] == orderedIds[it] }) return

        val previousSize = orderedIds.size
        val appendOnly = ids.size >= previousSize &&
            (0 until previousSize).all { ids[it] == orderedIds[it] }

        if (appendOnly) {
            for (index in previousSize until ids.size) orderedIds += ids[index]
            return
        }

        orderedIds.clear()
        orderedIds.addAll(ids)
        emittedIds.retainAll(ids.toSet())
        resetSession()
        idleObservedIndices.clear()
        idleAtDatasetEnd = false
    }

    fun synchronizeIdlePosition(firstVisibleIndex: Int, firstVisibleOffset: Int = 0) {
        resetSession()
        idleFirstVisibleIndex = firstVisibleIndex.coerceAtLeast(0)
        idleFirstVisibleOffset = firstVisibleOffset.coerceAtLeast(0)
        idleAtDatasetEnd = false
        idleObservedIndices.clear()
    }

    fun beginProgrammaticScroll(firstVisibleIndex: Int, firstVisibleOffset: Int = 0) {
        programmaticScrollActive = true
        synchronizeIdlePosition(firstVisibleIndex, firstVisibleOffset)
    }

    fun endProgrammaticScroll(firstVisibleIndex: Int, firstVisibleOffset: Int = 0) {
        synchronizeIdlePosition(firstVisibleIndex, firstVisibleOffset)
        programmaticScrollActive = false
    }

    fun observe(
        sample: AndroidScrolloverPositionSample,
        scrolling: Boolean,
        enabled: Boolean,
    ): List<Long> {
        val currentIndex = sample.firstVisibleIndex.coerceAtLeast(0)
        val currentOffset = sample.firstVisibleOffset.coerceAtLeast(0)
        val visibleIndices = sample.visibleArticleIndices.filter { it in orderedIds.indices }

        if (!enabled || programmaticScrollActive) {
            if (!scrolling && !programmaticScrollActive) {
                synchronizeIdlePosition(currentIndex, currentOffset)
            }
            return emptyList()
        }

        if (scrolling && !sessionActive) {
            sessionActive = true
            sessionStartedAtDatasetEnd = idleAtDatasetEnd
            lastFirstVisibleIndex = idleFirstVisibleIndex
            lastFirstVisibleOffset = idleFirstVisibleOffset
            sessionObservedIndices.addAll(idleObservedIndices)
        }

        if (!sessionActive) {
            recordIdle(sample, visibleIndices)
            return emptyList()
        }

        val movingForward = currentIndex > lastFirstVisibleIndex ||
            (currentIndex == lastFirstVisibleIndex && currentOffset > lastFirstVisibleOffset)

        if (movingForward) {
            // An article must have been observed BEFORE this crossing. Merely
            // passing over indices in a fast fling never qualifies those rows.
            for (index in sessionObservedIndices) {
                if (index < currentIndex) sessionCrossedIds.add(orderedIds[index])
            }

            // At the genuine end, already visible trailing rows can complete
            // without crossing the top boundary. Never include unseen rows.
            if (sample.atDatasetEnd && !sessionStartedAtDatasetEnd) {
                for (index in visibleIndices) sessionCrossedIds.add(orderedIds[index])
            }
        }

        sessionObservedIndices.addAll(visibleIndices)
        lastFirstVisibleIndex = currentIndex
        lastFirstVisibleOffset = currentOffset

        if (scrolling) return emptyList()

        val candidates = orderedIds.filter { it in sessionCrossedIds && it !in emittedIds }
        emittedIds.addAll(candidates)
        resetSession()
        recordIdle(sample, visibleIndices)
        return candidates
    }

    fun rearm(articleIds: Collection<Long>) {
        emittedIds.removeAll(articleIds.toSet())
    }

    private fun recordIdle(
        sample: AndroidScrolloverPositionSample,
        visibleIndices: List<Int>,
    ) {
        idleFirstVisibleIndex = sample.firstVisibleIndex.coerceAtLeast(0)
        idleFirstVisibleOffset = sample.firstVisibleOffset.coerceAtLeast(0)
        idleAtDatasetEnd = sample.atDatasetEnd
        idleObservedIndices.clear()
        idleObservedIndices.addAll(visibleIndices)
    }

    private fun resetSession() {
        sessionActive = false
        sessionStartedAtDatasetEnd = false
        sessionObservedIndices.clear()
        sessionCrossedIds.clear()
    }
}
