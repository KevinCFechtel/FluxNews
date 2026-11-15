package de.circledev.fluxnews.nativeapp

import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.flux_uniffi.ArticleQuery
import uniffi.flux_uniffi.ArticleScope
import uniffi.flux_uniffi.ArticleSort
import uniffi.flux_uniffi.CoreEvent
import uniffi.flux_uniffi.EventListener
import uniffi.flux_uniffi.Flux
import uniffi.flux_uniffi.FluxException
import uniffi.flux_uniffi.InitializationConfig
import uniffi.flux_uniffi.ReadFilter
import uniffi.flux_uniffi.StarredFilter

@RunWith(AndroidJUnit4::class)
class UniFFIRuntimeSmokeTest {
    @Test
    fun initializeAndQueryLocalCore() = withFlux { flux ->
        assertEquals("de.circle_dev.flux_news.native.dev", BuildConfig.APPLICATION_ID)
        assertFalse(Looper.myLooper() == Looper.getMainLooper())

        val count = flux.countArticles(
            ArticleQuery(
                scope = ArticleScope.All,
                readFilter = ReadFilter.ALL,
                starredFilter = StarredFilter.ALL,
                sort = ArticleSort.NEWEST_FIRST,
                limit = 0u,
                cursor = null,
            ),
        )

        assertEquals(0uL, count)
    }

    @Test
    fun typedErrorCrossesUniFFIBoundary() = withFlux { flux ->
        try {
            flux.createCategory("")
            fail("Expected an empty category title to be rejected locally.")
        } catch (error: FluxException.Data) {
            assertEquals("category title must not be empty", error.detail)
        }
    }

    @Test
    fun eventSubscriptionCanBeCreatedAndCleanedUp() = withFlux { flux ->
        val listener = object : EventListener {
            override fun onEvent(event: CoreEvent) = Unit
        }
        val subscription = flux.subscribeEvents(listener)

        try {
            subscription.unsubscribe()
        } finally {
            subscription.close()
        }
    }

    private fun <T> withFlux(block: (Flux) -> T): T {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "uniffi-runtime-smoke/${UUID.randomUUID()}")
        val persistentData = File(root, "persistent-data")
        val cache = File(root, "cache")
        val media = File(root, "media")
        check(persistentData.mkdirs() && cache.mkdirs() && media.mkdirs())

        var flux: Flux? = null
        try {
            flux = Flux.initialize(
                InitializationConfig(
                    persistentData = persistentData.absolutePath,
                    cache = cache.absolutePath,
                    media = media.absolutePath,
                    baseUrl = "https://runtime-smoke.invalid",
                    apiKey = "runtime-smoke-api-key",
                    customHeaders = emptyList(),
                ),
            )
            return block(flux)
        } finally {
            flux?.close()
            root.deleteRecursively()
        }
    }
}
