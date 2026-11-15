package de.circledev.fluxnews.nativeapp

internal data class AndroidScrolloverPositionSample(
    val firstVisibleIndex: Int,
    val atDatasetEnd: Boolean = false,
)

/**
 * Lightweight Compose-native Scrollover detector.
 *
 * A scroll interaction is summarized by the first-visible index at its start and
 * the highest first-visible index reached before LazyList becomes idle again.
 * Candidates are emitted once, at interaction end. Reverse movement does not erase
 * forward progress, so slow forward/backward movement remains deterministic.
 *
 * Known programmatic scrolls explicitly suppress collection and synchronize the
 * idle baseline afterwards.
 */
internal class AndroidScrolloverTracker(
    initialFirstVisibleIndex: Int = 0,
) {
    private val orderedIds = mutableListOf<Long>()
    private val emittedIds = mutableSetOf<Long>()
    private var idleFirstVisibleIndex: Int = initialFirstVisibleIndex
    private var sessionStartIndex: Int? = null
    private var sessionMaxIndex: Int? = null
    private var sessionReachedDatasetEnd = false
    private var programmaticScrollActive = false

    fun updateSnapshot(ids: List<Long>) {
        if (ids.size == orderedIds.size && ids.indices.all { ids[it] == orderedIds[it] }) return

        val previousSize = orderedIds.size
        val appendOnly = ids.size >= previousSize &&
            (0 until previousSize).all { ids[it] == orderedIds[it] }

        if (appendOnly) {
            for (index in previousSize until ids.size) {
                orderedIds += ids[index]
            }
            return
        }

        orderedIds.clear()
        orderedIds.addAll(ids)
        emittedIds.retainAll(ids.toSet())
        sessionStartIndex = null
        sessionMaxIndex = null
        sessionReachedDatasetEnd = false
    }

    fun synchronizeIdlePosition(firstVisibleIndex: Int) {
        sessionStartIndex = null
        sessionMaxIndex = null
        sessionReachedDatasetEnd = false
        idleFirstVisibleIndex = firstVisibleIndex.coerceAtLeast(0)
    }

    fun beginProgrammaticScroll(firstVisibleIndex: Int) {
        programmaticScrollActive = true
        synchronizeIdlePosition(firstVisibleIndex)
    }

    fun endProgrammaticScroll(firstVisibleIndex: Int) {
        synchronizeIdlePosition(firstVisibleIndex)
        programmaticScrollActive = false
    }

    fun observe(
        sample: AndroidScrolloverPositionSample,
        scrolling: Boolean,
        enabled: Boolean,
    ): List<Long> {
        val currentIndex = sample.firstVisibleIndex.coerceAtLeast(0)

        if (!enabled || programmaticScrollActive) {
            if (!scrolling && !programmaticScrollActive) {
                synchronizeIdlePosition(currentIndex)
            }
            return emptyList()
        }

        if (scrolling) {
            if (sessionStartIndex == null) {
                sessionStartIndex = idleFirstVisibleIndex
                sessionMaxIndex = maxOf(idleFirstVisibleIndex, currentIndex)
            } else {
                sessionMaxIndex = maxOf(sessionMaxIndex ?: currentIndex, currentIndex)
            }
            if (sample.atDatasetEnd) sessionReachedDatasetEnd = true
            return emptyList()
        }

        val start = sessionStartIndex
        val maxReached = sessionMaxIndex
        val reachedDatasetEnd = sessionReachedDatasetEnd || sample.atDatasetEnd
        sessionStartIndex = null
        sessionMaxIndex = null
        sessionReachedDatasetEnd = false
        idleFirstVisibleIndex = currentIndex

        if (start == null || maxReached == null) return emptyList()

        val startIndex = start.coerceIn(0, orderedIds.size)
        val endExclusive = if (reachedDatasetEnd) {
            orderedIds.size
        } else {
            maxReached.coerceIn(startIndex, orderedIds.size)
        }
        if (startIndex >= endExclusive) return emptyList()

        val candidates = buildList {
            for (index in startIndex until endExclusive) {
                val id = orderedIds[index]
                if (id !in emittedIds) add(id)
            }
        }
        emittedIds.addAll(candidates)
        return candidates
    }

    fun rearm(articleIds: Collection<Long>) {
        emittedIds.removeAll(articleIds.toSet())
    }
}
