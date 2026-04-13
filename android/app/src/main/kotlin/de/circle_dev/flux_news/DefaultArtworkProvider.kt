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
  }

  override fun onCreate(): Boolean = true

  override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
    val context = context ?: throw FileNotFoundException("Context unavailable")
    if (uri.lastPathSegment != artworkFileName) {
      throw FileNotFoundException("Unsupported artwork URI: $uri")
    }

    val file = File(context.filesDir, artworkFileName)
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

  override fun getType(uri: Uri): String = "image/png"

  override fun insert(uri: Uri, values: ContentValues?): Uri? = null

  override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

  override fun update(
    uri: Uri,
    values: ContentValues?,
    selection: String?,
    selectionArgs: Array<out String>?,
  ): Int = 0
}