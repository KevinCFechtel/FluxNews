package de.circledev.fluxnews.nativeapp

import androidx.compose.runtime.staticCompositionLocalOf
import uniffi.flux_uniffi.DeliveryMode
import uniffi.flux_uniffi.ReadArticleRetention

/**
 * Thin Android bridge for article settings that are authoritative in the shared Core.
 *
 * These values intentionally do not have DataStore mirrors. Reading and writing always goes
 * through the active Core session so Android, iOS and macOS observe the same persisted contract.
 */
internal class AndroidCoreArticleSettings(
    private val coreRuntime: AndroidCoreRuntime,
) {
    data class State(
        val retention: ReadArticleRetention,
        val detailCharacterLimit: UInt,
        val liveMutationDelivery: Boolean,
    )

    suspend fun load(): Result<State> = runCatching {
        coreRuntime.local { core ->
            val settings = core.coreSettings()
            State(
                retention = settings.retention,
                detailCharacterLimit = settings.detailCharacterLimit,
                liveMutationDelivery = settings.deliveryMode == DeliveryMode.LIVE,
            )
        }
    }

    suspend fun setRetention(value: ReadArticleRetention): Result<Unit> = runCatching {
        coreRuntime.local { core -> core.setRetention(value) }
    }

    suspend fun setDetailCharacterLimit(value: UInt): Result<Unit> = runCatching {
        coreRuntime.local { core -> core.setDetailCharacterLimit(value) }
    }

    suspend fun setLiveMutationDelivery(enabled: Boolean): Result<Unit> = runCatching {
        coreRuntime.local { core ->
            core.setDeliveryMode(if (enabled) DeliveryMode.LIVE else DeliveryMode.DEFERRED)
        }
    }
}

internal val LocalAndroidCoreArticleSettings = staticCompositionLocalOf<AndroidCoreArticleSettings> {
    error("AndroidCoreArticleSettings was not provided.")
}

internal fun ReadArticleRetention.androidDisplayName(): String = when (this) {
    ReadArticleRetention.DAYS30 -> "30 days"
    ReadArticleRetention.DAYS60 -> "60 days"
    ReadArticleRetention.DAYS90 -> "90 days"
    ReadArticleRetention.DAYS180 -> "180 days"
    ReadArticleRetention.DAYS365 -> "365 days"
}
