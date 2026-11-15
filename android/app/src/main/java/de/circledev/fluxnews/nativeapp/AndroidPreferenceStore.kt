package de.circledev.fluxnews.nativeapp

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** Typed keys for non-sensitive native preferences only. Credentials always belong to AndroidCredentialStore. */
sealed class AndroidPreferenceKey<T> protected constructor(
    internal val preferenceKey: Preferences.Key<T>,
) {
    companion object {
        fun boolean(name: String): AndroidPreferenceKey<Boolean> = BooleanKey(name)
        fun string(name: String): AndroidPreferenceKey<String> = StringKey(name)
        fun int(name: String): AndroidPreferenceKey<Int> = IntKey(name)
        fun long(name: String): AndroidPreferenceKey<Long> = LongKey(name)

        private fun requireNonSensitive(name: String) {
            require(name.isNotBlank()) { "Preference names must not be blank." }
            val normalized = name.lowercase()
            require(SENSITIVE_NAME_MARKERS.none(normalized::contains)) {
                "Sensitive account material must use AndroidCredentialStore."
            }
        }
    }

    private class BooleanKey(name: String) : AndroidPreferenceKey<Boolean>(booleanPreferencesKey(name)) {
        init { requireNonSensitive(name) }
    }
    private class StringKey(name: String) : AndroidPreferenceKey<String>(stringPreferencesKey(name)) {
        init { requireNonSensitive(name) }
    }
    private class IntKey(name: String) : AndroidPreferenceKey<Int>(intPreferencesKey(name)) {
        init { requireNonSensitive(name) }
    }
    private class LongKey(name: String) : AndroidPreferenceKey<Long>(longPreferencesKey(name)) {
        init { requireNonSensitive(name) }
    }
}

private val SENSITIVE_NAME_MARKERS = listOf("api", "credential", "header", "secret", "token", "auth")

class AndroidPreferenceStore private constructor(
    private val dataStore: DataStore<Preferences>,
    private val scope: CoroutineScope,
) {
    fun <T> observe(key: AndroidPreferenceKey<T>, defaultValue: T): Flow<T> =
        dataStore.data.map { preferences -> preferences[key.preferenceKey] ?: defaultValue }

    suspend fun <T> read(key: AndroidPreferenceKey<T>, defaultValue: T): T =
        observe(key, defaultValue).let { flow -> flow.first() }

    suspend fun <T> write(key: AndroidPreferenceKey<T>, value: T) {
        dataStore.edit { preferences -> preferences[key.preferenceKey] = value }
    }

    /**
     * Import only absent native values. Presence, including an explicitly
     * stored false or empty selection, always takes precedence over Flutter.
     * The check and write must share one DataStore transaction.
     */
    suspend fun <T> writeIfAbsent(key: AndroidPreferenceKey<T>, value: T): Boolean {
        var inserted = false
        dataStore.edit { preferences ->
            if (preferences[key.preferenceKey] == null) {
                preferences[key.preferenceKey] = value
                inserted = true
            }
        }
        return inserted
    }

    internal suspend fun acknowledgeVerifiedLegacyMigration(
        requiredKeys: List<AndroidPreferenceKey<Boolean>>,
        completionKind: AndroidPreferenceKey<String>,
        acknowledged: AndroidPreferenceKey<Boolean>,
    ) {
        dataStore.edit { prefs ->
            check(requiredKeys.all { prefs[it.preferenceKey] == true }) {
                "Migration stages have not all completed."
            }
            if (prefs[completionKind.preferenceKey] == null) {
                prefs[completionKind.preferenceKey] = "completed"
            }
            prefs[acknowledged.preferenceKey] = true
        }
    }

    /** Persist a manually accepted partial migration in one DataStore edit. */
    internal suspend fun finishLegacyMigrationWithSkippedMedia(
        requiredKeys: List<AndroidPreferenceKey<Boolean>>,
        playbackDone: AndroidPreferenceKey<Boolean>,
        downloadsDone: AndroidPreferenceKey<Boolean>,
        playbackReason: AndroidPreferenceKey<String>,
        downloadsReason: AndroidPreferenceKey<String>,
        skippedPlayback: AndroidPreferenceKey<String>,
        skippedDownloads: AndroidPreferenceKey<String>,
        completionKind: AndroidPreferenceKey<String>,
        acknowledged: AndroidPreferenceKey<Boolean>,
    ) {
        dataStore.edit { prefs ->
            check(requiredKeys.all { prefs[it.preferenceKey] == true }) {
                "Settings and catalog migration must complete first."
            }
            check(prefs[acknowledged.preferenceKey] != true) {
                "Migration already acknowledged."
            }
            val playbackComplete = prefs[playbackDone.preferenceKey] == true
            val downloadsComplete = prefs[downloadsDone.preferenceKey] == true
            check(!playbackComplete || !downloadsComplete) { "Media migration already completed." }
            val playbackDetails = prefs[playbackReason.preferenceKey].orEmpty()
            val downloadDetails = prefs[downloadsReason.preferenceKey].orEmpty()
            if (!playbackComplete) check(playbackDetails.isNotBlank()) { "Playback has no import result." }
            if (!downloadsComplete) check(downloadDetails.isNotBlank()) { "Downloads have no import result." }
            if (!playbackComplete) {
                prefs[skippedPlayback.preferenceKey] = playbackDetails
                prefs[playbackDone.preferenceKey] = true
            }
            if (!downloadsComplete) {
                prefs[skippedDownloads.preferenceKey] = downloadDetails
                prefs[downloadsDone.preferenceKey] = true
            }
            prefs[completionKind.preferenceKey] = "completed_with_skipped_items"
            prefs[acknowledged.preferenceKey] = true
        }
    }

    suspend fun <T> remove(key: AndroidPreferenceKey<T>) {
        dataStore.edit { preferences -> preferences.remove(key.preferenceKey) }
    }

    /** Test-only lifecycle hook. The application-owned store lives for the process lifetime. */
    internal fun close() {
        scope.cancel()
    }

    companion object {
        private const val DEFAULT_FILE_NAME = "native-preferences.preferences_pb"

        internal fun create(context: Context): AndroidPreferenceStore = create(context, DEFAULT_FILE_NAME)

        internal fun create(context: Context, fileName: String): AndroidPreferenceStore {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            return AndroidPreferenceStore(
                PreferenceDataStoreFactory.create(
                    scope = scope,
                    produceFile = { context.applicationContext.preferencesDataStoreFile(fileName) },
                ),
                scope,
            )
        }
    }
}
