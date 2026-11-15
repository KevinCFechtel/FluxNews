package de.circledev.fluxnews.nativeapp

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.LegacyPlaybackImport
import uniffi.flux_uniffi.SyncCompleted

/**
 * Retryable E9 playback import, always resolved by the authoritative Core.
 * Flutter article progress has no reliable update timestamp, so the import
 * passes null and Core preserves any existing native progress.
 */
internal class AndroidLegacyPlaybackMigration(
    private val legacyReader: () -> LegacyAndroidPlaybackReadResult,
    private val legacyDownloadReader: () -> LegacyAndroidDownloadReadResult,
    private val preferenceStore: AndroidPreferenceStore,
    private val credentialStore: AndroidCredentialStore,
    private val coreRuntime: AndroidCoreRuntime,
) : AndroidPostSyncEffect {
    internal constructor(
        context: Context,
        preferenceStore: AndroidPreferenceStore,
        credentialStore: AndroidCredentialStore,
        coreRuntime: AndroidCoreRuntime,
    ) : this(
        legacyReader = LegacyAndroidStateReader(context)::readPlaybackImports,
        legacyDownloadReader = LegacyAndroidStateReader(context)::readDownloadImports,
        preferenceStore = preferenceStore,
        credentialStore = credentialStore,
        coreRuntime = coreRuntime,
    )

    private val mutex = Mutex()

    override suspend fun apply(sessionGeneration: Long, metadata: SyncCompleted) {
        mutex.withLock {
            val provenance = preferenceStore.read(AndroidLegacyMigrationCoordinator.IMPORTED_ACCOUNT_SERVER, "")
            if (provenance.isBlank()) return@withLock
            if (credentialStore.read()?.serverUrl != provenance) return@withLock

            val playbackDone = preferenceStore.read(PLAYBACK_DONE, false)
            val verificationV2Done = preferenceStore.read(PLAYBACK_VERIFICATION_V2_DONE, false)
            if (playbackDone) {
                if (verificationV2Done) return@withLock

                val completionKind = preferenceStore.read(
                    AndroidLegacyMigrationNoticeStore.COMPLETION_KIND,
                    "",
                )
                val skippedPlayback = preferenceStore.read(
                    AndroidLegacyMigrationNoticeStore.SKIPPED_PLAYBACK_DETAILS,
                    "",
                )
                if (!shouldReopenManualPlaybackSkip(
                        playbackDone = playbackDone,
                        verificationV2Done = verificationV2Done,
                        completionKind = completionKind,
                        skippedPlaybackDetails = skippedPlayback,
                    )
                ) {
                    // Older installations whose playback import completed
                    // normally do not need the semantic v2 recheck.
                    preferenceStore.write(PLAYBACK_VERIFICATION_V2_DONE, true)
                    return@withLock
                }

                // Re-open only the playback stage. Account/settings/downloads/
                // widgets and already imported native Core state remain intact.
                preferenceStore.write(PLAYBACK_DONE, false)
                preferenceStore.remove(
                    AndroidLegacyMigrationNoticeStore.SKIPPED_PLAYBACK_DETAILS,
                )
                preferenceStore.remove(
                    AndroidLegacyMigrationNoticeStore.COMPLETION_KIND,
                )
                preferenceStore.write(
                    AndroidLegacyMigrationNoticeStore.ACKNOWLEDGED,
                    false,
                )
            }

            val records = when (val result = legacyReader()) {
                LegacyAndroidPlaybackReadResult.Unavailable -> return@withLock
                is LegacyAndroidPlaybackReadResult.Found -> result.records
            }
            val discardedArticleIds = parseDiscardedArticleIds(
                preferenceStore.read(PLAYBACK_DISCARDED_IDS, ""),
            ).toMutableSet()
            val downloadArticleIds = downloadedArticleIdsOrNull(legacyDownloadReader())

            // Playback migration runs before download migration. A confirmed
            // 404/410 may be discarded only when the complete read-only legacy
            // download scan proves there is no matching local audio file.
            // Connectivity errors, ambiguous identity and local downloads remain
            // retryable. Core reserves false specifically for HTTP 404/410.
            for (record in records) {
                if (record.articleId in discardedArticleIds) continue
                try {
                    val restored = coreRuntime.remoteForGeneration(sessionGeneration) {
                        it.restoreLegacyPlaybackArticle(record.articleId)
                    }
                    if (!restored &&
                        shouldDiscardRemoteMiss(record.articleId, downloadArticleIds)
                    ) {
                        discardedArticleIds += record.articleId
                    }
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    // Non-404 failures are not negative evidence. Keep the
                    // record for a later authoritative retry.
                }
            }
            preferenceStore.write(
                PLAYBACK_DISCARDED_IDS,
                encodeDiscardedArticleIds(discardedArticleIds),
            )
            val importableRecords = records.filterNot {
                it.articleId in discardedArticleIds
            }
            val outcome = coreRuntime.localForGeneration(sessionGeneration) { core ->
                core.importLegacyPlayback(
                    importableRecords.map {
                        LegacyPlaybackImport(
                            articleId = it.articleId,
                            positionMs = it.positionMs,
                            updatedAt = null,
                        )
                    },
                )
            }
            // An empty batch is a valid completed import only after both
            // legacy sources have been successfully inspected.
            val missing = outcome.skippedMissing.toInt()
            val ambiguous = outcome.skippedAmbiguous.toInt()
            val discardedDescription = discardedDescription(discardedArticleIds.size)
            if (missing == 0 && ambiguous == 0) {
                preferenceStore.write(PLAYBACK_DONE, true)
                preferenceStore.write(PLAYBACK_VERIFICATION_V2_DONE, true)
                if (discardedDescription.isBlank()) {
                    preferenceStore.remove(PLAYBACK_STATUS)
                } else {
                    preferenceStore.write(PLAYBACK_STATUS, discardedDescription)
                }
                preferenceStore.remove(
                    AndroidLegacyMigrationNoticeStore.SKIPPED_PLAYBACK_DETAILS,
                )
                val skippedDownloads = preferenceStore.read(
                    AndroidLegacyMigrationNoticeStore.SKIPPED_DOWNLOAD_DETAILS,
                    "",
                )
                preferenceStore.write(
                    AndroidLegacyMigrationNoticeStore.COMPLETION_KIND,
                    if (skippedDownloads.isBlank()) "completed"
                    else "completed_with_skipped_items",
                )
                // Surface the verified v2 result once, even when an older
                // manually skipped migration had already been acknowledged.
                preferenceStore.write(
                    AndroidLegacyMigrationNoticeStore.ACKNOWLEDGED,
                    false,
                )
            } else {
                preferenceStore.write(
                    PLAYBACK_STATUS,
                    buildList {
                        if (missing > 0) add("$missing missing article(s)")
                        if (ambiguous > 0) add("$ambiguous ambiguous audio attachment(s)")
                        if (discardedDescription.isNotBlank()) add(discardedDescription)
                    }.joinToString("; "),
                )
                preferenceStore.write(
                    AndroidLegacyMigrationNoticeStore.ACKNOWLEDGED,
                    false,
                )
            }
        }
    }

    companion object {
        internal val PLAYBACK_DONE = AndroidPreferenceKey.boolean("migration-e9-playback-done")
        internal val PLAYBACK_STATUS = AndroidPreferenceKey.string("migration-e9-playback-status")
        internal val PLAYBACK_DISCARDED_IDS =
            AndroidPreferenceKey.string("migration-e9-playback-discarded-ids-v1")
        internal val PLAYBACK_VERIFICATION_V2_DONE =
            AndroidPreferenceKey.boolean("migration-e9-playback-verification-v2-done")

        internal fun shouldReopenManualPlaybackSkip(
            playbackDone: Boolean,
            verificationV2Done: Boolean,
            completionKind: String,
            skippedPlaybackDetails: String,
        ): Boolean =
            playbackDone &&
                !verificationV2Done &&
                completionKind == "completed_with_skipped_items" &&
                skippedPlaybackDetails.isNotBlank()

        internal fun parseDiscardedArticleIds(raw: String): Set<Long> =
            raw.split(',').mapNotNull { it.trim().toLongOrNull()?.takeIf { id -> id > 0L } }.toSet()

        internal fun encodeDiscardedArticleIds(ids: Set<Long>): String =
            ids.filter { it > 0L }.sorted().joinToString(",")

        /**
         * Null means local download evidence is incomplete, so a remote miss
         * must stay retryable. A concrete set is safe negative evidence only
         * when every discovered legacy file has a read-only article mapping.
         */
        internal fun downloadedArticleIdsOrNull(
            result: LegacyAndroidDownloadReadResult,
        ): Set<Long>? = when (result) {
            LegacyAndroidDownloadReadResult.Unavailable -> null
            is LegacyAndroidDownloadReadResult.Found -> {
                if (result.records.any { it.articleId == null }) null
                else result.records.mapNotNull { it.articleId }.toSet()
            }
        }

        internal fun shouldDiscardRemoteMiss(
            articleId: Long,
            downloadedArticleIds: Set<Long>?,
        ): Boolean = downloadedArticleIds != null && articleId !in downloadedArticleIds

        internal fun discardedDescription(count: Int): String =
            when (count) {
                0 -> ""
                1 -> "1 old playback position discarded: no local download and no longer available on the server."
                else -> "$count old playback positions discarded: no local download and no longer available on the server."
            }
    }
}
