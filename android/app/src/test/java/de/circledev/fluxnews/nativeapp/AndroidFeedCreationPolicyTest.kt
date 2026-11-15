package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidFeedCreationPolicyTest {
    @Test fun acceptsHttpAndHttpsWithHostsAndTrimsWhitespace() {
        assertEquals("https://example.com/feed.xml", AndroidFeedCreationPolicy.validUrl("  https://example.com/feed.xml  "))
        assertEquals("http://example.org/", AndroidFeedCreationPolicy.validUrl("http://example.org/"))
    }

    @Test fun rejectsInvalidSchemesMissingHostAndCredentials() {
        listOf("", " ", "example.com/feed", "ftp://example.com/rss", "https:///feed", "javascript:alert(1)", "https://user:password@example.com/").forEach {
            assertNull("URL should be rejected: $it", AndroidFeedCreationPolicy.validUrl(it))
        }
    }

    @Test fun categoryNormalizationAndDuplicateDetection() {
        val categories = listOf(AndroidNavigationCategoryRef(1, "Technology"), AndroidNavigationCategoryRef(2, "News"))
        assertEquals("Technology", AndroidFeedCreationPolicy.categoryTitle(" Technology  "))
        assertNull(AndroidFeedCreationPolicy.categoryTitle("\n \t "))
        assertTrue(AndroidFeedCreationPolicy.isDuplicateCategory(" technology ", categories))
        assertFalse(AndroidFeedCreationPolicy.isDuplicateCategory("Science", categories))
    }

    @Test fun errorsRemainActionableAndDoNotLeakServerDetails() {
        assertEquals("This feed is already subscribed.", AndroidFeedCreationPolicy.failureMessage(Exception("409 already subscribed"), true))
        assertTrue(AndroidFeedCreationPolicy.failureMessage(Exception("connection timeout"), false).contains("connect"))
        assertFalse(AndroidFeedCreationPolicy.failureMessage(Exception("api key=secret"), true).contains("secret"))
    }
}
