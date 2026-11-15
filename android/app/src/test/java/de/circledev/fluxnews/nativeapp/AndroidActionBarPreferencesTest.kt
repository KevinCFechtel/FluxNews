package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidActionBarPreferencesTest {
    @Test
    fun starredScopeHidesReadFilterButKeepsSortControls() {
        assertFalse(
            AndroidArticleListActionPolicy.isAvailable(
                action = AndroidActionBarAction.ToggleReadFilter,
                scope = AndroidNewsScope.Starred,
                hasNextScope = false,
            ),
        )
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                action = AndroidActionBarAction.ToggleSortOrder,
                scope = AndroidNewsScope.Starred,
                hasNextScope = false,
            ),
        )
        assertTrue(
            AndroidArticleListActionPolicy.isAvailable(
                action = AndroidActionBarAction.FilterAndSort,
                scope = AndroidNewsScope.Starred,
                hasNextScope = false,
            ),
        )
    }
}
