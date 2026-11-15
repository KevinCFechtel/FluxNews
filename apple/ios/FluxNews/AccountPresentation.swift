import Foundation

enum IOSAccountValidationFailure {
    case invalidURL, network, unauthorized, incompatibleServer, invalidResponse, invalidCustomHeader
}

enum IOSAccountValidationPresentation {
    static func message(for failure: IOSAccountValidationFailure) -> String {
        switch failure {
        case .invalidURL: String(localized: "Enter a valid HTTP or HTTPS Miniflux server URL.")
        case .network: String(localized: "The Miniflux server could not be reached. Check the server URL and network connection.")
        case .unauthorized: String(localized: "Miniflux rejected the API key.")
        case .incompatibleServer: String(localized: "This server does not provide the required Miniflux endpoint.")
        case .invalidResponse: String(localized: "The Miniflux server returned an unexpected response.")
        case .invalidCustomHeader: String(localized: "Custom headers must have unique valid names and cannot replace FluxNews transport headers.")
        }
    }

    static func failure(for error: Error) -> IOSAccountValidationFailure {
        switch error {
        case AccountValidationError.InvalidUrl, AccountValidationError.UnsupportedUrlScheme: .invalidURL
        case AccountValidationError.Network, AccountValidationError.ServerUnavailable: .network
        case AccountValidationError.Unauthorized: .unauthorized
        case AccountValidationError.IncompatibleServer: .incompatibleServer
        case AccountValidationError.InvalidCustomHeader: .invalidCustomHeader
        case AccountValidationError.InvalidResponse: .invalidResponse
        default: .invalidResponse
        }
    }
}


enum IOSAccountInformationPresentation {
    static func normalizedServerVersion(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func usesUnencryptedHTTP(_ server: String) -> Bool {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        return URLComponents(string: trimmed)?.scheme?.lowercased() == "http"
    }
}
