import Foundation
import OSLog

enum MacSupportLevel: String, Codable, CaseIterable, Identifiable {
    case trace, debug, info, warning, error
    var id: String { rawValue }
}
struct MacSupportRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: MacSupportLevel
    let category: String
    let message: String
}
final class MacSupportDiagnostics: @unchecked Sendable {
    static let shared = MacSupportDiagnostics()
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let fileURL: URL
    private let capacity: Int
    private let maximumBytes: Int
    private var records: [MacSupportRecord] = []
    private var secrets: [String] = []
    private var debug: Bool
    init(root: URL? = nil, defaults: UserDefaults = .standard, capacity: Int = 5_000, maximumBytes: Int = 2_000_000) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
        self.maximumBytes = max(4096, maximumBytes)
        debug = defaults.bool(forKey: "FluxNews.macOS.debugLogging.v1")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let folder = root ?? support.appendingPathComponent("FluxNews/Diagnostics", isDirectory: true)
        fileURL = folder.appendingPathComponent("support.jsonl")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) {
            records = text.split(separator: "\n").suffix(self.capacity).compactMap { try? decoder.decode(MacSupportRecord.self, from: Data($0.utf8)) }
        }
    }
    var debugEnabled: Bool { locked { debug } }
    func setDebug(_ value: Bool) {
        locked { debug = value; defaults.set(value, forKey: "FluxNews.macOS.debugLogging.v1") }
        record(.info, "diagnostics", "Debug logging \(value ? "enabled" : "disabled")")
    }
    func registerSecrets(_ values: [String]) {
        locked {
            secrets = values.filter { $0.count >= 4 }
            records = records.map {
                MacSupportRecord(id: $0.id, timestamp: $0.timestamp, level: $0.level,
                                 category: $0.category, message: SupportLogRedaction.sanitize($0.message, secrets: secrets))
            }
            persist()
        }
    }
    func snapshot() -> [MacSupportRecord] { locked { records } }
    func clear() { locked { records.removeAll(); try? FileManager.default.removeItem(at: fileURL) } }
    @discardableResult
    func record(_ level: MacSupportLevel, _ category: String, _ message: String) -> String? {
        locked {
            guard debug || (level != .trace && level != .debug) else { return nil }
            let safe = String(SupportLogRedaction.sanitize(message, secrets: secrets).prefix(4096))
            records.append(MacSupportRecord(id: UUID(), timestamp: Date(), level: level, category: String(category.prefix(120)), message: safe))
            if records.count > capacity { records.removeFirst(records.count - capacity) }
            persist()
            return safe
        }
    }
    func exportText() -> String {
        locked {
            let fmt = ISO8601DateFormatter()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            return (["FluxNews macOS Diagnostics", "Generated: \(fmt.string(from: Date()))",
                     "Version: \(version) (\(build))", "OS: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "Debug logging: \(debug ? "enabled" : "disabled")", "Records: \(records.count)", ""]
                + records.map { "\(fmt.string(from: $0.timestamp)) [\($0.level.rawValue.uppercased())] [\($0.category)] \($0.message)" })
                .joined(separator: "\n") + "\n"
        }
    }
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var content = Data()
        for item in records {
            if var data = try? encoder.encode(item) { data.append(0x0A); content.append(data) }
        }
        while content.count > maximumBytes && records.count > 1 {
            records.removeFirst()
            content = Data()
            for item in records {
                if var data = try? encoder.encode(item) { data.append(0x0A); content.append(data) }
            }
        }
        try? content.write(to: fileURL, options: .atomic)
    }
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
final class CoreDiagnosticLogger: DiagnosticListener, @unchecked Sendable {
    func onDiagnostic(record: DiagnosticRecord) {
        let level: MacSupportLevel
        switch record.level {
        case .trace: level = .trace
        case .debug: level = .debug
        case .info: level = .info
        case .warn: level = .warning
        case .error: level = .error
        }
        guard let safe = MacSupportDiagnostics.shared.record(level, "core.\(record.target)", record.message) else { return }
        let logger = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "core")
        switch level {
        case .trace, .debug: logger.debug("\(safe, privacy: .private)")
        case .info: logger.info("\(safe, privacy: .private)")
        case .warning: logger.warning("\(safe, privacy: .private)")
        case .error: logger.error("\(safe, privacy: .private)")
        }
    }
}
enum NativeLog {
    static let app = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "app")
    static let sync = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "sync")
    static let keychain = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "keychain")
    static let launchAtLogin = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "launch_at_login")
    static let shortcut = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "shortcut")
    static let feedIcon = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "feed_icon")
    static let scrollover = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "scrollover")
    static let snapshot = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "snapshot")
    static let notification = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "notification")
    static func support(_ category: String, _ message: String, level: MacSupportLevel = .info) {
        guard let safe = MacSupportDiagnostics.shared.record(level, category, message) else { return }
        Logger(subsystem: "dev.kevincfechtel.fluxNews", category: category).notice("\(safe, privacy: .private)")
    }
}
