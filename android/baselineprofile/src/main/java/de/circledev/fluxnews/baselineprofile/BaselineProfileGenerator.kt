package de.circledev.fluxnews.baselineprofile

import android.content.ComponentName
import android.content.Intent
import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BaselineProfileGenerator {
    @get:Rule
    val baselineProfileRule = BaselineProfileRule()

    @Test
    fun startup() = baselineProfileRule.collect(
        packageName = DEVELOPMENT_PACKAGE,
        includeInStartupProfile = true,
    ) {
        pressHome()
        startActivityAndWait()
    }

    @Test
    fun timelineScroll() = baselineProfileRule.collect(
        packageName = DEVELOPMENT_PACKAGE,
        includeInStartupProfile = false,
    ) {
        pressHome()
        startActivityAndWait(timelineFixtureIntent())

        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.waitForIdle()

        val centerX = device.displayWidth / 2
        val startY = (device.displayHeight * 0.78f).toInt()
        val endY = (device.displayHeight * 0.30f).toInt()
        repeat(TIMELINE_SCROLLS) {
            check(device.swipe(centerX, startY, centerX, endY, SWIPE_STEPS)) {
                "Benchmark Timeline swipe could not be injected."
            }
            device.waitForIdle()
        }
    }

    private fun timelineFixtureIntent(): Intent =
        Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName(DEVELOPMENT_PACKAGE, MAIN_ACTIVITY)
            putExtra(TIMELINE_EXTRA, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }

    private companion object {
        const val DEVELOPMENT_PACKAGE = "de.circle_dev.flux_news.native.dev"
        const val MAIN_ACTIVITY = "de.circledev.fluxnews.nativeapp.MainActivity"
        const val TIMELINE_EXTRA = "flux.baselineProfile.timeline"
        const val TIMELINE_SCROLLS = 5
        const val SWIPE_STEPS = 24
    }
}
