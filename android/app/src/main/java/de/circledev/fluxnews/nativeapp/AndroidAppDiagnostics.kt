package de.circledev.fluxnews.nativeapp

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import uniffi.flux_uniffi.DiagnosticLevel
import uniffi.flux_uniffi.DiagnosticListener
import uniffi.flux_uniffi.DiagnosticRecord

enum class AndroidAppLogLevel { Trace, Debug, Info, Warning, Error }

data class AndroidAppLogEntry(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: String = Instant.now().toString(),
    val level: AndroidAppLogLevel,
    val category: String,
    val message: String,
)

class AndroidAppDiagnostics internal constructor(
    context: Context,
    private val storagePaths: AndroidStoragePaths,
    private val preferenceStore: AndroidPreferenceStore,
    private val maxEntries: Int = 5_000,
    private val maxFileBytes: Long = 2_000_000,
) {
    private val appContext = context.applicationContext
    private val lock = ReentrantLock()
    private val logFile = File(storagePaths.logs, "support.jsonl")
    private val _entries = MutableStateFlow(loadEntries())
    val entries: StateFlow<List<AndroidAppLogEntry>> = _entries.asStateFlow()
    private val sensitiveValues = linkedSetOf<String>()
    @Volatile private var debugLoggingEnabled = false

    suspend fun initialize() {
        debugLoggingEnabled = preferenceStore.read(DEBUG_LOGGING, false)
    }

    fun isDebugLoggingEnabled(): Boolean = debugLoggingEnabled

    suspend fun setDebugLoggingEnabled(enabled: Boolean) {
        debugLoggingEnabled = enabled
        preferenceStore.write(DEBUG_LOGGING, enabled)
        record(AndroidAppLogLevel.Info, "diagnostics", "Debug logging ${if (enabled) "enabled" else "disabled"}")
    }

    fun setSensitiveValues(values: Collection<String>) = lock.withLock {
        sensitiveValues.clear()
        sensitiveValues += values.map(String::trim).filter { it.length >= 4 }
    }

    fun record(level: AndroidAppLogLevel, category: String, message: String): String? {
        if ((level == AndroidAppLogLevel.Debug || level == AndroidAppLogLevel.Trace) && !debugLoggingEnabled) return null
        return lock.withLock {
            val sanitized = sanitize(message).take(4_096)
            val entry = AndroidAppLogEntry(level = level, category = category.take(120), message = sanitized)
            val updated = (_entries.value + entry).takeLast(maxEntries)
            _entries.value = updated
            append(entry, updated)
            logToPlatform(entry)
            sanitized
        }
    }

    fun clear() = lock.withLock {
        _entries.value = emptyList()
        if (logFile.exists()) logFile.delete()
    }

    fun exportText(versionName: String, versionCode: Long): String {
        val snapshot = _entries.value
        return buildString {
            appendLine("FluxNews Diagnostics")
            appendLine("Generated: ${Instant.now()}")
            appendLine("App version: $versionName ($versionCode)")
            appendLine("OS: Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Debug logging: ${if (debugLoggingEnabled) "enabled" else "disabled"}")
            appendLine("Records: ${snapshot.size}")
            appendLine()
            snapshot.forEach { appendLine(recordText(it)) }
        }
    }

    private fun sanitize(message: String): String {
        var value = message
        sensitiveValues.forEach { secret -> value = value.replace(secret, "<redacted>") }
        value = value.replace(Regex("(?i)(authorization|x-auth-token|api[-_ ]?key)(\\s*[:=]\\s*)([^\\s,;]+)"), "$1$2<redacted>")
        return value
    }

    private fun append(entry: AndroidAppLogEntry, current: List<AndroidAppLogEntry>) {
        storagePaths.logs.mkdirs()
        logFile.appendText(encode(entry) + "\n")
        if (logFile.length() > maxFileBytes) rewrite(current)
    }

    private fun rewrite(entries: List<AndroidAppLogEntry>) {
        val retained = entries.takeLast(maxEntries / 2.coerceAtLeast(1))
        logFile.writeText(retained.joinToString(separator = "\n", postfix = if (retained.isEmpty()) "" else "\n", transform = ::encode))
        _entries.value = retained
    }

    private fun loadEntries(): List<AndroidAppLogEntry> = runCatching {
        if (!logFile.isFile) return@runCatching emptyList()
        logFile.useLines { lines -> lines.mapNotNull(::decode).toList().takeLast(maxEntries) }
    }.getOrDefault(emptyList())

    private fun encode(entry: AndroidAppLogEntry): String = JSONObject()
        .put("id", entry.id).put("timestamp", entry.timestamp).put("level", entry.level.name)
        .put("category", entry.category).put("message", entry.message).toString()

    private fun decode(line: String): AndroidAppLogEntry? = runCatching {
        val json = JSONObject(line)
        AndroidAppLogEntry(json.getString("id"), json.getString("timestamp"), AndroidAppLogLevel.valueOf(json.getString("level")), json.getString("category"), json.getString("message"))
    }.getOrNull()

    private fun logToPlatform(entry: AndroidAppLogEntry) {
        val tag = "FluxNews/${entry.category}".take(23)
        when (entry.level) {
            AndroidAppLogLevel.Trace, AndroidAppLogLevel.Debug -> Log.d(tag, entry.message)
            AndroidAppLogLevel.Info -> Log.i(tag, entry.message)
            AndroidAppLogLevel.Warning -> Log.w(tag, entry.message)
            AndroidAppLogLevel.Error -> Log.e(tag, entry.message)
        }
    }

    companion object {
        private val DEBUG_LOGGING = AndroidPreferenceKey.boolean("support_debug_logging_v1")
        fun recordText(entry: AndroidAppLogEntry): String = "${entry.timestamp} [${entry.level.name.uppercase()}] [${entry.category}] ${entry.message}"
    }
}

internal class AndroidCoreDiagnosticListener(private val diagnostics: AndroidAppDiagnostics) : DiagnosticListener {
    override fun onDiagnostic(record: DiagnosticRecord) {
        diagnostics.record(
            when (record.level) {
                DiagnosticLevel.TRACE -> AndroidAppLogLevel.Trace
                DiagnosticLevel.DEBUG -> AndroidAppLogLevel.Debug
                DiagnosticLevel.INFO -> AndroidAppLogLevel.Info
                DiagnosticLevel.WARN -> AndroidAppLogLevel.Warning
                DiagnosticLevel.ERROR -> AndroidAppLogLevel.Error
            },
            "core.${record.target}",
            record.message,
        )
    }
}
