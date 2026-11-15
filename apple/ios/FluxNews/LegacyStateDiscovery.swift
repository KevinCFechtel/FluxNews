import Foundation
import Security
import SQLite3

struct LegacyDiscoveryResult: Equatable {
    enum Access: String {
        case accessible = "accessible"
        case unavailable = "unavailable"
    }

    let productionIdentity: Access
    let appGroup: Access
    let keychain: Access
    let accountURLPresent: Bool
    let accountAPIKeyPresent: Bool
    let customHeaderCount: Int
    let compatibleSettingCount: Int
    let feedPreferencePresent: Bool
    let playbackProgressCount: Int
    let downloadMetadataCount: Int
    let downloadFileCount: Int
    let legacyDatabase: Bool
    let legacyCache: Bool
}

struct LegacyAccountImport: Equatable {
    struct Header: Equatable {
        let name: String
        let value: String
    }

    let serverURL: String
    let apiKey: String
    let customHeaders: [Header]
}

struct LegacyPlaybackProgressImport: Equatable {
    let articleID: Int64
    let positionMs: UInt64
}

struct LegacyPlaybackArticleImport: Equatable {
    let articleID: Int64
    let feedID: Int64
    let title: String
    let url: String
    let commentsURL: String
    let publishedAt: String
    let isRead: Bool
    let isStarred: Bool
    let rawHTMLContent: String
    let readingTimeMinutes: UInt32
    let preview: String
    let imageURL: String?
    let enclosureID: Int64
    let enclosureURL: String
    let enclosureMimeType: String
}

struct LegacyDownloadImport: Equatable {
    let enclosureID: Int64
    let sourceFile: URL
    var articleID: Int64? = nil
}

struct LegacyFeedOpenInMinifluxImport: Equatable {
    let feedID: Int64
    let openInMiniflux: Bool
}

struct LegacyGlobalPreferencesImport: Equatable {
    let markReadOnScrollover: Bool?
    let removeArticlesWhenMarkedRead: Bool?
}

struct LegacySettingsImport: Equatable {
    let showArticleCount: Bool?
    let hideEmptyNavigationEntries: Bool?
    let tabActionExpands: Bool
    let leadingFull: IOSArticleSwipeAction??
    let leadingAdditional: IOSArticleSwipeAction??
    let trailingFull: IOSArticleSwipeAction??
    let trailingAdditional: IOSArticleSwipeAction??
    let startupMode: Int64?
    let startupCategoryID: Int64?
    let startupFeedID: Int64?
    let backgroundSyncEnabled: Bool?
    let autoDownloadListeningList: Bool?
}

struct LegacyToolbarImport: Equatable {
    let selectedActions: [IOSBottomAction]?
}

struct LegacyWidgetDefaultsImport: Equatable {
    let selection: WidgetContentSelection
}

enum LegacyStateDiscovery {
    static let productionBundleID = "dev.kevincfechtel.fluxNews"
    static let applicationGroup = "group.dev.kevincfechtel.fluxNews"
    static let flutterKeychainService = "flutter_secure_storage_service"

    private static let accountURLKey = "minifluxURL"
    private static let accountAPIKey = "minifluxAPIKey"
    private static let customHeaderKeyPrefix = "customHeadersKey_"
    private static let customHeaderValuePrefix = "customHeadersValue_"
    private static let feedSettingsKey = "feedSettingsOverrides"
    private static let markReadOnScrolloverKey = "markAsReadOnScrollOver"
    private static let removeArticlesWhenMarkedReadKey = "removeNewsFromListWhenRead"
    private static let widgetNewsStatusKey = "widgetNewsStatus"
    private static let widgetUnreadOnlyKey = "widgetUnreadOnly"
    private static let widgetFilterTypeKey = "widgetFilterType"
    private static let widgetFilterIDKey = "widgetFilterId"
    private static let widgetSortOrderKey = "widgetSortOrder"
    private static let playbackPrefix = "audio_progress_"
    private static let flutterPreferencesPrefix = "flutter."
    private static let downloadPathPrefix = "audio_download_path_"
    private static let downloadPathByURLPrefix = "audio_download_path_url_"
    private static let downloadTimestampPrefix = "audio_download_ts_"
    private static let downloadTitlePrefix = "flux_download_title_"
    private static let downloadFeedTitlePrefix = "flux_download_feed_title_"
    private static let audioFilePrefix = "audio_"

    // This probe only reads Keychain attributes, Flutter UserDefaults values,
    // directory entries, and file metadata.
    static func probe(fileManager: FileManager = .default,
                     homeDirectory: URL? = nil) -> LegacyDiscoveryResult {
        let isProduction = Bundle.main.bundleIdentifier == productionBundleID
        let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: applicationGroup)
        let keychainResult = keychainAccounts()
        let accounts = keychainResult.accounts
        let sharedPlayback = parseFlutterSharedPreferencesPlaybackImports(
            stringValues(UserDefaults.standard.dictionaryRepresentation())
        )
        let library = homeDirectory ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        let applicationSupport = library?.appendingPathComponent("Application Support", isDirectory: true)
        let caches = library?.appendingPathComponent("Caches", isDirectory: true)
        let database = library?.appendingPathComponent("news_database.db")
        let audioCache = applicationSupport?.appendingPathComponent("audio_cache", isDirectory: true)

        return LegacyDiscoveryResult(
            productionIdentity: isProduction ? .accessible : .unavailable,
            appGroup: groupURL == nil ? .unavailable : .accessible,
            keychain: keychainResult.access,
            accountURLPresent: accounts.contains(accountURLKey),
            accountAPIKeyPresent: accounts.contains(accountAPIKey),
            customHeaderCount: Set(accounts.compactMap { key in
                if key.hasPrefix(customHeaderKeyPrefix) {
                    return String(key.dropFirst(customHeaderKeyPrefix.count))
                }
                if key.hasPrefix(customHeaderValuePrefix) {
                    return String(key.dropFirst(customHeaderValuePrefix.count))
                }
                return nil
            }).count,
            compatibleSettingCount: accounts.intersection(auditedSettings).count,
            feedPreferencePresent: accounts.contains(feedSettingsKey),
            playbackProgressCount: Set(sharedPlayback.map(\.articleID)).union(
                accounts.compactMap(playbackArticleID)
            ).count,
            downloadMetadataCount: accounts.filter { key in
                downloadMetadataPrefixes.contains { key.hasPrefix($0) }
            }.count,
            downloadFileCount: countAudioFiles(in: audioCache, fileManager: fileManager),
            legacyDatabase: database.map { fileManager.fileExists(atPath: $0.path) } ?? false,
            legacyCache: countFiles(in: caches, fileManager: fileManager) > 0
        )
    }

    /// Reads only the legacy Flutter secure-storage namespace and returns the
    /// account material that has a direct native equivalent. This is a source
    /// reader for the D9 copy/import migration; it never writes to Keychain,
    /// native storage, Core storage, or the legacy store.
    static func readAccountImport() -> LegacyAccountImport? {
        guard Bundle.main.bundleIdentifier == productionBundleID else { return nil }
        guard let values = keychainValues() else { return nil }
        return parseAccountImport(values)
    }

    /// Reads only the four retained media policy values from the same Flutter
    /// secure-storage namespace as account import. It never mutates Keychain.
    static func readMediaSettingsImport() -> IOSLegacyMediaSettingsImport? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        let mediaValues = values.filter { compatibleMediaSettings.contains($0.key) }
        return IOSLegacyMediaSettingsImport.parse(mediaValues)
    }

    /// Reads only positive per-feed Open in Miniflux overrides from Flutter's
    /// secure storage. Flutter persisted default zero values for every field,
    /// so zero is not evidence of an explicit user choice.
    static func readFeedOpenInMinifluxImports() -> [LegacyFeedOpenInMinifluxImport]? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        return parseFeedOpenInMinifluxImports(values[feedSettingsKey])
    }

    /// Reads only global Flutter preferences with direct native equivalents. It
    /// is deliberately read-only and distinguishes an unavailable Keychain from
    /// a readable store whose keys are absent or malformed.
    static func readGlobalPreferencesImport() -> LegacyGlobalPreferencesImport? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        return parseGlobalPreferencesImport(values)
    }

    /// Reads the D9-A follow-up settings as exact Flutter strings. The double
    /// optional swipe fields distinguish an absent/malformed value from `none`.
    static func readSettingsImport() -> LegacySettingsImport? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        return parseSettingsImport(values)
    }

    /// Reads the final Flutter iOS toolbar configuration for D9-C. Selection and
    /// full action order are combined into one native priority list.
    static func readToolbarImport() -> LegacyToolbarImport? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        return parseToolbarImport(values)
    }

    /// Reads only the Flutter widget settings that have a direct semantic
    /// equivalent in the native per-instance WidgetKit configuration. The
    /// legacy widget-specific Open in Miniflux flag, item limit and background
    /// styling are intentionally excluded.
    static func readWidgetDefaultsImport() -> LegacyWidgetDefaultsImport? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        return parseWidgetDefaultsImport(values)
    }

    /// Reads Flutter's article-keyed playback values with the same source
    /// priority as Flutter: SharedPreferences first, then Keychain per missing
    /// article ID. It never modifies either legacy store.
    static func readPlaybackProgressImports() -> [LegacyPlaybackProgressImport]? {
        guard Bundle.main.bundleIdentifier == productionBundleID else { return nil }
        let shared = parseFlutterSharedPreferencesPlaybackImports(
            stringValues(UserDefaults.standard.dictionaryRepresentation())
        )
        guard let keychain = keychainValues() else {
            return shared.isEmpty ? nil : shared
        }
        return mergePlaybackProgressImports(
            sharedPreferences: shared,
            keychain: parsePlaybackProgressImports(keychain)
        )
    }

    /// Reads the local Flutter SQLite rows needed to identify historical
    /// playback progress without contacting Miniflux. Only articles with exactly
    /// one valid audio attachment are returned; ambiguous rows are intentionally
    /// omitted instead of guessed.
    static func readPlaybackArticleImports(
        articleIDs: [Int64],
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> [LegacyPlaybackArticleImport] {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              !articleIDs.isEmpty,
              let library = homeDirectory ?? fileManager.urls(
                for: .libraryDirectory,
                in: .userDomainMask
              ).first else {
            return []
        }
        return readLegacyPlaybackArticles(
            at: library.appendingPathComponent("news_database.db"),
            articleIDs: articleIDs
        )
    }

    /// Presence-only guard for old audio files when the secure-storage reader
    /// unexpectedly reports an empty download set. Never mutates Flutter data.
    static func hasUnmigratedAudioFiles(fileManager: FileManager = .default) -> Bool {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return false
        }
        let audioCache = library.appendingPathComponent("Application Support/audio_cache", isDirectory: true)
        return countAudioFiles(in: audioCache, fileManager: fileManager) > 0
    }

    /// Reads only primary attachment-ID download paths. URL-keyed values and
    /// filenames are not identity evidence and are intentionally ignored.
    static func readDownloadImports(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> [LegacyDownloadImport]? {
        guard Bundle.main.bundleIdentifier == productionBundleID,
              let values = keychainValues() else { return nil }
        let library = homeDirectory ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        guard let audioCache = library?.appendingPathComponent("Application Support/audio_cache", isDirectory: true) else {
            return nil
        }
        let database = library?.appendingPathComponent("news_database.db")
        let articleIDs = database.map { readLegacyAttachmentArticleIDs(at: $0) } ?? [:]
        // Flutter's Downloads screen scans audio_cache directly: the secure
        // storage keys are an optimization, not the source of truth. Merge
        // validated cached files back into the import set when keys are absent
        // or contain old sandbox UUIDs after an application upgrade.
        return mergeDownloadImports(
            values,
            audioCache: audioCache,
            fileManager: fileManager,
            articleIDs: articleIDs
        )
    }

    /// Pure decoder kept separate from Keychain access so migration semantics can
    /// be regression-tested without creating or mutating legacy credentials.
    static func parseAccountImport(_ values: [String: String]) -> LegacyAccountImport? {
        guard let rawServer = values[accountURLKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawServer.isEmpty,
              let rawAPIKey = values[accountAPIKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawAPIKey.isEmpty else {
            return nil
        }

        let headerIDs = Set(values.keys.compactMap { key -> String? in
            if key.hasPrefix(customHeaderKeyPrefix) {
                return String(key.dropFirst(customHeaderKeyPrefix.count))
            }
            if key.hasPrefix(customHeaderValuePrefix) {
                return String(key.dropFirst(customHeaderValuePrefix.count))
            }
            return nil
        })

        let headers = headerIDs.sorted().compactMap { id -> LegacyAccountImport.Header? in
            guard let rawName = values[customHeaderKeyPrefix + id],
                  let rawValue = values[customHeaderValuePrefix + id] else {
                return nil
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return .init(name: name, value: rawValue)
        }

        return LegacyAccountImport(
            serverURL: rawServer,
            apiKey: rawAPIKey,
            customHeaders: headers
        )
    }

    static func parsePlaybackProgressImports(
        _ values: [String: String]
    ) -> [LegacyPlaybackProgressImport] {
        values.compactMap { key, value in
            guard key.hasPrefix(playbackPrefix),
                  let articleID = Int64(key.dropFirst(playbackPrefix.count)),
                  articleID > 0,
                  let positionMs = UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return LegacyPlaybackProgressImport(articleID: articleID, positionMs: positionMs)
        }
        .sorted { $0.articleID < $1.articleID }
    }

    static func parseFlutterSharedPreferencesPlaybackImports(
        _ values: [String: String]
    ) -> [LegacyPlaybackProgressImport] {
        values.compactMap { key, value in
            guard key.hasPrefix(flutterPreferencesPrefix + playbackPrefix),
                  let articleID = Int64(key.dropFirst((flutterPreferencesPrefix + playbackPrefix).count)),
                  articleID > 0,
                  let positionMs = UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return LegacyPlaybackProgressImport(articleID: articleID, positionMs: positionMs)
        }
        .sorted { $0.articleID < $1.articleID }
    }

    static func mergePlaybackProgressImports(
        sharedPreferences: [LegacyPlaybackProgressImport],
        keychain: [LegacyPlaybackProgressImport]
    ) -> [LegacyPlaybackProgressImport] {
        var byArticleID = [Int64: LegacyPlaybackProgressImport]()
        for progress in keychain {
            byArticleID[progress.articleID] = progress
        }
        for progress in sharedPreferences {
            byArticleID[progress.articleID] = progress
        }
        return byArticleID.values.sorted { $0.articleID < $1.articleID }
    }

    static func readLegacyPlaybackArticles(
        at url: URL,
        articleIDs: [Int64]
    ) -> [LegacyPlaybackArticleImport] {
        let ids = Array(Set(articleIDs.filter { $0 > 0 })).sorted()
        guard !ids.isEmpty, FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = connection else {
            if connection != nil { sqlite3_close(connection) }
            return []
        }
        defer { sqlite3_close(db) }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
        SELECT n.newsID,n.feedID,n.title,n.url,n.commentsUrl,n.publishedAt,
               n.status,n.starred,n.content,n.readingTime,n.previewText,n.imageUrl,
               a.attachmentID,a.attachmentURL,a.attachmentMimeType
          FROM news n
          JOIN attachments a ON a.newsID=n.newsID
         WHERE n.newsID IN (\(placeholders))
           AND lower(a.attachmentMimeType) LIKE 'audio/%'
         ORDER BY n.newsID,a.attachmentID
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }
        for (index, id) in ids.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), id)
        }

        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                  let bytes = sqlite3_column_text(statement, column) else {
                return nil
            }
            return String(cString: bytes)
        }

        var grouped: [Int64: [LegacyPlaybackArticleImport]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let articleID = sqlite3_column_int64(statement, 0)
            let feedID = sqlite3_column_int64(statement, 1)
            let enclosureID = sqlite3_column_int64(statement, 12)
            guard articleID > 0,
                  feedID > 0,
                  enclosureID > 0,
                  let title = text(2),
                  let articleURL = text(3),
                  let publishedAt = text(5),
                  let enclosureURL = text(13),
                  let mimeType = text(14),
                  !title.isEmpty,
                  !articleURL.isEmpty,
                  !publishedAt.isEmpty,
                  !enclosureURL.isEmpty,
                  mimeType.lowercased().hasPrefix("audio/") else {
                continue
            }
            let readingTimeRaw = max(0, sqlite3_column_int64(statement, 9))
            let readingTime = UInt32(clamping: readingTimeRaw)
            let row = LegacyPlaybackArticleImport(
                articleID: articleID,
                feedID: feedID,
                title: title,
                url: articleURL,
                commentsURL: text(4) ?? "",
                publishedAt: publishedAt,
                isRead: (text(6) ?? "").lowercased() == "read",
                isStarred: sqlite3_column_int(statement, 7) != 0,
                rawHTMLContent: text(8) ?? "",
                readingTimeMinutes: readingTime,
                preview: text(10) ?? "",
                imageURL: text(11),
                enclosureID: enclosureID,
                enclosureURL: enclosureURL,
                enclosureMimeType: mimeType
            )
            grouped[articleID, default: []].append(row)
        }

        return grouped.values.compactMap { rows in
            rows.count == 1 ? rows[0] : nil
        }.sorted { $0.articleID < $1.articleID }
    }

    static func readLegacyAttachmentArticleIDs(at url: URL) -> [Int64: Int64] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let db = connection else {
            if connection != nil { sqlite3_close(connection) }
            return [:]
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT a.attachmentID,a.newsID FROM attachments a INNER JOIN news n ON n.newsID=a.newsID",
            -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return [:]
        }
        defer { sqlite3_finalize(statement) }
        var mapping: [Int64: Int64] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let enclosureID = sqlite3_column_int64(statement, 0)
            let articleID = sqlite3_column_int64(statement, 1)
            if enclosureID > 0 && articleID > 0 { mapping[enclosureID] = articleID }
        }
        return mapping
    }

    static func parseDownloadImports(
        _ values: [String: String],
        audioCache: URL,
        fileManager: FileManager = .default,
        articleIDs: [Int64: Int64] = [:]
    ) -> [LegacyDownloadImport] {
        let root = audioCache.standardizedFileURL.path + "/"
        return values.compactMap { key, value in
            guard key.hasPrefix(downloadPathPrefix),
                  !key.hasPrefix(downloadPathByURLPrefix),
                  let enclosureID = Int64(key.dropFirst(downloadPathPrefix.count)), enclosureID > 0 else {
                return nil
            }
            let source = URL(fileURLWithPath: value).standardizedFileURL
            guard source.path.hasPrefix(root),
                  source.deletingPathExtension().lastPathComponent.hasPrefix(audioFilePrefix),
                  (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  fileManager.isReadableFile(atPath: source.path) else { return nil }
            return LegacyDownloadImport(enclosureID: enclosureID, sourceFile: source, articleID: articleIDs[enclosureID])
        }
        .sorted { $0.enclosureID < $1.enclosureID }
    }

    /// Mirror Flutter AudioDownloadService.getDownloadedAudios(): files named
    /// audio_<positiveEnclosureID>_<epochMilliseconds>[.extension] are also
    /// discoverable without surviving secure-storage download-path keys.
    /// A positive enclosure ID alone is not sufficient to fabricate an article:
    /// the Core must still resolve the enclosure before accepting the import.
    static func discoverDownloadFiles(
        audioCache: URL,
        fileManager: FileManager = .default,
        articleIDs: [Int64: Int64] = [:]
    ) -> [LegacyDownloadImport] {
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: audioCache,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var newest: [Int64: (file: URL, modified: Date)] = [:]
        for file in candidates {
            let name = file.lastPathComponent
            guard name.hasPrefix(audioFilePrefix) else { continue }
            let suffix = String(name.dropFirst(audioFilePrefix.count))
            guard let underscore = suffix.firstIndex(of: "_"),
                  let enclosureID = Int64(suffix[..<underscore]),
                  enclosureID > 0 else { continue }
            let remainder = suffix[suffix.index(after: underscore)...]
            let timestamp = remainder.prefix(while: { $0.isNumber })
            let extensionSuffix = String(remainder.dropFirst(timestamp.count))
            guard !timestamp.isEmpty,
                  timestamp.count >= 10,
                  timestamp.count <= 17,
                  Int64(timestamp) != nil,
                  (extensionSuffix.isEmpty ||
                   (extensionSuffix.first == "." &&
                    extensionSuffix.dropFirst().count >= 1 &&
                    extensionSuffix.dropFirst().count <= 8 &&
                    extensionSuffix.dropFirst().allSatisfy { $0.isASCII && $0.isLetter || $0.isNumber })) else {
                continue
            }

            guard let properties = try? file.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey
            ]), properties.isRegularFile == true,
                properties.isSymbolicLink != true,
                fileManager.isReadableFile(atPath: file.path) else { continue }
            let modified = properties.contentModificationDate ?? .distantPast
            if let previous = newest[enclosureID], previous.modified >= modified {
                continue
            }
            newest[enclosureID] = (file, modified)
        }

        return newest.map { id, entry in
            LegacyDownloadImport(
                enclosureID: id,
                sourceFile: entry.file,
                articleID: articleIDs[id]
            )
        }.sorted { $0.enclosureID < $1.enclosureID }
    }

    /// Combine the legacy Keychain index with Flutter's actual on-disk source.
    /// A real file under audio_cache wins over a stale absolute Keychain path.
    static func mergeDownloadImports(
        _ values: [String: String],
        audioCache: URL,
        fileManager: FileManager = .default,
        articleIDs: [Int64: Int64] = [:]
    ) -> [LegacyDownloadImport] {
        var byID = Dictionary(
            uniqueKeysWithValues: parseDownloadImports(
                values, audioCache: audioCache, fileManager: fileManager,
                articleIDs: articleIDs
            ).map { ($0.enclosureID, $0) }
        )
        for record in discoverDownloadFiles(
            audioCache: audioCache, fileManager: fileManager, articleIDs: articleIDs
        ) {
            // The filesystem scanner handles duplicate historical downloads,
            // choosing the most recently modified file as Flutter does.
            byID[record.enclosureID] = record
        }
        return byID.values.sorted { $0.enclosureID < $1.enclosureID }
    }

    static func parseFeedOpenInMinifluxImports(
        _ rawValue: String?
    ) -> [LegacyFeedOpenInMinifluxImport] {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let overrides = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return overrides.compactMap { feedIDValue, overrideValue in
            guard let feedID = Int64(feedIDValue),
                  feedID > 0,
                  let override = overrideValue as? [String: Any],
                  let value = override["openMinifluxEntry"] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.stringValue == "1" else {
                return nil
            }
            return LegacyFeedOpenInMinifluxImport(feedID: feedID, openInMiniflux: true)
        }
        .sorted { $0.feedID < $1.feedID }
    }

    static func parseGlobalPreferencesImport(
        _ values: [String: String]
    ) -> LegacyGlobalPreferencesImport {
        func parseBool(_ key: String) -> Bool? {
            switch values[key] {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }

        return LegacyGlobalPreferencesImport(
            markReadOnScrollover: parseBool(markReadOnScrolloverKey),
            removeArticlesWhenMarkedRead: parseBool(removeArticlesWhenMarkedReadKey)
        )
    }

    static func parseSettingsImport(_ values: [String: String]) -> LegacySettingsImport {
        func bool(_ key: String) -> Bool? {
            switch values[key] {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        func integer(_ key: String) -> Int64? { values[key].flatMap(Int64.init) }
        func swipe(_ key: String) -> IOSArticleSwipeAction?? {
            guard let raw = values[key] else { return nil }
            if raw == "none" { return .some(nil) }
            guard let action: IOSArticleSwipeAction = switch raw {
            case "readUnread": .readUnread
            case "bookmark": .starUnstar
            case "saveToThirdParty": .saveToService
            case "openMiniflux": .openMiniflux
            case "share": .share
            case "open": .openOriginal
            case "downloadAudio": .downloadAudio
            case "openComments": .comments
            default: nil
            } else { return nil }
            return .some(action)
        }
        let interval = integer("backgroundSyncIntervalMinutes")
        return .init(
            showArticleCount: bool("multilineAppBarText"),
            hideEmptyNavigationEntries: bool("showOnlyFeedCategoriesWithNewNews"),
            tabActionExpands: values["tabAction"] == "expand",
            leadingFull: swipe("rightSwipeAction"),
            leadingAdditional: swipe("secondRightSwipeAction"),
            trailingFull: swipe("leftSwipeAction"),
            trailingAdditional: swipe("secondLeftSwipeAction"),
            startupMode: integer("startupCategorie"),
            startupCategoryID: integer("startupCategorieSelection"),
            startupFeedID: integer("startupFeedSelection"),
            backgroundSyncEnabled: interval.flatMap { $0 == 0 ? false : ($0 > 0 ? true : nil) },
            autoDownloadListeningList: bool("autoDownloadAudioAfterSync")
        )
    }

    static func parseToolbarImport(_ values: [String: String]) -> LegacyToolbarImport {
        func decode(_ key: String) -> [String]? {
            guard let raw = values[key],
                  let data = raw.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
                return nil
            }
            let strings = array.compactMap { $0 as? String }
            return strings.count == array.count ? strings : nil
        }

        func map(_ raw: String) -> IOSBottomAction? {
            switch raw {
            case "search": .search
            case "newsStatus": .toggleReadFilter
            case "sortOrder": .toggleSortOrder
            case "markAsRead": .markAllRead
            case "markAsReadAndNext": .markAllReadAndNext
            case "podcasts": .listeningList
            case "settings": .settings
            default: nil
            }
        }

        guard let selectedRaw = decode("iosToolbarActions") else {
            return LegacyToolbarImport(selectedActions: nil)
        }
        let selectedSet = Set(selectedRaw)
        let orderRaw = decode("iosToolbarActionOrder") ?? selectedRaw

        var seen = Set<IOSBottomAction>()
        var selected: [IOSBottomAction] = []
        for raw in orderRaw where selectedSet.contains(raw) {
            guard let action = map(raw), seen.insert(action).inserted else { continue }
            selected.append(action)
        }
        for raw in selectedRaw {
            guard let action = map(raw), seen.insert(action).inserted else { continue }
            selected.append(action)
        }
        return LegacyToolbarImport(selectedActions: selected)
    }

    static func parseWidgetDefaultsImport(
        _ values: [String: String]
    ) -> LegacyWidgetDefaultsImport? {
        let relevantKeys = [
            widgetNewsStatusKey,
            widgetUnreadOnlyKey,
            widgetFilterTypeKey,
            widgetSortOrderKey,
        ]
        guard relevantKeys.contains(where: { values[$0] != nil }) else {
            return nil
        }

        func exactBool(_ key: String) -> Bool? {
            switch values[key] {
            case "true": true
            case "false": false
            default: nil
            }
        }

        let readFilter: WidgetReadFilter
        if values[widgetUnreadOnlyKey] != nil {
            guard let unreadOnly = exactBool(widgetUnreadOnlyKey) else { return nil }
            readFilter = unreadOnly ? .unread : .all
        } else {
            switch values[widgetNewsStatusKey] {
            case "unread": readFilter = .unread
            case "all", "bookmarked": readFilter = .all
            case nil: readFilter = .unread
            default: return nil
            }
        }

        let scope: WidgetContentScope
        var categoryID: Int64?
        var feedID: Int64?
        if let rawScope = values[widgetFilterTypeKey] {
            switch rawScope {
            case "all":
                scope = .allNews
            case "bookmarked":
                scope = .bookmarks
            case "category":
                guard let rawID = values[widgetFilterIDKey],
                      let id = Int64(rawID), id > 0 else {
                    return nil
                }
                scope = .category
                categoryID = id
            case "feed":
                guard let rawID = values[widgetFilterIDKey],
                      let id = Int64(rawID), id > 0 else {
                    return nil
                }
                scope = .feed
                feedID = id
            default:
                return nil
            }
        } else {
            switch values[widgetNewsStatusKey] {
            case "bookmarked": scope = .bookmarks
            case "unread", "all", nil: scope = .allNews
            default: return nil
            }
        }

        let sortOrder: WidgetSortOrder
        switch values[widgetSortOrderKey] {
        case nil, "Newest first":
            sortOrder = .newestFirst
        case "Oldest first":
            sortOrder = .oldestFirst
        default:
            return nil
        }

        return .init(
            selection: .init(
                scope: scope,
                categoryID: categoryID,
                feedID: feedID,
                readFilter: readFilter,
                sortOrder: sortOrder
            )
        )
    }


    static func redactedSummary(_ result: LegacyDiscoveryResult) -> [String: String] {
        [
            "Production identity": result.productionIdentity.rawValue,
            "App Group": result.appGroup.rawValue,
            "Keychain credentials": result.keychain.rawValue,
            "Base URL": result.accountURLPresent ? "present" : "absent",
            "API key": result.accountAPIKeyPresent ? "present" : "absent",
            "Custom headers": String(result.customHeaderCount),
            "Compatible settings": String(result.compatibleSettingCount),
            "Feed preferences": result.feedPreferencePresent ? "present" : "absent",
            "Playback progress": String(result.playbackProgressCount),
            "Download metadata": String(result.downloadMetadataCount),
            "Legacy downloads": String(result.downloadFileCount),
            "Legacy database": result.legacyDatabase ? "detected" : "not detected",
            "Legacy cache": result.legacyCache ? "detected" : "not detected"
        ]
    }

    // Only settings with a retained native/Core semantic belong here. Explicitly
    // retired Flutter preferences such as useBlackMode and the replaced mobile
    // syncOnStart preference must not be counted as D9 migration candidates.
    // Includes recognized legacy values retained for the upgrade diagnostic.
    // The D9-A follow-up semantically imports autoDownloadAudioAfterSync into
    // the current Listening List policy, not Flutter's old sync trigger.
    private static let auditedSettings: Set<String> = [
        "brightnessMode", "activateTruncate", "charactersToTruncate",
        "autoDownloadAudioAfterSync", "downloadAudioOnlyOnWifi",
        "deleteAudioAfterPlayback", "audioDownloadRetentionDays",
        "iosToolbarActions", "iosToolbarActionOrder",
        widgetNewsStatusKey, widgetUnreadOnlyKey, widgetFilterTypeKey,
        widgetFilterIDKey, widgetSortOrderKey
    ]

    private static let compatibleMediaSettings: Set<String> = [
        "multilineAppBarText", "showOnlyFeedCategoriesWithNewNews", "tabAction",
        "leftSwipeAction", "rightSwipeAction", "secondLeftSwipeAction", "secondRightSwipeAction",
        "startupCategorie", "startupCategorieSelection", "startupFeedSelection",
        "backgroundSyncIntervalMinutes", "autoDownloadAudioAfterSync",
        "downloadAudioOnlyOnWifi",
        "deleteAudioAfterPlayback", "audioDownloadRetentionDays"
    ]

    private static let downloadMetadataPrefixes = [
        downloadPathPrefix, downloadPathByURLPrefix, downloadTimestampPrefix,
        downloadTitlePrefix, downloadFeedTitlePrefix
    ]

    private static func keychainAccounts() -> (access: LegacyDiscoveryResult.Access, accounts: Set<String>) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: flutterKeychainService,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnData: false
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return (.unavailable, [])
        }
        let items = (result as? [[CFString: Any]]) ?? []
        let accounts = Set(items.compactMap { $0[kSecAttrAccount] as? String })
        return (.accessible, accounts)
    }

    private static func playbackArticleID(_ key: String) -> Int64? {
        guard key.hasPrefix(playbackPrefix),
              let articleID = Int64(key.dropFirst(playbackPrefix.count)), articleID > 0 else {
            return nil
        }
        return articleID
    }

    private static func stringValues(_ values: [String: Any]) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            }
        }
    }

    private static func keychainValues() -> [String: String]? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: flutterKeychainService,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnData: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return nil
        }
        let items = (result as? [[CFString: Any]]) ?? []

        return items.reduce(into: [:]) { values, item in
            guard let account = item[kSecAttrAccount] as? String,
                  let data = item[kSecValueData] as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return
            }
            values[account] = value
        }
    }

    private static func countAudioFiles(in directory: URL?, fileManager: FileManager) -> Int {
        guard let directory, let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        return entries.filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(audioFilePrefix) }.count
    }

    private static func countFiles(in directory: URL?, fileManager: FileManager) -> Int {
        guard let directory, let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }
        return enumerator.compactMap { $0 as? URL }.reduce(into: 0) { count, url in
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
        }
    }
}