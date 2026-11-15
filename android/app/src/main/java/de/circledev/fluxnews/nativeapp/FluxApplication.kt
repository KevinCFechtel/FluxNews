package de.circledev.fluxnews.nativeapp

import android.app.Application
import android.content.Context
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.disk.directory
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.memory.MemoryCache
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch

/**
 * Process bootstrap.
 *
 * Platform trust must complete before any session can make a Core network request. The runtime is
 * intentionally empty after process death; AndroidAccountBootstrap reconstructs its session from
 * the native credential store when an app or future headless entry point requests readiness.
 */
class FluxApplication : Application(), SingletonImageLoader.Factory {
    @Volatile
    internal var carAppPlatformToken: android.media.session.MediaSession.Token? = null

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val storagePaths: AndroidStoragePaths by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidStoragePaths.create(applicationContext) }
    val preferenceStore: AndroidPreferenceStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidPreferenceStore.create(applicationContext) }
    internal val diagnostics: AndroidAppDiagnostics by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidAppDiagnostics(applicationContext, storagePaths, preferenceStore) }
    internal val legacyMigrationNoticeStore: AndroidLegacyMigrationNoticeStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidLegacyMigrationNoticeStore(preferenceStore)
    }
    val coreRuntime: AndroidCoreRuntime by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidCoreRuntime(AndroidCoreDiagnosticListener(diagnostics)) }
    internal val mediaPlaybackCoordinator: AndroidMediaPlaybackCoordinator by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidMediaPlaybackCoordinator(
            context = applicationContext,
            coreRuntime = coreRuntime,
            mediaRoot = storagePaths.media,
            scope = applicationScope,
            diagnostics = diagnostics,
            onCoreMediaMutation = { generation ->
                mediaTransferCoordinator.reconcileAndSignal(generation)
            },
        )
    }
    internal val mediaTransferCoordinator: AndroidMediaTransferCoordinator by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidMediaTransferCoordinator(
            context = applicationContext,
            coreRuntime = coreRuntime,
            playbackCoordinator = mediaPlaybackCoordinator,
            diagnostics = diagnostics,
        )
    }
    internal val mediaRuntime: AndroidMediaRuntime by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidMediaRuntime(
            coreRuntime,
            diagnostics,
            mediaPlaybackCoordinator,
            mediaTransferCoordinator,
        )
    }
    internal val systemNotifications: AndroidSystemNotificationManager by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidSystemNotificationManager(applicationContext, coreRuntime, diagnostics)
    }
    internal val widgetProjection: AndroidWidgetProjectionCoordinator by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidWidgetProjectionCoordinator(
            coreRuntime = coreRuntime,
            store = AndroidWidgetProjectionStore(storagePaths.widget),
            scope = applicationScope,
            diagnostics = diagnostics,
            onProjectionChanged = { AndroidWidgetUpdates.refreshAll(applicationContext) },
        )
    }
    internal val widgetRouting: AndroidWidgetRouting by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidWidgetRouting()
    }
    internal val legacySettingsMigration: AndroidLegacySettingsMigration by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidLegacySettingsMigration(applicationContext, preferenceStore, credentialStore, coreRuntime)
    }
    internal val legacyPlaybackMigration: AndroidLegacyPlaybackMigration by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidLegacyPlaybackMigration(applicationContext, preferenceStore, credentialStore, coreRuntime)
    }
    internal val legacyDownloadMigration: AndroidLegacyDownloadMigration by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidLegacyDownloadMigration(applicationContext, preferenceStore, credentialStore, coreRuntime, storagePaths.media, diagnostics)
    }
    internal val postSyncEffects: AndroidPostSyncEffects by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidPostSyncEffects(
            activeSessionGeneration = coreRuntime::activeSessionGeneration,
            effects = listOf(legacySettingsMigration, legacyPlaybackMigration, legacyDownloadMigration, systemNotifications, widgetProjection, mediaTransferCoordinator),
            onEffectError = { effect, error ->
                diagnostics.record(
                    AndroidAppLogLevel.Error,
                    "post-sync",
                    "${effect.javaClass.simpleName} failed: ${error.javaClass.simpleName}: ${error.message.orEmpty()}",
                )
            },
        )
    }
    val syncCoordinator: AndroidSyncCoordinator by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidSyncCoordinator(coreRuntime, postSyncEffects)
    }
    internal val timelineStore: AndroidArticleTimelineStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidArticleTimelineStore(coreRuntime, mediaTransferCoordinator)
    }
    internal val searchStore: AndroidSearchStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidSearchStore(coreRuntime, mediaTransferCoordinator)
    }
    internal val listeningListStore: AndroidListeningListStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidListeningListStore(coreRuntime, mediaTransferCoordinator)
    }
    internal val autoMediaLibraryStore: AndroidAutoMediaLibraryStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidAutoMediaLibraryStore(applicationContext, coreRuntime, diagnostics)
    }
    internal val readerStore: AndroidReaderStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidReaderStore(coreRuntime) }
    internal val articleOpenResolver: AndroidArticleOpenResolver by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidArticleOpenResolver(coreRuntime) }
    internal val backgroundSync: AndroidBackgroundSync by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidBackgroundSync(applicationContext, coreRuntime, accountBootstrap, postSyncEffects, diagnostics)
    }
    val credentialStore: AndroidCredentialStore by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidCredentialStore(applicationContext) }
    internal val legacyMigration: AndroidLegacyMigrationCoordinator by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidLegacyMigrationCoordinator(
            context = applicationContext,
            credentialStore = credentialStore,
            preferenceStore = preferenceStore,
            onCredentialsImported = { credentials ->
                diagnostics.setSensitiveValues(
                    buildList {
                        add(credentials.apiKey)
                        credentials.customHeaders.forEach { add(it.value) }
                    },
                )
                diagnostics.record(
                    AndroidAppLogLevel.Info,
                    "migration",
                    "Legacy Flutter account copied into native credential storage.",
                )
            },
        )
    }
    internal val navigationPreferences: AndroidNavigationPreferences by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidNavigationPreferences(preferenceStore) }
    internal val articlePreferences: AndroidArticlePreferences by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidArticlePreferences(preferenceStore) }
    internal val actionBarPreferences: AndroidActionBarPreferences by lazy(LazyThreadSafetyMode.SYNCHRONIZED) { AndroidActionBarPreferences(preferenceStore) }
    internal val configurationBackup: AndroidConfigurationBackupController by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidConfigurationBackupController(
            accountBootstrap,
            coreRuntime,
            navigationPreferences,
            articlePreferences,
            actionBarPreferences,
            mediaRuntime,
        )
    }
    val accountBootstrap: AndroidAccountBootstrap by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        AndroidAccountBootstrap(
            credentialStore = credentialStore,
            preferenceStore = preferenceStore,
            coreRuntime = coreRuntime,
            storagePaths = storagePaths,
            lifecycleParticipant = mediaRuntime,
            beforeCredentialRestore = legacyMigration::prepareAccountForRestore,
            onWidgetStateCleared = { AndroidWidgetUpdates.refreshAll(applicationContext) },
        )
    }

    override fun newImageLoader(context: Context): ImageLoader {
        val imageHttpClient = OkHttpClient.Builder()
            // OkHttp 5 Happy Eyeballs: race IPv6/IPv4 routes instead of waiting
            // for a broken IPv6 path to time out before trying IPv4.
            .fastFallback(true)
            .retryOnConnectionFailure(true)
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .callTimeout(8, TimeUnit.SECONDS)
            .build()

        return ImageLoader.Builder(context.applicationContext)
            .components {
                add(
                    OkHttpNetworkFetcherFactory(
                        callFactory = { imageHttpClient },
                    ),
                )
            }
            .memoryCache {
                MemoryCache.Builder()
                    .maxSizePercent(context.applicationContext, 0.15)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(context.applicationContext.cacheDir.resolve("article-images"))
                    .maxSizeBytes(256L * 1024L * 1024L)
                    .build()
            }
            .build()
    }

    override fun onCreate() {
        super.onCreate()
        AndroidPlatformTrust.initialize(this)
        applicationScope.launch {
            diagnostics.initialize()
            runCatching { credentialStore.read() }.getOrNull()?.let { credentials ->
                diagnostics.setSensitiveValues(buildList {
                    add(credentials.apiKey)
                    credentials.customHeaders.forEach { add(it.value) }
                })
            }
            diagnostics.record(AndroidAppLogLevel.Info, "app", "FluxNews process started")
        }
    }
}
