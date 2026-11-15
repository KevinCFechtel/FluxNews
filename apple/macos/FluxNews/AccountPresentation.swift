import Foundation

enum SupportLogRedaction {
    static func sanitize(_ text: String, secrets: [String] = []) -> String {
        var result = text
        for secret in secrets where secret.count >= 4 {
            result = result.replacingOccurrences(of: secret, with: "<redacted>")
        }
        for pattern in [
            // Mask the complete credential: a generic "Authorization: \S+" rule
            // leaves the token exposed for schemes such as "Bearer abc123".
            #"(?i)\b(?:proxy-)?authorization\s*[:=]\s*[^\r\n]+"#,
            #"(?i)\b(?:api[_ -]?key|password|access[_ -]?token|token|cookie)\s*[:=]\s*[^\s,;]+"#,
            #"(?i)\bBearer\s+[^\s,;]+"#,
            #"(?i)\bhttps?://[^\s<>"']+"#,
            #"(?i)\bfile://[^\s<>"']+"#,
            #"(?:/Users/|/private/|/var/|/tmp/|/Volumes/)[^\s,;)"']+"#
        ] {
            result = result.replacingOccurrences(of: pattern, with: "<redacted sensitive value>", options: .regularExpression)
        }
        return result
    }
}

enum AccountTransportWarning {
    static func usesUnencryptedHTTP(_ server: String) -> Bool {
        let input = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: input),
              url.scheme?.lowercased() == "http",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}

enum MacOSAboutInformation {
    static let fluxNewsRepositoryURL = URL(string: "https://github.com/KevinCFechtel/FluxNews")!
    static let fluxRepositoryURL = URL(string: "https://github.com/KevinCFechtel/Flux")!
    static let licenseURL = URL(string: "https://github.com/KevinCFechtel/Flux/blob/main/LICENSE")!
    static let minifluxProjectURL = URL(string: "https://miniflux.app")!

    static func version(from infoDictionary: [String: Any]) -> String {
        nonEmptyString(infoDictionary["CFBundleShortVersionString"]) ?? String(localized: "Unknown")
    }

    static func build(from infoDictionary: [String: Any]) -> String {
        nonEmptyString(infoDictionary["CFBundleVersion"]) ?? String(localized: "Unknown")
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AccountValidationFailure {
    case invalidURL
    case network
    case unauthorized
    case incompatibleServer
    case invalidResponse
    case invalidCustomHeader
}

enum AccountValidationPresentation {
    static func message(for failure: AccountValidationFailure) -> String {
        switch failure {
        case .invalidURL:
            "Enter a valid HTTP or HTTPS Miniflux server URL."
        case .network:
            "The Miniflux server could not be reached. Check the server URL and network connection."
        case .unauthorized:
            "Miniflux rejected the API key."
        case .incompatibleServer:
            "This server does not provide the required Miniflux endpoint."
        case .invalidResponse:
            "The Miniflux server returned an unexpected response."
        case .invalidCustomHeader:
            "Custom headers must have unique valid names and cannot replace FluxNews transport headers."
        }
    }
}

enum NativeErrorPresentation {
    static func message(for error: Error) -> String {
        switch error {
        case SystemNotificationError.authorizationDenied:
            String(localized: "FluxNews notification permission is disabled. Enable notifications in macOS System Settings to use System Notifications.")
        default:
            String(localized: "Something went wrong. Please try again.")
        }
    }
}

enum SystemNotificationError: LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        String(localized: "FluxNews notification permission is disabled. Enable notifications in macOS System Settings to use System Notifications.")
    }
}

enum MinifluxEntryURL {
    static func resolve(articleID: Int64, using coreURL: (Int64) -> String) -> URL? {
        guard let url = URL(string: coreURL(articleID)),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil else { return nil }
        return url
    }
}
