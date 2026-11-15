package de.circledev.fluxnews.nativeapp

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidStoragePathsTest {
    @Test
    fun usesIsolatedNoBackupAndCacheRoots() {
        val root = Files.createTempDirectory("flux-storage-paths").toFile()
        try {
            val noBackup = File(root, "no-backup")
            val cache = File(root, "cache")
            check(noBackup.mkdirs() && cache.mkdirs())

            val paths = AndroidStoragePaths.fromDirectories(noBackup, cache)

            assertEquals(File(noBackup, "flux-native/core"), paths.persistentData)
            assertEquals(File(noBackup, "flux-native/media"), paths.media)
            assertEquals(File(noBackup, "flux-native/logs"), paths.logs)
            assertEquals(File(noBackup, "flux-native/widget"), paths.widget)
            assertEquals(File(cache, "flux-native/core-cache"), paths.cache)
            listOf(paths.persistentData, paths.media, paths.logs, paths.widget, paths.cache).forEach {
                assertTrue(it.isDirectory)
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
