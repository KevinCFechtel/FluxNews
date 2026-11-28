package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidArticleTagsTest {
    private fun fit(widths: List<Int>, total: Int = widths.size, width: Int = 300) =
        AndroidArticleTagPolicy.layout(widths, total, width, spacing = 5) { hidden ->
            if (hidden < 10) 20 else 30
        }

    @Test
    fun absentTagsNeedNoRow() {
        assertEquals(AndroidArticleTagLayout(0), fit(emptyList()))
        assertEquals(AndroidArticleTagLayout(0), fit(listOf(50), width = 0))
    }

    @Test
    fun capsVisibleTagsEvenOnWideScreens() {
        assertEquals(AndroidArticleTagLayout(3), fit(listOf(40, 40, 40), total = 12, width = 1000))
        assertEquals(AndroidArticleTagLayout(3), fit(listOf(40, 40, 40)))
    }

    @Test
    fun fitsByActualWidthAndReservesOverflow() {
        assertEquals(AndroidArticleTagLayout(2), fit(listOf(70, 70, 70), total = 5, width = 170))
        assertEquals(AndroidArticleTagLayout(1), fit(listOf(70, 70, 70), total = 5, width = 169))
        assertEquals(AndroidArticleTagLayout(2), fit(listOf(70, 70), width = 145))
        assertEquals(AndroidArticleTagLayout(1), fit(listOf(70, 70), width = 144))
    }

    @Test
    fun oversizedFirstTagIsEllipsizedRatherThanWrapped() {
        assertEquals(
            AndroidArticleTagLayout(1, firstTagMaxWidth = 75),
            fit(listOf(300, 40), width = 100),
        )
        assertEquals(
            AndroidArticleTagLayout(1, firstTagMaxWidth = 100),
            fit(listOf(300), width = 100),
        )
    }

    @Test
    fun veryNarrowWidthsShowOnlyTheOverflowCount() {
        assertEquals(AndroidArticleTagLayout(0), fit(listOf(40, 40), width = 20))
    }

    @Test
    fun largerFontMetricsReduceCountWithoutChangingTheSingleRowContract() {
        assertEquals(AndroidArticleTagLayout(3), fit(listOf(40, 50, 60), total = 4, width = 190))
        assertEquals(AndroidArticleTagLayout(1), fit(listOf(80, 100, 120), total = 4, width = 190))
    }

    @Test
    fun reservesTheWidthOfTheActualOverflowCount() {
        assertEquals(AndroidArticleTagLayout(2), fit(listOf(50, 50, 50), total = 11, width = 130))
        assertEquals(AndroidArticleTagLayout(1), fit(listOf(50, 50, 50), total = 12, width = 130))
    }
}
