package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import java.io.Closeable
import java.io.File

internal enum class AndroidWidgetScopeType(val storedValue: String) {
    All("all"),
    Bookmarks("bookmarks"),
    Category("category"),
    Feed("feed");

    companion object {
        fun fromStored(value: String?): AndroidWidgetScopeType =
            entries.firstOrNull { it.storedValue == value } ?: All
    }
}

internal enum class AndroidWidgetReadFilter(val storedValue: String) {
    Unread("unread"),
    All("all");

    companion object {
        fun fromStored(value: String?): AndroidWidgetReadFilter =
            entries.firstOrNull { it.storedValue == value } ?: Unread
    }
}

internal enum class AndroidWidgetSortOrder(val storedValue: String) {
    NewestFirst("newest"),
    OldestFirst("oldest");

    companion object {
        fun fromStored(value: String?): AndroidWidgetSortOrder =
            entries.firstOrNull { it.storedValue == value } ?: NewestFirst
    }
}

internal data class AndroidWidgetConfiguration(
    val scopeType: AndroidWidgetScopeType = AndroidWidgetScopeType.All,
    val scopeId: Long? = null,
    val readFilter: AndroidWidgetReadFilter = AndroidWidgetReadFilter.Unread,
    val sortOrder: AndroidWidgetSortOrder = AndroidWidgetSortOrder.NewestFirst,
)

internal class AndroidWidgetConfigurationStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun read(appWidgetId: Int): AndroidWidgetConfiguration {
        val prefix = prefix(appWidgetId)
        if (!preferences.contains(prefix + SCOPE_TYPE) && !preferences.contains(prefix + READ_FILTER)) {
            return readSeed() ?: AndroidWidgetConfiguration()
        }
        return AndroidWidgetConfiguration(
            scopeType = AndroidWidgetScopeType.fromStored(preferences.getString(prefix + SCOPE_TYPE, null)),
            scopeId = preferences.getLong(prefix + SCOPE_ID, MISSING_ID).takeUnless { it == MISSING_ID },
            readFilter = AndroidWidgetReadFilter.fromStored(preferences.getString(prefix + READ_FILTER, null)),
            sortOrder = AndroidWidgetSortOrder.fromStored(preferences.getString(prefix + SORT_ORDER, null)),
        )
    }

    fun hasSeed(): Boolean = preferences.contains("migration.seed.scope")

    fun seedIfAbsent(configuration: AndroidWidgetConfiguration): Boolean {
        if (hasSeed()) return false
        return preferences.edit()
            .putString("migration.seed.scope", configuration.scopeType.storedValue)
            .putLong("migration.seed.id", configuration.scopeId ?: MISSING_ID)
            .putString("migration.seed.read", configuration.readFilter.storedValue)
            .putString("migration.seed.sort", configuration.sortOrder.storedValue)
            .commit()
    }

    private fun readSeed(): AndroidWidgetConfiguration? {
        if (!hasSeed()) return null
        return AndroidWidgetConfiguration(
            scopeType = AndroidWidgetScopeType.fromStored(preferences.getString("migration.seed.scope", null)),
            scopeId = preferences.getLong("migration.seed.id", MISSING_ID).takeUnless { it == MISSING_ID },
            readFilter = AndroidWidgetReadFilter.fromStored(preferences.getString("migration.seed.read", null)),
            sortOrder = AndroidWidgetSortOrder.fromStored(preferences.getString("migration.seed.sort", null)),
        )
    }

    fun write(appWidgetId: Int, configuration: AndroidWidgetConfiguration) {
        preferences.edit()
            .putString(prefix(appWidgetId) + SCOPE_TYPE, configuration.scopeType.storedValue)
            .putLong(prefix(appWidgetId) + SCOPE_ID, configuration.scopeId ?: MISSING_ID)
            .putString(prefix(appWidgetId) + READ_FILTER, configuration.readFilter.storedValue)
            .putString(prefix(appWidgetId) + SORT_ORDER, configuration.sortOrder.storedValue)
            .apply()
    }

    fun remove(appWidgetId: Int) {
        val prefix = prefix(appWidgetId)
        preferences.edit().apply {
            preferences.all.keys.filter { it.startsWith(prefix) }.forEach(::remove)
        }.apply()
    }

    private fun prefix(id: Int) = "widget.$id."

    private companion object {
        const val PREFERENCES = "flux_widget_configuration_v1"
        const val SCOPE_TYPE = "scope_type"
        const val SCOPE_ID = "scope_id"
        const val READ_FILTER = "read_filter"
        const val SORT_ORDER = "sort_order"
        const val MISSING_ID = Long.MIN_VALUE
    }
}

internal data class AndroidWidgetCatalogItem(val id: Long, val title: String)
internal data class AndroidWidgetCatalog(
    val categories: List<AndroidWidgetCatalogItem>,
    val feeds: List<AndroidWidgetCatalogItem>,
)

internal data class AndroidWidgetHeader(
    val title: String,
    val count: Long,
    val lastSuccessfulSyncAt: String?,
)

internal data class AndroidWidgetRow(
    val id: Long,
    val feedId: Long,
    val title: String,
    val feedTitle: String,
)

internal class AndroidWidgetProjectionReader(private val root: File) {
    private val store = AndroidWidgetProjectionStore(root)

    fun catalog(): AndroidWidgetCatalog = withDatabase {
        AndroidWidgetCatalog(
            categories = queryCatalog("categories"),
            feeds = queryCatalog("feeds"),
        )
    } ?: AndroidWidgetCatalog(emptyList(), emptyList())

    fun header(configuration: AndroidWidgetConfiguration): AndroidWidgetHeader? = withDatabase {
        val (scopeType, scopeId) = countKey(configuration)
        val countColumn = if (configuration.readFilter == AndroidWidgetReadFilter.Unread) "unread_count" else "all_count"
        val count = rawQuery(
            "SELECT $countColumn FROM counts WHERE scope_type=? AND scope_id=?",
            arrayOf(scopeType, scopeId.toString()),
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else 0L }
        val projectedLastSync = rawQuery(
            "SELECT value FROM metadata WHERE key='last_successful_sync_at'",
            null,
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0).takeIf(String::isNotBlank) else null }
        AndroidWidgetHeader(
            title = scopeTitle(configuration),
            count = count,
            lastSuccessfulSyncAt = store.lastSuccessfulSyncAt() ?: projectedLastSync,
        )
    }

    fun openRows(configuration: AndroidWidgetConfiguration): AndroidWidgetRows? {
        val directory = store.currentDirectory() ?: return null
        val databaseFile = File(directory, DATABASE_NAME)
        if (!databaseFile.isFile) return null
        val db = SQLiteDatabase.openDatabase(databaseFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
        return try {
            val clauses = mutableListOf<String>()
            val args = mutableListOf<String>()
            when (configuration.scopeType) {
                AndroidWidgetScopeType.All -> Unit
                AndroidWidgetScopeType.Bookmarks -> clauses += "is_starred=1"
                AndroidWidgetScopeType.Category -> configuration.scopeId?.let {
                    clauses += "category_id=?"; args += it.toString()
                }
                AndroidWidgetScopeType.Feed -> configuration.scopeId?.let {
                    clauses += "feed_id=?"; args += it.toString()
                }
            }
            if (configuration.readFilter == AndroidWidgetReadFilter.Unread) clauses += "is_read=0"
            val where = if (clauses.isEmpty()) "" else " WHERE " + clauses.joinToString(" AND ")
            val direction = if (configuration.sortOrder == AndroidWidgetSortOrder.NewestFirst) "DESC" else "ASC"
            val cursor = db.rawQuery(
                "SELECT id,feed_id,title,feed_title FROM articles$where ORDER BY published_at $direction,id $direction",
                args.toTypedArray(),
            )
            AndroidWidgetRows(directory, db, cursor)
        } catch (error: Exception) {
            db.close()
            throw error
        }
    }

    private fun countKey(configuration: AndroidWidgetConfiguration): Pair<String, Long> = when (configuration.scopeType) {
        AndroidWidgetScopeType.All -> "all" to 0L
        AndroidWidgetScopeType.Bookmarks -> "bookmarks" to 0L
        AndroidWidgetScopeType.Category -> "category" to (configuration.scopeId ?: Long.MIN_VALUE)
        AndroidWidgetScopeType.Feed -> "feed" to (configuration.scopeId ?: Long.MIN_VALUE)
    }

    private fun SQLiteDatabase.scopeTitle(configuration: AndroidWidgetConfiguration): String = when (configuration.scopeType) {
        AndroidWidgetScopeType.All -> "All News"
        AndroidWidgetScopeType.Bookmarks -> "Bookmarks"
        AndroidWidgetScopeType.Category -> titleFor("categories", configuration.scopeId) ?: "Category"
        AndroidWidgetScopeType.Feed -> titleFor("feeds", configuration.scopeId) ?: "Feed"
    }

    private fun SQLiteDatabase.titleFor(table: String, id: Long?): String? {
        if (id == null) return null
        return rawQuery("SELECT title FROM $table WHERE id=?", arrayOf(id.toString())).use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    }

    private fun SQLiteDatabase.queryCatalog(table: String): List<AndroidWidgetCatalogItem> =
        rawQuery("SELECT id,title FROM $table ORDER BY title COLLATE NOCASE,id", null).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(AndroidWidgetCatalogItem(cursor.getLong(0), cursor.getString(1)))
            }
        }

    private fun <T> withDatabase(block: SQLiteDatabase.() -> T): T? {
        val directory = store.currentDirectory() ?: return null
        val file = File(directory, DATABASE_NAME)
        if (!file.isFile) return null
        return SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use(block)
    }

    private companion object {
        const val DATABASE_NAME = "projection.sqlite3"
    }
}

internal class AndroidWidgetRows(
    val generationDirectory: File,
    private val database: SQLiteDatabase,
    private val cursor: Cursor,
) : Closeable {
    val count: Int get() = cursor.count

    fun rowAt(position: Int): AndroidWidgetRow? {
        if (position !in 0 until cursor.count || !cursor.moveToPosition(position)) return null
        return AndroidWidgetRow(
            id = cursor.getLong(0),
            feedId = cursor.getLong(1),
            title = cursor.getString(2),
            feedTitle = cursor.getString(3),
        )
    }

    fun iconFile(feedId: Long, dark: Boolean): File =
        File(generationDirectory, "icons/$feedId-${if (dark) "dark" else "normal"}.png")

    override fun close() {
        cursor.close()
        database.close()
    }
}
