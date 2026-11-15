package de.circledev.fluxnews.nativeapp

import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.datastore.preferences.preferencesDataStoreFile
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidStorageRuntimeTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext

    @Test
    fun credentialsRoundTripPersistTamperFailAndClearWithoutPlaintext() {
        val alias = "${context.packageName}.storage-test.${UUID.randomUUID()}"
        val store = AndroidCredentialStore(context, "credentials-${UUID.randomUUID()}", alias)
        val credentials = credentials()
        try {
            assertNull(store.read())
            store.write(credentials)
            assertEquals(credentials, store.read())

            val envelope = store.encryptedFile.readText()
            assertFalse(envelope.contains(credentials.serverUrl))
            assertFalse(envelope.contains(credentials.apiKey))
            assertFalse(envelope.contains(credentials.customHeaders.single().value))

            assertKeyAuthorization(alias)
            val relaunched = AndroidCredentialStore(context, store.encryptedFile.name, alias)
            assertEquals(credentials, relaunched.read())

            relaunched.write(credentials.copy(apiKey = "replacement-key"))
            assertEquals("replacement-key", relaunched.read()?.apiKey)

            tamperCiphertext(relaunched)
            assertStorageFailure("Credential envelope authentication failed.") { relaunched.read() }

            relaunched.clear()
            relaunched.clear()
            assertNull(relaunched.read())
            assertFalse(KeyStore.getInstance(AndroidCredentialStore.KEYSTORE).apply { load(null) }.containsAlias(alias))
        } finally {
            store.clear()
        }
    }

    @Test
    fun malformedAndUnsupportedCredentialEnvelopesAreExplicitFailures() {
        val store = AndroidCredentialStore(
            context,
            "credentials-${UUID.randomUUID()}",
            "${context.packageName}.storage-test.${UUID.randomUUID()}",
        )
        try {
            store.encryptedFile.parentFile?.mkdirs()
            store.encryptedFile.writeText("{")
            assertStorageFailure("Credential envelope is malformed.") { store.read() }

            store.encryptedFile.writeText(
                JSONObject()
                    .put("version", 99)
                    .put("iv", Base64.encodeToString(ByteArray(12), Base64.NO_WRAP))
                    .put("ciphertext", Base64.encodeToString(ByteArray(16), Base64.NO_WRAP))
                    .toString(),
            )
            assertStorageFailure("Credential envelope version is unsupported.") { store.read() }
        } finally {
            store.clear()
        }
    }

    @Test
    fun storesWorkFromApplicationContextOnBackgroundThreads() = runBlocking {
        val credentialStore = AndroidCredentialStore(
            context,
            "credentials-${UUID.randomUUID()}",
            "${context.packageName}.storage-test.${UUID.randomUUID()}",
        )
        val preferenceFile = "preferences-${UUID.randomUUID()}.preferences_pb"
        val preferenceStore = AndroidPreferenceStore.create(context, preferenceFile)
        val preference = AndroidPreferenceKey.boolean("background-sync-enabled")
        val executor = Executors.newSingleThreadExecutor()
        try {
            credentialStore.write(credentials())
            preferenceStore.write(preference, true)
            val result = executor.submit<Pair<StoredAccountCredentials?, Boolean>> {
                credentialStore.read() to runBlocking { preferenceStore.read(preference, false) }
            }.get()
            assertEquals(credentials(), result.first)
            assertTrue(result.second)
        } finally {
            executor.shutdownNow()
            preferenceStore.close()
            credentialStore.clear()
            context.preferencesDataStoreFile(preferenceFile).delete()
        }
    }

    @Test
    fun preferencesAreTypedAsyncPersistentAndRejectCredentialNames() = runBlocking {
        val fileName = "preferences-${UUID.randomUUID()}.preferences_pb"
        val enabled = AndroidPreferenceKey.boolean("background-sync-enabled")
        val title = AndroidPreferenceKey.string("timeline-title")
        var firstStore = AndroidPreferenceStore.create(context, fileName)
        try {
            assertFalse(firstStore.read(enabled, false))
            firstStore.write(enabled, true)
            firstStore.write(title, "first")
            assertEquals(true, firstStore.observe(enabled, false).first())
            firstStore.write(title, "second")
            assertEquals("second", firstStore.read(title, "missing"))
            firstStore.remove(title)
            assertEquals("missing", firstStore.read(title, "missing"))
        } finally {
            firstStore.close()
        }

        // Closing the first scope avoids a second active DataStore for this file.
        val relaunchedStore = AndroidPreferenceStore.create(context, fileName)
        try {
            assertTrue(relaunchedStore.read(enabled, false))
            assertStorageFailure("Sensitive account material must use AndroidCredentialStore.") {
                AndroidPreferenceKey.string("apiKey")
            }
            assertStorageFailure("Sensitive account material must use AndroidCredentialStore.") {
                AndroidPreferenceKey.string("customHeaders")
            }
            assertStorageFailure("Sensitive account material must use AndroidCredentialStore.") {
                AndroidPreferenceKey.string("encryptedCredentialPayload")
            }
        } finally {
            relaunchedStore.close()
            context.preferencesDataStoreFile(fileName).delete()
        }
    }

    private fun assertKeyAuthorization(alias: String) {
        val keyStore = KeyStore.getInstance(AndroidCredentialStore.KEYSTORE).apply { load(null) }
        val key = keyStore.getKey(alias, null) as? SecretKey
        assertNotNull(key)
        val secretKey = requireNotNull(key)
        assertEquals(KeyProperties.KEY_ALGORITHM_AES, secretKey.algorithm)
        val info = SecretKeyFactory.getInstance(secretKey.algorithm, AndroidCredentialStore.KEYSTORE)
            .getKeySpec(secretKey, KeyInfo::class.java) as KeyInfo
        assertEquals(
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            info.purposes and (KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT),
        )
        assertTrue(info.blockModes.contains(KeyProperties.BLOCK_MODE_GCM))
        assertTrue(info.encryptionPaddings.contains(KeyProperties.ENCRYPTION_PADDING_NONE))
        assertFalse(info.isUserAuthenticationRequired)
    }

    private fun tamperCiphertext(store: AndroidCredentialStore) {
        val envelope = JSONObject(store.encryptedFile.readText())
        val ciphertext = Base64.decode(envelope.getString("ciphertext"), Base64.NO_WRAP)
        ciphertext[0] = (ciphertext[0].toInt() xor 1).toByte()
        envelope.put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
        store.encryptedFile.writeText(envelope.toString())
    }

    private fun assertStorageFailure(message: String, block: () -> Unit) {
        try {
            block()
        } catch (error: CredentialStorageException) {
            assertEquals(message, error.message)
            return
        } catch (error: IllegalArgumentException) {
            assertEquals(message, error.message)
            return
        }
        throw AssertionError("Expected storage failure: $message")
    }

    private fun credentials() = StoredAccountCredentials(
        serverUrl = "https://storage-test.invalid/miniflux",
        apiKey = "storage-test-api-key",
        customHeaders = listOf(StoredCredentialHeader("Authorization", "Bearer storage-test-header")),
    )
}
