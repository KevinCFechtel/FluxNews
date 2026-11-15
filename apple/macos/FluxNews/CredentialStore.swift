import Foundation
import Security
import ServiceManagement

struct CustomHTTPHeader: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

struct MinifluxCredentials: Codable {
    var server: String
    var apiKey: String
    var showSplash: Bool?
    var newestFirst: Bool?
    var customHeaders: [CustomHTTPHeader]?

    var resolvedCustomHeaders: [CustomHTTPHeader] { customHeaders ?? [] }
}

enum CredentialStore {
    static let service = "dev.kevincfechtel.fluxNews.miniflux"
    private static let account = "credentials"

    static func load() throws -> MinifluxCredentials? {
        try load(service: service)
    }

    static func save(_ credentials: MinifluxCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw statusError(status) }
        var insertion = query
        insertion[kSecValueData] = data
        insertion[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard insertionStatus == errSecSuccess else { throw statusError(insertionStatus) }
    }

    static func remove() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw statusError(status) }
    }

    static var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    private static func load(service: String) throws -> MinifluxCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw statusError(status) }
        return try JSONDecoder().decode(MinifluxCredentials.self, from: data)
    }

    private static func statusError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"])
    }
}
