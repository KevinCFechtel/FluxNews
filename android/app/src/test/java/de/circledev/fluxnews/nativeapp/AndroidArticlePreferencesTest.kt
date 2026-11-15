package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidArticlePreferencesTest {
    @Test
    fun storedValueFallbacksMatchNativeMobileDefaults() {
        assertEquals(AndroidArticleOpenPreference.OriginalLink, AndroidArticleOpenPreference.fromStoredValue("unknown"))
        assertEquals(AndroidArticlePresentationMode.Visual, AndroidArticlePresentationMode.fromStoredValue("unknown"))
        assertEquals(AndroidArticlePreviewLines.Standard, AndroidArticlePreviewLines.fromStoredValue(999))
    }

    @Test
    fun defaultStateMatchesSharedArticlePresentationBaseline() {
        val state = AndroidArticlePreferenceState()
        assertEquals(AndroidArticleOpenPreference.OriginalLink, state.openArticle)
        assertEquals(AndroidArticlePresentationMode.Visual, state.presentationMode)
        assertEquals(AndroidArticlePreviewLines.Standard, state.previewLines)
        assertTrue(state.showArticleCount)
        assertFalse(state.showRelativePublicationTime)
        assertFalse(state.removeArticlesWhenRead)
        assertTrue(state.markReadOnScrollover)
    }

    @Test
    fun previewLineChoicesRemainTwoThreeAndFive() {
        assertEquals(listOf(2, 3, 5), AndroidArticlePreviewLines.entries.map { it.lineCount })
    }
}
