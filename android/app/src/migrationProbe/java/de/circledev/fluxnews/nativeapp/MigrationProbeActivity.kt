package de.circledev.fluxnews.nativeapp

import android.app.Activity
import android.os.Bundle
import java.io.File

/** Explicit E1-F-only entry point. It neither initializes Core nor writes native stores. */
class MigrationProbeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val result = LegacyAndroidStateReader(applicationContext).readProbe()
        File(cacheDir, REPORT_FILE_NAME).writeText(result.toJson())
        finish()
    }

    companion object {
        const val REPORT_FILE_NAME = "legacy-migration-probe.json"
    }
}
