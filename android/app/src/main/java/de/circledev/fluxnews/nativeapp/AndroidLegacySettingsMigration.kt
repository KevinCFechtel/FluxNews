package de.circledev.fluxnews.nativeapp

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.DownloadRetention
import uniffi.flux_uniffi.LegacyFeedOpenInMinifluxImportOutcome
import uniffi.flux_uniffi.SyncCompleted

/**
 * E9 settings follow-up. Only the account copied by the account migration can
 * consume Flutter settings. Core's legacy import operations preserve native
 * values. Independent completion markers keep each part retryable.
 */
internal class AndroidLegacySettingsMigration(
    private val reader: () -> LegacyAndroidSettingsReadResult,
    private val preferences: AndroidPreferenceStore,
    private val credentials: AndroidCredentialStore,
    private val runtime: AndroidCoreRuntime,
    private val widgetStore: AndroidWidgetConfigurationStore?,
) : AndroidPostSyncEffect {
    internal constructor(
        context: Context,
        preferences: AndroidPreferenceStore,
        credentials: AndroidCredentialStore,
        runtime: AndroidCoreRuntime,
    ) : this(
        reader = LegacyAndroidStateReader(context)::readSettingsImport,
        preferences = preferences,
        credentials = credentials,
        runtime = runtime,
        widgetStore = AndroidWidgetConfigurationStore(context),
    )

    private val mutex = Mutex()

    override suspend fun apply(sessionGeneration: Long, metadata: SyncCompleted) {
        mutex.withLock {
            val provenance = preferences.read(AndroidLegacyMigrationCoordinator.IMPORTED_ACCOUNT_SERVER, "")
            if (provenance.isBlank()) return@withLock
            val active = credentials.read() ?: return@withLock
            if (active.serverUrl != provenance) return@withLock
            if (preferences.read(SETTINGS_DONE, false) && preferences.read(FEEDS_DONE, false) &&
                preferences.read(LOCAL_DONE, false) && preferences.read(STARTUP_DONE, false) &&
                preferences.read(WIDGET_DONE, false)) return@withLock
            val settings = when (val result = reader()) {
                LegacyAndroidSettingsReadResult.Unavailable -> return@withLock
                is LegacyAndroidSettingsReadResult.Found -> result.settings
            }
            if (!preferences.read(LOCAL_DONE, false)) {
                val local = settings.local
                suspend fun boolean(key: String, value: Boolean?) {
                    if (value != null) preferences.writeIfAbsent(AndroidPreferenceKey.boolean(key), value)
                }
                suspend fun string(key: String, value: String?) {
                    if (value != null) preferences.writeIfAbsent(AndroidPreferenceKey.string(key), value)
                }
                boolean("articles-show-count", local.showArticleCount)
                boolean("navigation-hide-empty", local.hideEmptyNavigation)
                boolean("articles-mark-read-on-scrollover", local.markReadOnScrollover)
                boolean("articles-remove-when-read", local.removeWhenRead)
                if (local.openArticleInReader == true) string("articles-open", "reader")
                string("articles-swipe-leading-full", local.leadingFull)
                string("articles-swipe-leading-additional", local.leadingAdditional)
                string("articles-swipe-trailing-full", local.trailingFull)
                string("articles-swipe-trailing-additional", local.trailingAdditional)
                local.actionBar?.let { actions ->
                    string("article-list-action-ids", actions.joinToString(","))
                }
                preferences.write(LOCAL_DONE, true)
            }
            if (!preferences.read(WIDGET_DONE, false)) {
                settings.widget?.let { seed ->
                    val config = AndroidWidgetConfiguration(
                        scopeType = AndroidWidgetScopeType.fromStored(seed.scope),
                        scopeId = seed.scopeId,
                        readFilter = if (seed.unreadOnly) AndroidWidgetReadFilter.Unread else AndroidWidgetReadFilter.All,
                        sortOrder = if (seed.oldestFirst) AndroidWidgetSortOrder.OldestFirst else AndroidWidgetSortOrder.NewestFirst,
                    )
                    widgetStore?.let { check(it.seedIfAbsent(config) || it.hasSeed()) }
                }
                preferences.write(WIDGET_DONE, true)
            }
            if (!preferences.read(STARTUP_DONE, false)) {
                val local = settings.local
                val nativeScope = preferences.read(
                    AndroidPreferenceKey.string("navigation-startup-scope"), "__absent__",
                )
                if (nativeScope != "__absent__" || local.startupMode == null) {
                    preferences.write(STARTUP_DONE, true)
                } else {
                    val catalog = runtime.localForGeneration(sessionGeneration) { it.navigationCatalog() }
                    val target = when (local.startupMode) {
                        0 -> "allNews"
                        1 -> "starred"
                        2 -> local.startupCategoryId?.takeIf { id -> catalog.categories.any { it.id == id } }
                            ?.let { "category" }
                        3 -> local.startupFeedId?.takeIf { id -> catalog.feeds.any { it.id == id } }
                            ?.let { "feed" }
                        else -> null
                    }
                    if (target == null) {
                        preferences.write(STARTUP_STATUS, "Selected startup feed or category is not in the current catalog")
                    }
                    if (target != null) {
                        if (target == "category") local.startupCategoryId?.let {
                            preferences.writeIfAbsent(AndroidPreferenceKey.long("navigation-startup-category"), it)
                        }
                        if (target == "feed") local.startupFeedId?.let {
                            preferences.writeIfAbsent(AndroidPreferenceKey.long("navigation-startup-feed"), it)
                        }
                        preferences.writeIfAbsent(AndroidPreferenceKey.string("navigation-startup-scope"), target)
                        preferences.write(STARTUP_DONE, true)
                        preferences.remove(STARTUP_STATUS)
                    }
                }
            }
            if (!preferences.read(SETTINGS_DONE, false)) {
                runtime.localForGeneration(sessionGeneration) { core ->
                    core.importLegacyPolicySettings(
                        backgroundSyncEnabled = settings.backgroundSyncEnabled,
                        autoDownloadListeningList = settings.autoDownloadListeningList,
                    )
                    core.importLegacyMediaSettings(
                        unmeteredOnly = settings.unmeteredDownloadsOnly,
                        retention = settings.retentionDays?.let { DownloadRetention.Days(it.toUInt()) },
                        deleteAfterPlayback = settings.deleteAfterPlayback,
                    )
                }
                preferences.write(SETTINGS_DONE, true)
            }
            if (!preferences.read(FEEDS_DONE, false)) {
                var missing = false
                for (feedId in settings.openInMinifluxFeedIds) {
                    val outcome = runtime.localForGeneration(sessionGeneration) {
                        it.importLegacyFeedOpenInMiniflux(feedId)
                    }
                    if (outcome == LegacyFeedOpenInMinifluxImportOutcome.MISSING_FEED) missing = true
                }
                if (!missing) {
                    preferences.write(FEEDS_DONE, true)
                    preferences.remove(FEEDS_STATUS)
                } else {
                    preferences.write(FEEDS_STATUS, "Some legacy feeds are missing from the current catalog")
                }
            }
        }
    }

    companion object {
        internal val SETTINGS_DONE = AndroidPreferenceKey.boolean("migration-e9-settings-done")
        internal val FEEDS_DONE = AndroidPreferenceKey.boolean("migration-e9-feeds-done")
        internal val LOCAL_DONE = AndroidPreferenceKey.boolean("migration-e9-local-done")
        internal val STARTUP_DONE = AndroidPreferenceKey.boolean("migration-e9-startup-done")
        internal val WIDGET_DONE = AndroidPreferenceKey.boolean("migration-e9-widget-done")
        internal val STARTUP_STATUS = AndroidPreferenceKey.string("migration-e9-startup-status")
        internal val FEEDS_STATUS = AndroidPreferenceKey.string("migration-e9-feeds-status")
    }
}
