package de.circledev.fluxnews.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Test

class DevelopmentIdentityTest {
    @Test
    fun developmentVariantUsesItsSeparateApplicationId() {
        assertEquals("de.circle_dev.flux_news.native.dev", BuildConfig.APPLICATION_ID)
    }
}
