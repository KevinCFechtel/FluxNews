package de.circledev.fluxnews.nativeapp

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.LruCache
import androidx.annotation.DrawableRes
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Request
import uniffi.flux_uniffi.MediaArtworkSource

/**
 * Read-only local artwork bridge for Android Auto / AAOS.
 *
 * Car media browsers require artwork URIs that resolve locally. Core keeps artwork ownership,
 * while this provider exposes only the selected enclosure artwork through per-item content URIs.
 * Browse requests keep the normal Listening List fallback. Now Playing requests use the dedicated
 * padded Now Playing fallback so system surfaces can crop it independently without changing rows.
 */
class AndroidAutoArtworkProvider : ContentProvider() {
    private val artworkCache = object : LruCache<String, ByteArray>(16 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int =
            (value.size / 1024).coerceAtLeast(1)
    }

    private val httpClient = OkHttpClient.Builder()
        .fastFallback(true)
        .retryOnConnectionFailure(true)
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .callTimeout(8, TimeUnit.SECONDS)
        .build()

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "image/*"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Artwork provider is read-only.")
        val pathSegments = uri.pathSegments
        val artworkPath = pathSegments
            .takeIf { it.size == 2 }
            ?.firstOrNull()
            ?.takeIf { it == ENCLOSURE_PATH || it == NOW_PLAYING_PATH }
            ?: throw FileNotFoundException("Invalid artwork URI.")
        val enclosureId = pathSegments[1]
            .toLongOrNull()
            ?.takeIf { it > 0L }
            ?: throw FileNotFoundException("Invalid artwork URI.")
        val nowPlaying = artworkPath == NOW_PLAYING_PATH

        return openPipeHelper(
            uri,
            getType(uri),
            Bundle.EMPTY,
            enclosureId,
        ) { output, _, _, _, _ ->
            val bytes = resolveArtworkBytes(enclosureId) ?: fallbackArtworkBytes(nowPlaying)
            runCatching {
                ParcelFileDescriptor.AutoCloseOutputStream(output).use { stream ->
                    stream.write(bytes)
                }
            }.onFailure { failure ->
                // Car hosts cancel artwork requests aggressively while rows leave the viewport.
                // A closed consumer pipe is normal cancellation, not an app-fatal condition.
                val app = context?.applicationContext as? FluxApplication
                app?.diagnostics?.record(
                    AndroidAppLogLevel.Debug,
                    "android-auto-artwork",
                    "Artwork pipe closed enclosure=" + enclosureId +
                        " nowPlaying=" + nowPlaying +
                        " error=" + failure.javaClass.simpleName,
                )
            }
        }
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private fun resolveArtworkBytes(enclosureId: Long): ByteArray? {
        val app = context?.applicationContext as? FluxApplication ?: return null
        val source = runBlocking {
            val ready = app.accountBootstrap.restoreStoredAccount()
            if (ready !is AndroidAccountBootstrap.State.Ready) return@runBlocking null
            val generation = app.coreRuntime.activeSessionGeneration() ?: return@runBlocking null
            runCatching {
                app.coreRuntime.localForGeneration(generation) { core ->
                    core.mediaArtworkSource(enclosureId = enclosureId)
                }
            }.getOrNull()
        } ?: return null

        val cacheKey = when (source) {
            is MediaArtworkSource.LocalReference -> "local:" + source.reference
            is MediaArtworkSource.RemoteUrl -> "remote:" + source.url
        }
        artworkCache.get(cacheKey)?.let { return it }

        val bytes = when (source) {
            is MediaArtworkSource.LocalReference -> runBlocking {
                val generation = app.coreRuntime.activeSessionGeneration()
                    ?: return@runBlocking null
                runCatching {
                    app.coreRuntime.localForGeneration(generation) { core ->
                        core.mediaArtwork(reference = source.reference)
                    }
                }.getOrNull()
            }
            is MediaArtworkSource.RemoteUrl -> loadRemoteArtwork(source.url)
        } ?: return null

        artworkCache.put(cacheKey, bytes)
        return bytes
    }

    private fun loadRemoteArtwork(url: String): ByteArray? {
        val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() !in setOf("http", "https")) return null

        return runCatching {
            httpClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
                if (!response.isSuccessful) return@use null
                val body = response.body
                val contentLength = body.contentLength()
                if (contentLength > MAX_ARTWORK_BYTES) return@use null

                body.byteStream().use { input ->
                    val output = ByteArrayOutputStream(
                        contentLength
                            .takeIf { it in 1..MAX_ARTWORK_BYTES }
                            ?.toInt()
                            ?: DEFAULT_BUFFER_SIZE,
                    )
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_ARTWORK_BYTES) return@use null
                        output.write(buffer, 0, read)
                    }
                    output.toByteArray().takeIf(ByteArray::isNotEmpty)
                }
            }
        }.getOrNull()
    }

    private fun fallbackArtworkBytes(nowPlaying: Boolean): ByteArray {
        val cacheKey = if (nowPlaying) {
            NOW_PLAYING_FALLBACK_CACHE_KEY
        } else {
            BROWSE_FALLBACK_CACHE_KEY
        }
        artworkCache.get(cacheKey)?.let { return it }

        val drawable = if (nowPlaying) {
            R.drawable.fallback_artwork_now_playing
        } else {
            R.drawable.fallback_artwork
        }
        val bytes = drawableResourceBytes(drawable)
        artworkCache.put(cacheKey, bytes)
        return bytes
    }

    private fun drawableResourceBytes(
        @DrawableRes drawable: Int,
    ): ByteArray {
        val appContext = requireNotNull(context)
        val uri = Uri.Builder()
            .scheme("android.resource")
            .authority(appContext.packageName)
            .appendPath("drawable")
            .appendPath(appContext.resources.getResourceEntryName(drawable))
            .build()

        return requireNotNull(appContext.contentResolver.openInputStream(uri)) {
            "Unable to open fallback artwork resource."
        }.use { it.readBytes() }
    }

    companion object {
        private const val ENCLOSURE_PATH = "enclosure"
        private const val NOW_PLAYING_PATH = "now-playing"
        private const val BROWSE_FALLBACK_CACHE_KEY = "fallback:browse"
        private const val NOW_PLAYING_FALLBACK_CACHE_KEY = "fallback:now-playing"
        private const val MAX_ARTWORK_BYTES = 8L * 1024L * 1024L

        fun uri(context: Context, enclosureId: Long): Uri =
            artworkUri(context, ENCLOSURE_PATH, enclosureId)

        fun nowPlayingUri(context: Context, enclosureId: Long): Uri =
            artworkUri(context, NOW_PLAYING_PATH, enclosureId)

        private fun artworkUri(
            context: Context,
            path: String,
            enclosureId: Long,
        ): Uri =
            Uri.Builder()
                .scheme("content")
                .authority(context.packageName + ".autoartwork")
                .appendPath(path)
                .appendPath(enclosureId.toString())
                .build()
    }
}
