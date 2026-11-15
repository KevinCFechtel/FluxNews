import Foundation
import OSLog
import UIKit

enum IOSAppLogLevel: String, Codable, CaseIterable, Sendable {
    case trace
    case debug
    case info
    case warning
    case error

    var exportLabel: String { rawValue.uppercased() }
}

struct IOSAppLogEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: IOSAppLogLevel
    let category: String
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: IOSAppLogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// App-owned support diagnostics used in addition to Apple's unified logging.
///
/// This store deliberately remains presentation/support infrastructure. It is not
/// Core/domain persistence and must never become authoritative application state.
final class IOSAppDiagnostics: @unchecked Sendable {
    static let shared = IOSAppDiagnostics()

    private enum Key {
        static let debugLogging = "FluxNews.iOS.debugLogging.v1"
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let logFileURL: URL
    private let exportDirectoryURL: URL
    private let maxEntries: Int
    private let maxFileBytes: Int

    private var entries: [IOSAppLogEntry]
    private var debugLoggingEnabledStorage: Bool
    private var sensitiveValues = Set<String>()

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        maxEntries: Int = 5_000,
        maxFileBytes: Int = 2_000_000
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
        self.maxFileBytes = max(64 * 1024, maxFileBytes)
        debugLoggingEnabledStorage = defaults.bool(forKey: Key.debugLogging)

        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            let applicationSupport =
                fileManager.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first ?? fileManager.temporaryDirectory
            let namespace =
                (Bundle.main.object(
                    forInfoDictionaryKey: "FluxStorageNamespace"
                ) as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "FluxNewsNativeDev"
            root = applicationSupport
                .appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent("Diagnostics", isDirectory: true)
        }

        logFileURL = root.appendingPathComponent("support.jsonl")
        exportDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("FluxNews-Diagnostics", isDirectory: true)

        try? fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try? fileManager.createDirectory(
            at: exportDirectoryURL,
            withIntermediateDirectories: true
        )
        entries = Self.loadEntries(
            from: logFileURL,
            fileManager: fileManager,
            limit: self.maxEntries
        )
    }

    var isDebugLoggingEnabled: Bool {
        withLock { debugLoggingEnabledStorage }
    }

    var count: Int {
        withLock { entries.count }
    }

    func setDebugLoggingEnabled(_ enabled: Bool) {
        withLock {
            debugLoggingEnabledStorage = enabled
            defaults.set(enabled, forKey: Key.debugLogging)
        }
        IOSAppLogger(category: "diagnostics").info(
            "Debug logging \(enabled ? "enabled" : "disabled")"
        )
    }

    /// Register credential material for exact-match redaction. Values remain only
    /// in memory and are never persisted to diagnostics storage.
    func setSensitiveValues(_ values: [String]) {
        withLock {
            sensitiveValues = Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 4 }
            )
        }
    }

    func snapshot() -> [IOSAppLogEntry] {
        withLock { entries }
    }

    func clear() {
        withLock {
            entries.removeAll(keepingCapacity: false)
            try? fileManager.removeItem(at: logFileURL)
        }
    }

    /// Records a privacy-sanitized entry and returns the same text for unified
    /// logging. Debug/Trace records are dropped when Debug Logging is disabled.
    @discardableResult
    func record(
        level: IOSAppLogLevel,
        category: String,
        message: String
    ) -> String? {
        withLock {
            if (level == .debug || level == .trace),
               !debugLoggingEnabledStorage {
                return nil
            }

            let sanitized = sanitizeLocked(message)
            let entry = IOSAppLogEntry(
                level: level,
                category: String(category.prefix(120)),
                message: String(sanitized.prefix(4_096))
            )
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            appendLocked(entry)
            return entry.message
        }
    }

    func makeExportURL() throws -> URL {
        let currentEntries = snapshot()
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = exportDirectoryURL
            .appendingPathComponent("FluxNews-Diagnostics-\(stamp).txt")

        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"
        let build =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown"

        var lines = [
            "FluxNews Diagnostics",
            "Generated: \(formatter.string(from: Date()))",
            "App version: \(version) (\(build))",
            "OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "Device class: \(UIDevice.current.model)",
            "Debug logging: \(isDebugLoggingEnabled ? "enabled" : "disabled")",
            "Records: \(currentEntries.count)",
            ""
        ]

        lines.append(
            contentsOf: currentEntries.map { entry in
                "\(formatter.string(from: entry.timestamp)) [\(entry.level.exportLabel)] [\(entry.category)] \(entry.message)"
            }
        )

        try lines.joined(separator: "\n")
            .appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func sanitizeLocked(_ message: String) -> String {
        var sanitized = message
        for value in sensitiveValues {
            sanitized = sanitized.replacingOccurrences(
                of: value,
                with: "<redacted>"
            )
        }

        let credentialPatterns = [
            #"(?i)(authorization|api[_ -]?key|password|access[_ -]?token|token)\s*[:=]\s*[^\s,;]+"#,
            #"(?i)[?&](api[_-]?key|access_token|token)=[^&\s]+"#
        ]
        for pattern in credentialPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "<redacted credential>",
                options: .regularExpression
            )
        }
        return sanitized
    }

    private func appendLocked(_ entry: IOSAppLogEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)

        let attributes = try? fileManager.attributesOfItem(
            atPath: logFileURL.path
        )
        let currentBytes =
            (attributes?[.size] as? NSNumber)?.intValue ?? 0

        if currentBytes + data.count > maxFileBytes {
            rewriteLocked()
            return
        }

        do {
            if fileManager.fileExists(atPath: logFileURL.path) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logFileURL, options: .atomic)
            }
        } catch {
            // Support logging must never affect product behavior.
        }
    }

    private func rewriteLocked() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let retained = entries.suffix(max(1, maxEntries / 2))
        let data = retained.reduce(into: Data()) { result, entry in
            guard var encoded = try? encoder.encode(entry) else { return }
            encoded.append(0x0A)
            result.append(encoded)
        }
        try? data.write(to: logFileURL, options: .atomic)
    }

    private static func loadEntries(
        from url: URL,
        fileManager: FileManager,
        limit: Int
    ) -> [IOSAppLogEntry] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line in
                try? decoder.decode(
                    IOSAppLogEntry.self,
                    from: Data(line.utf8)
                )
            }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

struct IOSAppLogger: @unchecked Sendable {
    private let category: String
    private let logger: Logger
    private let diagnostics: IOSAppDiagnostics

    init(
        category: String,
        diagnostics: IOSAppDiagnostics = .shared
    ) {
        self.category = category
        self.diagnostics = diagnostics
        logger = Logger(
            subsystem: Bundle.main.bundleIdentifier
                ?? "dev.kevincfechtel.fluxNews",
            category: category
        )
    }

    func trace(_ message: String) {
        guard let message = diagnostics.record(
            level: .trace,
            category: category,
            message: message
        ) else { return }
        logger.trace("\(message, privacy: .public)")
    }

    func debug(_ message: String) {
        guard let message = diagnostics.record(
            level: .debug,
            category: category,
            message: message
        ) else { return }
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        guard let message = diagnostics.record(
            level: .info,
            category: category,
            message: message
        ) else { return }
        logger.info("\(message, privacy: .public)")
    }

    func notice(_ message: String) {
        info(message)
    }

    func warning(_ message: String) {
        guard let message = diagnostics.record(
            level: .warning,
            category: category,
            message: message
        ) else { return }
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        guard let message = diagnostics.record(
            level: .error,
            category: category,
            message: message
        ) else { return }
        logger.error("\(message, privacy: .public)")
    }
}

final class IOSCoreDiagnosticListener: DiagnosticListener, @unchecked Sendable {
    static let shared = IOSCoreDiagnosticListener()

    func onDiagnostic(record: DiagnosticRecord) {
        let logger = IOSAppLogger(category: "core.\(record.target)")
        switch record.level {
        case .trace:
            logger.trace(record.message)
        case .debug:
            logger.debug(record.message)
        case .info:
            logger.info(record.message)
        case .warn:
            logger.warning(record.message)
        case .error:
            logger.error(record.message)
        }
    }
}
