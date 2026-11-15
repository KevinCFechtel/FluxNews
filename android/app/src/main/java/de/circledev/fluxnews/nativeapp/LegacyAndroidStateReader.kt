package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import org.json.JSONObject

/**
 * E1-F compatibility reader for the exact FlutterSecureStorage 10.3.1 Android format.
 * It never initializes the plugin, opens legacy SQLite in place, or edits any legacy source.
 */
internal class LegacyAndroidStateReader(private val context: Context) {
    /**
     * Productive E9 reader for the one retained account identity. This reuses the
     * exact E1-F FlutterSecureStorage decoder and remains strictly read-only.
     */
    internal fun readAccountImport(): LegacyAndroidAccountReadResult {
        if (context.packageName != PRODUCTION_PACKAGE) return LegacyAndroidAccountReadResult.Absent
        val secureValues = LegacyFlutterSecureStorageReader(context).readAll()
        if (!secureValues.readable) return LegacyAndroidAccountReadResult.Unavailable
        return LegacyAndroidImportParsing.account(secureValues.values)
            ?.let(LegacyAndroidAccountReadResult::Found)
            ?: LegacyAndroidAccountReadResult.Absent
    }

    internal fun readSettingsImport(): LegacyAndroidSettingsReadResult {
        if (context.packageName != PRODUCTION_PACKAGE) return LegacyAndroidSettingsReadResult.Unavailable
        val values = LegacyFlutterSecureStorageReader(context).readAll()
        if (!values.readable) return LegacyAndroidSettingsReadResult.Unavailable
        return LegacyAndroidSettingsReadResult.Found(LegacyAndroidImportParsing.settings(values.values))
    }

    internal fun readPlaybackImports(): LegacyAndroidPlaybackReadResult {
        if (context.packageName != PRODUCTION_PACKAGE) return LegacyAndroidPlaybackReadResult.Unavailable
        val secure = LegacyFlutterSecureStorageReader(context).readAll()
        if (!secure.readable) return LegacyAndroidPlaybackReadResult.Unavailable
        val shared = context.getSharedPreferences(FLUTTER_SHARED_PREFERENCES, Context.MODE_PRIVATE).all
            .mapNotNull { (key, value) -> (value as? String)?.let { key to it } }.toMap()
        return LegacyAndroidPlaybackReadResult.Found(
            LegacyAndroidImportParsing.playback(shared, secure.values),
        )
    }

    internal fun readDownloadImports(): LegacyAndroidDownloadReadResult {
        if (context.packageName != PRODUCTION_PACKAGE) return LegacyAndroidDownloadReadResult.Unavailable
        val secure = LegacyFlutterSecureStorageReader(context).readAll()
        if (!secure.readable) return LegacyAndroidDownloadReadResult.Unavailable
        val database = inspectDatabase()
        if (database.present && !database.readable) return LegacyAndroidDownloadReadResult.Unavailable
        return LegacyAndroidDownloadReadResult.Found(
            LegacyAndroidImportParsing.downloads(
                secure.values,
                File(context.filesDir, "audio_cache"),
                database.attachmentIds,
                database.attachmentArticleIds,
            ),
        )
    }

    internal fun readProbe(): LegacyMigrationProbeResult {
        val before = LegacySourceFingerprints.capture(context)
        val aliasesBefore = legacyAliases()
        val secureValues = LegacyFlutterSecureStorageReader(context).readAll()
        val database = inspectDatabase()
        val playback = inspectPlayback(secureValues.values)
        val downloads = inspectDownloads(secureValues.values, database.attachmentIds)
        val widget = inspectWidget(secureValues.values)
        val backup = inspectBackup()
        val after = LegacySourceFingerprints.capture(context)
        return LegacyMigrationProbeResult(
            productionPackage = context.packageName == PRODUCTION_PACKAGE,
            credentials = CredentialEvidence(
                urlReadable = secureValues.values["minifluxURL"]?.isNotEmpty() == true,
                apiKeyReadable = secureValues.values["minifluxAPIKey"]?.isNotEmpty() == true,
                customHeaderCount = legacyCustomHeaders(secureValues.values).size,
                customHeadersReadable = secureValues.readable,
            ),
            settings = LegacySettingEvidence.from(secureValues.values),
            database = database,
            playback = playback,
            downloads = downloads,
            widget = widget,
            autoBackup = backup,
            sourceFingerprintsUnchanged = before == after,
            keystoreAliasesUnchanged = aliasesBefore == legacyAliases(),
        )
    }

    private fun inspectDatabase(): DatabaseEvidence {
        val original = context.getDatabasePath(LEGACY_DATABASE)
        if (!original.isFile) return DatabaseEvidence.absent()
        val copyRoot = File(context.cacheDir, "legacy-db-probe").apply { mkdirs() }
        val copy = File(copyRoot, LEGACY_DATABASE)
        original.copyTo(copy, overwrite = true)
        listOf("-wal", "-shm", "-journal").forEach { suffix ->
            File(original.path + suffix).takeIf(File::isFile)?.copyTo(File(copy.path + suffix), overwrite = true)
        }
        return try {
            SQLiteDatabase.openDatabase(copy.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                val tables = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null).use { cursor ->
                    generateSequence { if (cursor.moveToNext()) cursor.getString(0) else null }.toSet()
                }
                val attachmentIds = db.rawQuery("SELECT attachmentID FROM attachments", null).use { cursor ->
                    buildSet<Long> { while (cursor.moveToNext()) add(cursor.getLong(0)) }
                }
                // Read the association from the same read-only SQLite snapshot as
                // the legacy enclosure IDs. Never infer an article ID from an enclosure ID.
                val attachmentArticleIds = db.rawQuery(
                    "SELECT a.attachmentID,a.newsID FROM attachments a INNER JOIN news n ON n.newsID=a.newsID",
                    null,
                ).use { cursor ->
                    buildMap<Long, Long> {
                        while (cursor.moveToNext()) {
                            val enclosureId = cursor.getLong(0)
                            val articleId = cursor.getLong(1)
                            if (enclosureId > 0 && articleId > 0) put(enclosureId, articleId)
                        }
                    }
                }
                val relationshipsReadable = db.rawQuery(
                    "SELECT COUNT(*) FROM attachments INNER JOIN news ON attachments.newsID = news.newsID", null,
                ).use { it.moveToFirst(); true }
                DatabaseEvidence(
                    present = true,
                    readable = REQUIRED_TABLES.all(tables::contains),
                    schemaVersion = db.version,
                    newsCount = count(db, "news"),
                    feedCount = count(db, "feeds"),
                    categoryCount = count(db, "categories"),
                    attachmentCount = attachmentIds.size,
                    audioAttachmentCount = db.rawQuery(
                        "SELECT COUNT(*) FROM attachments WHERE attachmentMimeType LIKE 'audio/%'", null,
                    ).use { it.moveToFirst(); it.getInt(0) },
                    articleAttachmentRelationshipsReadable = relationshipsReadable,
                    attachmentIds = attachmentIds,
                    attachmentArticleIds = attachmentArticleIds,
                )
            }
        } catch (_: Exception) {
            DatabaseEvidence(present = true, readable = false)
        } finally {
            copyRoot.deleteRecursively()
        }
    }

    private fun inspectPlayback(values: Map<String, String>): PlaybackEvidence {
        val shared = context.getSharedPreferences(FLUTTER_SHARED_PREFERENCES, Context.MODE_PRIVATE).all
            .filterKeys { it.startsWith(PLAYBACK_PREFIX) }
            .mapValues { it.value as? String }
        val all = (shared.keys + values.keys.filter { it.startsWith(PLAYBACK_PREFIX) }).associateWith { key ->
            shared[key] ?: values[key]
        }
        return PlaybackEvidence(
            entryCount = all.size,
            positiveEntryCount = all.values.count { it?.toLongOrNull()?.let { value -> value > 0 } == true },
            explicitZeroEntryCount = all.values.count { it == "0" },
            legacySecureFallbackCount = all.keys.count { shared[it] == null && values[it] != null },
        )
    }

    private fun inspectDownloads(values: Map<String, String>, attachmentIds: Set<Long>): DownloadEvidence {
        val audioDir = File(context.filesDir, "audio_cache")
        val files = audioDir.listFiles()?.filter(File::isFile).orEmpty()
        val fileIds = files.mapNotNull { LegacyKeyParsing.attachmentIdFromAudioFile(it.name) }.toSet()
        val metadataIds = values.keys.mapNotNull(LegacyKeyParsing::downloadMetadataAttachmentId).toSet()
        val metadataEntries = values.keys.count { LegacyKeyParsing.isDownloadMetadataKey(it) }
        val resolvable = (fileIds intersect metadataIds intersect attachmentIds).size
        return DownloadEvidence(
            audioCachePresent = audioDir.isDirectory,
            downloadedFileCount = files.size,
            metadataEntryCount = metadataEntries,
            resolvableDownloadCount = resolvable,
            unresolvedDownloadCount = files.size - resolvable,
        )
    }

    private fun inspectWidget(values: Map<String, String>): WidgetEvidence {
        val preferences = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val snapshot = preferences.getString("snapshot", null)
        return WidgetEvidence(
            preferencesPresent = legacyPreferenceFile("HomeWidgetPreferences").isFile,
            snapshotPresent = snapshot != null,
            snapshotParseable = snapshot?.let { runCatching { JSONObject(it) }.isSuccess } ?: false,
            configurationKeysPresent = WIDGET_KEYS.count(values::containsKey),
        )
    }

    private fun inspectBackup(): BackupEvidence {
        val file = File(context.filesDir, "android_auto_backup/flux_news_auto_backup.fnbak")
        return BackupEvidence(file.isFile, file.canRead(), file.takeIf(File::isFile)?.length())
    }

    private fun count(database: SQLiteDatabase, table: String): Int =
        database.rawQuery("SELECT COUNT(*) FROM $table", null).use { it.moveToFirst(); it.getInt(0) }

    private fun legacyAliases(): Set<String> = KeyStore.getInstance("AndroidKeyStore").run {
        load(null)
        buildSet {
            val aliases = aliases()
            while (aliases.hasMoreElements()) {
                aliases.nextElement().takeIf { it == OAEP_ALIAS || it == PKCS1_ALIAS }?.let(::add)
            }
        }
    }

    private fun legacyPreferenceFile(name: String) = File(context.applicationInfo.dataDir, "shared_prefs/$name.xml")

    companion object {
        const val PRODUCTION_PACKAGE = "de.circle_dev.flux_news"
        private const val LEGACY_DATABASE = "news_database.db"
        private const val FLUTTER_SHARED_PREFERENCES = "FlutterSharedPreferences"
        private const val PLAYBACK_PREFIX = "audio_progress_"
        private val REQUIRED_TABLES = setOf("news", "feeds", "categories", "attachments")
        private val WIDGET_KEYS = setOf("widgetNewsStatus", "widgetUnreadOnly", "widgetFilterType", "widgetFilterId", "widgetSortOrder", "widgetItemLimit", "widgetOpenMiniflux", "widgetTranslucentBackground")
        private const val OAEP_ALIAS = "$PRODUCTION_PACKAGE.FlutterSecureStoragePluginKeyOAEP"
        private const val PKCS1_ALIAS = "$PRODUCTION_PACKAGE.FlutterSecureStoragePluginKey"
    }
}

private class LegacyFlutterSecureStorageReader(private val context: Context) {
    fun readAll(): SecureReadResult {
        val encrypted = context.getSharedPreferences(DATA_PREFS, Context.MODE_PRIVATE).all
            .filterValues { it is String }
            .mapNotNull { (key, value) -> key.takeIf { it.startsWith(KEY_PREFIX) }?.let { it.removePrefix("${KEY_PREFIX}_") to value as String } }
            .toMap()
        if (encrypted.isEmpty()) return SecureReadResult(emptyMap(), true)
        val keyBytes = wrappedAesKey() ?: return SecureReadResult(emptyMap(), false)
        val algorithms = listOf(CipherSpec.oaepGcm(), CipherSpec.pkcs1Cbc())
        for (spec in algorithms) {
            val aes = unwrap(keyBytes, spec) ?: continue
            val values = encrypted.mapNotNull { (key, value) -> decrypt(value, aes, spec)?.let { key to it } }.toMap()
            if (values.isNotEmpty() || encrypted.isEmpty()) return SecureReadResult(values, values.size == encrypted.size)
        }
        return SecureReadResult(emptyMap(), false)
    }

    private fun wrappedAesKey(): ByteArray? = context.getSharedPreferences(KEY_PREFS, Context.MODE_PRIVATE)
        .getString(WRAPPED_AES_KEY, null)?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() }

    private fun unwrap(wrapped: ByteArray, spec: CipherSpec): ByteArray? = runCatching {
        val key = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.getKey(spec.alias, null) as? PrivateKey
            ?: return null
        Cipher.getInstance(spec.rsaTransformation, "AndroidKeyStoreBCWorkaround").run {
            init(Cipher.UNWRAP_MODE, key, spec.oaep)
            unwrap(wrapped, KeyProperties.KEY_ALGORITHM_AES, Cipher.SECRET_KEY).encoded
        }
    }.getOrNull()

    private fun decrypt(encoded: String, key: ByteArray, spec: CipherSpec): String? = runCatching {
        val input = Base64.decode(encoded, Base64.DEFAULT)
        val iv = input.copyOfRange(0, spec.ivBytes)
        Cipher.getInstance(spec.aesTransformation).run {
            init(Cipher.DECRYPT_MODE, javax.crypto.spec.SecretKeySpec(key, "AES"), spec.parameters(iv))
            String(doFinal(input.copyOfRange(spec.ivBytes, input.size)), StandardCharsets.UTF_8)
        }
    }.getOrNull()

    private data class CipherSpec(
        val alias: String, val rsaTransformation: String, val oaep: OAEPParameterSpec?,
        val aesTransformation: String, val ivBytes: Int, val parameters: (ByteArray) -> java.security.spec.AlgorithmParameterSpec,
    ) {
        companion object {
            fun oaepGcm() = CipherSpec(
                "$PACKAGE.FlutterSecureStoragePluginKeyOAEP", "RSA/ECB/OAEPPadding",
                OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT),
                "AES/GCM/NoPadding", 12, { GCMParameterSpec(128, it) },
            )
            fun pkcs1Cbc() = CipherSpec(
                "$PACKAGE.FlutterSecureStoragePluginKey", "RSA/ECB/PKCS1Padding", null,
                "AES/CBC/PKCS7Padding", 16, ::IvParameterSpec,
            )
        }
    }

    companion object {
        private const val PACKAGE = LegacyAndroidStateReader.PRODUCTION_PACKAGE
        private const val DATA_PREFS = "FlutterSecureStorage"
        private const val KEY_PREFS = "FlutterSecureKeyStorage"
        private const val KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
        private const val WRAPPED_AES_KEY = "AESVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
    }
}

private data class SecureReadResult(val values: Map<String, String>, val readable: Boolean)

internal object LegacyKeyParsing {
    private val playback = Regex("^audio_progress_\\d+$")
    private val audioFile = Regex("^audio_(-?\\d+)_\\d+\\..+$")
    private val metadata = Regex("^(?:audio_download_path_|audio_download_ts_|audio_download_skipped_|flux_download_title_|flux_download_feed_title_)(-?\\d+)$")
    fun isPlaybackKey(key: String) = playback.matches(key)
    fun attachmentIdFromAudioFile(name: String) = audioFile.matchEntire(name)?.groupValues?.get(1)?.toLongOrNull()
    fun downloadMetadataAttachmentId(key: String) = metadata.matchEntire(key)?.groupValues?.get(1)?.toLongOrNull()
    fun isDownloadMetadataKey(key: String): Boolean = downloadMetadataAttachmentId(key) != null ||
        key.startsWith("audio_download_path_url_")
}

internal fun legacyCustomHeaders(values: Map<String, String>): Map<Int, Pair<String, String>> = values.keys
    .mapNotNull { key -> Regex("^customHeadersKey_(\\d+)$").matchEntire(key)?.groupValues?.get(1)?.toIntOrNull() }
    .mapNotNull { index -> values["customHeadersKey_$index"]?.let { name -> values["customHeadersValue_$index"]?.let { index to (name to it) } } }
    .toMap()

private object LegacySourceFingerprints {
    fun capture(context: Context): Map<String, String> {
        val files = listOf(
            File(context.applicationInfo.dataDir, "shared_prefs/FlutterSecureStorage.xml"),
            File(context.applicationInfo.dataDir, "shared_prefs/FlutterSecureKeyStorage.xml"),
            File(context.applicationInfo.dataDir, "shared_prefs/FlutterSecureStorageConfiguration.xml"),
            File(context.applicationInfo.dataDir, "shared_prefs/FlutterSecureStorageConfiguration:FlutterSecureStorage.xml"),
            File(context.applicationInfo.dataDir, "shared_prefs/FlutterSharedPreferences.xml"),
            File(context.applicationInfo.dataDir, "shared_prefs/HomeWidgetPreferences.xml"),
            context.getDatabasePath("news_database.db"),
            File(context.getDatabasePath("news_database.db").path + "-wal"),
            File(context.getDatabasePath("news_database.db").path + "-shm"),
            File(context.getDatabasePath("news_database.db").path + "-journal"),
            File(context.filesDir, "android_auto_backup/flux_news_auto_backup.fnbak"),
        )
        return files.associate { it.path to fingerprint(it) } + audioFingerprint(File(context.filesDir, "audio_cache"))
    }

    private fun fingerprint(file: File): String = if (!file.isFile) "absent" else MessageDigest.getInstance("SHA-256")
        .digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun audioFingerprint(directory: File): Pair<String, String> = "audio_cache" to directory.listFiles()
        ?.filter(File::isFile)?.sortedBy { it.name }?.joinToString("|") { "${it.name}:${it.length()}:${it.lastModified()}" }.orEmpty()
}

internal data class CredentialEvidence(
    val urlReadable: Boolean,
    val apiKeyReadable: Boolean,
    val customHeaderCount: Int,
    val customHeadersReadable: Boolean,
)

internal data class LegacySettingEvidence(val discovered: Int, val parseable: Int) {
    companion object {
        private val candidates = listOf(
            "minifluxVersionKey", "backgroundSyncIntervalMinutes", "autoDownloadAudioAfterSync",
            "downloadAudioOnlyOnWifi", "deleteAudioAfterPlayback", "audioDownloadRetentionDays",
            "openAudioItemsInPlayer", "feedSettingsOverrides", "syncReadStatusImmediately", "syncReadNewsAfterDays",
        )
        fun from(values: Map<String, String>): LegacySettingEvidence {
            val present = candidates.filter(values::containsKey)
            return LegacySettingEvidence(present.size, present.count { key -> parseable(key, values.getValue(key)) })
        }
        private fun parseable(key: String, value: String): Boolean = when (key) {
            "backgroundSyncIntervalMinutes", "audioDownloadRetentionDays", "syncReadNewsAfterDays" -> value.toIntOrNull() != null
            "autoDownloadAudioAfterSync", "downloadAudioOnlyOnWifi", "deleteAudioAfterPlayback", "openAudioItemsInPlayer", "syncReadStatusImmediately" -> value == "true" || value == "false"
            "feedSettingsOverrides" -> runCatching { JSONObject(value) }.isSuccess
            else -> value.isNotEmpty()
        }
    }
}

internal data class DatabaseEvidence(
    val present: Boolean,
    val readable: Boolean,
    val schemaVersion: Int? = null,
    val newsCount: Int? = null,
    val feedCount: Int? = null,
    val categoryCount: Int? = null,
    val attachmentCount: Int? = null,
    val audioAttachmentCount: Int? = null,
    val articleAttachmentRelationshipsReadable: Boolean = false,
    val attachmentIds: Set<Long> = emptySet(),
    val attachmentArticleIds: Map<Long, Long> = emptyMap(),
) {
    companion object { fun absent() = DatabaseEvidence(false, false) }
}

internal data class PlaybackEvidence(
    val entryCount: Int,
    val positiveEntryCount: Int,
    val explicitZeroEntryCount: Int,
    val legacySecureFallbackCount: Int,
)

internal data class DownloadEvidence(
    val audioCachePresent: Boolean,
    val downloadedFileCount: Int,
    val metadataEntryCount: Int,
    val resolvableDownloadCount: Int,
    val unresolvedDownloadCount: Int,
)

internal data class WidgetEvidence(
    val preferencesPresent: Boolean,
    val snapshotPresent: Boolean,
    val snapshotParseable: Boolean,
    val configurationKeysPresent: Int,
)

internal data class BackupEvidence(val present: Boolean, val readable: Boolean, val size: Long?)

internal data class LegacyMigrationProbeResult(
    val productionPackage: Boolean,
    val credentials: CredentialEvidence,
    val settings: LegacySettingEvidence,
    val database: DatabaseEvidence,
    val playback: PlaybackEvidence,
    val downloads: DownloadEvidence,
    val widget: WidgetEvidence,
    val autoBackup: BackupEvidence,
    val sourceFingerprintsUnchanged: Boolean,
    val keystoreAliasesUnchanged: Boolean,
) {
    fun toJson(): String = JSONObject().apply {
        put("productionPackage", productionPackage)
        put("credentials", JSONObject().apply {
            put("urlReadable", credentials.urlReadable)
            put("apiKeyReadable", credentials.apiKeyReadable)
            put("customHeaderCount", credentials.customHeaderCount)
            put("customHeadersReadable", credentials.customHeadersReadable)
        })
        put("settings", JSONObject().put("discovered", settings.discovered).put("parseable", settings.parseable))
        put("database", JSONObject().apply {
            put("present", database.present); put("readable", database.readable); put("schemaVersion", database.schemaVersion)
            put("newsCount", database.newsCount); put("feedCount", database.feedCount); put("categoryCount", database.categoryCount)
            put("attachmentCount", database.attachmentCount); put("audioAttachmentCount", database.audioAttachmentCount)
            put("articleAttachmentRelationshipsReadable", database.articleAttachmentRelationshipsReadable)
        })
        put("playback", JSONObject().put("entries", playback.entryCount).put("positive", playback.positiveEntryCount)
            .put("explicitZero", playback.explicitZeroEntryCount).put("legacySecureFallback", playback.legacySecureFallbackCount))
        put("downloads", JSONObject().put("audioCachePresent", downloads.audioCachePresent).put("files", downloads.downloadedFileCount)
            .put("metadataEntries", downloads.metadataEntryCount).put("resolvable", downloads.resolvableDownloadCount).put("unresolved", downloads.unresolvedDownloadCount))
        put("widget", JSONObject().put("preferencesPresent", widget.preferencesPresent).put("snapshotPresent", widget.snapshotPresent)
            .put("snapshotParseable", widget.snapshotParseable).put("configurationKeysPresent", widget.configurationKeysPresent))
        put("autoBackup", JSONObject().put("present", autoBackup.present).put("readable", autoBackup.readable).put("size", autoBackup.size))
        put("nonDestructive", JSONObject().put("sourceFingerprintsUnchanged", sourceFingerprintsUnchanged)
            .put("keystoreAliasesUnchanged", keystoreAliasesUnchanged))
    }.toString()
}


internal sealed interface LegacyAndroidAccountReadResult {
    data object Absent : LegacyAndroidAccountReadResult
    data object Unavailable : LegacyAndroidAccountReadResult
    data class Found(val account: LegacyAndroidAccountImport) : LegacyAndroidAccountReadResult
}

internal data class LegacyAndroidDownloadImport(
    val enclosureId: Long,
    val sourceFile: File,
    val articleId: Long? = null,
)

internal sealed interface LegacyAndroidDownloadReadResult {
    data object Unavailable : LegacyAndroidDownloadReadResult
    data class Found(val records: List<LegacyAndroidDownloadImport>) : LegacyAndroidDownloadReadResult
}

internal data class LegacyAndroidPlaybackProgressImport(
    val articleId: Long,
    val positionMs: ULong,
)

internal sealed interface LegacyAndroidPlaybackReadResult {
    data object Unavailable : LegacyAndroidPlaybackReadResult
    data class Found(val records: List<LegacyAndroidPlaybackProgressImport>) : LegacyAndroidPlaybackReadResult
}

internal sealed interface LegacyAndroidSettingsReadResult {
    data object Unavailable : LegacyAndroidSettingsReadResult
    data class Found(val settings: LegacyAndroidSettingsImport) : LegacyAndroidSettingsReadResult
}

internal data class LegacyAndroidSettingsImport(
    val backgroundSyncEnabled: Boolean?,
    val autoDownloadListeningList: Boolean?,
    val unmeteredDownloadsOnly: Boolean?,
    val retentionDays: Int?,
    val deleteAfterPlayback: Boolean?,
    val openInMinifluxFeedIds: List<Long>,
    val local: LegacyAndroidLocalSettingsImport,
    val widget: LegacyAndroidWidgetSeed?,
)

internal data class LegacyAndroidLocalSettingsImport(
    val showArticleCount: Boolean?,
    val hideEmptyNavigation: Boolean?,
    val markReadOnScrollover: Boolean?,
    val removeWhenRead: Boolean?,
    val openArticleInReader: Boolean?,
    val leadingFull: String?,
    val leadingAdditional: String?,
    val trailingFull: String?,
    val trailingAdditional: String?,
    val startupMode: Int?,
    val startupCategoryId: Long?,
    val startupFeedId: Long?,
    val actionBar: List<String>?,
)

internal data class LegacyAndroidWidgetSeed(
    val scope: String,
    val scopeId: Long?,
    val unreadOnly: Boolean,
    val oldestFirst: Boolean,
)

internal data class LegacyAndroidAccountImport(
    val serverUrl: String,
    val apiKey: String,
    val customHeaders: List<LegacyAndroidHeaderImport>,
)

internal data class LegacyAndroidHeaderImport(
    val name: String,
    val value: String,
)

/** Pure retained-state parsing kept separate from Android/Keystore access for regression tests. */
internal object LegacyAndroidImportParsing {
    fun downloads(
        secure: Map<String, String>,
        audioRoot: File,
        knownLegacyEnclosureIds: Set<Long>,
        articleIdsByEnclosureId: Map<Long, Long> = emptyMap(),
    ): List<LegacyAndroidDownloadImport> {
        val root = audioRoot.canonicalFile
        fun verifiedImport(id: Long, file: File): LegacyAndroidDownloadImport? {
            if (id <= 0L || id !in knownLegacyEnclosureIds) return null
            val source = runCatching { file.canonicalFile }.getOrNull() ?: return null
            if (source.parentFile != root ||
                !source.name.startsWith("audio_") ||
                !source.isFile ||
                !source.canRead() ||
                source.length() <= 0L
            ) return null
            return LegacyAndroidDownloadImport(id, source, articleIdsByEnclosureId[id])
        }

        val keyed = secure.mapNotNull { (key, value) ->
            val id = Regex("^audio_download_path_(\\d+)$").matchEntire(key)
                ?.groupValues?.get(1)?.toLongOrNull()
                ?: return@mapNotNull null
            verifiedImport(id, File(value))
        }

        // Flutter's Downloads screen also treats audio_cache itself as source
        // data. Old absolute sandbox paths can become stale across an upgrade,
        // so scan only the validated legacy filename form as a read-only fallback.
        val cached = root.listFiles()
            ?.asSequence()
            ?.filter(File::isFile)
            ?.mapNotNull { file ->
                val id = LegacyKeyParsing.attachmentIdFromAudioFile(file.name)
                    ?: return@mapNotNull null
                verifiedImport(id, file)
            }
            ?.toList()
            .orEmpty()

        return (keyed + cached)
            .distinctBy { it.enclosureId }
            .sortedBy { it.enclosureId }
    }

    fun playback(
        sharedPreferences: Map<String, String>,
        legacySecure: Map<String, String>,
    ): List<LegacyAndroidPlaybackProgressImport> {
        // Flutter's AudioProgressStore uses SharedPreferences first and only
        // falls back to secure storage for article IDs absent there.
        val combined = legacySecure + sharedPreferences
        return combined.mapNotNull { (key, value) ->
            val id = key.takeIf { it.startsWith("audio_progress_") }
                ?.removePrefix("audio_progress_")?.toLongOrNull()?.takeIf { it > 0L }
                ?: return@mapNotNull null
            val position = value.trim().toULongOrNull()?.takeIf { it > 0uL }
                ?: return@mapNotNull null
            LegacyAndroidPlaybackProgressImport(id, position)
        }.sortedBy { it.articleId }
    }

    private fun legacySwipe(raw: String?): String? = when (raw) {
        "readUnread" -> "readUnread"
        "bookmark" -> "starUnstar"
        "open" -> "openOriginal"
        "openMiniflux" -> "openMiniflux"
        "openComments" -> "comments"
        "share" -> "share"
        "saveToThirdParty" -> "saveToService"
        "downloadAudio" -> "downloadAudio"
        "none" -> ""
        else -> null
    }

    private fun legacyActionBar(values: Map<String, String>): List<String>? {
        val selectedRaw = values["androidFloatingToolbarActions"] ?: return null
        fun strings(raw: String): List<String>? = runCatching {
            val array = org.json.JSONArray(raw)
            List(array.length()) { array.getString(it) }
        }.getOrNull()
        val selected = strings(selectedRaw) ?: return null
        val order = values["androidFloatingToolbarActionOrder"]?.let(::strings) ?: selected
        val mapping = mapOf(
            "search" to "search",
            "newsStatus" to "toggleReadFilter",
            "sortOrder" to "toggleSortOrder",
            "markAsRead" to "markAllRead",
            "markAsReadAndNext" to "markAllReadAndNext",
            "podcasts" to "listeningList",
            "settings" to "settings",
        )
        return (order + selected).distinct().filter { it in selected }
            .mapNotNull(mapping::get).distinct()
    }

    private fun legacyWidgetSeed(values: Map<String, String>): LegacyAndroidWidgetSeed? {
        val keys = setOf("widgetNewsStatus", "widgetUnreadOnly", "widgetFilterType", "widgetFilterId", "widgetSortOrder")
        if (keys.none(values::containsKey)) return null
        val oldStatus = values["widgetNewsStatus"]
        val rawScope = values["widgetFilterType"] ?: when (oldStatus) {
            "bookmarked" -> "bookmarked"
            else -> "all"
        }
        val scope = when (rawScope) {
            "bookmarked" -> "bookmarks"
            "feed" -> "feed"
            "category" -> "category"
            else -> "all"
        }
        val scopeId = values["widgetFilterId"]?.toLongOrNull()?.takeIf { it > 0 }
        val safeScope = if (scope in setOf("feed", "category") && scopeId == null) "all" else scope
        val unread = when (values["widgetUnreadOnly"]) {
            "true" -> true
            "false" -> false
            else -> oldStatus != "all" && oldStatus != "bookmarked"
        }
        return LegacyAndroidWidgetSeed(
            scope = safeScope,
            scopeId = if (safeScope == "all") null else scopeId,
            unreadOnly = unread,
            oldestFirst = values["widgetSortOrder"] == "Oldest first",
        )
    }

    fun settings(values: Map<String, String>): LegacyAndroidSettingsImport {
        fun boolean(key: String) = when (values[key]?.trim()) {
            "true" -> true
            "false" -> false
            else -> null
        }
        val interval = values["backgroundSyncIntervalMinutes"]?.trim()?.toIntOrNull()
        val feedIds = runCatching {
            val overrides = JSONObject(values["feedSettingsOverrides"] ?: "{}")
            overrides.keys().asSequence().mapNotNull { key ->
                val id = key.toLongOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
                val setting = overrides.optJSONObject(key) ?: return@mapNotNull null
                if (setting.opt("openMinifluxEntry") is Number &&
                    setting.optInt("openMinifluxEntry") == 1
                ) id else null
            }.sorted().toList()
        }.getOrDefault(emptyList())
        val local = LegacyAndroidLocalSettingsImport(
            showArticleCount = boolean("multilineAppBarText"),
            hideEmptyNavigation = boolean("showOnlyFeedCategoriesWithNewNews"),
            markReadOnScrollover = boolean("markAsReadOnScrollOver"),
            removeWhenRead = boolean("removeNewsFromListWhenRead"),
            openArticleInReader = if (values["tabAction"] == "expand") true else null,
            leadingFull = legacySwipe(values["rightSwipeAction"]),
            leadingAdditional = legacySwipe(values["secondRightSwipeAction"]),
            trailingFull = legacySwipe(values["leftSwipeAction"]),
            trailingAdditional = legacySwipe(values["secondLeftSwipeAction"]),
            startupMode = values["startupCategorie"]?.toIntOrNull()?.takeIf { it in 0..3 },
            startupCategoryId = values["startupCategorieSelection"]?.toLongOrNull()?.takeIf { it > 0 },
            startupFeedId = values["startupFeedSelection"]?.toLongOrNull()?.takeIf { it > 0 },
            actionBar = legacyActionBar(values),
        )
        return LegacyAndroidSettingsImport(
            backgroundSyncEnabled = interval?.takeIf { it >= 0 }?.let { it > 0 },
            autoDownloadListeningList = boolean("autoDownloadAudioAfterSync"),
            unmeteredDownloadsOnly = boolean("downloadAudioOnlyOnWifi"),
            retentionDays = values["audioDownloadRetentionDays"]?.trim()?.toIntOrNull()
                ?.takeIf { it in setOf(7, 30, 90) },
            deleteAfterPlayback = boolean("deleteAudioAfterPlayback"),
            openInMinifluxFeedIds = feedIds,
            local = local,
            widget = legacyWidgetSeed(values),
        )
    }

    fun account(values: Map<String, String>): LegacyAndroidAccountImport? {
        val serverUrl = values["minifluxURL"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val apiKey = values["minifluxAPIKey"]?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val headers = legacyCustomHeaders(values)
            .toSortedMap()
            .values
            .mapNotNull { (name, value) ->
                name.trim().takeIf(String::isNotEmpty)?.let { LegacyAndroidHeaderImport(it, value) }
            }
        return LegacyAndroidAccountImport(serverUrl, apiKey, headers)
    }
}
