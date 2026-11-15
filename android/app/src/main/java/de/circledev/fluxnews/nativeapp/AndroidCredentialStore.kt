package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** Android-only encrypted account material. Its string representation never exposes secrets. */
data class StoredAccountCredentials(
    val serverUrl: String,
    val apiKey: String,
    val customHeaders: List<StoredCredentialHeader>,
) {
    override fun toString(): String = "StoredAccountCredentials(redacted)"
}

data class StoredCredentialHeader(
    val name: String,
    val value: String,
) {
    override fun toString(): String = "StoredCredentialHeader(redacted)"
}

class CredentialStorageException internal constructor(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Stores the one active account's sensitive configuration in a Keystore-backed AES-GCM envelope.
 * This uses normal credential-encrypted app storage and deliberately provides no Direct Boot path.
 */
class AndroidCredentialStore(
    context: Context,
    fileName: String = DEFAULT_FILE_NAME,
    private val keyAlias: String = defaultKeyAlias(context),
) {
    internal val encryptedFile = File(context.applicationContext.noBackupFilesDir, fileName)
    private val atomicFile = AtomicFile(encryptedFile)

    fun read(): StoredAccountCredentials? {
        if (!encryptedFile.exists()) {
            return null
        }
        val envelope = try {
            JSONObject(atomicFile.readFully().toString(StandardCharsets.UTF_8))
        } catch (error: IOException) {
            throw CredentialStorageException("Credential envelope could not be read.", error)
        } catch (error: JSONException) {
            throw CredentialStorageException("Credential envelope is malformed.", error)
        }
        val iv = envelopeBytes(envelope, "iv")
        val ciphertext = envelopeBytes(envelope, "ciphertext")
        if (envelope.optInt("version", -1) != ENVELOPE_VERSION) {
            throw CredentialStorageException("Credential envelope version is unsupported.")
        }
        if (iv.size != GCM_IV_BYTES) {
            throw CredentialStorageException("Credential envelope is malformed.")
        }
        val key = existingKey()
            ?: throw CredentialStorageException("Credential encryption key is unavailable.")
        val plaintext = try {
            Cipher.getInstance(CIPHER_TRANSFORMATION).run {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
                updateAAD(AAD)
                doFinal(ciphertext)
            }
        } catch (error: Exception) {
            throw CredentialStorageException("Credential envelope authentication failed.", error)
        }
        return decodeCredentials(plaintext)
    }

    fun write(credentials: StoredAccountCredentials) {
        val key = keyForWrite()
        val cipher = try {
            Cipher.getInstance(CIPHER_TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, key)
                updateAAD(AAD)
            }
        } catch (error: Exception) {
            throw CredentialStorageException("Credential encryption could not be initialized.", error)
        }
        val ciphertext = try {
            cipher.doFinal(encodeCredentials(credentials))
        } catch (error: Exception) {
            throw CredentialStorageException("Credentials could not be encrypted.", error)
        }
        val envelope = JSONObject()
            .put("version", ENVELOPE_VERSION)
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
        var stream: java.io.FileOutputStream? = null
        try {
            stream = atomicFile.startWrite()
            stream.write(envelope)
            atomicFile.finishWrite(stream)
        } catch (error: IOException) {
            stream?.let(atomicFile::failWrite)
            throw CredentialStorageException("Credential envelope could not be written.", error)
        }
    }

    fun clear() {
        try {
            atomicFile.delete()
            synchronized(keyCreationLock) {
                keyStore().takeIf { it.containsAlias(keyAlias) }?.deleteEntry(keyAlias)
            }
        } catch (error: Exception) {
            throw CredentialStorageException("Credentials could not be cleared.", error)
        }
    }

    private fun envelopeBytes(envelope: JSONObject, name: String): ByteArray = try {
        Base64.decode(envelope.getString(name), Base64.NO_WRAP)
    } catch (error: Exception) {
        throw CredentialStorageException("Credential envelope is malformed.", error)
    }

    private fun decodeCredentials(plaintext: ByteArray): StoredAccountCredentials = try {
        val objectValue = JSONObject(plaintext.toString(StandardCharsets.UTF_8))
        val headers = objectValue.getJSONArray("customHeaders").let { array ->
            List(array.length()) { index ->
                array.getJSONObject(index).let { StoredCredentialHeader(it.getString("name"), it.getString("value")) }
            }
        }
        StoredAccountCredentials(
            serverUrl = objectValue.getString("serverUrl"),
            apiKey = objectValue.getString("apiKey"),
            customHeaders = headers,
        )
    } catch (error: JSONException) {
        throw CredentialStorageException("Credential payload is malformed.", error)
    }

    private fun encodeCredentials(credentials: StoredAccountCredentials): ByteArray {
        val headers = JSONArray()
        credentials.customHeaders.forEach { header ->
            headers.put(JSONObject().put("name", header.name).put("value", header.value))
        }
        return JSONObject()
            .put("serverUrl", credentials.serverUrl)
            .put("apiKey", credentials.apiKey)
            .put("customHeaders", headers)
            .toString()
            .toByteArray(StandardCharsets.UTF_8)
    }

    private fun existingKey(): SecretKey? = keyStore().getKey(keyAlias, null) as? SecretKey

    private fun keyForWrite(): SecretKey = synchronized(keyCreationLock) {
        existingKey() ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    keyAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
            generateKey()
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    companion object {
        internal const val DEFAULT_FILE_NAME = "account-credentials.v1"
        internal const val KEYSTORE = "AndroidKeyStore"
        internal const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val ENVELOPE_VERSION = 1
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private val AAD = "FluxNews Android credentials v1".toByteArray(StandardCharsets.UTF_8)
        private val keyCreationLock = Any()

        private fun defaultKeyAlias(context: Context): String =
            "${context.applicationContext.packageName}.credentials.v1"
    }
}
