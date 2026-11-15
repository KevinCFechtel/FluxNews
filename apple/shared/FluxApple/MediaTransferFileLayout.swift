import Foundation

enum MediaTransferError: Error, Equatable {
    case network
    case storage
    case invalidMedia
}

enum MediaTransferFileLayout {
    static func reference(
        executionNamespace: String? = nil,
        enclosureID: Int64,
        url: String,
        mimeType: String
    ) -> String {
        let filename = "enclosure-\(enclosureID).\(audioExtension(url: url, mimeType: mimeType))"
        guard let executionNamespace, !executionNamespace.isEmpty else {
            return "downloads/\(filename)"
        }
        return "downloads/\(executionNamespace)/\(filename)"
    }

    static func audioExtension(url: String, mimeType: String) -> String {
        let urlExtension = URL(string: url)?.pathExtension.lowercased()
        if let urlExtension, isSafeAudioExtension(urlExtension) {
            return urlExtension
        }

        let normalizedMimeType = mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            ?? ""

        switch normalizedMimeType {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/aac", "audio/x-aac": return "aac"
        case "audio/ogg", "application/ogg": return "ogg"
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/webm": return "webm"
        default: return "audio"
        }
    }

    static func destination(reference: String, under root: URL) throws -> URL {
        guard !reference.hasPrefix("/"), !reference.contains("..") else {
            throw MediaTransferError.storage
        }
        let destination = root.appendingPathComponent(reference).standardizedFileURL
        guard destination.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw MediaTransferError.storage
        }
        return destination
    }

    private static func isSafeAudioExtension(_ value: String) -> Bool {
        ["aac", "aiff", "alac", "flac", "m4a", "mp3", "oga", "ogg", "wav", "webm"]
            .contains(value)
    }
}
