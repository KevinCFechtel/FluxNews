package de.circledev.fluxnews.nativeapp

import java.net.URI
import uniffi.flux_uniffi.AccountValidationException

/** Android-native presentation mapping for the shared Miniflux account semantics. */
internal object AndroidAccountPresentation {
    fun validationMessage(error: Exception): String = when (error) {
        is AccountValidationException.InvalidUrl,
        is AccountValidationException.UnsupportedUrlScheme ->
            "Enter a valid HTTP or HTTPS Miniflux server URL."
        is AccountValidationException.Network,
        is AccountValidationException.ServerUnavailable ->
            "The Miniflux server could not be reached. Check the server URL and network connection."
        is AccountValidationException.Unauthorized -> "Miniflux rejected the API key."
        is AccountValidationException.IncompatibleServer ->
            "This server does not provide the required Miniflux endpoint."
        is AccountValidationException.InvalidCustomHeader ->
            "Custom headers must have unique valid names and cannot replace FluxNews transport headers."
        is AccountValidationException.InvalidResponse ->
            "The Miniflux server returned an unexpected response."
        else -> "The Miniflux account could not be validated."
    }

    fun usesUnencryptedHttp(server: String): Boolean = runCatching {
        URI(server.trim()).scheme?.equals("http", ignoreCase = true) == true
    }.getOrDefault(false)

    fun normalizedServerVersion(version: String?): String? =
        version?.trim()?.takeIf(String::isNotEmpty)
}
