package de.circledev.fluxnews.nativeapp

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal class AndroidLegacyMigrationException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * One-time Flutter -> native migration coordinator.
 *
 * Legacy sources remain read-only. Native credentials win. The provenance
 * marker is persisted before the credential copy so process death cannot leave
 * an unmarked migrated account that would incorrectly skip later E9 follow-up
 * imports.
 */
internal class AndroidLegacyMigrationCoordinator private constructor(
    private val nativeCredentialReader: () -> StoredAccountCredentials?,
    private val nativeCredentialWriter: (StoredAccountCredentials) -> Unit,
    private val nativeCredentialClearer: () -> Unit,
    private val legacyAccountReader: () -> LegacyAndroidAccountReadResult,
    private val importedAccountMarkerWriter: suspend (String) -> Unit,
    private val importedAccountMarkerClearer: suspend () -> Unit,
    private val onCredentialsImported: (StoredAccountCredentials) -> Unit,
) {
    internal constructor(
        context: Context,
        credentialStore: AndroidCredentialStore,
        preferenceStore: AndroidPreferenceStore,
        onCredentialsImported: (StoredAccountCredentials) -> Unit = {},
    ) : this(
        nativeCredentialReader = credentialStore::read,
        nativeCredentialWriter = credentialStore::write,
        nativeCredentialClearer = credentialStore::clear,
        legacyAccountReader = LegacyAndroidStateReader(context.applicationContext)::readAccountImport,
        importedAccountMarkerWriter = { server ->
            preferenceStore.write(IMPORTED_ACCOUNT_SERVER, server)
        },
        importedAccountMarkerClearer = {
            preferenceStore.remove(IMPORTED_ACCOUNT_SERVER)
        },
        onCredentialsImported = onCredentialsImported,
    )

    internal constructor(
        nativeCredentialReader: () -> StoredAccountCredentials?,
        nativeCredentialWriter: (StoredAccountCredentials) -> Unit,
        nativeCredentialClearer: () -> Unit = {},
        legacyAccountReader: () -> LegacyAndroidAccountReadResult,
        importedAccountMarkerWriter: suspend (String) -> Unit = {},
        importedAccountMarkerClearer: suspend () -> Unit = {},
        onCredentialsImported: (StoredAccountCredentials) -> Unit = {},
        @Suppress("UNUSED_PARAMETER") testOnly: Unit,
    ) : this(
        nativeCredentialReader,
        nativeCredentialWriter,
        nativeCredentialClearer,
        legacyAccountReader,
        importedAccountMarkerWriter,
        importedAccountMarkerClearer,
        onCredentialsImported,
    )

    private val mutex = Mutex()

    suspend fun prepareAccountForRestore() = mutex.withLock {
        val nativeCredentials = try {
            nativeCredentialReader()
        } catch (error: Exception) {
            throw AndroidLegacyMigrationException(
                "Native account storage could not be inspected before legacy migration.",
                error,
            )
        }
        if (nativeCredentials != null) return@withLock

        val legacy = try {
            legacyAccountReader()
        } catch (error: Exception) {
            throw AndroidLegacyMigrationException(
                "Legacy account storage could not be inspected.",
                error,
            )
        }

        val account = when (legacy) {
            LegacyAndroidAccountReadResult.Absent -> return@withLock
            LegacyAndroidAccountReadResult.Unavailable -> throw AndroidLegacyMigrationException(
                "Legacy account storage is temporarily unavailable.",
            )
            is LegacyAndroidAccountReadResult.Found -> legacy.account
        }

        val credentials = StoredAccountCredentials(
            serverUrl = account.serverUrl,
            apiKey = account.apiKey,
            customHeaders = account.customHeaders.map {
                StoredCredentialHeader(name = it.name, value = it.value)
            },
        )

        var markerWritten = false
        try {
            // Marker first: a process death here is harmless because no native
            // account exists yet and the next restore repeats this copy.
            importedAccountMarkerWriter(credentials.serverUrl)
            markerWritten = true
            nativeCredentialWriter(credentials)
            onCredentialsImported(credentials)
        } catch (error: Exception) {
            if (markerWritten) {
                runCatching { importedAccountMarkerClearer() }
            }
            runCatching { nativeCredentialClearer() }
            throw AndroidLegacyMigrationException(
                "Legacy account could not be copied into native storage.",
                error,
            )
        }
    }

    companion object {
        internal val IMPORTED_ACCOUNT_SERVER =
            AndroidPreferenceKey.string("migration-e9-imported-account-server")
    }
}
