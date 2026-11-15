package de.circledev.fluxnews.nativeapp

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.LegacyDownloadImportOutcome
import uniffi.flux_uniffi.SyncCompleted

/**
 * Copies verified Flutter downloads to a distinct native media root, then
 * adopts them through Core. Does not mutate or delete Flutter source files.
 */
internal class AndroidLegacyDownloadMigration(
    private val legacyReader: () -> LegacyAndroidDownloadReadResult,
    private val preferences: AndroidPreferenceStore,
    private val credentials: AndroidCredentialStore,
    private val runtime: AndroidCoreRuntime,
    private val mediaRoot: File,
    private val log: (AndroidAppLogLevel, String) -> Unit = { _, _ -> },
) : AndroidPostSyncEffect {
    internal constructor(
        context: Context,
        preferences: AndroidPreferenceStore,
        credentials: AndroidCredentialStore,
        runtime: AndroidCoreRuntime,
        mediaRoot: File,
        diagnostics: AndroidAppDiagnostics,
    ) : this(
        legacyReader = LegacyAndroidStateReader(context)::readDownloadImports,
        preferences = preferences,
        credentials = credentials,
        runtime = runtime,
        mediaRoot = mediaRoot,
        log = { level, message -> diagnostics.record(level, "migration.downloads", message) },
    )

    private val mutex = Mutex()

    override suspend fun apply(sessionGeneration: Long, metadata: SyncCompleted) {
        mutex.withLock {
            val provenance = preferences.read(AndroidLegacyMigrationCoordinator.IMPORTED_ACCOUNT_SERVER, "")
            if (provenance.isBlank() || credentials.read()?.serverUrl != provenance) return@withLock
            if (preferences.read(DOWNLOADS_DONE, false)) {
                repairExistingDownloads(sessionGeneration)
                return@withLock
            }
            val records = when (val result = legacyReader()) {
                LegacyAndroidDownloadReadResult.Unavailable -> {
                    log(AndroidAppLogLevel.Warning, "Legacy download sources unavailable; retrying after next sync")
                    return@withLock
                }
                is LegacyAndroidDownloadReadResult.Found -> result.records
            }
            var shouldRetry = false
            var missingEnclosures = 0
            var failedFiles = 0
            var imported = 0
            var alreadyPresent = 0
            val missingIds = mutableListOf<Long>()
            val failedIds = mutableListOf<Long>()
            for (record in records) {
                val reference = "downloads/legacy/enclosure-${record.enclosureId}.audio"
                val destination = AndroidMediaTransferFileLayout.destination(mediaRoot, reference)
                var created = false
                try {
                    val sourceLength = record.sourceFile.length()
                    require(sourceLength > 0 && record.sourceFile.isFile && record.sourceFile.canRead())
                    // The initial full sync contains unread/starred entries only.
                    // For historical Flutter audio, hydrate the exact server entry
                    // before copying bytes. A mismatch leaves the original untouched.
                    if (record.articleId != null) {
                        val restored = runtime.remoteForGeneration(sessionGeneration) {
                            it.restoreLegacyMediaArticle(record.articleId, record.enclosureId)
                        }
                        if (!restored) {
                            shouldRetry = true
                            missingEnclosures++
                            missingIds += record.enclosureId
                            log(AndroidAppLogLevel.Warning,
                                "Legacy media article/enclosure not available articleId=${record.articleId} enclosureId=${record.enclosureId}")
                            continue
                        }
                    }
                    if (!destination.exists()) {
                        val directory = requireNotNull(destination.parentFile)
                        check(directory.isDirectory || directory.mkdirs())
                        val partial = File(directory, ".enclosure-${record.enclosureId}.migration-partial")
                        // A leftover staging file is never an authoritative native download.
                        if (partial.exists()) check(partial.delete())
                        try {
                            record.sourceFile.inputStream().use { input ->
                                FileOutputStream(partial).use { output ->
                                    input.copyTo(output)
                                    output.fd.sync()
                                }
                            }
                            check(partial.length() == sourceLength)
                            try {
                                Files.move(partial.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE)
                            } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                                Files.move(partial.toPath(), destination.toPath())
                            }
                            created = true
                        } finally {
                            partial.delete()
                        }
                    }
                    check(destination.isFile && destination.length() == sourceLength)
                    val outcome = runtime.localForGeneration(sessionGeneration) {
                        it.importLegacyDownload(
                            enclosureId = record.enclosureId,
                            localFile = reference,
                            fileSizeBytes = sourceLength.toULong(),
                        )
                    }
                    when (outcome) {
                        LegacyDownloadImportOutcome.IMPORTED -> imported++
                        LegacyDownloadImportOutcome.ALREADY_PRESENT -> {
                            alreadyPresent++
                            if (created) destination.delete()
                        }
                        LegacyDownloadImportOutcome.MISSING_ENCLOSURE -> {
                            if (created) destination.delete()
                            shouldRetry = true
                            missingEnclosures++
                            missingIds += record.enclosureId
                        }
                    }
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    // If Core may have accepted this file before the exception,
                    // retain it for the next idempotent import attempt.
                    shouldRetry = true
                    failedFiles++
                    failedIds += record.enclosureId
                    log(AndroidAppLogLevel.Warning, "Legacy download file/adoption error enclosureId=${record.enclosureId} type=${error.javaClass.simpleName}")
                }
            }
            log(
                if (shouldRetry) AndroidAppLogLevel.Warning else AndroidAppLogLevel.Info,
                "Legacy download import summary discovered=${records.size} imported=$imported " +
                    "alreadyPresent=$alreadyPresent missing=$missingEnclosures fileErrors=$failedFiles",
            )
            if (missingIds.isNotEmpty()) {
                log(AndroidAppLogLevel.Warning, "Missing Core enclosure IDs: ${missingIds.joinToString(",")}")
            }
            if (failedIds.isNotEmpty()) {
                log(AndroidAppLogLevel.Warning, "Failed legacy enclosure IDs: ${failedIds.joinToString(",")}")
            }
            if (!shouldRetry) {
                preferences.write(DOWNLOADS_DONE, true)
                preferences.remove(DOWNLOADS_STATUS)
                repairExistingDownloads(sessionGeneration)
            } else {
                preferences.write(DOWNLOADS_STATUS, buildList {
                    if (missingEnclosures > 0) add("$missingEnclosures missing audio attachment(s)")
                    if (failedFiles > 0) add("$failedFiles file(s) could not be adopted")
                }.joinToString("; "))
            }
        }
    }

    private suspend fun repairExistingDownloads(sessionGeneration: Long) {
        if (preferences.read(ARTWORK_REPAIR_DONE, false)) return
        // Core holds the sync lock and only analyzes Core-owned downloaded files.
        // If a file is missing or an error occurs, keep the marker unset for retry.
        val result = runtime.localForGeneration(sessionGeneration) {
            it.repairLegacyDownloadMetadata()
        }
        log(AndroidAppLogLevel.Info,
            "Legacy media metadata repair scanned=${result.scanned} recoveredArtworks=${result.recoveredArtworks}")
        preferences.write(ARTWORK_REPAIR_DONE, true)
    }

    companion object {
        internal val ARTWORK_REPAIR_DONE = AndroidPreferenceKey.boolean("migration-e9-media-metadata-repair-done-v1")
        internal val DOWNLOADS_DONE = AndroidPreferenceKey.boolean("migration-e9-downloads-done")
        internal val DOWNLOADS_STATUS = AndroidPreferenceKey.string("migration-e9-downloads-status")
    }
}
