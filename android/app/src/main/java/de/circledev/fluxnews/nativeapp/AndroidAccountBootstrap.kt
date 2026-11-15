package de.circledev.fluxnews.nativeapp

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.flux_uniffi.AccountValidationResult
import uniffi.flux_uniffi.HttpHeader
import uniffi.flux_uniffi.InitializationConfig

/** Process-scoped account/session lifecycle for normal and headless Android startup paths. */
class AndroidAccountBootstrap private constructor(
    private val credentialReader: () -> StoredAccountCredentials?,
    private val credentialWriter: (StoredAccountCredentials) -> Unit,
    private val credentialClearer: () -> Unit,
    private val hasActiveSession: () -> Boolean,
    private val sessionOpener: suspend (InitializationConfig) -> Unit,
    private val sessionReplacer: suspend (InitializationConfig) -> Unit,
    private val sessionCloser: suspend () -> Unit,
    private val accountValidator: suspend (String, String, List<HttpHeader>) -> AccountValidationResult,
    private val localStateRebuilder: suspend () -> Unit,
    private val accountStateRemover: suspend () -> Unit,
    private val serverVersionReader: suspend (String) -> String?,
    private val serverVersionWriter: suspend (String, String) -> Unit,
    private val serverVersionClearer: suspend () -> Unit,
    private val widgetStateClearer: () -> Unit,
    private val lifecycleParticipant: AndroidCoreLifecycleParticipant,
    private val beforeCredentialRestore: suspend () -> Unit,
    storagePaths: AndroidStoragePaths,
) {
    internal constructor(
        credentialStore: AndroidCredentialStore,
        preferenceStore: AndroidPreferenceStore,
        coreRuntime: AndroidCoreRuntime,
        storagePaths: AndroidStoragePaths,
        onWidgetStateCleared: () -> Unit = {},
        lifecycleParticipant: AndroidCoreLifecycleParticipant = AndroidNoopCoreLifecycleParticipant,
        beforeCredentialRestore: suspend () -> Unit = {},
    ) : this(
        credentialReader = credentialStore::read,
        credentialWriter = credentialStore::write,
        credentialClearer = credentialStore::clear,
        hasActiveSession = coreRuntime::hasActiveSession,
        sessionOpener = { config -> coreRuntime.openSession(config) },
        sessionReplacer = { config -> coreRuntime.replaceSession(config) },
        sessionCloser = coreRuntime::closeSession,
        accountValidator = coreRuntime::validateAccount,
        localStateRebuilder = { coreRuntime.remote { core -> core.rebuildLocalState() } },
        accountStateRemover = { coreRuntime.remote { core -> core.removeAccountState() } },
        serverVersionReader = { server ->
            val storedServer = preferenceStore.read(SERVER_INFO_BASE, "")
            if (storedServer == server) {
                AndroidAccountPresentation.normalizedServerVersion(
                    preferenceStore.read(SERVER_INFO_VERSION, ""),
                )
            } else {
                null
            }
        },
        serverVersionWriter = { server, version ->
            preferenceStore.write(SERVER_INFO_BASE, server)
            preferenceStore.write(SERVER_INFO_VERSION, version)
        },
        serverVersionClearer = {
            preferenceStore.remove(SERVER_INFO_BASE)
            preferenceStore.remove(SERVER_INFO_VERSION)
        },
        widgetStateClearer = {
            AndroidWidgetProjectionStore(storagePaths.widget).clear()
            onWidgetStateCleared()
        },
        lifecycleParticipant = lifecycleParticipant,
        beforeCredentialRestore = beforeCredentialRestore,
        storagePaths = storagePaths,
    )

    internal constructor(
        credentialReader: () -> StoredAccountCredentials?,
        credentialWriter: (StoredAccountCredentials) -> Unit = {},
        credentialClearer: () -> Unit = {},
        hasActiveSession: () -> Boolean,
        sessionOpener: suspend (InitializationConfig) -> Unit,
        sessionReplacer: suspend (InitializationConfig) -> Unit = {},
        sessionCloser: suspend () -> Unit = {},
        accountValidator: suspend (String, String, List<HttpHeader>) -> AccountValidationResult =
            { _, _, _ -> error("Account validation was not configured for this test.") },
        localStateRebuilder: suspend () -> Unit = {},
        accountStateRemover: suspend () -> Unit = {},
        serverVersionReader: suspend (String) -> String? = { null },
        serverVersionWriter: suspend (String, String) -> Unit = { _, _ -> },
        serverVersionClearer: suspend () -> Unit = {},
        widgetStateClearer: () -> Unit = {},
        lifecycleParticipant: AndroidCoreLifecycleParticipant = AndroidNoopCoreLifecycleParticipant,
        beforeCredentialRestore: suspend () -> Unit = {},
        storagePaths: AndroidStoragePaths,
        @Suppress("UNUSED_PARAMETER") testOnly: Unit,
    ) : this(
        credentialReader,
        credentialWriter,
        credentialClearer,
        hasActiveSession,
        sessionOpener,
        sessionReplacer,
        sessionCloser,
        accountValidator,
        localStateRebuilder,
        accountStateRemover,
        serverVersionReader,
        serverVersionWriter,
        serverVersionClearer,
        widgetStateClearer,
        lifecycleParticipant,
        beforeCredentialRestore,
        storagePaths,
    )

    sealed interface State {
        data object Starting : State
        data object AccountRequired : State
        data class Ready(val serverUrl: String, val serverVersion: String? = null) : State
        data class RecoverableError(val message: String) : State
    }

    sealed interface ActivationResult {
        data class Activated(val serverUrl: String, val serverVersion: String) : ActivationResult
        data class Rejected(val message: String) : ActivationResult
    }

    enum class LocalStateRebuildState { Idle, Rebuilding, Succeeded, Failed }

    sealed interface RemovalResult {
        data object Removed : RemovalResult
        data class Rejected(val message: String) : RemovalResult
    }

    private val configFactory = AndroidInitializationConfigFactory(storagePaths)
    private val lifecycleMutex = Mutex()

    @Volatile
    var state: State = State.Starting
        private set

    @Volatile
    var localStateRebuildState: LocalStateRebuildState = LocalStateRebuildState.Idle
        private set

    suspend fun restoreStoredAccount(): State = lifecycleMutex.withLock {
        if (hasActiveSession()) return@withLock state

        state = State.Starting
        try {
            beforeCredentialRestore()
            val credentials = credentialReader()
            if (credentials == null) {
                state = State.AccountRequired
            } else {
                sessionOpener(configFactory.create(credentials))
                lifecycleParticipant.resumeAfterCoreLifecycleChange(AndroidCoreLifecycleChange.SessionBootstrap)
                val version = try {
                    serverVersionReader(credentials.serverUrl)
                } catch (_: Exception) {
                    null
                }
                state = State.Ready(credentials.serverUrl, version)
            }
        } catch (error: Exception) {
            state = State.RecoverableError(safeStartupMessage(error))
        }
        state
    }

    /** Returns the encrypted account material only for the account editor in this process. */
    fun credentialsForEditing(): StoredAccountCredentials? = try {
        credentialReader()
    } catch (_: Exception) {
        null
    }

    /** Internal lifecycle boundary used by the configuration-backup controller. */
    internal suspend fun <T> withConfigurationBackupLock(block: suspend () -> T): T = lifecycleMutex.withLock {
        check(localStateRebuildState != LocalStateRebuildState.Rebuilding) { "Local state rebuild is active." }
        block()
    }

    internal fun credentialsForConfigurationBackup(): StoredAccountCredentials? = credentialReader()

    internal fun writeCredentialsForConfigurationBackup(credentials: StoredAccountCredentials) = credentialWriter(credentials)

    internal fun clearCredentialsForConfigurationBackup() = credentialClearer()

    internal fun initializationConfigFor(credentials: StoredAccountCredentials): InitializationConfig =
        configFactory.create(credentials)

    internal fun publishRestoredAccount(credentials: StoredAccountCredentials) {
        widgetStateClearer()
        localStateRebuildState = LocalStateRebuildState.Idle
        state = State.Ready(credentials.serverUrl)
    }

    internal fun publishConfigurationRecoveryError() {
        state = State.RecoverableError("Configuration restore could not be recovered. Restart FluxNews before making further changes.")
    }

    /** Validates before persistence and stores Core's canonical installation base on success. */
    suspend fun activateAccount(
        serverUrl: String,
        apiKey: String,
        customHeaders: List<StoredCredentialHeader>,
    ): ActivationResult = lifecycleMutex.withLock {
        if (localStateRebuildState == LocalStateRebuildState.Rebuilding) {
            return@withLock ActivationResult.Rejected("Wait for the local state rebuild to finish.")
        }
        localStateRebuildState = LocalStateRebuildState.Idle
        val proposedServer = serverUrl.trim()
        val proposedApiKey = apiKey.trim()
        if (proposedServer.isEmpty() || proposedApiKey.isEmpty()) {
            return@withLock ActivationResult.Rejected("Enter both a Miniflux server URL and API key.")
        }

        val validation = try {
            accountValidator(
                proposedServer,
                proposedApiKey,
                customHeaders.map { HttpHeader(name = it.name, value = it.value) },
            )
        } catch (error: Exception) {
            return@withLock ActivationResult.Rejected(
                AndroidAccountPresentation.validationMessage(error),
            )
        }
        val normalized = StoredAccountCredentials(
            serverUrl = validation.installationBase,
            apiKey = proposedApiKey,
            customHeaders = customHeaders,
        )
        val previous = try {
            credentialReader()
        } catch (_: Exception) {
            return@withLock ActivationResult.Rejected("The existing account credentials could not be read.")
        }

        val replacingSession = hasActiveSession()
        val lifecycleChange = if (replacingSession) {
            AndroidCoreLifecycleChange.AccountReplacement
        } else {
            AndroidCoreLifecycleChange.SessionBootstrap
        }

        try {
            credentialWriter(normalized)
            try {
                val config = configFactory.create(normalized)
                if (replacingSession) {
                    lifecycleParticipant.prepareForCoreLifecycleChange(lifecycleChange)
                    try {
                        sessionReplacer(config)
                    } finally {
                        lifecycleParticipant.resumeAfterCoreLifecycleChange(lifecycleChange)
                    }
                } else {
                    sessionOpener(config)
                    lifecycleParticipant.resumeAfterCoreLifecycleChange(lifecycleChange)
                }
            } catch (error: Exception) {
                if (previous != null) credentialWriter(previous) else credentialClearer()
                throw error
            }
        } catch (_: Exception) {
            return@withLock ActivationResult.Rejected(
                "The account could not be activated. Your previous account is still active.",
            )
        }

        widgetStateClearer()
        try {
            serverVersionWriter(normalized.serverUrl, validation.version)
        } catch (_: Exception) {
            // Account activation is authoritative; informational version persistence is best effort.
        }
        state = State.Ready(normalized.serverUrl, validation.version)
        ActivationResult.Activated(normalized.serverUrl, validation.version)
    }

    suspend fun rebuildLocalState(): LocalStateRebuildState = lifecycleMutex.withLock {
        if (localStateRebuildState == LocalStateRebuildState.Rebuilding) {
            return@withLock localStateRebuildState
        }
        if (!hasActiveSession()) {
            localStateRebuildState = LocalStateRebuildState.Failed
            return@withLock localStateRebuildState
        }

        localStateRebuildState = LocalStateRebuildState.Rebuilding
        lifecycleParticipant.prepareForCoreLifecycleChange(AndroidCoreLifecycleChange.LocalStateRebuild)
        localStateRebuildState = try {
            localStateRebuilder()
            LocalStateRebuildState.Succeeded
        } catch (_: Exception) {
            // Core's rebuild is destructive before the remote synchronization attempt; failure is
            // therefore surfaced exactly as on iOS rather than pretending the old state survived.
            LocalStateRebuildState.Failed
        } finally {
            lifecycleParticipant.resumeAfterCoreLifecycleChange(AndroidCoreLifecycleChange.LocalStateRebuild)
        }
        localStateRebuildState
    }

    suspend fun removeAccount(): RemovalResult = lifecycleMutex.withLock {
        if (localStateRebuildState == LocalStateRebuildState.Rebuilding) {
            return@withLock RemovalResult.Rejected("Wait for the local state rebuild to finish.")
        }

        val hadActiveSession = hasActiveSession()
        if (hadActiveSession) {
            lifecycleParticipant.prepareForCoreLifecycleChange(AndroidCoreLifecycleChange.AccountRemoval)
        }
        try {
            if (hadActiveSession) {
                accountStateRemover()
            }
            credentialClearer()
            widgetStateClearer()
            try {
                serverVersionClearer()
            } catch (_: Exception) {
                // Version metadata is non-sensitive and must not block removal of the account.
            }
            if (hadActiveSession) {
                sessionCloser()
            }
        } catch (_: Exception) {
            if (hasActiveSession()) {
                lifecycleParticipant.resumeAfterCoreLifecycleChange(AndroidCoreLifecycleChange.AccountRemoval)
            }
            return@withLock RemovalResult.Rejected("The account could not be removed.")
        }

        localStateRebuildState = LocalStateRebuildState.Idle
        state = State.AccountRequired
        RemovalResult.Removed
    }

    private fun safeStartupMessage(error: Exception): String = when (error) {
        is CredentialStorageException -> "Stored account credentials could not be read."
        is AndroidLegacyMigrationException -> "The previous FluxNews account could not be migrated yet. Retry or configure the account manually."
        else -> "The stored account could not be started."
    }

    private companion object {
        val SERVER_INFO_BASE = AndroidPreferenceKey.string("account_info_server_base")
        val SERVER_INFO_VERSION = AndroidPreferenceKey.string("account_info_server_version")
    }
}
