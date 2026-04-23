package de.circle_dev.flux_news

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

class DefaultArtworkProvider : ContentProvider() {
  companion object {
    const val authority = "de.circle_dev.flux_news.defaultart"
    private const val artworkFileName = "default_audio_artwork.png"
    private const val androidArtworkFileName = "default_audio_artwork_android.png"
    private const val artworkCacheDir = "audio_artwork_cache"
  }

  override fun onCreate(): Boolean = true

  override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
    val context = context ?: throw FileNotFoundException("Context unavailable")
    val segments = uri.pathSegments

    val file: File = when {
      segments.size == 1 && (segments[0] == artworkFileName || segments[0] == androidArtworkFileName) -> {
        File(context.filesDir, segments[0])
      }
      segments.size == 2 && segments[0] == artworkCacheDir -> {
        val fileName = segments[1]
        if (fileName.contains('/') || fileName.contains("..") || !fileName.startsWith("artwork_")) {
          throw FileNotFoundException("Invalid artwork filename: $fileName")
        }
        File(File(context.filesDir, artworkCacheDir), fileName)
      }
      else -> throw FileNotFoundException("Unsupported artwork URI: $uri")
    }

    if (!file.exists()) {
      throw FileNotFoundException("Artwork file missing: ${file.absolutePath}")
    }

    return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
  }

  override fun query(
    uri: Uri,
    projection: Array<out String>?,
    selection: String?,
    selectionArgs: Array<out String>?,
    sortOrder: String?,
  ): Cursor? = null

  override fun getType(uri: Uri): String {
    val segment = uri.lastPathSegment ?: return "image/png"
    return when {
      segment.endsWith(".jpg", ignoreCase = true) || segment.endsWith(".jpeg", ignoreCase = true) -> "image/jpeg"
      segment.endsWith(".gif", ignoreCase = true) -> "image/gif"
      else -> "image/png"
    }
  }

  override fun insert(uri: Uri, values: ContentValues?): Uri? = null

  override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

  override fun update(
    uri: Uri,
    values: ContentValues?,
    selection: String?,
    selectionArgs: Array<out String>?,
  ): Int = 0
}