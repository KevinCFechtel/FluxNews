package de.circledev.fluxnews.nativeapp

import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.flux_uniffi.AccountValidationResult
import uniffi.flux_uniffi.InitializationConfig

class AndroidAccountBootstrapTest {
    @Test
    fun missingCredentialsRequireAccountWithoutOpeningCore() = withPaths { paths ->
        var opened = false
        val bootstrap = bootstrap(paths, credentialReader = { null }) { opened = true }
        val state = runBlocking { bootstrap.restoreStoredAccount() }
        assertEquals(AndroidAccountBootstrap.State.AccountRequired, state)
        assertFalse(opened)
    }

    @Test
    fun storedCredentialsOpenCanonicalCoreSession() = withPaths { paths ->
        val credentials = credentials("https://miniflux.example/subpath", "secret")
        var opened: InitializationConfig? = null
        val bootstrap = bootstrap(paths, credentialReader = { credentials }) { opened = it }
        val state = runBlocking { bootstrap.restoreStoredAccount() }
        assertEquals(AndroidAccountBootstrap.State.Ready(credentials.serverUrl), state)
        assertEquals(paths.persistentData.absolutePath, opened?.persistentData)
        assertEquals(paths.cache.absolutePath, opened?.cache)
        assertEquals(paths.media.absolutePath, opened?.media)
        assertEquals(credentials.serverUrl, opened?.baseUrl)
        assertEquals(credentials.apiKey, opened?.apiKey)
        assertEquals("X-Tenant", opened?.customHeaders?.single()?.name)
        assertEquals("tenant-secret", opened?.customHeaders?.single()?.value)
    }

    @Test
    fun credentialFailureIsRecoverableAndDoesNotExposeSecret() = withPaths { paths ->
        val secret = "must-not-leak"
        val bootstrap = bootstrap(
            paths,
            credentialReader = { throw CredentialStorageException("failed: $secret") },
        ) { error("Core must not open") }
        val state = runBlocking { bootstrap.restoreStoredAccount() }
        assertTrue(state is AndroidAccountBootstrap.State.RecoverableError)
        val message = (state as AndroidAccountBootstrap.State.RecoverableError).message
        assertEquals("Stored account credentials could not be read.", message)
        assertFalse(message.contains(secret))
    }

    @Test
    fun existingSessionIsNotOpenedAgain() = withPaths { paths ->
        var opens = 0
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { error("Credentials must not be reread") },
            hasActiveSession = { true },
            sessionOpener = { opens += 1 },
            storagePaths = paths,
            testOnly = Unit,
        )
        val state = runBlocking { bootstrap.restoreStoredAccount() }
        assertEquals(AndroidAccountBootstrap.State.Starting, state)
        assertEquals(0, opens)
    }

    @Test
    fun validatedAccountUsesCanonicalBasePersistsAndOpensSession() = withPaths { paths ->
        var stored: StoredAccountCredentials? = null
        var opened: InitializationConfig? = null
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { stored },
            credentialWriter = { stored = it },
            hasActiveSession = { false },
            sessionOpener = { opened = it },
            accountValidator = { server, apiKey, headers ->
                assertEquals("https://example.test/miniflux/", server)
                assertEquals("token", apiKey)
                assertEquals("X-Tenant", headers.single().name)
                AccountValidationResult("https://example.test/miniflux", "2.2.0")
            },
            storagePaths = paths,
            testOnly = Unit,
        )

        val result = runBlocking {
            bootstrap.activateAccount(
                " https://example.test/miniflux/ ",
                " token ",
                listOf(StoredCredentialHeader("X-Tenant", "tenant-secret")),
            )
        }

        assertEquals(
            AndroidAccountBootstrap.ActivationResult.Activated(
                "https://example.test/miniflux",
                "2.2.0",
            ),
            result,
        )
        assertEquals("https://example.test/miniflux", stored?.serverUrl)
        assertEquals("token", stored?.apiKey)
        assertEquals("https://example.test/miniflux", opened?.baseUrl)
        assertEquals(AndroidAccountBootstrap.State.Ready("https://example.test/miniflux", "2.2.0"), bootstrap.state)
    }

    @Test
    fun existingSessionUsesReplacementPath() = withPaths { paths ->
        val previous = credentials("https://old.example", "old-token")
        var stored: StoredAccountCredentials? = previous
        var opened = 0
        var replaced: InitializationConfig? = null
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { stored },
            credentialWriter = { stored = it },
            hasActiveSession = { true },
            sessionOpener = { opened += 1 },
            sessionReplacer = { replaced = it },
            accountValidator = { _, _, _ -> AccountValidationResult("https://new.example", "2.2.0") },
            storagePaths = paths,
            testOnly = Unit,
        )
        val result = runBlocking { bootstrap.activateAccount("https://new.example", "new-token", emptyList()) }
        assertTrue(result is AndroidAccountBootstrap.ActivationResult.Activated)
        assertEquals(0, opened)
        assertEquals("https://new.example", replaced?.baseUrl)
        assertEquals("https://new.example", stored?.serverUrl)
    }

    @Test
    fun replacementFailureRestoresPreviousCredentials() = withPaths { paths ->
        val previous = credentials("https://old.example", "old-token")
        var stored: StoredAccountCredentials? = previous
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { stored },
            credentialWriter = { stored = it },
            hasActiveSession = { true },
            sessionOpener = {},
            sessionReplacer = { error("replacement failed with new-token") },
            accountValidator = { _, _, _ -> AccountValidationResult("https://new.example", "2.2.0") },
            storagePaths = paths,
            testOnly = Unit,
        )
        val result = runBlocking { bootstrap.activateAccount("https://new.example", "new-token", emptyList()) }
        assertEquals(previous, stored)
        assertTrue(result is AndroidAccountBootstrap.ActivationResult.Rejected)
        assertFalse((result as AndroidAccountBootstrap.ActivationResult.Rejected).message.contains("new-token"))
    }

    @Test
    fun firstActivationFailureClearsNewCredentials() = withPaths { paths ->
        var stored: StoredAccountCredentials? = null
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { stored },
            credentialWriter = { stored = it },
            credentialClearer = { stored = null },
            hasActiveSession = { false },
            sessionOpener = { error("open failed") },
            accountValidator = { _, _, _ -> AccountValidationResult("https://new.example", "2.2.0") },
            storagePaths = paths,
            testOnly = Unit,
        )
        val result = runBlocking { bootstrap.activateAccount("https://new.example", "new-token", emptyList()) }
        assertEquals(null, stored)
        assertTrue(result is AndroidAccountBootstrap.ActivationResult.Rejected)
    }


    @Test
    fun mediaLifecycleWrapsAccountReplacement() = withPaths { paths ->
        val calls = mutableListOf<String>()
        var stored: StoredAccountCredentials? = credentials("old", "old-token")
        val lifecycle = recordingLifecycle(calls)
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { stored },
            credentialWriter = { stored = it },
            hasActiveSession = { true },
            sessionOpener = {},
            sessionReplacer = { calls += "replace" },
            accountValidator = { _, _, _ -> AccountValidationResult("https://new.example", "2.2.0") },
            lifecycleParticipant = lifecycle,
            storagePaths = paths,
            testOnly = Unit,
        )

        val result = runBlocking {
            bootstrap.activateAccount("https://new.example", "new-token", emptyList())
        }

        assertTrue(result is AndroidAccountBootstrap.ActivationResult.Activated)
        assertEquals(
            listOf(
                "prepare:AccountReplacement",
                "replace",
                "resume:AccountReplacement",
            ),
            calls,
        )
    }

    @Test
    fun mediaLifecycleWrapsLocalStateRebuildAndResumesOnFailure() = withPaths { paths ->
        val calls = mutableListOf<String>()
        val bootstrap = AndroidAccountBootstrap(
            credentialReader = { credentials("old", "old-token") },
            hasActiveSession = { true },
            sessionOpener = {},
            localStateRebuilder = {
                calls += "rebuild"
                error("rebuild failed")
            },
            lifecycleParticipant = recordingLifecycle(calls),
            storagePaths = paths,
            testOnly = Unit,
        )

        val result = runBlocking { bootstrap.rebuildLocalState() }

        assertEquals(AndroidAccountBootstrap.LocalStateRebuildState.Failed, result)
        assertEquals(
            listOf(
                "prepare:LocalStateRebuild",
                "rebuild",
                "resume:LocalStateRebuild",
            ),
            calls,
        )
    }

    private fun recordingLifecycle(calls: MutableList<String>) =
        object : AndroidCoreLifecycleParticipant {
            override suspend fun prepareForCoreLifecycleChange(change: AndroidCoreLifecycleChange) {
                calls += "prepare:${change.name}"
            }

            override suspend fun resumeAfterCoreLifecycleChange(change: AndroidCoreLifecycleChange) {
                calls += "resume:${change.name}"
            }
        }

    private fun bootstrap(
        paths: AndroidStoragePaths,
        credentialReader: () -> StoredAccountCredentials?,
        sessionOpener: suspend (InitializationConfig) -> Unit,
    ) = AndroidAccountBootstrap(
        credentialReader = credentialReader,
        hasActiveSession = { false },
        sessionOpener = sessionOpener,
        storagePaths = paths,
        testOnly = Unit,
    )

    private fun credentials(server: String, token: String) = StoredAccountCredentials(
        serverUrl = server,
        apiKey = token,
        customHeaders = listOf(StoredCredentialHeader("X-Tenant", "tenant-secret")),
    )

    private fun withPaths(block: (AndroidStoragePaths) -> Unit) {
        val root = Files.createTempDirectory("flux-account-bootstrap").toFile()
        try {
            val noBackup = File(root, "no-backup").also { check(it.mkdirs()) }
            val cache = File(root, "cache").also { check(it.mkdirs()) }
            block(AndroidStoragePaths.fromDirectories(noBackup, cache))
        } finally {
            root.deleteRecursively()
        }
    }
}
