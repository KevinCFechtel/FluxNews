package de.circledev.fluxnews.nativeapp

/**
 * Native process components that must quiesce before an active Core session is replaced or
 * destructively rebuilt participate through this narrow lifecycle boundary.
 */
internal enum class AndroidCoreLifecycleChange {
    SessionBootstrap,
    AccountReplacement,
    LocalStateRebuild,
    AccountRemoval,
    ConfigurationRestore,
}

internal interface AndroidCoreLifecycleParticipant {
    suspend fun prepareForCoreLifecycleChange(change: AndroidCoreLifecycleChange)
    suspend fun resumeAfterCoreLifecycleChange(change: AndroidCoreLifecycleChange)
}

internal object AndroidNoopCoreLifecycleParticipant : AndroidCoreLifecycleParticipant {
    override suspend fun prepareForCoreLifecycleChange(change: AndroidCoreLifecycleChange) = Unit
    override suspend fun resumeAfterCoreLifecycleChange(change: AndroidCoreLifecycleChange) = Unit
}
