import Foundation
import Security

enum IOSCredentialStoreError: Error, Equatable {
    case temporarilyUnavailable
    case keychainStatus(OSStatus)
}

enum IOSKeychainAccessibility: Equatable {
    case backgroundAfterFirstUnlock

    var securityValue: CFString {
        switch self {
        case .backgroundAfterFirstUnlock:
            kSecAttrAccessibleAfterFirstUnlock
        }
    }
}

protocol IOSKeychainDataStoreProtocol {
    func loadData(service: String, account: String) throws -> Data?
    func saveData(
        _ data: Data,
        service: String,
        account: String,
        accessibility: IOSKeychainAccessibility
    ) throws
    func updateAccessibility(
        service: String,
        account: String,
        accessibility: IOSKeychainAccessibility
    ) throws
    func remove(service: String, account: String) throws
}

struct IOSSystemKeychainDataStore: IOSKeychainDataStoreProtocol {
    func loadData(service: String, account: String) throws -> Data? {
        let query = Self.query(service: service, account: account)
        var result: CFTypeRef?
        var dataQuery = query
        dataQuery[kSecReturnData] = true
        dataQuery[kSecMatchLimit] = kSecMatchLimitOne

        let status = SecItemCopyMatching(dataQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Self.error(status)
        }
        return data
    }

    func saveData(
        _ data: Data,
        service: String,
        account: String,
        accessibility: IOSKeychainAccessibility
    ) throws {
        let query = Self.query(service: service, account: account)
        let updates: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: accessibility.securityValue,
        ]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Self.error(status) }

        var insertion = query
        insertion[kSecValueData] = data
        insertion[kSecAttrAccessible] = accessibility.securityValue
        let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard insertionStatus == errSecSuccess else {
            throw Self.error(insertionStatus)
        }
    }

    func updateAccessibility(
        service: String,
        account: String,
        accessibility: IOSKeychainAccessibility
    ) throws {
        let query = Self.query(service: service, account: account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecAttrAccessible: accessibility.securityValue] as CFDictionary
        )
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    func remove(service: String, account: String) throws {
        let status = SecItemDelete(
            Self.query(service: service, account: account) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.error(status)
        }
    }

    private static func query(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    private static func error(_ status: OSStatus) -> IOSCredentialStoreError {
        if status == errSecInteractionNotAllowed {
            return .temporarilyUnavailable
        }
        return .keychainStatus(status)
    }
}

struct IOSCustomHTTPHeader: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

struct IOSMinifluxCredentials: Codable, Equatable, CustomStringConvertible, Sendable {
    var server: String
    var apiKey: String
    var customHeaders: [IOSCustomHTTPHeader]

    var description: String { "IOSMinifluxCredentials(server: \(server), apiKey: <redacted>, headers: \(customHeaders.count))" }
}

protocol IOSCredentialStoreProtocol {
    func load() throws -> IOSMinifluxCredentials?
    func save(_ credentials: IOSMinifluxCredentials) throws
    func remove() throws
}

struct IOSKeychainCredentialStore: IOSCredentialStoreProtocol {
    private static let account = "credentials"
    private static let accessibility = IOSKeychainAccessibility.backgroundAfterFirstUnlock

    private let keychain: IOSKeychainDataStoreProtocol

    init(keychain: IOSKeychainDataStoreProtocol = IOSSystemKeychainDataStore()) {
        self.keychain = keychain
    }

    // This service is intentionally unrelated to Flutter's secure-storage service.
    private var service: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.kevincfechtel.fluxNews.nativeDev"
        return "\(bundleID).native-miniflux"
    }

    func load() throws -> IOSMinifluxCredentials? {
        guard let data = try keychain.loadData(
            service: service,
            account: Self.account
        ) else {
            return nil
        }
        let credentials = try JSONDecoder().decode(IOSMinifluxCredentials.self, from: data)

        // Migrate credentials created by older native builds from
        // WhenUnlocked to the background-capable AfterFirstUnlock class.
        // This can only happen after the item is readable; before first unlock
        // the system reports temporary unavailability and the caller retries
        // later instead of treating the account as missing or corrupt.
        try keychain.updateAccessibility(
            service: service,
            account: Self.account,
            accessibility: Self.accessibility
        )
        return credentials
    }

    func save(_ credentials: IOSMinifluxCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.saveData(
            data,
            service: service,
            account: Self.account,
            accessibility: Self.accessibility
        )
    }

    func remove() throws {
        try keychain.remove(service: service, account: Self.account)
    }
}

final class IOSMemoryCredentialStore: IOSCredentialStoreProtocol {
    var credentials: IOSMinifluxCredentials?

    func load() throws -> IOSMinifluxCredentials? { credentials }
    func save(_ credentials: IOSMinifluxCredentials) throws { self.credentials = credentials }
    func remove() throws { self.credentials = nil }
}
