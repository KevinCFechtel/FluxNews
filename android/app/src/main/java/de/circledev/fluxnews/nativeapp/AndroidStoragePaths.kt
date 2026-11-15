package de.circledev.fluxnews.nativeapp

import android.content.Context
import java.io.File

/** App-private roots supplied to the Core and Android-owned runtime components. */
class AndroidStoragePaths private constructor(
    val persistentData: File,
    val media: File,
    val logs: File,
    val widget: File,
    val cache: File,
) {
    companion object {
        fun create(context: Context): AndroidStoragePaths = fromDirectories(
            context.applicationContext.noBackupFilesDir,
            context.applicationContext.cacheDir,
        )

        internal fun fromDirectories(noBackupFilesDir: File, cacheDir: File): AndroidStoragePaths =
            AndroidStoragePaths(
                persistentData = File(noBackupFilesDir, "flux-native/core"),
                media = File(noBackupFilesDir, "flux-native/media"),
                logs = File(noBackupFilesDir, "flux-native/logs"),
                widget = File(noBackupFilesDir, "flux-native/widget"),
                cache = File(cacheDir, "flux-native/core-cache"),
            ).also { paths ->
                listOf(paths.persistentData, paths.media, paths.logs, paths.widget, paths.cache).forEach {
                    directory -> check(directory.mkdirs() || directory.isDirectory) {
                        "Could not create Flux storage directory: ${directory.absolutePath}"
                    }
                }
            }
    }
}
