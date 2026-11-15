package de.circledev.fluxnews.nativeapp

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidInitializationConfigFactoryTest {
    @Test
    fun mapsOnlyCanonicalStoragePathsAndStoredCredentials() {
        val root = Files.createTempDirectory("flux-init-config").toFile()
        try {
            val noBackup = File(root, "no-backup").also { check(it.mkdirs()) }
            val cacheRoot = File(root, "cache").also { check(it.mkdirs()) }
            val paths = AndroidStoragePaths.fromDirectories(noBackup, cacheRoot)
            val credentials = StoredAccountCredentials(
                serverUrl = "https://miniflux.example/subpath",
                apiKey = "secret-api-key",
                customHeaders = listOf(
                    StoredCredentialHeader("X-Tenant", "tenant-secret"),
                    StoredCredentialHeader("Authorization", "proxy-secret"),
                ),
            )

            val config = AndroidInitializationConfigFactory(paths).create(credentials)

            assertEquals(paths.persistentData.absolutePath, config.persistentData)
            assertEquals(paths.cache.absolutePath, config.cache)
            assertEquals(paths.media.absolutePath, config.media)
            assertEquals(credentials.serverUrl, config.baseUrl)
            assertEquals(credentials.apiKey, config.apiKey)
            assertEquals(2, config.customHeaders.size)
            assertEquals("X-Tenant", config.customHeaders[0].name)
            assertEquals("tenant-secret", config.customHeaders[0].value)
            assertEquals("Authorization", config.customHeaders[1].name)
            assertEquals("proxy-secret", config.customHeaders[1].value)
        } finally {
            root.deleteRecursively()
        }
    }
}
