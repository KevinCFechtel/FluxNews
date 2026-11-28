package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidArticleTagsTest {
    private fun fit(first: Int = 70, total: Int = 5, width: Int = 100, minimum: Int = 30) =
        AndroidArticleTagPolicy.layout(first, minimum, total, width, spacing = 4, iconWidth = 12) {
            if (it < 10) 20 else 30
        }

    @Test
    fun absentTagsAndInsufficientResidualWidthProduceNoPixels() {
        assertEquals(AndroidArticleTagLayout(), fit(total = 0))
        assertEquals(AndroidArticleTagLayout(), fit(width = 0))
        assertEquals(AndroidArticleTagLayout(), fit(width = 35))
    }

    @Test
    fun oneNameAtMostEvenWithUnlimitedSpace() {
        assertEquals(AndroidArticleTagLayout(1, 70, showsOverflow = true, showsIcon = true), fit(width = 1000))
        assertEquals(AndroidArticleTagLayout(1, 70, showsIcon = true), fit(total = 1))
    }

    @Test
    fun oversizedNameReservesTheCounterBeforeEllipsizing() {
        assertEquals(AndroidArticleTagLayout(1, 60, showsOverflow = true, showsIcon = true), fit(first = 300))
        assertEquals(AndroidArticleTagLayout(1, 84, showsIcon = true), fit(first = 300, total = 1))
    }

    @Test
    fun unreadableNameFallsBackToSymbolAndTotalCount() {
        assertEquals(AndroidArticleTagLayout(showsOverflow = true, showsIcon = true), fit(width = 69))
        assertEquals(AndroidArticleTagLayout(1, 30, showsOverflow = true, showsIcon = true), fit(width = 70))
    }

    @Test
    fun reservesSymbolForBothNameAndCounterOnlyInEveryStyle() {
        assertEquals(AndroidArticleTagLayout(1, 60, showsOverflow = true, showsIcon = true), fit())
        assertEquals(AndroidArticleTagLayout(showsOverflow = true, showsIcon = true), fit(width = 36))
        assertEquals(AndroidArticleTagLayout(), fit(width = 35))
        assertEquals(AndroidArticleTagLayout(1, 20, showsIcon = true), fit(first = 20, total = 1, width = 36))
        assertEquals(AndroidArticleTagLayout(showsOverflow = true, showsIcon = true), fit(total = 1, width = 36))
    }

    @Test
    fun fontScalingAndCounterDigitCountAffectActualFit() {
        assertEquals(AndroidArticleTagLayout(1, 70, showsOverflow = true, showsIcon = true), fit(first = 100, width = 110, minimum = 60))
        assertEquals(AndroidArticleTagLayout(showsOverflow = true, showsIcon = true), fit(first = 100, width = 110, minimum = 80))
        assertEquals(AndroidArticleTagLayout(1, 30, showsOverflow = true, showsIcon = true), fit(total = 10, width = 70))
        assertEquals(AndroidArticleTagLayout(showsOverflow = true, showsIcon = true), fit(total = 11, width = 70))
    }

    @Test
    fun normalizeLabelsWithoutChangingRemoteMetadata() {
        assertEquals(listOf("Science news", "Space"), AndroidArticleTagPolicy.labels(listOf(" Science\nnews ", "", "Science news", "Space")))
    }
}
