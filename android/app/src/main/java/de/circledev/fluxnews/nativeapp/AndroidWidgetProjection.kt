package de.circledev.fluxnews.nativeapp

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.util.AtomicFile
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import uniffi.flux_uniffi.FeedIconVariant
import uniffi.flux_uniffi.SyncCompleted
import uniffi.flux_uniffi.WidgetArticle
import uniffi.flux_uniffi.WidgetData

/**
 * Android-owned, credential-free widget projection.
 *
 * The widget process reads only this projection. It never initializes Core, opens Core SQLite,
 * reads credentials, or talks to Miniflux.
 */
internal class AndroidWidgetProjectionCoordinator(
    private val coreRuntime: AndroidCoreRuntime,
    private val store: AndroidWidgetProjectionStore,
    scope: CoroutineScope,
    private val diagnostics: AndroidAppDiagnostics? = null,
    private val onProjectionChanged: () -> Unit = {},
) : AndroidPostSyncEffect {
    private val writeMutex = Mutex()
    private val refreshRequests = Channel<Long>(Channel.CONFLATED)

    init {
        scope.launch {
            for (generation in refreshRequests) {
                delay(300)
                runCatching { refreshNow(generation) }
            }
        }
    }

    fun requestRefresh(sessionGeneration: Long) {
        refreshRequests.trySend(sessionGeneration)
    }

    suspend fun ensureAvailable(sessionGeneration: Long) {
        if (!store.hasCurrentProjection()) refreshNow(sessionGeneration)
    }

    override suspend fun apply(sessionGeneration: Long, metadata: SyncCompleted) {
        diagnostics?.record(
            AndroidAppLogLevel.Info,
            "widget",
            "post-sync projection pass reason=" + metadata.reason +
                " data_changed=" + metadata.dataChanged +
                " navigation_changed=" + metadata.navigationChanged,
        )
        if (!metadata.dataChanged && !metadata.navigationChanged && store.hasCurrentProjection()) {
            val lastSuccessfulSyncAt = coreRuntime.localForGeneration(sessionGeneration) {
                it.lastSuccessfulSyncAt()
            }
            store.writeLastSuccessfulSyncAt(lastSuccessfulSyncAt)
            onProjectionChanged()
            diagnostics?.record(AndroidAppLogLevel.Info, "widget", "projection timestamp refreshed")
            return
        }
        refreshNow(sessionGeneration)
    }

    suspend fun refreshNow(sessionGeneration: Long) = withContext(Dispatchers.IO) {
        if (coreRuntime.activeSessionGeneration() != sessionGeneration) return@withContext
        writeMutex.withLock {
            if (coreRuntime.activeSessionGeneration() != sessionGeneration) return@withLock

            val widgetData = coreRuntime.localForGeneration(sessionGeneration) { it.widgetData() }
            val articles = ArrayList<WidgetArticle>()
            var cursor: uniffi.flux_uniffi.ArticleCursor? = null
            do {
                val page = coreRuntime.localForGeneration(sessionGeneration) {
                    it.widgetArticlesPage(PAGE_SIZE, cursor)
                }
                articles += page.articles
                cursor = page.nextCursor
            } while (cursor != null && coreRuntime.activeSessionGeneration() == sessionGeneration)

            if (coreRuntime.activeSessionGeneration() != sessionGeneration) return@withLock
            val icons = buildMap {
                for (feed in widgetData.feeds) {
                    for (variant in listOf(FeedIconVariant.NORMAL, FeedIconVariant.DARK)) {
                        val icon = runCatching {
                            coreRuntime.remoteForGeneration(sessionGeneration) {
                                it.feedIcon(feed.id, variant)
                            }
                        }.getOrNull()
                        if (icon != null) put(AndroidWidgetIconKey(feed.id, variant), icon.pngData)
                    }
                }
            }
            if (coreRuntime.activeSessionGeneration() != sessionGeneration) return@withLock
            store.replace(widgetData, articles, icons)
            store.writeLastSuccessfulSyncAt(widgetData.lastSuccessfulSyncAt)
            onProjectionChanged()
            diagnostics?.record(
                AndroidAppLogLevel.Info,
                "widget",
                "projection refreshed articles=" + articles.size + " feeds=" + widgetData.feeds.size + " icons=" + icons.size,
            )
        }
    }

    fun clear() {
        store.clear()
        onProjectionChanged()
    }

    private companion object {
        const val PAGE_SIZE = 500u
    }
}

internal data class AndroidWidgetIconKey(
    val feedId: Long,
    val variant: FeedIconVariant,
)

internal class AndroidWidgetProjectionStore(
    private val root: File,
) {
    private val generations = File(root, "projection-v1")
    private val pointer = AtomicFile(File(root, "projection-v1.current"))
    private val lastSuccessfulSync = AtomicFile(File(root, "last-successful-sync-v1"))

    fun hasCurrentProjection(): Boolean = currentDirectory()?.let { File(it, DATABASE_NAME).isFile } == true

    fun replace(
        data: WidgetData,
        articles: List<WidgetArticle>,
        icons: Map<AndroidWidgetIconKey, ByteArray>,
    ) {
        root.mkdirs()
        generations.mkdirs()
        val generationId = UUID.randomUUID().toString()
        val directory = File(generations, generationId).apply { mkdirs() }
        try {
            val databaseFile = File(directory, DATABASE_NAME)
            writeDatabase(databaseFile, data, articles)
            writeIcons(File(directory, "icons"), icons)
            writePointer(generationId)
            prune(generationId)
        } catch (error: Exception) {
            directory.deleteRecursively()
            throw error
        }
    }

    fun writeLastSuccessfulSyncAt(value: String?) {
        root.mkdirs()
        if (value.isNullOrBlank()) {
            runCatching { lastSuccessfulSync.delete() }
            return
        }
        val stream = lastSuccessfulSync.startWrite()
        try {
            stream.write(value.toByteArray(StandardCharsets.UTF_8))
            lastSuccessfulSync.finishWrite(stream)
        } catch (error: Exception) {
            lastSuccessfulSync.failWrite(stream)
            throw error
        }
    }

    fun lastSuccessfulSyncAt(): String? {
        val file = lastSuccessfulSync.baseFile
        if (!file.isFile) return null
        return runCatching { file.readText().trim().takeIf(String::isNotBlank) }.getOrNull()
    }

    fun currentDirectory(): File? {
        val pointerFile = pointer.baseFile
        if (!pointerFile.isFile) return null
        val generationId = runCatching { pointerFile.readText().trim() }.getOrNull().orEmpty()
        if (generationId.isBlank()) return null
        return File(generations, generationId).takeIf { it.isDirectory }
    }

    fun clear() {
        runCatching { pointer.delete() }
        runCatching { lastSuccessfulSync.delete() }
        generations.deleteRecursively()
    }

    private fun writeDatabase(file: File, data: WidgetData, articles: List<WidgetArticle>) {
        SQLiteDatabase.openOrCreateDatabase(file, null).use { db ->
            db.beginTransaction()
            try {
                db.execSQL("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT)")
                db.execSQL("CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL)")
                db.execSQL("CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL, title TEXT NOT NULL)")
                db.execSQL("CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL, category_id INTEGER NOT NULL, feed_title TEXT NOT NULL, title TEXT NOT NULL, published_at TEXT NOT NULL, is_read INTEGER NOT NULL, is_starred INTEGER NOT NULL)")
                db.execSQL("CREATE INDEX articles_newest ON articles(published_at DESC, id DESC)")
                db.execSQL("CREATE INDEX articles_oldest ON articles(published_at ASC, id ASC)")
                db.execSQL("CREATE INDEX articles_feed ON articles(feed_id, published_at DESC, id DESC)")
                db.execSQL("CREATE INDEX articles_category ON articles(category_id, published_at DESC, id DESC)")
                db.execSQL("CREATE INDEX articles_unread ON articles(is_read, published_at DESC, id DESC)")
                db.execSQL("CREATE INDEX articles_starred ON articles(is_starred, published_at DESC, id DESC)")
                db.execSQL("CREATE TABLE counts (scope_type TEXT NOT NULL, scope_id INTEGER NOT NULL, unread_count INTEGER NOT NULL, all_count INTEGER NOT NULL, PRIMARY KEY(scope_type, scope_id))")

                putMetadata(db, "schema_version", "1")
                putMetadata(db, "last_successful_sync_at", data.lastSuccessfulSyncAt.orEmpty())

                data.categories.forEach { category ->
                    db.insertOrThrow("categories", null, ContentValues().apply {
                        put("id", category.id); put("title", category.title)
                    })
                }
                data.feeds.forEach { feed ->
                    db.insertOrThrow("feeds", null, ContentValues().apply {
                        put("id", feed.id); put("category_id", feed.categoryId); put("title", feed.title)
                    })
                }
                articles.forEach { article ->
                    db.insertOrThrow("articles", null, ContentValues().apply {
                        put("id", article.id)
                        put("feed_id", article.feedId)
                        put("category_id", article.categoryId)
                        put("feed_title", article.feedTitle)
                        put("title", article.title)
                        put("published_at", article.publishedAt)
                        put("is_read", if (article.isRead) 1 else 0)
                        put("is_starred", if (article.isStarred) 1 else 0)
                    })
                }

                insertCount(db, "all", 0L, data.counts.allUnread, data.counts.allArticles)
                insertCount(db, "bookmarks", 0L, data.counts.bookmarksUnread, data.counts.bookmarks)
                val feedUnread = data.counts.feedUnread.associate { it.id to it.count }
                val feedAll = data.counts.feedAll.associate { it.id to it.count }
                data.feeds.forEach { insertCount(db, "feed", it.id, feedUnread[it.id] ?: 0uL, feedAll[it.id] ?: 0uL) }
                val categoryUnread = data.counts.categoryUnread.associate { it.id to it.count }
                val categoryAll = data.counts.categoryAll.associate { it.id to it.count }
                data.categories.forEach { insertCount(db, "category", it.id, categoryUnread[it.id] ?: 0uL, categoryAll[it.id] ?: 0uL) }

                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }
    }

    private fun writeIcons(directory: File, icons: Map<AndroidWidgetIconKey, ByteArray>) {
        directory.mkdirs()
        icons.forEach { (key, bytes) ->
            val suffix = if (key.variant == FeedIconVariant.DARK) "dark" else "normal"
            File(directory, "${key.feedId}-$suffix.png").writeBytes(bytes)
        }
    }

    private fun putMetadata(db: SQLiteDatabase, key: String, value: String) {
        db.insertOrThrow("metadata", null, ContentValues().apply { put("key", key); put("value", value) })
    }

    private fun insertCount(db: SQLiteDatabase, type: String, id: Long, unread: ULong, all: ULong) {
        db.insertOrThrow("counts", null, ContentValues().apply {
            put("scope_type", type)
            put("scope_id", id)
            put("unread_count", unread.toLong())
            put("all_count", all.toLong())
        })
    }

    private fun writePointer(generationId: String) {
        val stream = pointer.startWrite()
        try {
            stream.write(generationId.toByteArray(StandardCharsets.UTF_8))
            pointer.finishWrite(stream)
        } catch (error: Exception) {
            pointer.failWrite(stream)
            throw error
        }
    }

    private fun prune(current: String) {
        val directories = generations.listFiles()?.filter { it.isDirectory }.orEmpty()
            .sortedByDescending { it.lastModified() }
        directories.filter { it.name != current }.drop(1).forEach { it.deleteRecursively() }
    }

    private companion object {
        const val DATABASE_NAME = "projection.sqlite3"
    }
}
