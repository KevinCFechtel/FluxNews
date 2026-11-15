package de.circledev.fluxnews.nativeapp

import android.os.Looper
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.flux_uniffi.ArticleQuery
import uniffi.flux_uniffi.ArticleScope
import uniffi.flux_uniffi.ArticleSort
import uniffi.flux_uniffi.InitializationConfig
import uniffi.flux_uniffi.ReadFilter
import uniffi.flux_uniffi.StarredFilter

@RunWith(AndroidJUnit4::class)
class AndroidCoreRuntimeTest {
    @Test
    fun processRuntimeOwnsOneSessionAcrossActivityRecreationAndClosesCleanly() = runBlocking {
        val application = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as FluxApplication
        val runtime = application.coreRuntime
        runtime.closeSession()
        val root = testRoot(application.cacheDir)
        val sessionConfig = config(root)

        try {
            val firstGeneration = runtime.openSession(sessionConfig)
            assertTrue(runtime.hasActiveSession())

            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                assertSame(runtime, scenario.withActivity { (it.application as FluxApplication).coreRuntime })
                scenario.recreate()
                assertSame(runtime, scenario.withActivity { (it.application as FluxApplication).coreRuntime })
            }

            val localThread = runtime.local { flux ->
                assertFalse(Looper.myLooper() == Looper.getMainLooper())
                flux.countArticles(query())
                Thread.currentThread().name
            }
            assertTrue(localThread.startsWith("FluxCore-local"))

            val remoteThread = runtime.remote { flux ->
                assertFalse(Looper.myLooper() == Looper.getMainLooper())
                flux.navigationCatalog()
                Thread.currentThread().name
            }
            assertTrue(remoteThread.startsWith("FluxCore-remote"))

            val remoteStarted = CountDownLatch(1)
            val releaseRemote = CountDownLatch(1)
            val remoteWork = async(Dispatchers.Default) {
                runtime.remote {
                    remoteStarted.countDown()
                    check(releaseRemote.await(10, TimeUnit.SECONDS))
                }
            }
            assertTrue(remoteStarted.await(10, TimeUnit.SECONDS))
            assertEquals(0uL, runtime.local { it.countArticles(query()) })
            releaseRemote.countDown()
            remoteWork.await()

            val secondGeneration = runtime.replaceSession(sessionConfig)
            assertTrue(secondGeneration > firstGeneration)
            assertEquals(0uL, runtime.local { it.countArticles(query()) })

            runtime.closeSession()
            assertFalse(runtime.hasActiveSession())
            try {
                runtime.local { it.countArticles(query()) }
                fail("Expected Core work without a session to fail.")
            } catch (error: IllegalStateException) {
                assertEquals("No active Core session.", error.message)
            }

        } finally {
            runtime.closeSession()
            root.deleteRecursively()
        }
    }

    private fun <T> ActivityScenario<MainActivity>.withActivity(block: (MainActivity) -> T): T {
        var result: T? = null
        onActivity { result = block(it) }
        @Suppress("UNCHECKED_CAST")
        return result as T
    }

    private fun testRoot(cacheDir: File): File = File(
        cacheDir,
        "core-runtime/${UUID.randomUUID()}",
    ).also { check(it.mkdirs()) }

    private fun config(root: File): InitializationConfig {
        val persistentData = File(root, "persistent-data")
        val cache = File(root, "cache")
        val media = File(root, "media")
        check(persistentData.mkdirs() && cache.mkdirs() && media.mkdirs())
        return InitializationConfig(
            persistentData = persistentData.absolutePath,
            cache = cache.absolutePath,
            media = media.absolutePath,
            baseUrl = "https://core-runtime.invalid",
            apiKey = "test-api-key",
            customHeaders = emptyList(),
        )
    }

    private fun query() = ArticleQuery(
        scope = ArticleScope.All,
        readFilter = ReadFilter.ALL,
        starredFilter = StarredFilter.ALL,
        sort = ArticleSort.NEWEST_FIRST,
        limit = 0u,
        cursor = null,
    )
}
