package de.circledev.fluxnews.nativeapp

import uniffi.flux_uniffi.HttpHeader
import uniffi.flux_uniffi.InitializationConfig

/**
 * The single productive Android mapping from native account/storage ownership into Core startup.
 *
 * Callers supply only Android-owned durable paths and credentials that were either restored from
 * AndroidCredentialStore or freshly validated before persistence. Screens and ViewModels must not
 * assemble Core paths or InitializationConfig values themselves.
 */
internal class AndroidInitializationConfigFactory(
    private val storagePaths: AndroidStoragePaths,
) {
    fun create(credentials: StoredAccountCredentials): InitializationConfig = InitializationConfig(
        persistentData = storagePaths.persistentData.absolutePath,
        cache = storagePaths.cache.absolutePath,
        media = storagePaths.media.absolutePath,
        baseUrl = credentials.serverUrl,
        apiKey = credentials.apiKey,
        customHeaders = credentials.customHeaders.map { header ->
            HttpHeader(name = header.name, value = header.value)
        },
    )
}
