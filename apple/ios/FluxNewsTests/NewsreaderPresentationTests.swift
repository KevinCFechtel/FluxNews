import XCTest
import ImageIO
import Observation
import UniformTypeIdentifiers
import UIKit
import CoreText
@testable import FluxNews

final class NewsreaderPresentationTests: XCTestCase {

    func testLocalizationCatalogKeepsRuntimeArticleCounterPluralKeysManual() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let catalogURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(
            root["strings"] as? [String: Any]
        )

        for key in ["%lld article", "%lld unread article"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            XCTAssertEqual(
                entry["extractionState"] as? String,
                "manual",
                "Runtime-generated plural key must remain manual: \(key)"
            )
        }
    }

    func testProductionLocalizationSourceKeysExistAndHaveGermanTranslation() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let iosDirectory = testsDirectory.deletingLastPathComponent()
        let repositoryAppleDirectory = iosDirectory.deletingLastPathComponent()

        let catalogURL = iosDirectory
            .appendingPathComponent("FluxNews/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(
            root["strings"] as? [String: Any]
        )

        let sourceRoots = [
            iosDirectory.appendingPathComponent("FluxNews"),
            iosDirectory.appendingPathComponent("FluxNewsWidgets"),
            repositoryAppleDirectory.appendingPathComponent("shared/FluxApple"),
        ]
        let excludedFiles: Set<String> = [
            "DeveloperDiagnosticsView.swift",
        ]

        let patterns = [
            #"String\s*\(\s*localized:\s*"((?:\\.|[^"\\])*)""#,
            #"LocalizedStringResource\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bText\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bButton\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bLabel\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.navigationTitle\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bToggle\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bPicker\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bSection\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bSecureField\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bTextField\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bContentUnavailableView\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bProgressView\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bLabeledContent\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bDisclosureGroup\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bMenu\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bNavigationLink\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bLink\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bStepper\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bDatePicker\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.alert\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.confirmationDialog\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.accessibilityLabel\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.accessibilityHint\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.accessibilityValue\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.configurationDisplayName\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\.description\s*\(\s*"((?:\\.|[^"\\])*)""#,
            #"\bprompt\s*:\s*"((?:\\.|[^"\\])*)""#,
        ].map { try! NSRegularExpression(pattern: $0) }

        var sourceKeys = Set<String>()
        let fileManager = FileManager.default
        for root in sourceRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            ) else {
                XCTFail("Could not enumerate localization source root: \(root.path)")
                continue
            }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift",
                      !excludedFiles.contains(fileURL.lastPathComponent)
                else {
                    continue
                }
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let sourceRange = NSRange(source.startIndex..., in: source)
                for regex in patterns {
                    for match in regex.matches(in: source, range: sourceRange) {
                        guard match.numberOfRanges > 1,
                              let range = Range(match.range(at: 1), in: source)
                        else {
                            continue
                        }
                        let key = String(source[range])
                        guard !key.isEmpty,
                              !key.contains(#"\("#)
                        else {
                            continue
                        }
                        sourceKeys.insert(key)
                    }
                }
            }
        }

        // These are real runtime localization keys whose source form is
        // interpolated or carried by a typed LocalizedStringKey/Resource value,
        // so Xcode/static regex extraction is not reliable enough to discover
        // them from the call site alone.
        sourceKeys.formUnion([
            "%lld article",
            "%lld unread article",
            "%lld article marked as read",
            "%lld unread",
            "%lld audio",
            "%lld downloaded",
            "%lld pending",
            "%lld min",
            "%lld%% downloaded",
            "Audio %lld",
            "Audio %lld of %lld",
            "Chapter %lld",
            "Chapter %lld of %lld",
            "%lld items",
            "%lld visible records",
            "FluxNews · %lld %@",
            "Open %@ in FluxNews",
            "Sync",
            "Filter and Sort",
            "All / Unread",
            "Sort Order",
            "Search",
            "Mark All as Read",
            "Mark All as Read and Continue",
            "Listening List",
            "Now Playing",
            "Settings",
            "More",
            "Forever",
            "7 days",
            "30 days",
            "90 days",
            "No bookmarks",
            "No articles",
            "No unread news",
            "Open FluxNews to refresh widget data",
            "Selected category unavailable",
            "Selected feed unavailable",
            "Open FluxNews to configure",
            "Waiting for first successful sync",
            "No widget data available",
            "Search Miniflux",
            "Search Results",
            "Set Up FluxNews",
            "Compact",
            "Visual",
        ])

        let ignoredLiteralKeys: Set<String> = [
            "https://example.com",
        ]
        sourceKeys.subtract(ignoredLiteralKeys)

        let requiredLocales = Set(["de", "es", "gl", "nl", "ta", "tr"])
        for key in sourceKeys.sorted() {
            let entry = try XCTUnwrap(
                strings[key] as? [String: Any],
                "Production localization source key is missing from the catalog: \(key)"
            )
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "Production localization key has no localizations: \(key)"
            )
            XCTAssertTrue(
                requiredLocales.isSubset(of: Set(localizations.keys)),
                "Production localization key is missing a required locale: \(key)"
            )
            let german = try XCTUnwrap(
                localizations["de"] as? [String: Any],
                "Production localization key has no German localization: \(key)"
            )

            func containsTranslatedStringUnit(_ node: Any) -> Bool {
                guard let dictionary = node as? [String: Any] else {
                    return false
                }
                if let unit = dictionary["stringUnit"] as? [String: Any],
                   unit["state"] as? String == "translated",
                   let value = unit["value"] as? String,
                   !value.isEmpty {
                    return true
                }
                return dictionary.values.contains {
                    containsTranslatedStringUnit($0)
                }
            }

            XCTAssertTrue(
                containsTranslatedStringUnit(german),
                "Production localization key has no translated German value: \(key)"
            )
        }
    }

    func testXcodeProjectDeclaresFullProductionLocaleSet() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let projectURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        for locale in ["en", "de", "es", "gl", "nl", "ta", "tr"] {
            XCTAssertTrue(
                project.contains("\n\t\t\t\t\(locale),"),
                "Missing Xcode knownRegion for \(locale)"
            )
        }
    }

    func testLocalizationCatalogRestoresProductionLanguageSet() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let catalogURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(root["sourceLanguage"] as? String, "en")

        let strings = try XCTUnwrap(
            root["strings"] as? [String: Any]
        )
        let requiredLocales = Set(["de", "es", "gl", "nl", "ta", "tr"])

        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  entry["extractionState"] as? String != "stale" else {
                continue
            }
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "Missing localizations for active key: \(key)"
            )
            XCTAssertTrue(
                requiredLocales.isSubset(of: Set(localizations.keys)),
                "Active key is missing a production locale: \(key)"
            )
        }
    }

    func testLocalizationCatalogPreservesEnglishPlaceholderStructure() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let catalogURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(
            root["strings"] as? [String: Any]
        )
        let requiredLocales = ["de", "es", "gl", "nl", "ta", "tr"]

        func stringUnits(
            _ node: Any,
            path: String = ""
        ) -> [String: String] {
            guard let dictionary = node as? [String: Any] else { return [:] }
            var result: [String: String] = [:]
            if let unit = dictionary["stringUnit"] as? [String: Any],
               let value = unit["value"] as? String {
                result[path] = value
            }
            for (key, value) in dictionary where key != "stringUnit" {
                let nestedPath = path.isEmpty ? key : "\(path).\(key)"
                result.merge(
                    stringUnits(value, path: nestedPath),
                    uniquingKeysWith: { first, _ in first }
                )
            }
            return result
        }

        func placeholders(_ value: String) -> [String] {
            let pattern = #"%(?:\d+\$)?(lld|ld|d|f|@)"#
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(value.startIndex..., in: value)
            return regex.matches(in: value, range: range).compactMap {
                Range($0.range(at: 1), in: value).map { String(value[$0]) }
            }
        }

        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let english = localizations["en"] else {
                continue
            }
            let englishUnits = stringUnits(english)
            guard !englishUnits.isEmpty else { continue }

            for locale in requiredLocales {
                guard let localization = localizations[locale] else {
                    continue
                }
                let translatedUnits = stringUnits(localization)
                XCTAssertEqual(
                    Set(translatedUnits.keys),
                    Set(englishUnits.keys),
                    "Plural/variation structure differs for \(key) [\(locale)]"
                )
                for (path, englishValue) in englishUnits {
                    guard let translatedValue = translatedUnits[path] else {
                        continue
                    }
                    XCTAssertEqual(
                        placeholders(translatedValue).sorted(),
                        placeholders(englishValue).sorted(),
                        "Placeholder mismatch for \(key) [\(locale)] at \(path)"
                    )
                }
            }
        }
    }


    func testAboutInformationReadsVersionAndBuildFromBundleMetadata() {
        let metadata: [String: Any] = [
            "CFBundleShortVersionString": " 2.3.5 ",
            "CFBundleVersion": " 2026092601 ",
        ]

        XCTAssertEqual(
            IOSAboutInformation.version(from: metadata),
            "2.3.5"
        )
        XCTAssertEqual(
            IOSAboutInformation.build(from: metadata),
            "2026092601"
        )
    }

    func testAboutInformationFallsBackForMissingBundleMetadata() {
        XCTAssertEqual(
            IOSAboutInformation.version(from: [:]),
            String(localized: "Unknown")
        )
        XCTAssertEqual(
            IOSAboutInformation.build(
                from: ["CFBundleVersion": "   "]
            ),
            String(localized: "Unknown")
        )
    }

    func testAboutInformationUsesExpectedProjectDestinations() {
        XCTAssertEqual(
            IOSAboutInformation.fluxNewsRepositoryURL.absoluteString,
            "https://github.com/KevinCFechtel/FluxNews"
        )
        XCTAssertEqual(
            IOSAboutInformation.fluxRepositoryURL.absoluteString,
            "https://github.com/KevinCFechtel/Flux"
        )
        XCTAssertEqual(
            IOSAboutInformation.minifluxProjectURL.absoluteString,
            "https://miniflux.app"
        )
        XCTAssertEqual(
            IOSAboutInformation.licenseURL.absoluteString,
            "https://github.com/KevinCFechtel/FluxNews/blob/main/LICENSE"
        )
    }

    @MainActor
    private final class ObservationFlag {
        var value = false
    }

    @MainActor
    func testUnconfiguredFeedPreferenceOperationsFail() async {
        let store = NewsreaderStore(defaults: UserDefaults())
        let read = expectation(description: "read failure")
        let write = expectation(description: "write failure")
        let mediaWrite = expectation(description: "media write failure")
        store.loadFeedPreferences(feedID: 42) { result in
            if case .success = result { XCTFail("Unexpected read success") }
            read.fulfill()
        }
        store.setFeedOpenInMiniflux(feedID: 42, enabled: true) { result in
            if case .success = result { XCTFail("Unexpected write success") }
            write.fulfill()
        }
        store.setFeedAutoDownloadAudio(
            feedID: 42,
            enabled: true
        ) { result in
            if case .success = result {
                XCTFail("Unexpected media write success")
            }
            mediaWrite.fulfill()
        }
        await fulfillment(
            of: [read, write, mediaWrite],
            timeout: 1
        )
    }

    func testFeedSettingsRequestLifecycleRejectsStaleResults() {
        var lifecycle = IOSFeedSettingsRequestLifecycle()
        let first = lifecycle.begin()
        let second = lifecycle.begin()

        XCTAssertFalse(lifecycle.isCurrent(first))
        XCTAssertTrue(lifecycle.isCurrent(second))
        lifecycle.invalidate()
        XCTAssertFalse(lifecycle.isCurrent(second))
    }

    func testDefaultConfiguredArticleListActionsAreFilterAndSortOnly() {
        XCTAssertEqual(
            IOSBottomAction.defaultConfiguredActions,
            [.filterAndSort]
        )
        XCTAssertEqual(IOSBottomAction.fixedLeadingAction, .sync)
        XCTAssertEqual(IOSBottomAction.fixedTrailingAction, .more)
    }

    func testArticleListActionPolicyPersistsOnlyConfigurableActionsInOrder() {
        XCTAssertEqual(
            IOSArticleListActionPolicy.normalizedConfiguredActions(
                from: ["search", "sync", "more", "nowPlaying", "filterAndSort", "search"]
            ),
            [.search, .filterAndSort]
        )
    }

    @MainActor
    func testArticleListActionPreferencesRoundTripPersistedOrder() {
        let suite = "FluxNews.ArticleListActionPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = IOSArticleListActionPreferences(defaults: defaults)
        preferences.setActions([
            .listeningList,
            .sync,
            .more,
            .search,
            .toggleReadFilter,
        ])

        XCTAssertEqual(
            IOSArticleListActionPreferences(defaults: defaults).actions,
            [.listeningList, .search, .toggleReadFilter]
        )
        XCTAssertEqual(
            defaults.stringArray(forKey: IOSArticleListActionPreferences.defaultsKey),
            ["listeningList", "search", "toggleReadFilter"]
        )
    }

    func testArticleListActionPolicyAllowsExplicitEmptyConfiguration() {
        XCTAssertEqual(
            IOSArticleListActionPolicy.normalizedConfiguredActions(from: []),
            []
        )
        XCTAssertEqual(
            IOSArticleListActionPolicy.normalizedConfiguredActions(from: nil),
            IOSBottomAction.defaultConfiguredActions
        )
    }

    func testArticleListOverflowContainsSelectedOverflowThenUnselectedActions() {
        let resolved = IOSArticleListActionPolicy.resolvedActions(
            configuredActions: [.search, .toggleReadFilter, .listeningList],
            directCapacity: 2,
            scope: .all,
            hasNextScope: false,
            hasLoadedMedia: false,
            playbackStatus: .stopped
        )

        XCTAssertEqual(resolved.direct, [.search, .toggleReadFilter])
        XCTAssertEqual(resolved.overflow.first, .listeningList)
        XCTAssertFalse(resolved.overflow.contains(.search))
        XCTAssertFalse(resolved.overflow.contains(.toggleReadFilter))
        XCTAssertTrue(resolved.overflow.contains(.filterAndSort))
        XCTAssertTrue(resolved.overflow.contains(.toggleSortOrder))
        XCTAssertTrue(resolved.overflow.contains(.settings))
        XCTAssertFalse(resolved.overflow.contains(.nowPlaying))
    }

    func testArticleListOverflowKeepsAllUnselectedRelevantActionsReachable() {
        let resolved = IOSArticleListActionPolicy.resolvedActions(
            configuredActions: [],
            directCapacity: 3,
            scope: .feed(1),
            hasNextScope: true,
            hasLoadedMedia: true,
            playbackStatus: .paused
        )

        XCTAssertTrue(resolved.direct.isEmpty)
        XCTAssertEqual(
            Set(resolved.overflow),
            Set(IOSBottomAction.configurableActions)
        )
    }

    func testMarkReadActionsFollowCurrentScopeAvailability() {
        XCTAssertTrue(
            IOSArticleListActionPolicy.isAvailable(
                .markAllRead,
                scope: .all,
                hasNextScope: false,
                hasLoadedMedia: false,
                playbackStatus: .stopped
            )
        )
        XCTAssertFalse(
            IOSArticleListActionPolicy.isAvailable(
                .markAllRead,
                scope: .starred,
                hasNextScope: false,
                hasLoadedMedia: false,
                playbackStatus: .stopped
            )
        )
        XCTAssertTrue(
            IOSArticleListActionPolicy.isAvailable(
                .markAllReadAndNext,
                scope: .feed(1),
                hasNextScope: true,
                hasLoadedMedia: false,
                playbackStatus: .stopped
            )
        )
        XCTAssertFalse(
            IOSArticleListActionPolicy.isAvailable(
                .markAllReadAndNext,
                scope: .feed(1),
                hasNextScope: false,
                hasLoadedMedia: false,
                playbackStatus: .stopped
            )
        )
    }

    @MainActor
    func testNowPlayingAvailabilityTracksLoadedPlaybackWithoutChangingConfiguration() {
        let configured = [IOSBottomAction.nowPlaying, .search]
        let state = IOSMediaPlaybackPresentationState()

        XCTAssertFalse(
            IOSArticleListActionPolicy.isAvailable(
                .nowPlaying,
                scope: .all,
                hasNextScope: false,
                hasLoadedMedia: state.loadedEnclosure != nil,
                playbackStatus: state.status
            )
        )

        state.setLoadedMedia(
            enclosure: Enclosure(
                id: 1,
                articleId: 2,
                url: "https://example.test/episode.mp3",
                mimeType: "audio/mpeg",
                sizeBytes: nil,
                remoteMediaProgressionSeconds: 0,
                mediaKind: .audio
            ),
            feedTitle: "Feed",
            mediaTitle: "Episode",
            artworkSource: nil,
            chapters: [],
            positionMs: 0,
            durationMs: nil
        )
        state.setStatus(.playing)
        XCTAssertTrue(
            IOSArticleListActionPolicy.isAvailable(
                .nowPlaying,
                scope: .all,
                hasNextScope: false,
                hasLoadedMedia: state.loadedEnclosure != nil,
                playbackStatus: state.status
            )
        )

        state.setStatus(.stopped)
        XCTAssertFalse(
            IOSArticleListActionPolicy.isAvailable(
                .nowPlaying,
                scope: .all,
                hasNextScope: false,
                hasLoadedMedia: state.loadedEnclosure != nil,
                playbackStatus: state.status
            )
        )
        XCTAssertEqual(configured, [.nowPlaying, .search])
    }

    func testMiniPlayerPlacementAdaptsToArticleListChrome() {
        XCTAssertEqual(
            IOSMiniPlayerPlacementPolicy.placement(for: .compactPortrait),
            .portraitBottomDock
        )
        XCTAssertEqual(
            IOSMiniPlayerPlacementPolicy.placement(for: .compactLandscape),
            .compactTopBar
        )
        XCTAssertEqual(
            IOSMiniPlayerPlacementPolicy.placement(for: .persistentSplit),
            .sidebarFooter
        )
        XCTAssertEqual(
            IOSMiniPlayerPlacementPolicy.placement(for: .persistentSplitCollapsed),
            .compactTopBar
        )
    }

    func testCompactPortraitBottomInsetKeepsVerticalActionsIndependentOfMiniPlayer() {
        XCTAssertEqual(
            IOSCompactPortraitBottomInsetPolicy.presentation(
                chromeMode: .compactPortrait,
                actionPlacement: .topBarTrailing,
                miniPlayerIsVisible: false
            ),
            .none
        )
        XCTAssertEqual(
            IOSCompactPortraitBottomInsetPolicy.presentation(
                chromeMode: .compactPortrait,
                actionPlacement: .topBarTrailing,
                miniPlayerIsVisible: true
            ),
            .standaloneMiniPlayer
        )
        XCTAssertEqual(
            IOSCompactPortraitBottomInsetPolicy.presentation(
                chromeMode: .compactPortrait,
                actionPlacement: .bottomBar,
                miniPlayerIsVisible: true
            ),
            .combinedMiniPlayerAndActions
        )
        XCTAssertEqual(
            IOSCompactPortraitBottomInsetPolicy.presentation(
                chromeMode: .compactLandscape,
                actionPlacement: .topBarTrailing,
                miniPlayerIsVisible: true
            ),
            .none
        )
    }

    func testMiniPlayerVisibilityRequiresLoadedNonStoppedPlayback() {
        XCTAssertFalse(
            IOSMiniPlayerPresentation.isVisible(
                loadedEnclosureID: nil,
                status: .paused
            )
        )
        XCTAssertFalse(
            IOSMiniPlayerPresentation.isVisible(
                loadedEnclosureID: 1,
                status: .stopped
            )
        )
        XCTAssertTrue(
            IOSMiniPlayerPresentation.isVisible(
                loadedEnclosureID: 1,
                status: .paused
            )
        )
        XCTAssertTrue(
            IOSMiniPlayerPresentation.isVisible(
                loadedEnclosureID: 1,
                status: .playing
            )
        )
    }

    func testMiniPlayerElapsedDurationLabelUsesBoundedPlaybackTime() {
        XCTAssertEqual(
            IOSMiniPlayerPresentation.elapsedDurationLabel(
                positionMs: 754_000,
                durationMs: 2_890_000
            ),
            "12:34 / 48:10"
        )
        XCTAssertEqual(
            IOSMiniPlayerPresentation.elapsedDurationLabel(
                positionMs: 4_000_000,
                durationMs: 3_700_000
            ),
            "1:01:40 / 1:01:40"
        )
        XCTAssertNil(
            IOSMiniPlayerPresentation.elapsedDurationLabel(
                positionMs: 0,
                durationMs: nil
            )
        )
        XCTAssertNil(
            IOSMiniPlayerPresentation.elapsedDurationLabel(
                positionMs: 0,
                durationMs: 0
            )
        )
    }

    func testNowPlayingIsNoLongerAConfigurableArticleListAction() {
        XCTAssertFalse(IOSBottomAction.configurableActions.contains(.nowPlaying))
        XCTAssertEqual(
            IOSArticleListActionPolicy.normalizedConfiguredActions(
                from: ["nowPlaying", "search"]
            ),
            [.search]
        )
    }

    func testNowPlayingPlayerPresentationFindsLoadedListeningListItem() {
        let enclosure = Enclosure(
            id: 7,
            articleId: 70,
            url: "https://example.test/episode.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )
        let item = ListeningListItem(
            articleId: 70,
            feedId: 9,
            title: "Episode with notes",
            feedTitle: "Feed",
            publishedAt: "",
            addedAt: "",
            remotePresent: true,
            audioEnclosures: [
                ListeningListEnclosure(
                    enclosure: enclosure,
                    remotePresent: true,
                    playbackState: nil,
                    download: nil,
                    durationMs: nil
                )
            ],
            activeEnclosureId: 7
        )

        let resolved = IOSListeningListPlayerPresentation.item(
            for: enclosure,
            in: [item]
        )

        XCTAssertEqual(resolved?.articleId, item.articleId)
        XCTAssertEqual(resolved?.feedId, item.feedId)
        XCTAssertEqual(resolved?.audioEnclosures.first?.enclosure.id, enclosure.id)
    }

    func testNowPlayingPlayerPresentationFallsBackWhenLoadedItemIsMissing() {
        let enclosure = Enclosure(
            id: 7,
            articleId: 70,
            url: "https://example.test/episode.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )

        XCTAssertNil(
            IOSListeningListPlayerPresentation.item(for: enclosure, in: [])
        )
    }

    func testFloatingActionGroupUsesStableCapsuleMetrics() {
        XCTAssertEqual(IOSArticleListActionChromeMetrics.floatingHorizontalPadding, 8)
        XCTAssertEqual(IOSArticleListActionChromeMetrics.floatingVerticalPadding, 5)
        XCTAssertEqual(IOSArticleListActionChromeMetrics.floatingSpacing, 6)
    }

    func testPortraitTitleCapsuleNaturalTopInsetMatchesItsChromeHeight() {
        let singleLine = IOSArticleListTitleCapsuleMetrics.portraitNaturalTopContentInset(showSubtitle: false)
        let twoLine = IOSArticleListTitleCapsuleMetrics.portraitNaturalTopContentInset(showSubtitle: true)

        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.stackedVerticalPadding, 7)
        XCTAssertGreaterThan(twoLine, singleLine)
        XCTAssertGreaterThan(singleLine, IOSArticleListTitleCapsuleMetrics.floatingVerticalInset * 2)
    }

    func testCollapsedSplitInlineTitleCapsuleKeepsUsefulMinimumWidth() {
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.inlineMinimumContentWidth, 280)
        XCTAssertGreaterThan(
            IOSArticleListTitleCapsuleMetrics.inlineCountPriority,
            IOSArticleListTitleCapsuleMetrics.inlineTitlePriority
        )
    }

    func testRegularCollapsedToolbarCanReleaseTitleWidthForActions() {
        XCTAssertGreaterThan(
            IOSArticleListTitleCapsuleMetrics.inlineMinimumContentWidth,
            IOSArticleListTitleCapsuleMetrics.regularToolbarTitleMinimumWidth
        )
        XCTAssertEqual(
            IOSArticleListTitleCapsuleMetrics.regularToolbarTitleMinimumWidth,
            96
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.configurableDirectActionCapacity(
                for: .persistentSplitCollapsed
            ),
            3
        )
    }

    func testArticleListTitleChromeSeparatesPortraitLandscapeAndSplitModes() {
        XCTAssertEqual(IOSArticleListChromePresentation.titleCapsulePlacement(for: .compactPortrait), .floatingTopCenter)
        XCTAssertEqual(IOSArticleListChromePresentation.titleCapsulePlacement(for: .compactLandscape), .navigationTopLeading)
        XCTAssertEqual(IOSArticleListChromePresentation.titleCapsulePlacement(for: .persistentSplit), .hidden)
        XCTAssertEqual(IOSArticleListChromePresentation.titleCapsulePlacement(for: .persistentSplitCollapsed), .navigationTopLeading)
        XCTAssertEqual(
            IOSArticleListChromePresentation.titleCapsulePlacement(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: true
            ),
            .navigationTopLeading
        )
        XCTAssertEqual(IOSArticleListChromePresentation.navigationBarVisibility(for: .compactPortrait), .hidden)
        XCTAssertEqual(
            IOSArticleListChromePresentation.navigationBarVisibility(
                for: .compactPortrait,
                systemPrefersVerticalToolbar: true,
                systemUsesAdaptiveToolbar: true
            ),
            .visible
        )
        XCTAssertEqual(IOSArticleListChromePresentation.navigationBarVisibility(for: .compactLandscape), .visible)
        XCTAssertEqual(IOSArticleListChromePresentation.navigationBarVisibility(for: .persistentSplit), .hidden)
        XCTAssertEqual(IOSArticleListChromePresentation.navigationBarVisibility(for: .persistentSplitCollapsed), .hidden)
        XCTAssertTrue(IOSArticleListChromePresentation.usesNativeTopEdgeEffect(for: .compactPortrait))
        XCTAssertFalse(IOSArticleListChromePresentation.usesNativeTopEdgeEffect(for: .compactLandscape))
        XCTAssertTrue(IOSArticleListChromePresentation.usesNativeTopEdgeEffect(for: .persistentSplit))
        XCTAssertTrue(IOSArticleListChromePresentation.usesNativeTopEdgeEffect(for: .persistentSplitCollapsed))
        XCTAssertTrue(
            IOSArticleListChromePresentation.usesNativeTopEdgeEffect(
                for: .compactPortrait,
                systemPrefersVerticalToolbar: true
            )
        )
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.floatingHorizontalInset, 12)
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.floatingVerticalInset, 4)
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.floatingRowSpacing, 10)
    }

    func testCompactLandscapeTitleCapsuleFitsCompactFloatingRow() {
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.compactStackedVerticalPadding, 0)
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.compactStackedHorizontalPadding, 8)
        XCTAssertLessThan(IOSArticleListTitleCapsuleMetrics.compactStackedSpacing, 8)
        XCTAssertEqual(IOSArticleListTitleCapsuleMetrics.compactStackedMinimumContentWidth, 190)
        XCTAssertGreaterThan(
            IOSArticleListTitleCapsuleMetrics.compactStackedTitlePriority,
            IOSArticleListTitleCapsuleMetrics.inlineTitlePriority
        )
    }

    func testRegularCollapsedTitleUsesPassiveNavigationPlacement() {
        XCTAssertEqual(
            IOSArticleListChromePresentation.titleCapsulePlacement(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: false,
                systemUsesAdaptiveToolbar: true
            ),
            .navigationTopLeading
        )
    }

    func testLandscapeCounterGermanLocalizationCatalog() throws {
        let german = try localizationBundle("de")
        XCTAssertEqual(String(localized: "\(79) unread", bundle: german), "79 ungelesen")
        XCTAssertEqual(String(localized: "\(79) article", bundle: german), "79 Artikel")
    }

    func testArticleListActionCapacityAdaptsToChromeMode() {
        XCTAssertEqual(
            IOSArticleListChromePresentation.configurableDirectActionCapacity(
                for: .compactPortrait
            ),
            3
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.configurableDirectActionCapacity(
                for: .compactLandscape
            ),
            2
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.configurableDirectActionCapacity(
                for: .persistentSplit
            ),
            5
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.configurableDirectActionCapacity(
                for: .persistentSplit,
                systemPrefersVerticalToolbar: true
            ),
            3
        )
    }

    func testPersistentSplitModesAdaptActionsToSystemVerticalToolbar() {
        XCTAssertEqual(IOSArticleListChromePresentation.actionPlacement(for: .persistentSplit), .floatingTopTrailing)
        XCTAssertEqual(IOSArticleListChromePresentation.actionPlacement(for: .persistentSplitCollapsed), .floatingTopTrailing)

        XCTAssertEqual(
            IOSArticleListChromePresentation.actionPlacement(
                for: .persistentSplit,
                systemPrefersVerticalToolbar: true
            ),
            .topBarTrailing
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.actionPlacement(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: true
            ),
            .topBarTrailing
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.navigationBarVisibility(
                for: .persistentSplit,
                systemPrefersVerticalToolbar: true
            ),
            .visible
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.navigationBarVisibility(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: true
            ),
            .visible
        )
        XCTAssertTrue(
            IOSArticleListChromePresentation.usesNativeTopEdgeEffect(
                for: .persistentSplit,
                systemPrefersVerticalToolbar: true
            )
        )
        XCTAssertTrue(
            IOSArticleListChromePresentation.usesNativeTopEdgeEffect(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: true
            )
        )
    }

    func testListeningListUsesSearchStyleFlyoverNavigationInsteadOfScopeDetail() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let iosDirectory = testsDirectory.deletingLastPathComponent()
        let navigationSource = try String(
            contentsOf: iosDirectory
                .appendingPathComponent("FluxNews/NewsNavigationView.swift"),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: iosDirectory
                .appendingPathComponent("FluxNews/ContentView.swift"),
            encoding: .utf8
        )
        let listeningListSource = try String(
            contentsOf: iosDirectory
                .appendingPathComponent("FluxNews/IOSListeningListView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            navigationSource.contains(
                "accessibilityIdentifier(\"navigation.listeningList\")"
            )
        )
        XCTAssertFalse(
            navigationSource.contains(
                "scopeRow(\"Listening List\""
            )
        )
        XCTAssertTrue(
            contentSource.contains(
                ".sheet(isPresented: $listeningListPresented)"
            )
        )
        XCTAssertTrue(
            contentSource.contains(
                ".toolbarMinimizationBehavior("
            )
        )
        XCTAssertTrue(
            contentSource.contains(
                "get: { listeningListPlayerArticleID != nil }"
            )
        )
        XCTAssertFalse(
            contentSource.contains(
                "if newsreaderStore.scope == .listeningList {\n            IOSListeningListView"
            )
        )
        XCTAssertFalse(
            listeningListSource.contains("showsScopeChooser")
        )
        XCTAssertFalse(
            listeningListSource.contains("onPresentScopeChooser")
        )
    }

    func testCompactShellRejectsPersistentSidebarVisibility() {
        XCTAssertEqual(
            AdaptiveShellTransitionPolicy.constrainedSplitColumnVisibility(
                requested: .all,
                presentation: .compact
            ),
            .detailOnly
        )
        XCTAssertEqual(
            AdaptiveShellTransitionPolicy.constrainedSplitColumnVisibility(
                requested: .all,
                presentation: .regular
            ),
            .all
        )
    }

    func testCompactPresentationIgnoresStaleSplitVisibilityDuringTransition() {
        XCTAssertEqual(
            IOSArticleListChromePresentation.mode(
                for: .compact,
                verticalSizeClass: .compact,
                splitColumnVisibility: .all
            ),
            .compactLandscape
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.mode(
                for: .compact,
                verticalSizeClass: .regular,
                splitColumnVisibility: .all
            ),
            .compactPortrait
        )
    }

    func testArticleListChromeAdaptsPortraitLandscapeAndPersistentNavigation() {
        let portrait = IOSArticleListChromePresentation.mode(
            for: .compact,
            verticalSizeClass: .regular,
            splitColumnVisibility: .detailOnly
        )
        XCTAssertEqual(portrait, .compactPortrait)
        XCTAssertEqual(IOSArticleListChromePresentation.actionPlacement(for: portrait), .bottomBar)
        XCTAssertEqual(
            IOSArticleListChromePresentation.actionPlacement(
                for: portrait,
                systemPrefersVerticalToolbar: true,
                systemUsesAdaptiveToolbar: true
            ),
            .topBarTrailing
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.navigationBarVisibility(
                for: portrait,
                systemPrefersVerticalToolbar: true,
                systemUsesAdaptiveToolbar: true
            ),
            .visible
        )

        let landscape = IOSArticleListChromePresentation.mode(
            for: .compact,
            verticalSizeClass: .compact,
            splitColumnVisibility: .detailOnly
        )
        XCTAssertEqual(landscape, .compactLandscape)
        XCTAssertEqual(IOSArticleListChromePresentation.actionPlacement(for: landscape), .topBarTrailing)

        let persistent = IOSArticleListChromePresentation.mode(
            for: .regular,
            verticalSizeClass: .regular,
            splitColumnVisibility: .all
        )
        XCTAssertEqual(persistent, .persistentSplit)
        XCTAssertEqual(IOSArticleListChromePresentation.actionPlacement(for: persistent), .floatingTopTrailing)

        let collapsedPersistent = IOSArticleListChromePresentation.mode(
            for: .regular,
            verticalSizeClass: .regular,
            splitColumnVisibility: .detailOnly
        )
        XCTAssertEqual(collapsedPersistent, .persistentSplitCollapsed)
        XCTAssertEqual(IOSArticleListChromePresentation.actionPlacement(for: collapsedPersistent), .floatingTopTrailing)
    }

    func testDuoRegularPoseChangesKeepSplitModeAndOnlyChangeToolbarAxis() {
        let visibleSidebar = IOSArticleListChromePresentation.mode(
            for: .regular,
            verticalSizeClass: .regular,
            splitColumnVisibility: .all
        )
        XCTAssertEqual(visibleSidebar, .persistentSplit)
        XCTAssertEqual(
            IOSArticleListChromePresentation.actionPlacement(
                for: visibleSidebar,
                systemPrefersVerticalToolbar: false
            ),
            .floatingTopTrailing
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.actionPlacement(
                for: visibleSidebar,
                systemPrefersVerticalToolbar: true
            ),
            .topBarTrailing
        )

        let collapsedSidebar = IOSArticleListChromePresentation.mode(
            for: .regular,
            verticalSizeClass: .regular,
            splitColumnVisibility: .detailOnly
        )
        XCTAssertEqual(collapsedSidebar, .persistentSplitCollapsed)
        XCTAssertEqual(
            IOSArticleListChromePresentation.titleCapsulePlacement(
                for: collapsedSidebar,
                systemPrefersVerticalToolbar: false
            ),
            .navigationTopLeading
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.titleCapsulePlacement(
                for: collapsedSidebar,
                systemPrefersVerticalToolbar: true
            ),
            .navigationTopLeading
        )
    }

    func testCompactLandscapePlayerPrefersExpandedTitleWidth() {
        XCTAssertEqual(IOSMiniPlayerMetrics.topBarExpandedWidth, 270)
        XCTAssertLessThan(IOSMiniPlayerMetrics.topBarCompactWidth, IOSMiniPlayerMetrics.topBarExpandedWidth)
        XCTAssertEqual(IOSMiniPlayerPlacementPolicy.placement(for: .compactLandscape), .compactTopBar)
    }

    func testRegularCollapsedMiniPlayerHasLargerFloatingStyle() {
        XCTAssertEqual(IOSMiniPlayerMetrics.regularFloatingArtworkSize, 34)
        XCTAssertEqual(IOSMiniPlayerMetrics.regularFloatingWidth, 320)
        XCTAssertGreaterThan(
            IOSMiniPlayerMetrics.regularFloatingWidth,
            IOSMiniPlayerMetrics.topBarExpandedWidth
        )
    }

    func testCollapsedRegularMiniPlayerPlacementRemainsTopChrome() {
        XCTAssertEqual(
            IOSMiniPlayerPlacementPolicy.placement(for: .persistentSplitCollapsed),
            .compactTopBar
        )
        XCTAssertEqual(
            IOSMiniPlayerPlacementPolicy.placement(for: .persistentSplit),
            .sidebarFooter
        )
    }

    func testMediaPlayerFoldPolicyUsesTabletopOnlyForHorizontalDivision() {
        XCTAssertTrue(
            IOSMediaPlayerFoldLayoutPolicy.usesTabletopLayout(
                for: CGRect(x: 0, y: 300, width: 800, height: 12)
            )
        )
        XCTAssertFalse(
            IOSMediaPlayerFoldLayoutPolicy.usesTabletopLayout(
                for: CGRect(x: 400, y: 0, width: 12, height: 700)
            )
        )
        XCTAssertFalse(
            IOSMediaPlayerFoldLayoutPolicy.usesTabletopLayout(
                for: .zero
            )
        )
    }

    func testMediaPlayerQueriesDivisionReservedRegionForTabletopLayout() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let iosDirectory = testsDirectory.deletingLastPathComponent()
        let playerSource = try String(
            contentsOf: iosDirectory
                .appendingPathComponent("FluxNews/IOSMediaPlayerView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            playerSource.contains("reservedRegions(kind: .division)")
        )
        XCTAssertTrue(
            playerSource.contains("tabletopPlayerContent(")
        )
    }

    func testIPadRegularModesKeepActionsInTopToolbar() {
        for mode in [IOSArticleListChromeMode.persistentSplit, .persistentSplitCollapsed] {
            XCTAssertEqual(
                mode == .persistentSplit || mode == .persistentSplitCollapsed
                    ? IOSArticleListActionPlacement.topBarTrailing
                    : IOSArticleListChromePresentation.actionPlacement(for: mode),
                .topBarTrailing
            )
        }
    }

    func testIPadRegularToolbarUsesOneHorizontalPathIndependentOfVerticalToolbarCapability() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let iosDirectory = testsDirectory.deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: iosDirectory
                .appendingPathComponent("FluxNews/ContentView.swift"),
            encoding: .utf8
        )

        let ipadRoute = "if UIDevice.current.userInterfaceIdiom == .pad"
        let adaptiveRoute = "IOSArticleListVerticalToolbarCapabilityEnvironment"
        guard let ipadRange = contentSource.range(of: ipadRoute),
              let adaptiveRange = contentSource.range(of: adaptiveRoute) else {
            return XCTFail("Expected iPad and adaptive toolbar routing")
        }

        XCTAssertLessThan(
            contentSource.distance(from: contentSource.startIndex, to: ipadRange.lowerBound),
            contentSource.distance(from: contentSource.startIndex, to: adaptiveRange.lowerBound)
        )
        XCTAssertTrue(contentSource.contains("systemUsesAdaptiveToolbar: false"))
        XCTAssertTrue(contentSource.contains("systemPrefersVerticalToolbar: false"))
        XCTAssertTrue(contentSource.contains(".toolbar(.visible, for: .navigationBar)"))
    }

    func testVerticalToolbarCapabilityKeepsDuoChromeNativeAcrossPoseChanges() {
        for mode in [IOSArticleListChromeMode.persistentSplit, .persistentSplitCollapsed] {
            XCTAssertEqual(
                IOSArticleListChromePresentation.actionPlacement(
                    for: mode,
                    systemPrefersVerticalToolbar: false,
                    systemUsesAdaptiveToolbar: true
                ),
                .topBarTrailing
            )
            XCTAssertEqual(
                IOSArticleListChromePresentation.actionPlacement(
                    for: mode,
                    systemPrefersVerticalToolbar: true,
                    systemUsesAdaptiveToolbar: true
                ),
                .topBarTrailing
            )
            XCTAssertEqual(
                IOSArticleListChromePresentation.navigationBarVisibility(
                    for: mode,
                    systemPrefersVerticalToolbar: false,
                    systemUsesAdaptiveToolbar: true
                ),
                .automatic
            )
            XCTAssertEqual(
                IOSArticleListChromePresentation.navigationBarVisibility(
                    for: mode,
                    systemPrefersVerticalToolbar: true,
                    systemUsesAdaptiveToolbar: true
                ),
                .visible
            )
        }

        XCTAssertEqual(
            IOSArticleListChromePresentation.titleCapsulePlacement(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: false,
                systemUsesAdaptiveToolbar: true
            ),
            .navigationTopLeading
        )
        XCTAssertEqual(
            IOSArticleListChromePresentation.titleCapsulePlacement(
                for: .persistentSplitCollapsed,
                systemPrefersVerticalToolbar: true,
                systemUsesAdaptiveToolbar: true
            ),
            .navigationTopLeading
        )
    }

    func testActionFeedbackClearsBottomActionBarChrome() {
        XCTAssertEqual(
            IOSActionFeedbackPresentation.bottomPadding(
                hasBottomActionBar: false
            ),
            18
        )
        XCTAssertEqual(
            IOSActionFeedbackPresentation.bottomPadding(
                hasBottomActionBar: true
            ),
            72
        )
        XCTAssertEqual(
            IOSActionFeedbackPresentation.bottomPadding(
                hasBottomActionBar: true,
                hasMiniPlayer: true
            ),
            130
        )
    }

    func testPassiveActionFeedbackUsesBoundedTransientPresentation() {
        XCTAssertEqual(
            IOSActionFeedbackPresentation.autoDismissDelay,
            .seconds(3)
        )

        let first = IOSActionFeedbackItem(
            id: 1,
            kind: .addedToListeningList
        )
        let replacement = IOSActionFeedbackItem(
            id: 2,
            kind: .downloadRequested
        )

        XCTAssertTrue(
            IOSActionFeedbackPresentation.shouldDismiss(
                current: first,
                id: 1
            )
        )
        XCTAssertFalse(
            IOSActionFeedbackPresentation.shouldDismiss(
                current: replacement,
                id: 1
            )
        )
        XCTAssertEqual(
            IOSActionFeedbackKind.addedToListeningList.message,
            String(localized: "Added to Listening List")
        )
        XCTAssertEqual(
            IOSActionFeedbackKind.downloadRequested.symbolName,
            "arrow.down.circle"
        )
    }

    func testNextFeedUsesNavigationOrderAndDoesNotWrap() {
        let catalog = NavigationCatalog(categories: [], feeds: [
            .init(id: 10, categoryId: 1, title: "First"),
            .init(id: 20, categoryId: 1, title: "Second")
        ])
        XCTAssertEqual(IOSScopeNavigation.nextScope(after: .feed(10), catalog: catalog, hidingEmpty: false, counts: [:]), .feed(20))
        XCTAssertNil(IOSScopeNavigation.nextScope(after: .feed(20), catalog: catalog, hidingEmpty: false, counts: [:]))
    }

    func testNextCategoryUsesNavigationOrderAndDoesNotWrap() {
        let catalog = NavigationCatalog(
            categories: [.init(id: 1, title: "First"), .init(id: 2, title: "Second")],
            feeds: [.init(id: 10, categoryId: 1, title: "Feed"), .init(id: 20, categoryId: 2, title: "Feed")]
        )
        XCTAssertEqual(IOSScopeNavigation.nextScope(after: .category(1), catalog: catalog, hidingEmpty: false, counts: [:]), .category(2))
        XCTAssertNil(IOSScopeNavigation.nextScope(after: .category(2), catalog: catalog, hidingEmpty: false, counts: [:]))
    }

    func testNextScopeUsesVisibleNavigationProjectionAndNeverAppliesToGlobalScopes() {
        let catalog = NavigationCatalog(
            categories: [.init(id: 1, title: "First"), .init(id: 2, title: "Second"), .init(id: 3, title: "Third")],
            feeds: [.init(id: 10, categoryId: 1, title: "Current"), .init(id: 20, categoryId: 2, title: "Empty"), .init(id: 30, categoryId: 3, title: "Visible")]
        )
        XCTAssertEqual(IOSScopeNavigation.nextScope(after: .feed(10), catalog: catalog, hidingEmpty: true, counts: [10: 1, 20: 0, 30: 1]), .feed(30))
        XCTAssertNil(IOSScopeNavigation.nextScope(after: .all, catalog: catalog, hidingEmpty: false, counts: [:]))
        XCTAssertNil(IOSScopeNavigation.nextScope(after: .starred, catalog: catalog, hidingEmpty: false, counts: [:]))
    }

    func testNewsNavigationPresentationMatchesAdaptiveRoutes() {
        XCTAssertEqual(NewsNavigationPresentation.sidebar, .sidebar)
        XCTAssertEqual(NewsNavigationPresentation.sheet, .sheet)
    }

    func testAdaptivePresentationUsesTransientNavigationWhenCompact() {
        let presentation = AdaptivePresentationPolicy.presentation(horizontalSizeClass: .compact, verticalSizeClass: .regular)
        XCTAssertEqual(presentation, .compact)
        XCTAssertFalse(presentation.usesPersistentSplitNavigation)
    }

    func testIOSFirstReleaseUsesOneScene() {
        XCTAssertFalse(IOSSceneOwnershipPolicy.supportsMultipleScenes)

        let appBundle = Bundle(for: FluxNewsAppBundleMarker.self)
        let manifest = appBundle.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?["UIApplicationSupportsMultipleScenes"] as? Bool, false)
    }

    func testAdaptivePresentationUsesSplitNavigationWhenRegularRegardlessOfDeviceIdentity() {
        let presentation = AdaptivePresentationPolicy.presentation(horizontalSizeClass: .regular, verticalSizeClass: .regular)
        XCTAssertEqual(presentation, .regular)
        XCTAssertTrue(presentation.usesPersistentSplitNavigation)
    }

    func testNavigationExpansionStateAllowsExplicitCollapseOfSelectedCategory() {
        var expansion = NewsNavigationExpansionState()
        expansion.setExpanded(true, categoryID: 7)
        XCTAssertTrue(expansion.isExpanded(7))

        expansion.setExpanded(false, categoryID: 7)
        XCTAssertFalse(expansion.isExpanded(7))
    }

    @MainActor
    func testAdaptivePresentationDoesNotChangeSemanticScrollResetRevision() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let resetRevision = store.scrollResetRevision

        _ = AdaptiveShellTransitionPolicy.navigationSheetPresented(after: .compact, wasPresented: true)
        _ = AdaptiveShellTransitionPolicy.splitColumnVisibility(after: .regular)

        XCTAssertEqual(store.scrollResetRevision, resetRevision)
        XCTAssertTrue(AdaptivePresentation.compact != AdaptivePresentation.regular)
    }

    func testAdaptiveShellTransitionNormalizesOnlyNavigationPresentation() {
        XCTAssertFalse(AdaptiveShellTransitionPolicy.navigationSheetPresented(after: .regular, wasPresented: true))
        XCTAssertTrue(AdaptiveShellTransitionPolicy.navigationSheetPresented(after: .compact, wasPresented: true))
        XCTAssertEqual(AdaptiveShellTransitionPolicy.splitColumnVisibility(after: .regular), .automatic)
        XCTAssertEqual(AdaptiveShellTransitionPolicy.splitColumnVisibility(after: .compact), .detailOnly)
    }

    func testAdaptiveShellTransitionPreservesSearchAndReaderRequestGenerations() {
        var searchRequest = IOSSearchRequestState()
        var readerRequest = ReaderRequestState()
        let searchGeneration = searchRequest.begin()
        let readerGeneration = readerRequest.begin()

        _ = AdaptiveShellTransitionPolicy.navigationSheetPresented(after: .regular, wasPresented: true)
        _ = AdaptiveShellTransitionPolicy.navigationSheetPresented(after: .compact, wasPresented: false)

        XCTAssertTrue(searchRequest.isCurrent(searchGeneration))
        XCTAssertTrue(readerRequest.isCurrent(readerGeneration))
    }

    @MainActor
    func testAdaptiveShellTransitionDoesNotRecreateNewsreaderOrSearchState() {
        let newsreader = NewsreaderStore(defaults: UserDefaults())
        let search = IOSSearchStore()
        search.query = "adaptive"
        let structuralRevision = newsreader.timelineStructuralState.revision

        _ = AdaptiveShellTransitionPolicy.splitColumnVisibility(after: .regular)
        _ = AdaptiveShellTransitionPolicy.splitColumnVisibility(after: .compact)

        XCTAssertEqual(search.query, "adaptive")
        XCTAssertEqual(newsreader.timelineStructuralState.revision, structuralRevision)
    }

    @MainActor
    func testSemanticScrollResetPreservesTimelineControllerAndAvoidsStructuralSnapshot() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let controllerIdentity = ObjectIdentifier(controller)
        let structuralReconciliations = controller.structuralReconciliationCount
        let snapshotApplications = controller.structuralSnapshotApplicationCount
        let scrolloverGeneration = controller.scrolloverLayoutGenerationForTesting

        controller.update(
            structuralState: timelineStructuralState([timelineArticle(id: 1), timelineArticle(id: 2)], revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 1,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )

        XCTAssertEqual(ObjectIdentifier(controller), controllerIdentity)
        XCTAssertEqual(controller.structuralReconciliationCount, structuralReconciliations)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, snapshotApplications)
        XCTAssertEqual(controller.scrollResetApplicationCountForTesting, 1)
        XCTAssertEqual(controller.lastScrollResetOffsetForTesting, .init(x: 0, y: 0))
        XCTAssertEqual(controller.contentOffsetForTesting, .init(x: 0, y: 0))
        XCTAssertGreaterThan(controller.scrolloverLayoutGenerationForTesting, scrolloverGeneration)
    }

    @MainActor
    func testNaturalTopContentInsetScrollsWithContentAndParticipatesInSemanticReset() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let structuralReconciliations = controller.structuralReconciliationCount
        let snapshotApplications = controller.structuralSnapshotApplicationCount

        controller.update(
            structuralState: timelineStructuralState([timelineArticle(id: 1), timelineArticle(id: 2)], revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false,
            naturalTopContentInset: 64
        )

        XCTAssertEqual(controller.naturalTopContentInsetForTesting, 64, accuracy: 0.001)
        XCTAssertEqual(controller.contentOffsetForTesting.y, -64, accuracy: 0.001)
        XCTAssertEqual(controller.structuralReconciliationCount, structuralReconciliations)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, snapshotApplications)

        controller.update(
            structuralState: timelineStructuralState([timelineArticle(id: 1), timelineArticle(id: 2)], revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 1,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false,
            naturalTopContentInset: 64
        )

        XCTAssertEqual(controller.scrollResetApplicationCountForTesting, 1)
        XCTAssertEqual(controller.lastScrollResetOffsetForTesting?.y ?? .nan, -64, accuracy: 0.001)
        XCTAssertEqual(controller.contentOffsetForTesting.y, -64, accuracy: 0.001)
    }

    @MainActor
    func testRelativePublicationTimeToggleRekeysGeometryWithoutStructuralSnapshot() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let articles = [timelineArticle(id: 1), timelineArticle(id: 2)]
        let controller = IOSUIKitArticleTimelineController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        bridge.replaceArticleStates(Dictionary(uniqueKeysWithValues: articles.map {
            ($0.id, IOSUIKitArticlePresentationState(isRead: $0.isRead, isStarred: $0.isStarred, revision: 0))
        }))
        let structuralState = timelineStructuralState(articles, revision: 1)

        controller.update(
            structuralState: structuralState,
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            showRelativePublicationTime: false,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        await controller.settleForTesting()

        let structuralReconciliations = controller.structuralReconciliationCount
        let snapshotApplications = controller.structuralSnapshotApplicationCount
        let ids = controller.orderedArticleIDsForTesting
        controller.resetPerformanceMetrics()

        controller.update(
            structuralState: structuralState,
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            showRelativePublicationTime: true,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        await controller.settleForTesting()

        let performance = controller.performanceSnapshot()
        XCTAssertEqual(controller.structuralReconciliationCount, structuralReconciliations)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, snapshotApplications)
        XCTAssertEqual(controller.orderedArticleIDsForTesting, ids)
        XCTAssertGreaterThan(performance.geometryIdentityChanges, 0)
        XCTAssertEqual(performance.snapshotApplyCount, 0)
    }

    func testArticleActionHapticPolicyConfirmsRealStarStateChangesOnly() {
        XCTAssertTrue(IOSArticleActionHapticPolicy.shouldConfirmStar(previous: false, requested: true))
        XCTAssertTrue(IOSArticleActionHapticPolicy.shouldConfirmStar(previous: true, requested: false))
        XCTAssertFalse(IOSArticleActionHapticPolicy.shouldConfirmStar(previous: true, requested: true))
        XCTAssertFalse(IOSArticleActionHapticPolicy.shouldConfirmStar(previous: false, requested: false))
        XCTAssertFalse(IOSArticleActionHapticPolicy.shouldConfirmStar(previous: nil, requested: true))
    }

    func testArticleActionHapticPolicyConfirmsOnlySuccessfulThirdPartySave() {
        XCTAssertTrue(IOSArticleActionHapticPolicy.shouldConfirmSaveToService(.saved))
        XCTAssertFalse(IOSArticleActionHapticPolicy.shouldConfirmSaveToService(.noIntegrationConfigured))
    }

    @MainActor
    func testTimelineUsesAutomaticNativeTopEdgeEffectWhenAvailable() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        controller.loadViewIfNeeded()

        if #available(iOS 26.0, *) {
            XCTAssertTrue(controller.nativeTopEdgeEffectEnabledForTesting)
            XCTAssertTrue(controller.nativeTopEdgeEffectUsesAutomaticStyleForTesting)
            XCTAssertFalse(controller.statusBarScrimVisibleForTesting)
        } else {
            XCTAssertFalse(controller.nativeTopEdgeEffectEnabledForTesting)
            XCTAssertFalse(controller.nativeTopEdgeEffectUsesAutomaticStyleForTesting)
            XCTAssertTrue(controller.statusBarScrimVisibleForTesting)
        }
        XCTAssertEqual(IOSUIKitTimelineTopScrimView.peakAlpha, 0.68, accuracy: 0.001)
    }

    func testIPhoneNavigationButtonUsesTheFluxTemplateAsset() {
        XCTAssertEqual(IOSNavigationButtonPresentation.imageName, "FluxNewsTemplate")
        XCTAssertEqual(IOSNavigationButtonPresentation.accessibilityLabel, String(localized: "Choose news scope"))
        XCTAssertEqual(IOSNavigationButtonPresentation.glyphSize, 22)
    }

    func testNavigationBrandingUsesTheExistingFluxNewsTemplateAsset() {
        XCTAssertEqual(IOSNavigationBranding.assetName, "FluxNewsTemplate")
        XCTAssertEqual(IOSNavigationBranding.accessibilityLabel, String(localized: "FluxNews"))
        XCTAssertTrue(IOSNavigationBranding.iconUsesSolidAccentColor)
    }

    func testArticleNavigationKeepsLargeTitleCompatibleContainerModeBehindScopeCapsule() {
        XCTAssertEqual(IOSArticleNavigationPresentation.titleDisplayMode, .large)
    }

    func testArticleListTitleDoesNotContainSelectionCount() {
        XCTAssertEqual(ArticleListTitlePresentation.title(scope: .all, catalog: NavigationCatalog(categories: [], feeds: [])), String(localized: "All News"))
    }

    func testArticleListTitleUsesCategorySelectionCount() {
        let catalog = NavigationCatalog(categories: [Category(id: 1, title: "Technology")], feeds: [])
        XCTAssertEqual(ArticleListTitlePresentation.title(scope: .category(1), catalog: catalog), "Technology")
    }

    func testArticleListTitleUsesFeedSelectionCount() {
        let catalog = NavigationCatalog(categories: [], feeds: [Feed(id: 10, categoryId: 1, title: "Ars Technica")])
        XCTAssertEqual(ArticleListTitlePresentation.title(scope: .feed(10), catalog: catalog), "Ars Technica")
    }

    func testArticleListTitleUsesStarredSelectionCount() {
        XCTAssertEqual(ArticleListTitlePresentation.title(scope: .starred, catalog: NavigationCatalog(categories: [], feeds: [])), String(localized: "Starred"))
    }

    @MainActor
    func testArticleListTitleReflectsUpdatedSelectionCount() {
        let store = NewsreaderStore(defaults: UserDefaults())
        store.scope = .all
        store.unreadOnly = false
        store.setSelectionTotalForTesting(4)
        XCTAssertEqual(
            ArticleListCounterPresentation.inlineLandscapeLabel(
                scope: store.scope,
                unreadOnly: store.unreadOnly,
                count: store.selectionTotal
            ),
            String(localized: "\(4) article")
        )

        store.setSelectionTotalForTesting(3)
        XCTAssertEqual(
            ArticleListCounterPresentation.inlineLandscapeLabel(
                scope: store.scope,
                unreadOnly: store.unreadOnly,
                count: store.selectionTotal
            ),
            String(localized: "\(3) article")
        )
    }

    func testArticleListCounterUsesCurrentScopeAndFilterSemantics() {
        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .all, unreadOnly: true, count: 117), String(localized: "\(117) unread article"))
        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .all, unreadOnly: false, count: 842), String(localized: "\(842) article"))
        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .starred, unreadOnly: true, count: 8), String(localized: "\(8) article"))
        XCTAssertEqual(
            ArticleListCounterPresentation.inlineLandscapeLabel(scope: .all, unreadOnly: false, count: 1000),
            String(localized: "\(1000) article")
        )
    }

    func testLandscapeArticleCountUsesScopeAwareInlinePresentation() {
        XCTAssertEqual(
            ArticleListCounterPresentation.inlineLandscapeLabel(scope: .all, unreadOnly: false, count: 42),
            String(localized: "\(42) article")
        )
        XCTAssertEqual(
            ArticleListCounterPresentation.inlineLandscapeLabel(scope: .all, unreadOnly: true, count: 12_345),
            String(localized: "\(12345) unread")
        )
        XCTAssertEqual(
            ArticleListCounterPresentation.inlineLandscapeLabel(scope: .starred, unreadOnly: true, count: 8),
            String(localized: "\(8) article")
        )
    }

    /// `locale:` only decides how numbers are formatted — the language comes
    /// from the bundle. Passing `Locale(identifier: "en")` to the app bundle
    /// therefore returned whatever language the host was running in.
    func testArticleListCounterUsesEnglishAndGermanPluralVariations() throws {
        let english = try localizationBundle("en")
        let german = try localizationBundle("de")

        XCTAssertEqual(String(localized: "\(1) article", bundle: english), "1 article")
        XCTAssertEqual(String(localized: "\(2) article", bundle: english), "2 articles")
        XCTAssertEqual(String(localized: "\(1) article", bundle: german), "1 Artikel")
        XCTAssertEqual(String(localized: "\(2) article", bundle: german), "2 Artikel")
    }

    private func localizationBundle(_ identifier: String) throws -> Bundle {
        let appBundle = try XCTUnwrap(Bundle(identifier: "dev.kevincfechtel.fluxNews.nativeDev"))
        let path = try XCTUnwrap(appBundle.path(forResource: identifier, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testArticleListCounterUsesGermanPluralVariations() throws {
        try XCTSkipUnless(Locale.current.language.languageCode?.identifier == "de")

        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .all, unreadOnly: false, count: 1), "1 Artikel")
        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .all, unreadOnly: false, count: 2), "2 Artikel")
        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .all, unreadOnly: true, count: 1), "1 ungelesener Artikel")
        XCTAssertEqual(ArticleListCounterPresentation.expandedLabel(scope: .all, unreadOnly: true, count: 2), "2 ungelesene Artikel")
    }

    func testRelativePublicationTimeSettingIsLocalizedInEnglishAndGerman() throws {
        let english = try localizationBundle("en")
        let german = try localizationBundle("de")

        XCTAssertEqual(
            String(localized: "Show relative publication time", bundle: english),
            "Show relative publication time"
        )
        XCTAssertEqual(
            String(localized: "Show relative publication time", bundle: german),
            "Veröffentlichungszeit relativ anzeigen"
        )
    }

    @MainActor
    func testRelativePublicationTimePreferenceDefaultsOffAndPersists() {
        let suiteName = "FluxNews.RelativePublicationTimeSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = NewsreaderStore(defaults: defaults)
        XCTAssertFalse(store.showRelativePublicationTime)

        store.setShowRelativePublicationTime(true)
        XCTAssertTrue(store.showRelativePublicationTime)

        let reloaded = NewsreaderStore(defaults: defaults)
        XCTAssertTrue(reloaded.showRelativePublicationTime)
    }

    @MainActor
    func testArticleCountPreferenceDefaultsPersistsAndOnlyControlsCounterPresentation() {
        let suiteName = "FluxNews.CounterSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = NewsreaderStore(defaults: defaults)
        XCTAssertTrue(store.showArticleCount)
        XCTAssertTrue(ArticleListCounterPresentation.isVisible(showArticleCount: store.showArticleCount))

        store.setShowArticleCount(false)
        XCTAssertFalse(store.showArticleCount)
        XCTAssertFalse(ArticleListCounterPresentation.isVisible(showArticleCount: store.showArticleCount))
        XCTAssertFalse(ArticleListCounterPresentation.usesNativeSubtitle(showArticleCount: store.showArticleCount, supportsNativeSubtitle: true))
        XCTAssertFalse(ArticleListCounterPresentation.usesToolbarFallback(showArticleCount: store.showArticleCount, supportsNativeSubtitle: false))
        XCTAssertEqual(ArticleListTitlePresentation.title(scope: .all, catalog: store.catalog), String(localized: "All News"))
        XCTAssertEqual(store.selectionTotal, 0)

        let reloaded = NewsreaderStore(defaults: defaults)
        XCTAssertFalse(reloaded.showArticleCount)
    }

    func testArticleCountPresentationSelectsNativeSubtitleOrToolbarFallback() {
        XCTAssertTrue(ArticleListCounterPresentation.usesNativeSubtitle(showArticleCount: true, supportsNativeSubtitle: true))
        XCTAssertFalse(ArticleListCounterPresentation.usesToolbarFallback(showArticleCount: true, supportsNativeSubtitle: true))
        XCTAssertFalse(ArticleListCounterPresentation.usesNativeSubtitle(showArticleCount: true, supportsNativeSubtitle: false))
        XCTAssertTrue(ArticleListCounterPresentation.usesToolbarFallback(showArticleCount: true, supportsNativeSubtitle: false))
    }

    func testEmptyStatePresentationUsesSyncingAndNoNews() {
        XCTAssertEqual(IOSArticleListEmptyState.resolve(isSyncing: true, isLoading: false, errorMessage: nil, hasArticles: false), .syncing)
        XCTAssertEqual(IOSArticleListEmptyState.resolve(isSyncing: false, isLoading: true, errorMessage: nil, hasArticles: false), .loading)
        XCTAssertEqual(IOSArticleListEmptyState.resolve(isSyncing: false, isLoading: false, errorMessage: nil, hasArticles: false), .noNews)
        XCTAssertEqual(IOSArticleListEmptyState.resolve(isSyncing: true, isLoading: true, errorMessage: nil, hasArticles: false), .syncing)
        XCTAssertEqual(IOSArticleListEmptyState.resolve(isSyncing: true, isLoading: true, errorMessage: "Offline", hasArticles: false), .error("Offline"))
        XCTAssertNil(IOSArticleListEmptyState.resolve(isSyncing: true, isLoading: true, errorMessage: nil, hasArticles: true))
    }

    @MainActor
    func testSyncReplacementRemainsLoadingUntilSnapshotResolves() {
        let store = NewsreaderStore(defaults: UserDefaults())
        store.completeSyncForTesting(SyncCompleted(reason: .manual, newArticles: 0, updatedArticles: 0, mutationsDelivered: 0, dataChanged: true, navigationChanged: false, newArticlesByFeed: [], systemNotificationCandidates: []))

        XCTAssertEqual(IOSArticleListEmptyState.resolve(isSyncing: store.isSyncing, isLoading: store.isLoading, errorMessage: store.errorMessage, hasArticles: !store.articles.isEmpty), .loading)
    }

    func testSyncButtonPresentationMakesRunningSyncAnExplicitCancelAction() {
        XCTAssertEqual(IOSSyncButtonPresentation.symbolName(for: .idle), "arrow.clockwise")
        XCTAssertEqual(IOSSyncButtonPresentation.symbolName(for: .syncing), "xmark")
        XCTAssertEqual(IOSSyncButtonPresentation.symbolName(for: .cancelling), "arrow.clockwise")
        XCTAssertEqual(IOSSyncButtonPresentation.symbolName(for: .success), "checkmark")

        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityLabel(for: .idle), String(localized: "Sync news"))
        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityLabel(for: .syncing), String(localized: "Cancel sync"))
        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityLabel(for: .cancelling), String(localized: "Sync news"))
        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityValue(for: .idle), String(localized: "Ready"))
        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityValue(for: .syncing), String(localized: "Syncing"))
        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityValue(for: .cancelling), String(localized: "Cancelling"))
        XCTAssertEqual(IOSSyncButtonPresentation.accessibilityValue(for: .success), String(localized: "Sync complete"))

        XCTAssertEqual(
            IOSSyncButtonPresentation.resolve(manualSyncState: .running, transientState: .success),
            .syncing
        )
        XCTAssertEqual(
            IOSSyncButtonPresentation.resolve(manualSyncState: .cancelling, transientState: .success),
            .cancelling
        )
        XCTAssertEqual(
            IOSSyncButtonPresentation.resolve(manualSyncState: .idle, transientState: .success),
            .success
        )
    }

    func testSyncButtonSuccessTimeoutCannotOverwriteNewerSync() {
        XCTAssertTrue(IOSSyncButtonPresentation.canEndSuccess(generation: 2, currentGeneration: 2, isSyncing: false))
        XCTAssertFalse(IOSSyncButtonPresentation.canEndSuccess(generation: 1, currentGeneration: 2, isSyncing: false))
        XCTAssertFalse(IOSSyncButtonPresentation.canEndSuccess(generation: 2, currentGeneration: 2, isSyncing: true))
    }

    @MainActor
    func testEmptyStatePresentationUsesSyncLifecycle() {
        let store = NewsreaderStore(defaults: UserDefaults())
        XCTAssertFalse(store.isSyncing)
        store.setManualSyncStateForTesting(.running)
        XCTAssertTrue(store.isSyncing)
        store.setManualSyncStateForTesting(.cancelling)
        XCTAssertTrue(store.isSyncing)
        store.setManualSyncStateForTesting(.idle)
        XCTAssertFalse(store.isSyncing)
    }

    @MainActor
    func testCountOnlyChangeDoesNotInvalidateArticleListDependencies() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let articleListInvalidated = ObservationFlag()

        withObservationTracking {
            _ = store.articles
            _ = store.isLoading
            _ = store.errorMessage
            _ = store.articlePresentationMode
            _ = store.articlePreviewLines
            _ = store.snapshotRevision
            _ = store.scrollResetRevision
            _ = store.markReadOnScrolloverEnabled
            _ = store.scrolloverRearmRevision
            _ = store.hasPendingNewData
            _ = store.hasUnscopedNewDataSignal
        } onChange: {
            MainActor.assumeIsolated { articleListInvalidated.value = true }
        }

        store.setSelectionTotalForTesting(3)

        XCTAssertFalse(articleListInvalidated.value)
    }

    @MainActor
    func testFeedIconCompletionInvalidatesOnlyItsPresentationState() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let icon = store.feedIconPresentationState(for: 10, variant: .normal)
        let otherIcon = store.feedIconPresentationState(for: 20, variant: .normal)
        let otherInvalidated = ObservationFlag()

        withObservationTracking {
            _ = otherIcon.image
        } onChange: {
            MainActor.assumeIsolated { otherInvalidated.value = true }
        }

        icon.image = UIImage()

        XCTAssertFalse(otherInvalidated.value)
    }

    @MainActor
    func testRowReadStateDoesNotInvalidateTheStructuralArticleSnapshot() {
        let store = NewsreaderStore(defaults: UserDefaults())
        store.setArticlesForTesting([.init(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "", imageUrl: nil)])
        let articleListInvalidated = ObservationFlag()

        withObservationTracking {
            _ = store.articles
        } onChange: {
            MainActor.assumeIsolated { articleListInvalidated.value = true }
        }

        let rowState = store.rowPresentationStateForTesting(1)!
        rowState.setRead(true)

        XCTAssertFalse(articleListInvalidated.value)
        XCTAssertTrue(rowState.isRead)
    }

    @MainActor
    func testTimelinePageAppendPreservesExistingRowStateAndAddsOnlyNewIDs() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let first = ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "First", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "", imageUrl: nil)
        let second = ArticleSummary(id: 2, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Second", url: "https://example.com/2", commentsUrl: "", publishedAt: "2026-01-02T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "", imageUrl: nil)
        store.setArticlesForTesting([first])
        store.applyReadMutationForTesting([1], read: true)
        let revision = store.rowPresentationStateForTesting(1)!.mutationRevision

        store.appendArticlesForTesting([first, second])

        XCTAssertEqual(store.articles.map(\.id), [1, 2])
        XCTAssertEqual(store.timelineStructuralItemCountForTesting, 2)
        XCTAssertEqual(store.rowPresentationStateForTesting(1)?.mutationRevision, revision)
        XCTAssertEqual(store.isArticleReadForTesting(1), true)
        XCTAssertNotNil(store.rowPresentationStateForTesting(2))
    }

    @MainActor
    func testTimelineRemovalPreservesUnaffectedRowStateAndPagingCursor() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let first = timelineArticle(id: 1)
        let second = timelineArticle(id: 2)
        let third = timelineArticle(id: 3)
        let cursor = ArticleCursor(publishedAt: "2026-01-01T00:00:00Z", articleId: 3)
        store.setArticlesForTesting([first, second, third])
        store.applyReadMutationForTesting([3], read: true)
        let survivingState = store.rowPresentationStateForTesting(3)!
        let survivingRevision = survivingState.mutationRevision
        store.setTimelinePagingForTesting(cursor: cursor, hasMore: true)

        store.removeVisibleArticlesForTesting([1, 2])

        XCTAssertEqual(store.articles.map(\.id), [3])
        XCTAssertTrue(store.rowPresentationStateForTesting(3) === survivingState)
        XCTAssertEqual(store.rowPresentationStateForTesting(3)?.mutationRevision, survivingRevision)
        XCTAssertNil(store.rowPresentationStateForTesting(1))
        XCTAssertNil(store.rowPresentationStateForTesting(2))
        XCTAssertEqual(store.timelinePagingStateForTesting.cursor, cursor)
        XCTAssertTrue(store.timelinePagingStateForTesting.hasMore)
        if case let .remove(ids) = store.timelineStructuralChangeForTesting {
            XCTAssertEqual(Set(ids), Set([1, 2]))
        } else {
            XCTFail("targeted removal must not publish a full replacement")
        }
    }

    @MainActor
    func testTimelineControllerAppliesTargetedStructuralRemoval() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let first = timelineArticle(id: 1)
        let second = timelineArticle(id: 2)
        let controller = makeTimelineController(articles: [first, second], presentationBridge: bridge, feedIconBridge: bridge)
        let storage = IOSUIKitArticleTimelineStructuralStorage()
        storage.items = [.init(article: second, content: ArticleRowContent(article: second))]

        controller.update(
            structuralState: .init(storage: storage, change: .remove([1]), revision: 2),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )

        XCTAssertEqual(controller.orderedArticleIDsForTesting, [2])
    }

    @MainActor
    func testUIKitPrefetchKeepsLayoutPreparationAndBoundsArticleImagePrefetch() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let articles = (1...8).map {
            timelineArticle(id: Int64($0), imageURL: "https://example.com/image-\($0).jpg")
        }
        let controller = makeTimelineController(
            articles: articles,
            presentationBridge: bridge,
            feedIconBridge: bridge
        )
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        await controller.settleForTesting()

        let initialLayoutPrefetchCount = controller.layoutPrefetchInputCountForTesting
        controller.tableView(
            controller.tableViewForTesting,
            prefetchRowsAt: [
                IndexPath(row: 5, section: 0),
                IndexPath(row: 6, section: 0),
                IndexPath(row: 7, section: 0),
            ]
        )

        XCTAssertEqual(
            controller.layoutPrefetchInputCountForTesting,
            initialLayoutPrefetchCount + 3
        )
        XCTAssertLessThanOrEqual(controller.articleImagePrefetchTaskCountForTesting, 2)
    }

    @MainActor
    func testFeedIconRetryDuringStructuralRemovalDoesNotForceDiffableCellMaterialization() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let articles = (1...30).map { timelineArticle(id: Int64($0)) }
        let controller = makeTimelineController(
            articles: articles,
            presentationBridge: bridge,
            feedIconBridge: bridge
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        await controller.settleForTesting()
        controller.tableViewForTesting.layoutIfNeeded()

        XCTAssertFalse(controller.tableViewForTesting.indexPathsForVisibleRows?.isEmpty ?? true)

        let remaining = Array(articles.dropFirst())
        let storage = IOSUIKitArticleTimelineStructuralStorage()
        storage.items = remaining.map { .init(article: $0, content: ArticleRowContent(article: $0)) }

        // This combination reproduced the TestFlight abort: the structural
        // model has already removed ID 1 while the table can still be
        // presenting the prior diffable snapshot, and the feed-icon revision
        // requests another pass over the visible rows.
        controller.update(
            structuralState: .init(
                storage: storage,
                change: .remove([articles[0].id]),
                revision: 2
            ),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 1,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        await controller.settleForTesting()
        controller.tableViewForTesting.layoutIfNeeded()

        XCTAssertEqual(controller.orderedArticleIDsForTesting, remaining.map(\.id))
        XCTAssertEqual(controller.tableViewForTesting.numberOfRows(inSection: 0), remaining.count)
    }

    @MainActor
    func testIncrementalTimelineChangesDoNotPerformFullReplacementCleanup() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let first = timelineArticle(id: 1)
        let second = timelineArticle(id: 2)
        let third = timelineArticle(id: 3)
        let controller = makeTimelineController(articles: [first, second], presentationBridge: bridge, feedIconBridge: bridge)
        let initialPrefetchCancellations = controller.fullPrefetchCancellationCountForTesting
        let initialLayoutInvalidations = controller.layoutInvalidationCountForTesting
        let initialVisibleReconfigurePasses = controller.visibleCellReconfigurationPassCountForTesting

        let appendedStorage = IOSUIKitArticleTimelineStructuralStorage()
        appendedStorage.items = [first, second, third].map { .init(article: $0, content: ArticleRowContent(article: $0)) }
        controller.update(
            structuralState: .init(storage: appendedStorage, change: .append([.init(article: third, content: ArticleRowContent(article: third))]), revision: 2),
            presentationBridge: bridge, feedIconPresentationBridge: bridge, mode: .visual, previewLines: .standard,
            iconVariant: .normal, feedIconRequestRevision: 0, scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false, showsRefreshControl: false
        )
        XCTAssertEqual(controller.orderedArticleIDsForTesting, [1, 2, 3])
        XCTAssertEqual(controller.fullPrefetchCancellationCountForTesting, initialPrefetchCancellations)
        XCTAssertEqual(controller.layoutInvalidationCountForTesting, initialLayoutInvalidations)
        XCTAssertEqual(controller.visibleCellReconfigurationPassCountForTesting, initialVisibleReconfigurePasses)

        let removedStorage = IOSUIKitArticleTimelineStructuralStorage()
        removedStorage.items = [first, third].map { .init(article: $0, content: ArticleRowContent(article: $0)) }
        controller.update(
            structuralState: .init(storage: removedStorage, change: .remove([2]), revision: 3),
            presentationBridge: bridge, feedIconPresentationBridge: bridge, mode: .visual, previewLines: .standard,
            iconVariant: .normal, feedIconRequestRevision: 0, scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false, showsRefreshControl: false
        )
        XCTAssertEqual(controller.orderedArticleIDsForTesting, [1, 3])
        XCTAssertEqual(controller.fullPrefetchCancellationCountForTesting, initialPrefetchCancellations)
        XCTAssertEqual(controller.layoutInvalidationCountForTesting, initialLayoutInvalidations)
        XCTAssertEqual(controller.visibleCellReconfigurationPassCountForTesting, initialVisibleReconfigurePasses)

        controller.update(
            structuralState: .init(items: [.init(article: first, content: ArticleRowContent(article: first))], revision: 5),
            presentationBridge: bridge, feedIconPresentationBridge: bridge, mode: .visual, previewLines: .standard,
            iconVariant: .normal, feedIconRequestRevision: 0, scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false, showsRefreshControl: false
        )
        XCTAssertEqual(controller.fullPrefetchCancellationCountForTesting, initialPrefetchCancellations + 1)
        XCTAssertEqual(controller.layoutInvalidationCountForTesting, initialLayoutInvalidations + 1)
    }

    @MainActor
    func testStaleTimelinePageCompletionCannotClearNewerRequestOwnership() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let stale = store.beginTimelinePageRequestForTesting()
        store.resetTimelinePagingGenerationForTesting()
        let current = store.beginTimelinePageRequestForTesting()

        XCTAssertFalse(store.completeTimelinePageRequestForTesting(stale))
        XCTAssertTrue(store.timelinePagingStateForTesting.inFlight)
        XCTAssertTrue(store.completeTimelinePageRequestForTesting(current))
        XCTAssertFalse(store.timelinePagingStateForTesting.inFlight)
    }

    @MainActor
    func testRowStatusMutationsDoNotInvalidateImmutableRowContent() {
        let article = ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "https://example.com/comments", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: "https://example.com/image.jpg")
        let rowState = ArticleRowPresentationState(article: article)
        let invalidated = ObservationFlag()

        withObservationTracking {
            _ = rowState.content
        } onChange: {
            MainActor.assumeIsolated { invalidated.value = true }
        }

        rowState.setRead(true)
        rowState.setStarred(true)

        XCTAssertFalse(invalidated.value)
        XCTAssertEqual(rowState.content.article, ArticleRowArticle(article: article))
        XCTAssertEqual(rowState.content.imageURL, URL(string: "https://example.com/image.jpg"))
        XCTAssertTrue(rowState.content.hasComments)
        XCTAssertNotEqual(rowState.content.publishedDate, article.publishedAt)
    }

    @MainActor
    func testReadOnlySnapshotReconciliationKeepsImmutableContent() {
        let original = ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: nil)
        let state = ArticleRowPresentationState(article: original)
        let content = state.content

        state.reconcile(with: ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: true, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: nil))

        XCTAssertEqual(state.content, content)
        XCTAssertTrue(state.isRead)
    }

    @MainActor
    func testStarredOnlySnapshotReconciliationKeepsImmutableContent() {
        let original = ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: nil)
        let state = ArticleRowPresentationState(article: original)
        let content = state.content

        state.reconcile(with: ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: true, readingTimeMinutes: 0, preview: "Preview", imageUrl: nil))

        XCTAssertEqual(state.content, content)
        XCTAssertTrue(state.isStarred)
    }

    @MainActor
    func testImmutableSnapshotReconciliationUpdatesContent() {
        let original = ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Article", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: nil)
        let state = ArticleRowPresentationState(article: original)

        state.reconcile(with: ArticleSummary(id: 1, feedId: 10, categoryId: 20, feedTitle: "Feed", title: "Updated", url: "https://example.com/1", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: nil))

        XCTAssertEqual(state.content.article.title, "Updated")
    }





    @MainActor
    func testTargetedReadAndStarredDeltasDoNotReconcileStructuralTimelineInput() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let structuralCount = controller.structuralReconciliationCount
        let snapshotCount = controller.structuralSnapshotApplicationCount

        bridge.publishArticle(.init(articleID: 1, state: .init(isRead: true, isStarred: false, revision: 1), rearmScrollover: false))
        bridge.publishArticle(.init(articleID: 1, state: .init(isRead: true, isStarred: true, revision: 2), rearmScrollover: false))

        XCTAssertEqual(controller.structuralReconciliationCount, structuralCount)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, snapshotCount)
        XCTAssertEqual(controller.articlePresentationApplicationCount, 2)
    }

    @MainActor
    func testFeedIconDeltaDoesNotApplyStructuralSnapshot() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let structuralCount = controller.structuralReconciliationCount
        let snapshotCount = controller.structuralSnapshotApplicationCount

        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: UIImage(), revision: 1))

        XCTAssertEqual(controller.structuralReconciliationCount, structuralCount)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, snapshotCount)
        XCTAssertEqual(controller.feedIconPresentationApplicationCount, 1)
    }

    @MainActor
    func testSharedFeedIconBridgeDeliversToTimelineAndSearchWithoutStealingUpdates() {
        let sharedIconBridge = IOSUIKitArticleTimelinePresentationBridge()
        let timeline = makeTimelineController(presentationBridge: sharedIconBridge, feedIconBridge: sharedIconBridge)
        let searchArticleBridge = IOSUIKitArticleTimelinePresentationBridge()
        let search = makeTimelineController(presentationBridge: searchArticleBridge, feedIconBridge: sharedIconBridge)

        sharedIconBridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: UIImage(), revision: 1))

        XCTAssertEqual(timeline.feedIconPresentationApplicationCount, 1)
        XCTAssertEqual(search.feedIconPresentationApplicationCount, 1)

        search.detachPresentationBridges()
        sharedIconBridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: UIImage(), revision: 2))

        XCTAssertEqual(timeline.feedIconPresentationApplicationCount, 2)
        XCTAssertEqual(search.feedIconPresentationApplicationCount, 1)
    }

    @MainActor
    func testArticleStatusAndSharedFeedIconChannelsRemainIsolated() {
        let sharedIconBridge = IOSUIKitArticleTimelinePresentationBridge()
        let timeline = makeTimelineController(presentationBridge: sharedIconBridge, feedIconBridge: sharedIconBridge)
        let searchArticleBridge = IOSUIKitArticleTimelinePresentationBridge()
        let search = makeTimelineController(presentationBridge: searchArticleBridge, feedIconBridge: sharedIconBridge)

        sharedIconBridge.publishArticle(.init(articleID: 1, state: .init(isRead: true, isStarred: false, revision: 1), rearmScrollover: false))
        searchArticleBridge.publishArticle(.init(articleID: 1, state: .init(isRead: false, isStarred: true, revision: 1), rearmScrollover: false))

        XCTAssertEqual(timeline.articlePresentationApplicationCount, 1)
        XCTAssertEqual(search.articlePresentationApplicationCount, 1)
        XCTAssertEqual(sharedIconBridge.articleState(for: 1, fallback: timelineArticle(id: 1)).isRead, true)
        XCTAssertEqual(searchArticleBridge.articleState(for: 1, fallback: timelineArticle(id: 1)).isStarred, true)
    }

    @MainActor
    func testRepeatedBridgeUpdatesDoNotDuplicatePresentationDelivery() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let structuralState = timelineStructuralState([timelineArticle(id: 1), timelineArticle(id: 2)], revision: 1)

        for _ in 0..<4 {
            controller.update(
                structuralState: structuralState,
                presentationBridge: bridge,
                feedIconPresentationBridge: bridge,
                mode: .visual,
                previewLines: .standard,
                iconVariant: .normal,
                feedIconRequestRevision: 0,
                scrollResetRevision: 0,
                markReadOnScrolloverEnabled: false,
                showsRefreshControl: false
            )
        }
        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: UIImage(), revision: 1))

        XCTAssertEqual(controller.feedIconPresentationApplicationCount, 1)
    }

    @MainActor
    func testPreparedCellReconcilesRetainedIconWithoutStructuralOrSizingWork() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let cell = makeUIKitArticleCell(mode: .visual, width: 390)
        let height = measureUIKitArticleCell(cell, width: 390)
        let solveCount = cell.measurementSolveCount
        let variant = cell.layoutVariantForTesting
        let variantRevision = cell.layoutVariantRevision
        let structuralCount = controller.structuralReconciliationCount
        let snapshotCount = controller.structuralSnapshotApplicationCount

        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 30, height: 30), revision: 1))
        XCTAssertNil(cell.feedIconImageForTesting)

        controller.reconcilePresentationForDisplay(cell)
        cell.layoutIfNeeded()

        XCTAssertNotNil(cell.feedIconImageForTesting)
        XCTAssertEqual(cell.bounds.height, height, accuracy: 0.5)
        XCTAssertEqual(cell.measurementSolveCount, solveCount)
        XCTAssertEqual(cell.layoutVariantForTesting, variant)
        XCTAssertEqual(cell.layoutVariantRevision, variantRevision)
        XCTAssertEqual(controller.structuralReconciliationCount, structuralCount)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, snapshotCount)
    }

    @MainActor
    func testCachedAndStaleFeedIconBindingsReconcileOnlyTheCurrentFeed() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let articles = [timelineArticle(id: 1, feedID: 10), timelineArticle(id: 2, feedID: 20)]
        let controller = makeTimelineController(articles: articles, presentationBridge: bridge, feedIconBridge: bridge)
        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 30, height: 30), revision: 1))

        let reboundCell = makeUIKitArticleCell(mode: .visual, width: 390, articleID: 2, feedID: 20)
        controller.reconcilePresentationForDisplay(reboundCell)
        XCTAssertNil(reboundCell.feedIconImageForTesting)

        bridge.publishFeedIcon(.init(key: .init(feedID: 20, variant: .normal), image: testImage(width: 30, height: 30), revision: 1))
        controller.reconcilePresentationForDisplay(reboundCell)
        XCTAssertNotNil(reboundCell.feedIconImageForTesting)

        let cachedCell = makeUIKitArticleCell(mode: .visual, width: 390, articleID: 1, feedID: 10)
        controller.reconcilePresentationForDisplay(cachedCell)
        XCTAssertNotNil(cachedCell.feedIconImageForTesting)
    }

    @MainActor
    func testOneFeedIconDeltaUpdatesAllRelevantBoundCellsOnly() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let articles = [timelineArticle(id: 1, feedID: 10), timelineArticle(id: 2, feedID: 10), timelineArticle(id: 3, feedID: 20)]
        let controller = makeTimelineController(articles: articles, presentationBridge: bridge, feedIconBridge: bridge)
        let first = makeUIKitArticleCell(mode: .visual, width: 390, articleID: 1, feedID: 10)
        let second = makeUIKitArticleCell(mode: .visual, width: 390, articleID: 2, feedID: 10)
        let unrelated = makeUIKitArticleCell(mode: .visual, width: 390, articleID: 3, feedID: 20)

        controller.applyFeedIconPresentation(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 30, height: 30), revision: 1), to: [first, second, unrelated])

        XCTAssertNotNil(first.feedIconImageForTesting)
        XCTAssertNotNil(second.feedIconImageForTesting)
        XCTAssertNil(unrelated.feedIconImageForTesting)
    }

    @MainActor
    func testFeedIconTransientFailureRetriesAfterCooldownAndSuccessfulNilDoesNotRetry() async throws {
        let retryLoader = FeedIconLoader(results: [.failure(URLError(.notConnectedToInternet)), .success(try imageData(width: 40, height: 40))])
        let store = NewsreaderStore(defaults: UserDefaults())
        store.setFeedIconLoaderForTesting { _, _ in try retryLoader.load() }
        let retryState = store.feedIconPresentationState(for: 10, variant: .normal)

        store.requestFeedIcon(10, variant: .normal, now: 0)
        await waitForFeedIconState(retryState, matching: .retryableFailure(retryAfter: 30))
        XCTAssertEqual(retryLoader.callCount, 1)

        store.requestFeedIcon(10, variant: .normal, now: 1)
        await Task.yield()
        XCTAssertEqual(retryLoader.callCount, 1)

        store.requestFeedIcon(10, variant: .normal, now: 30)
        await waitForFeedIconState(retryState, matching: .available)
        XCTAssertNotNil(retryState.image)
        XCTAssertEqual(retryLoader.callCount, 2)

        let unavailableLoader = FeedIconLoader(results: [.success(nil)])
        let unavailableStore = NewsreaderStore(defaults: UserDefaults())
        unavailableStore.setFeedIconLoaderForTesting { _, _ in try unavailableLoader.load() }
        let unavailableState = unavailableStore.feedIconPresentationState(for: 20, variant: .normal)
        unavailableStore.requestFeedIcon(20, variant: .normal, now: 0)
        await waitForFeedIconState(unavailableState, matching: .unavailable)
        unavailableStore.requestFeedIcon(20, variant: .normal, now: 1_000)
        await Task.yield()

        XCTAssertEqual(unavailableLoader.callCount, 1)
        XCTAssertEqual(unavailableState.loadState, .unavailable)

        let decodeFailureLoader = FeedIconLoader(results: [.success(Data("not an image".utf8))])
        let decodeFailureStore = NewsreaderStore(defaults: UserDefaults())
        decodeFailureStore.setFeedIconLoaderForTesting { _, _ in try decodeFailureLoader.load() }
        let decodeFailureState = decodeFailureStore.feedIconPresentationState(for: 30, variant: .normal)
        decodeFailureStore.requestFeedIcon(30, variant: .normal, now: 0)
        await waitForFeedIconState(decodeFailureState, matching: .retryableFailure(retryAfter: 30))
        XCTAssertEqual(decodeFailureLoader.callCount, 1)
    }

    @MainActor
    func testNavigationRefreshMakesNegativeFeedIconResultRequestableAgain() async throws {
        let loader = FeedIconLoader(results: [.success(nil), .success(try imageData(width: 40, height: 40))])
        let store = NewsreaderStore(defaults: UserDefaults())
        store.setFeedIconLoaderForTesting { _, _ in try loader.load() }

        let unavailable = store.feedIconPresentationState(for: 10, variant: .normal)
        store.requestFeedIcon(10, variant: .normal, now: 0)
        await waitForFeedIconState(unavailable, matching: .unavailable)
        XCTAssertEqual(loader.callCount, 1)

        store.invalidateFeedIconAvailabilityForTesting()
        let refreshed = store.feedIconPresentationState(for: 10, variant: .normal)
        XCTAssertFalse(refreshed === unavailable)
        store.requestFeedIcon(10, variant: .normal, now: 1)
        await waitForFeedIconState(refreshed, matching: .available)

        XCTAssertNotNil(refreshed.image)
        XCTAssertEqual(loader.callCount, 2)
    }

    @MainActor
    func testFeedIconDetachLetsSameKeyRequestAgainAndRejectsOldSessionCompletion() async throws {
        let oldLoader = FeedIconLoadGate(result: .success(nil))
        let newData = try imageData(width: 40, height: 40)
        let newLoader = FeedIconLoadGate(result: .success(newData))
        let store = NewsreaderStore(defaults: UserDefaults())
        store.setFeedIconLoaderForTesting { _, _ in try oldLoader.load() }

        let oldState = store.feedIconPresentationState(for: 10, variant: .normal)
        store.requestFeedIcon(10, variant: .normal, now: 0)
        await oldLoader.waitUntilStarted()

        store.detach()
        store.setFeedIconLoaderForTesting { _, _ in try newLoader.load() }
        let newState = store.feedIconPresentationState(for: 10, variant: .normal)
        store.requestFeedIcon(10, variant: .normal, now: 1)
        await newLoader.waitUntilStarted()
        newLoader.release()
        await newState.waitForLoadStateForTesting(.available)

        oldLoader.release()
        await oldLoader.waitUntilReturned()
        for _ in 0..<100 { await Task.yield() }

        XCTAssertEqual(oldState.loadState, .loading)
        XCTAssertEqual(newState.loadState, .available)
        XCTAssertNotNil(store.timelinePresentationBridge.feedIcon(for: 10, variant: .normal))
    }

    @MainActor
    func testFeedIconBridgeResetRemovesCachedIconsAndPreservesArticlePresentation() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let article = timelineArticle(id: 1)
        bridge.replaceArticleStates([1: .init(isRead: true, isStarred: true, revision: 4)])
        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 30, height: 30), revision: 1))

        bridge.resetFeedIcons()

        XCTAssertNil(bridge.feedIcon(for: 10, variant: .normal))
        XCTAssertEqual(bridge.articleState(for: 1, fallback: article), .init(isRead: true, isStarred: true, revision: 4))
    }

    @MainActor
    func testFeedIconBridgeResetClearsSubscribedControllerCellsWithoutSnapshotWork() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let cell = makeUIKitArticleCell(mode: .visual, width: 390, articleID: 1, feedID: 10)
        let structuralCount = controller.structuralSnapshotApplicationCount

        controller.applyFeedIconPresentation(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 30, height: 30), revision: 1), to: [cell])
        XCTAssertNotNil(cell.feedIconImageForTesting)

        bridge.resetFeedIcons()
        XCTAssertEqual(controller.feedIconPresentationApplicationCount, 1)
        controller.clearFeedIconPresentation(to: [cell])

        XCTAssertNil(cell.feedIconImageForTesting)
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, structuralCount)
    }

    @MainActor
    func testFeedIconBridgePublishesNormallyAfterReset() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)

        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 20, height: 20), revision: 1))
        bridge.resetFeedIcons()
        bridge.publishFeedIcon(.init(key: .init(feedID: 10, variant: .normal), image: testImage(width: 30, height: 30), revision: 1))

        XCTAssertNotNil(bridge.feedIcon(for: 10, variant: .normal))
        XCTAssertEqual(controller.feedIconPresentationApplicationCount, 3)
    }

    @MainActor
    func testExplicitUnreadDeltaRearmsOnlyTargetedScrolloverArticle() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)

        bridge.publishArticle(.init(articleID: 1, state: .init(isRead: false, isStarred: false, revision: 1), rearmScrollover: true))

        XCTAssertEqual(controller.scrolloverRearmCount, 1)
        XCTAssertEqual(controller.structuralReconciliationCount, 1)
    }

    @MainActor
    func testBridgeRejectsStalePresentationAndRetainsLatestOffscreenState() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let article = timelineArticle(id: 1)
        bridge.publishArticle(.init(articleID: 1, state: .init(isRead: true, isStarred: true, revision: 2), rearmScrollover: false))
        bridge.publishArticle(.init(articleID: 1, state: .init(isRead: false, isStarred: false, revision: 1), rearmScrollover: true))

        XCTAssertEqual(bridge.articleState(for: 1, fallback: article), .init(isRead: true, isStarred: true, revision: 2))
    }

    @MainActor
    func testNewerStructuralStateSupersedesPendingSnapshotPublication() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(
            articles: [timelineArticle(id: 1), timelineArticle(id: 2), timelineArticle(id: 3)],
            presentationBridge: bridge,
            feedIconBridge: bridge
        )
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        await controller.settleForTesting()

        controller.update(
            structuralState: timelineStructuralState([timelineArticle(id: 1), timelineArticle(id: 2), timelineArticle(id: 3), timelineArticle(id: 4)], revision: 2),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        controller.update(
            structuralState: timelineStructuralState([timelineArticle(id: 1), timelineArticle(id: 2)], revision: 3),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )

        await controller.settleForTesting()

        XCTAssertEqual(controller.orderedArticleIDsForTesting, [1, 2])
        XCTAssertEqual(controller.tableViewForTesting.numberOfRows(inSection: 0), 2)
    }

    @MainActor
    func testStructuralOrderChangeAppliesAnotherSnapshot() {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        let firstSnapshots = controller.structuralSnapshotApplicationCount
        let articles = [timelineArticle(id: 2), timelineArticle(id: 1)]
        controller.update(
            structuralState: timelineStructuralState(articles, revision: 2),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        XCTAssertEqual(controller.structuralSnapshotApplicationCount, firstSnapshots + 1)
    }

    @MainActor
    private func makeTimelineController(bridge: IOSUIKitArticleTimelinePresentationBridge) -> IOSUIKitArticleTimelineController {
        makeTimelineController(presentationBridge: bridge, feedIconBridge: bridge)
    }

    @MainActor
    private func makeTimelineController(
        articles: [ArticleSummary]? = nil,
        presentationBridge: IOSUIKitArticleTimelinePresentationBridge,
        feedIconBridge: IOSUIKitArticleTimelinePresentationBridge
    ) -> IOSUIKitArticleTimelineController {
        let articles = articles ?? [timelineArticle(id: 1), timelineArticle(id: 2)]
        let controller = IOSUIKitArticleTimelineController()
        presentationBridge.replaceArticleStates(Dictionary(uniqueKeysWithValues: articles.map { ($0.id, .init(isRead: $0.isRead, isStarred: $0.isStarred, revision: 0)) }))
        controller.update(
            structuralState: timelineStructuralState(articles, revision: 1),
            presentationBridge: presentationBridge,
            feedIconPresentationBridge: feedIconBridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        return controller
    }

    private func timelineStructuralState(_ articles: [ArticleSummary], revision: UInt64) -> IOSUIKitArticleTimelineStructuralState {
        .init(items: articles.map { .init(article: $0, content: ArticleRowContent(article: $0)) }, revision: revision)
    }

    private func timelineArticle(id: Int64, feedID: Int64 = 10, imageURL: String? = nil) -> ArticleSummary {
        .init(id: id, feedId: feedID, categoryId: 20, feedTitle: "Feed \(feedID)", title: "Article \(id)", url: "https://example.com/\(id)", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "Preview", imageUrl: imageURL)
    }



    func testNewsNavigationSelectionMatchesOnlyTheActiveScope() {
        XCTAssertTrue(NewsNavigationSelection.isSelected(.all, activeScope: .all))
        XCTAssertTrue(NewsNavigationSelection.isSelected(.starred, activeScope: .starred))
        XCTAssertTrue(NewsNavigationSelection.isSelected(.category(1), activeScope: .category(1)))
        XCTAssertTrue(NewsNavigationSelection.isSelected(.feed(10), activeScope: .feed(10)))
        XCTAssertFalse(NewsNavigationSelection.isSelected(.category(1), activeScope: .feed(10)))
        XCTAssertFalse(NewsNavigationSelection.isSelected(.feed(11), activeScope: .feed(10)))
    }

    func testCategoryPresentationDistinguishesDirectSelectionAndSelectedFeedContext() {
        let catalog = NavigationCatalog(
            categories: [.init(id: 1, title: "Technology"), .init(id: 2, title: "World")],
            feeds: [.init(id: 10, categoryId: 1, title: "Ars"), .init(id: 11, categoryId: 2, title: "BBC")]
        )

        XCTAssertEqual(NewsNavigationSelection.categoryPresentation(categoryID: 1, activeScope: .category(1), catalog: catalog), .directlySelected)
        XCTAssertEqual(NewsNavigationSelection.categoryPresentation(categoryID: 1, activeScope: .feed(10), catalog: catalog), .containsSelectedFeed)
        XCTAssertEqual(NewsNavigationSelection.categoryPresentation(categoryID: 2, activeScope: .feed(10), catalog: catalog), .unselected)
        XCTAssertEqual(NewsNavigationSelection.categoryPresentation(categoryID: 1, activeScope: .all, catalog: catalog), .unselected)
        XCTAssertEqual(NewsNavigationSelection.categoryPresentation(categoryID: 1, activeScope: .starred, catalog: catalog), .unselected)
        XCTAssertTrue(NewsNavigationSelection.isSelected(.feed(10), activeScope: .feed(10)))
    }

    func testNavigationExpansionEnsuresTheSelectedFeedParentWithoutDiscardingManualExpansion() {
        let catalog = NavigationCatalog(
            categories: [.init(id: 1, title: "Technology"), .init(id: 2, title: "World")],
            feeds: [.init(id: 10, categoryId: 1, title: "Ars"), .init(id: 11, categoryId: 2, title: "BBC")]
        )
        var expansion = NewsNavigationExpansionState()

        expansion.setExpanded(true, categoryID: 1)
        expansion.ensureSelectedFeedIsExpanded(scope: .feed(11), catalog: catalog)

        XCTAssertTrue(expansion.isExpanded(1))
        XCTAssertTrue(expansion.isExpanded(2))
    }

    func testNavigationExpansionIgnoresNonFeedScopesAndExpandsNewActiveFeed() {
        let catalog = NavigationCatalog(
            categories: [.init(id: 1, title: "Technology"), .init(id: 2, title: "World")],
            feeds: [.init(id: 10, categoryId: 1, title: "Ars"), .init(id: 11, categoryId: 2, title: "BBC")]
        )
        var expansion = NewsNavigationExpansionState()

        expansion.ensureSelectedFeedIsExpanded(scope: .category(1), catalog: catalog)
        expansion.ensureSelectedFeedIsExpanded(scope: .all, catalog: catalog)
        expansion.ensureSelectedFeedIsExpanded(scope: .starred, catalog: catalog)
        XCTAssertFalse(expansion.isExpanded(1))
        XCTAssertFalse(expansion.isExpanded(2))

        expansion.ensureSelectedFeedIsExpanded(scope: .feed(10), catalog: catalog)
        XCTAssertTrue(expansion.isExpanded(1))
        XCTAssertFalse(expansion.isExpanded(2))
    }

    func testFeedIconAppearanceUsesCoreVariants() {
        XCTAssertEqual(IOSFeedIconPresentation.variant(isDark: false), .normal)
        XCTAssertEqual(IOSFeedIconPresentation.variant(isDark: true), .dark)
        XCTAssertNotEqual(IOSFeedIconKey(feedID: 1, variant: .normal), IOSFeedIconKey(feedID: 1, variant: .dark))
    }

    func testFeedCreationPoliciesValidateURLsAndTrimCategories() {
        XCTAssertEqual(IOSFeedCreationPolicy.validURL(" https://example.com/feed "), "https://example.com/feed")
        XCTAssertNil(IOSFeedCreationPolicy.validURL("not a url"))
        XCTAssertEqual(IOSFeedCreationPolicy.categoryTitle("  Technology  "), "Technology")
        XCTAssertNil(IOSFeedCreationPolicy.categoryTitle(" \n "))
    }

    func testSingleAndMultipleDiscoveryOutcomesRemainDistinct() {
        let item = DiscoveredSubscription(url: "https://example.com/feed", title: "Feed", feedType: "rss")
        XCTAssertEqual(IOSAddFeedDiscoveryOutcome.from([]), .none)
        XCTAssertEqual(IOSAddFeedDiscoveryOutcome.from([item]), .automatic(item))
        XCTAssertEqual(IOSAddFeedDiscoveryOutcome.from([item, item]), .choose)
    }

    func testTechnicalChapterTitlesUseGeneratedPresentationNames() {
        XCTAssertTrue(MediaChapterPresentation.usesGeneratedTitle("cp 1"))
        XCTAssertTrue(MediaChapterPresentation.usesGeneratedTitle("CP2"))
        XCTAssertTrue(MediaChapterPresentation.usesGeneratedTitle("chapter 3"))
        XCTAssertTrue(MediaChapterPresentation.usesGeneratedTitle(""))
        XCTAssertFalse(MediaChapterPresentation.usesGeneratedTitle("Introduction"))
        XCTAssertFalse(MediaChapterPresentation.usesGeneratedTitle("Chapter One"))
    }

    func testArticleAudioIndicatorRequiresAudioEnclosure() {
        let audio = Enclosure(
            id: 1,
            articleId: 10,
            url: "https://example.test/audio.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )
        let other = Enclosure(
            id: 2,
            articleId: 10,
            url: "https://example.test/file.bin",
            mimeType: "application/octet-stream",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .other
        )

        XCTAssertTrue(
            IOSArticleAudioPresentation.hasAudio(
                IOSArticleAudioActionState(
                    articleID: 10,
                    enclosures: [audio],
                    isInListeningList: false,
                    downloads: [:]
                )
            )
        )
        XCTAssertFalse(
            IOSArticleAudioPresentation.hasAudio(
                IOSArticleAudioActionState(
                    articleID: 10,
                    enclosures: [other],
                    isInListeningList: false,
                    downloads: [:]
                )
            )
        )
        XCTAssertFalse(IOSArticleAudioPresentation.hasAudio(nil))
    }

    func testArticlePresentationModesAreStableAndVisualIsFirst() {
        XCTAssertEqual(ArticlePresentationMode.allCases, [.visual, .visualCompact, .compact])
        // The raw values persist in UserDefaults and sync through the core, so
        // they are part of the contract, not an implementation detail.
        XCTAssertEqual(ArticlePresentationMode(rawValue: "visual"), .visual)
        XCTAssertEqual(ArticlePresentationMode(rawValue: "visualCompact"), .visualCompact)
        XCTAssertEqual(ArticlePresentationMode(rawValue: "compact"), .compact)
        // Only the text-only mode drops the image.
        XCTAssertEqual(ArticlePresentationMode.allCases.filter(\.showsArticleImage), [.visual, .visualCompact])
    }

    func testUIKitTimelineUsesStructuralSnapshotsOnlyForMembershipOrOrderChanges() {
        XCTAssertFalse(IOSUIKitTimelineSnapshotPolicy.requiresStructuralUpdate(previousIDs: [1, 2, 3], newIDs: [1, 2, 3]))
        XCTAssertTrue(IOSUIKitTimelineSnapshotPolicy.requiresStructuralUpdate(previousIDs: [1, 2, 3], newIDs: [1, 3, 2]))
        XCTAssertTrue(IOSUIKitTimelineSnapshotPolicy.requiresStructuralUpdate(previousIDs: [1, 2, 3], newIDs: [1, 2]))
    }

    @MainActor
    func testManualSyncWithoutAttachedCoreIsIgnoredAndPreservesScope() async {
        let store = NewsreaderStore(defaults: UserDefaults())
        store.scope = .starred

        await store.syncManually()

        XCTAssertEqual(store.scope, .starred)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    func testArticlePresentationLayoutKeepsSemanticModeIndependentOfGeometry() {
        XCTAssertTrue(ArticlePresentationLayout.usesLandscapeVisual(mode: .visual, availableWidth: 720))
        XCTAssertFalse(ArticlePresentationLayout.usesLandscapeVisual(mode: .visual, availableWidth: 390))
        XCTAssertFalse(ArticlePresentationLayout.usesLandscapeVisual(mode: .compact, availableWidth: 720))
        XCTAssertEqual(ArticlePresentationLayout.internalUnreadIndicatorOpacity(isRead: false), 1)
        XCTAssertEqual(ArticlePresentationLayout.internalUnreadIndicatorOpacity(isRead: true), 0)
        XCTAssertTrue(ArticlePresentationMode.visual.showsArticleImage)
        XCTAssertFalse(ArticlePresentationMode.compact.showsArticleImage)
    }

    func testDifferentRasterScalesCannotAliasInTheMemoryCache() async throws {
        let data = try imageData(width: 2_400, height: 1_200)
        let counter = ImageLoadCounter(data: data)
        let pipeline = ArticleImagePipeline { _ in await counter.load() }
        let targetSize = IOSUIKitArticleGeometry(mode: .visual, containerWidth: 393).imageSize(hasImage: true)
        let twoX = ArticleImageRequest(
            url: URL(string: "https://example.com/image.jpg")!, targetSize: targetSize, displayScale: 3,
            rasterScale: 2
        )
        let threeX = ArticleImageRequest(
            url: twoX.url, targetSize: targetSize, displayScale: 3,
        )

        let image = try await pipeline.prefetch(twoX)
        // The decoded image keeps source aspect ratio and only guarantees enough
        // pixels to cover the requested slot with UIImageView aspect-fill.
        XCTAssertGreaterThanOrEqual(image.width, Int(twoX.targetPixelSize.width))
        XCTAssertGreaterThanOrEqual(image.height, Int(twoX.targetPixelSize.height))
        XCTAssertNotEqual(twoX, threeX)
        XCTAssertNil(pipeline.cachedImage(for: threeX))
        XCTAssertNotNil(pipeline.cachedImage(for: twoX))
        let calls = await counter.callCount()
        let metrics = await pipeline.metrics()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(metrics.memoryCacheInsertions, 1)
    }

    @MainActor
    func testCachedProductionRasterIsPresentedImmediatelyAtPhysicalDisplayScale() async throws {
        let data = try imageData(width: 1_600, height: 800)
        let counter = ImageLoadCounter(data: data)
        let pipeline = ArticleImagePipeline { _ in await counter.load() }
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: false)
        let geometry = IOSUIKitArticleGeometry(mode: .visual, containerWidth: 390)
        let request = ArticleImageRequest(
            url: try XCTUnwrap(item.content.imageURL),
            targetSize: geometry.imageSize(hasImage: true),
            displayScale: 3,
            rasterScale: 2
        )
        let cached = try await pipeline.prefetch(request)
        let cell = configuredArticleImageTestCell(item: item, pipeline: pipeline, rasterScale: 2)

        XCTAssertTrue(cell.articleImageForTesting?.cgImage === cached)
        XCTAssertEqual(cell.articleImageForTesting?.scale, 3)
        XCTAssertGreaterThanOrEqual(cached.width, Int(request.targetPixelSize.width))
        XCTAssertGreaterThanOrEqual(cached.height, Int(request.targetPixelSize.height))
        XCTAssertEqual(ArticleImagePipeline.memoryCost(of: cached), cached.width * cached.height * 4)
        let presentation = cell.articleImagePresentationForTesting
        XCTAssertTrue(presentation.placeholderHidden)
        XCTAssertEqual(presentation.contentMode, .scaleAspectFill)
        XCTAssertTrue(presentation.clipsToBounds)
        XCTAssertEqual(presentation.cornerRadius, IOSUIKitArticleGeometry.articleImageCornerRadius)
        let calls = await counter.callCount()
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testRasterScaleSeamKeepsArticleImageAndLayoutPrefetchActive() {
        // The diagnostic changes the request's raster scale, not the Standard
        // article-image prefetch policy or its two-image forward window.
        XCTAssertEqual(
            IOSArticleImagePrefetchPolicy.candidateIDs(
                orderedIDs: [1, 2, 3], visibleIDs: [1], imageIDs: [2, 3], direction: .forward
            ),
            [2, 3]
        )
        let request = ArticleImageRequest(
            url: URL(string: "https://example.com/image.jpg")!, targetSize: .init(width: 361, height: 203), displayScale: 3,
            rasterScale: 2
        )
        XCTAssertEqual(request.rasterScale, 2)
    }

    @MainActor
    func testRasterScaleSeamAssignsAsyncImageAndNormalReuseClearsIt() async throws {
        let gate = ImageLoadGate(data: try imageData(width: 800, height: 400))
        let pipeline = ArticleImagePipeline { _ in try await gate.load() }
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: false)
        let cell = configuredArticleImageTestCell(item: item, pipeline: pipeline, rasterScale: 2)
        await gate.waitUntilSuspended()
        await gate.release()
        await waitForArticleImagePresentation { cell.articleImageForTesting != nil }

        XCTAssertNotNil(cell.articleImageForTesting)
        XCTAssertEqual(
            cell.articleImagePresentationForTesting.cornerRadius,
            IOSUIKitArticleGeometry.articleImageCornerRadius
        )
        cell.prepareForReuse()
        XCTAssertNil(cell.articleImageForTesting)
        XCTAssertFalse(cell.articleImagePresentationForTesting.placeholderHidden)
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testCompactArticleCellsRemainWithoutArticleImageWork() async throws {
        let gate = ImageLoadGate(data: try imageData(width: 800, height: 400))
        let pipeline = ArticleImagePipeline { _ in try await gate.load() }
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: false)
        let cell = configuredArticleImageTestCell(item: item, pipeline: pipeline, mode: .compact, rasterScale: 2)

        await Task.yield()
        XCTAssertEqual(cell.layoutVariantForTesting, .compact)
        XCTAssertTrue(cell.articleImageSlotIsHiddenForTesting)
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testRasterScaleSeamPreservesStandardImageSlotGeometry() {
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: true)
        let cell = configuredOracleCell(item: item, mode: .visual, previewLines: .standard, width: 390, rasterScale: 2)
        let input = IOSUIKitArticleLayoutInput(item: item, mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: cell.traitCollection.displayScale, contentSizeCategory: .large, layoutDirection: .leftToRight)
        let expected = IOSUIKitArticleLayoutEngine.metrics(for: input)

        XCTAssertEqual(cell.layoutVariantForTesting, .visualPortrait)
        XCTAssertEqual(measureUIKitArticleCell(cell, width: 390), expected.cellSize.height, accuracy: 0.5)
        guard let expectedImageFrame = expected.imageFrame else {
            return XCTFail("Standard visual geometry must retain its image slot")
        }
        assertFrameEqual(cell.articleImageSlotFrameForTesting, expectedImageFrame)
        XCTAssertFalse(cell.articleImageSlotIsHiddenForTesting)
    }

    func testArticlePresentationLayoutUsesBoundedDeterministicImageSlots() {
        let availableWidth: CGFloat = 390
        let contentWidth = ArticlePresentationLayout.articleContentWidth(availableWidth)

        XCTAssertEqual(ArticlePresentationLayout.boundedArticleWidth(availableWidth), availableWidth)
        XCTAssertEqual(contentWidth, 366)
        XCTAssertEqual(ArticlePresentationLayout.visualPortraitContentWidth(availableWidth), availableWidth)
        XCTAssertEqual(ArticlePresentationLayout.portraitImageHeight(contentWidth: contentWidth), 205.875, accuracy: 0.01)
        let landscapeImageWidth = ArticlePresentationLayout.landscapeImageWidth(availableWidth: availableWidth)
        let landscapeTextWidth = ArticlePresentationLayout.landscapeTextWidth(availableWidth: availableWidth, imageWidth: landscapeImageWidth, interColumnSpacing: 14)
        XCTAssertEqual(landscapeImageWidth, 175.68, accuracy: 0.01)
        XCTAssertEqual(landscapeTextWidth, 176.32, accuracy: 0.01)
        XCTAssertEqual(ArticlePresentationLayout.landscapeImageHeight(imageWidth: landscapeImageWidth), 98.82, accuracy: 0.01)
        XCTAssertLessThanOrEqual(landscapeImageWidth + landscapeTextWidth + 14, contentWidth)
        XCTAssertEqual(ArticlePresentationLayout.boundedArticleWidth(availableWidth + 100), availableWidth + 100)
        XCTAssertEqual(ArticlePresentationLayout.boundedArticleWidth(-1), 0)
    }

    @MainActor
    func testUIKitPortraitArticleImagePixelsDoNotChangeMeasuredGeometry() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 390)
        let baseline = measureUIKitArticleCell(cell, width: 390)
        let baselineSlot = cell.articleImageSlotFrameForTesting
        let baselineVariant = cell.layoutVariantForTesting
        let baselineVariantRevision = cell.layoutVariantRevision

        for image in [testImage(width: 400, height: 400), testImage(width: 200, height: 800), testImage(width: 1200, height: 200)] {
            cell.applyArticleImagePixelsForTesting(image)
            let height = measureUIKitArticleCell(cell, width: 390)

            XCTAssertEqual(height, baseline, accuracy: 0.5)
            XCTAssertEqual(cell.articleImageSlotFrameForTesting.width, baselineSlot.width, accuracy: 0.5)
            XCTAssertEqual(cell.articleImageSlotFrameForTesting.height, baselineSlot.height, accuracy: 0.5)
            XCTAssertEqual(cell.layoutVariantForTesting, baselineVariant)
            XCTAssertEqual(cell.layoutVariantRevision, baselineVariantRevision)
        }
    }

    @MainActor
    func testUIKitArticleImageArrivalBeforeAndAfterMeasurementHasIdenticalGeometry() {
        let before = makeUIKitArticleCell(mode: .visual, width: 390)
        before.applyArticleImagePixelsForTesting(testImage(width: 200, height: 800))
        let beforeHeight = measureUIKitArticleCell(before, width: 390)
        let beforeSlot = before.articleImageSlotFrameForTesting
        let beforeVariantRevision = before.layoutVariantRevision

        let after = makeUIKitArticleCell(mode: .visual, width: 390)
        let afterHeight = measureUIKitArticleCell(after, width: 390)
        after.applyArticleImagePixelsForTesting(testImage(width: 1200, height: 200))
        let afterImageHeight = measureUIKitArticleCell(after, width: 390)

        XCTAssertEqual(beforeHeight, afterHeight, accuracy: 0.5)
        XCTAssertEqual(beforeHeight, afterImageHeight, accuracy: 0.5)
        XCTAssertEqual(before.articleImageSlotFrameForTesting.width, beforeSlot.width, accuracy: 0.5)
        XCTAssertEqual(after.articleImageSlotFrameForTesting.width, beforeSlot.width, accuracy: 0.5)
        XCTAssertEqual(after.articleImageSlotFrameForTesting.height, beforeSlot.height, accuracy: 0.5)
        XCTAssertEqual(before.layoutVariantForTesting, .visualPortrait)
        XCTAssertEqual(after.layoutVariantForTesting, .visualPortrait)
        XCTAssertEqual(before.layoutVariantRevision, beforeVariantRevision)
    }

    @MainActor
    func testUIKitLandscapeArticleImageAndPresentationUpdatesDoNotChangeGeometry() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 760)
        let baseline = measureUIKitArticleCell(cell, width: 760)
        let baselineSlot = cell.articleImageSlotFrameForTesting
        let baselineVariantRevision = cell.layoutVariantRevision

        cell.applyArticleImagePixelsForTesting(testImage(width: 200, height: 800))
        XCTAssertEqual(measureUIKitArticleCell(cell, width: 760), baseline, accuracy: 0.5)
        XCTAssertEqual(cell.articleImageSlotFrameForTesting.width, baselineSlot.width, accuracy: 0.5)
        XCTAssertEqual(cell.articleImageSlotFrameForTesting.height, baselineSlot.height, accuracy: 0.5)

        cell.applyArticleImagePixelsForTesting(testImage(width: 1200, height: 200))
        cell.updateStatus(isRead: true, isStarred: true)
        cell.updateFeedIcon(image: testImage(width: 80, height: 20), title: "Feed")
        XCTAssertEqual(measureUIKitArticleCell(cell, width: 760), baseline, accuracy: 0.5)
        XCTAssertEqual(cell.articleImageSlotFrameForTesting.width, baselineSlot.width, accuracy: 0.5)
        XCTAssertEqual(cell.articleImageSlotFrameForTesting.height, baselineSlot.height, accuracy: 0.5)
        XCTAssertEqual(cell.layoutVariantForTesting, .visualLandscape)
        XCTAssertEqual(cell.layoutVariantRevision, baselineVariantRevision)

        cell.updateStatus(isRead: false, isStarred: false)
        cell.updateFeedIcon(image: nil, title: "Feed")
        cell.applyArticleImagePixelsForTesting(nil)
        XCTAssertEqual(measureUIKitArticleCell(cell, width: 760), baseline, accuracy: 0.5)
        XCTAssertEqual(cell.layoutVariantForTesting, .visualLandscape)
        XCTAssertEqual(cell.layoutVariantRevision, baselineVariantRevision)
    }

    @MainActor
    func testUIKitArticleAndFeedImagePresentationTransitionsRestoreSafeStates() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 390)
        let placeholder = cell.articleImagePresentationForTesting
        XCTAssertFalse(placeholder.placeholderHidden)
        XCTAssertEqual(placeholder.contentMode, .scaleAspectFill)
        XCTAssertFalse(placeholder.clipsToBounds)
        XCTAssertEqual(placeholder.cornerRadius, IOSUIKitArticleGeometry.articleImageCornerRadius)

        cell.applyArticleImagePixelsForTesting(testImage(width: 200, height: 100))
        let loaded = cell.articleImagePresentationForTesting
        XCTAssertTrue(loaded.placeholderHidden)
        XCTAssertEqual(loaded.contentMode, .scaleAspectFill)
        XCTAssertTrue(loaded.clipsToBounds)
        XCTAssertEqual(loaded.cornerRadius, IOSUIKitArticleGeometry.articleImageCornerRadius)

        cell.prepareForReuse()
        let reused = cell.articleImagePresentationForTesting
        XCTAssertFalse(reused.placeholderHidden)
        XCTAssertFalse(reused.clipsToBounds)
        XCTAssertEqual(reused.cornerRadius, IOSUIKitArticleGeometry.articleImageCornerRadius)

        cell.updateFeedIcon(image: testImage(width: 22, height: 22), title: "Feed")
        let icon = cell.feedIconPresentationForTesting
        XCTAssertFalse(icon.imageHidden)
        XCTAssertTrue(icon.fallbackHidden)
        XCTAssertFalse(icon.clipsToBounds)
        XCTAssertEqual(icon.cornerRadius, 0)

        cell.updateFeedIcon(image: nil, title: "Feed")
        let fallback = cell.feedIconPresentationForTesting
        XCTAssertTrue(fallback.imageHidden)
        XCTAssertFalse(fallback.fallbackHidden)
        // The rounded background must never mask a sublayer: that combination
        // forces a per-frame offscreen render pass. Same contract as the cold
        // article-image placeholder asserted above.
        XCTAssertFalse(fallback.clipsToBounds)
        XCTAssertEqual(fallback.cornerRadius, IOSFeedIconImagePreparation.cornerRadius)
    }

    func testArticleImageRequestBucketsDisplayPixelsDeterministically() {
        let url = URL(string: "https://example.com/image.jpg")!
        XCTAssertEqual(ArticleImageRequest(url: url, targetSize: CGSize(width: 100, height: 50), displayScale: 2).maxPixelDimension, 256)
        XCTAssertEqual(ArticleImageRequest(url: url, targetSize: CGSize(width: 127.9, height: 20), displayScale: 1).maxPixelDimension, 128)
        XCTAssertEqual(ArticleImageRequest(url: url, targetSize: CGSize(width: 128.1, height: 20), displayScale: 1).maxPixelDimension, 192)
    }

    @MainActor
    func testUIKitArticleCellUsesSeparateStableVariantReuseIdentifiers() {
        let identifiers = [
            IOSUIKitArticleCell.reuseIdentifier(for: .compact),
            IOSUIKitArticleCell.reuseIdentifier(for: .visualTextOnly),
            IOSUIKitArticleCell.reuseIdentifier(for: .visualPortrait),
            IOSUIKitArticleCell.reuseIdentifier(for: .visualLandscape),
        ]
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testFeedIconPreparationDownsamplesToTheFixedDisplaySlotOffMain() async throws {
        let data = try solidPNGData(width: 800, height: 400, color: .red)
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)
        let ranOnMain = try await execution.blocking { Thread.isMainThread }
        let prepared = try await execution.blocking {
            try IOSFeedIconImagePreparation.prepare(data: data, displayScale: 3)
        }

        XCTAssertFalse(ranOnMain)
        XCTAssertEqual(prepared.pixelSize.width, IOSFeedIconImagePreparation.displaySidePoints * 3)
        XCTAssertEqual(prepared.pixelSize.height, IOSFeedIconImagePreparation.displaySidePoints * 3)
        XCTAssertEqual(prepared.image.scale, 3)
        let image = try XCTUnwrap(prepared.image.cgImage)
        XCTAssertEqual(image.alphaInfo, .premultipliedFirst)
        XCTAssertTrue(image.bitmapInfo.contains(.byteOrder32Little))
        XCTAssertEqual(pixel(at: .zero, in: image).alpha, 0)
        let center = pixel(at: .init(x: image.width / 2, y: image.height / 2), in: image)
        XCTAssertEqual(center, .init(blue: 0, green: 0, red: 255, alpha: 255))
    }

    func testPrefetchMetadataReusesAnUnchangedStructuralSnapshot() {
        func article(_ id: Int64, imageURL: String? = nil) -> ArticleSummary {
            ArticleSummary(id: id, feedId: 1, categoryId: 1, feedTitle: "Feed", title: "Article", url: "https://example.com/\(id)", commentsUrl: "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: 0, preview: "", imageUrl: imageURL)
        }
        var metadata = IOSArticleImagePrefetchMetadata()
        XCTAssertTrue(metadata.update(articles: [article(1), article(2, imageURL: "https://example.com/2.jpg")]))
        XCTAssertFalse(metadata.update(articles: [article(1), article(2, imageURL: "https://example.com/changed.jpg")]))
        XCTAssertEqual(metadata.candidateIDs(visibleIDs: [1], direction: .forward), [2])
        XCTAssertTrue(metadata.update(articles: [article(2, imageURL: "https://example.com/2.jpg"), article(1)]))
    }

    func testArticleImagePrefetchSelectsAtMostTwoImagesForwardAndSkipsTextOnlyArticles() {
        XCTAssertEqual(
            IOSArticleImagePrefetchPolicy.candidateIDs(
                orderedIDs: [1, 2, 3, 4, 5, 6],
                visibleIDs: [2],
                imageIDs: [3, 5, 6],
                direction: .forward
            ),
            [3, 5]
        )
    }

    func testArticleImagePrefetchLooksBackwardFromTheLeadingVisibleArticle() {
        XCTAssertEqual(
            IOSArticleImagePrefetchPolicy.candidateIDs(
                orderedIDs: [1, 2, 3, 4, 5],
                visibleIDs: [4, 5],
                imageIDs: [1, 2, 3],
                direction: .backward
            ),
            [3, 2]
        )
    }

    func testArticleImagePrefetchRespectsEdgesHorizonAndExcludedRequests() {
        XCTAssertEqual(
            IOSArticleImagePrefetchPolicy.candidateIDs(
                orderedIDs: [1, 2, 3],
                visibleIDs: [1],
                imageIDs: [2, 3],
                direction: .backward
            ),
            []
        )
        XCTAssertEqual(
            IOSArticleImagePrefetchPolicy.candidateIDs(
                orderedIDs: [1, 2, 3, 4, 5, 6],
                visibleIDs: [1],
                imageIDs: [2, 3, 4, 5, 6],
                direction: .forward,
                excludedIDs: [2],
                searchHorizon: 3
            ),
            [3, 4]
        )
    }

    func testPrefetchCoordinatorCoalescesRequestsUntilTheSnapshotChanges() {
        let url = URL(string: "https://example.com/image.jpg")!
        let request = ArticleImageRequest(url: url, targetSize: CGSize(width: 100, height: 50), displayScale: 2)
        let secondRequest = ArticleImageRequest(url: URL(string: "https://example.com/second.jpg")!, targetSize: CGSize(width: 100, height: 50), displayScale: 2)
        let coordinator = IOSArticleImagePrefetchCoordinator()

        XCTAssertEqual(coordinator.accept([request, secondRequest]), [request, secondRequest])
        XCTAssertTrue(coordinator.accept([secondRequest, request]).isEmpty)

        coordinator.reset()

        XCTAssertEqual(coordinator.accept([request]), [request])
    }

    @MainActor
    func testArticleImagePresentationSchedulerPacesOneReadyImagePerTickAndTracksDelay() {
        let scheduler = IOSArticleImagePresentationScheduler.shared
        scheduler.resetMetrics()
        scheduler.setScrolling(true)

        var presented: [Int] = []
        scheduler.enqueue(isStillValid: { true }) { presented.append(1) }
        scheduler.enqueue(isStillValid: { true }) { presented.append(2) }

        XCTAssertEqual(scheduler.metrics().queued, 2)
        XCTAssertEqual(scheduler.metrics().maximumQueued, 2)

        scheduler.setScrolling(false)

        XCTAssertEqual(presented, [1, 2])
        let metrics = scheduler.metrics()
        XCTAssertEqual(metrics.queued, 0)
        XCTAssertEqual(metrics.presented, 2)
        XCTAssertGreaterThanOrEqual(metrics.maximumQueued, 2)
    }

    func testArticleImageCacheDiagnosticsSnapshotFormatsVisibleHitRate() {
        let metrics = ArticleImagePipeline.Metrics(
            activeOperations: 1,
            queuedVisibleRequests: 0,
            queuedPrefetchRequests: 0,
            trackedRequests: 1,
            memoryCacheHits: 8,
            memoryCacheMisses: 2,
            visibleMemoryCacheHits: 8,
            visibleMemoryCacheMisses: 2,
            prefetchMemoryCacheHits: 0,
            prefetchMemoryCacheMisses: 0,
            memoryCacheInsertions: 4,
            memoryCacheEvictions: 1,
            memoryCacheCostLimit: 128 * 1024 * 1024,
            inFlightDedupHits: 0,
            startedOperations: 5,
            completedOperations: 4,
            retiredOperations: 1,
            maximumActiveOperations: 3,
            visibleStarts: 5,
            prefetchStarts: 0
        )

        let snapshot = ArticleImageCacheDiagnosticsSnapshot(metrics: metrics)

        XCTAssertEqual(snapshot.visibleHits, 8)
        XCTAssertEqual(snapshot.visibleMisses, 2)
        XCTAssertEqual(snapshot.visibleHitRate, 0.8)
        XCTAssertEqual(snapshot.visibleHitRateText, "80.0%")
        XCTAssertEqual(snapshot.evictions, 1)
        XCTAssertEqual(snapshot.activeOperations, 1)
    }

    func testArticleImagePipelineUsesDecodedCacheAndSeparatesLargerRequests() async throws {
        let data = try imageData(width: 800, height: 400)
        let counter = ImageLoadCounter(data: data)
        let pipeline = ArticleImagePipeline { _ in await counter.load() }
        let url = URL(string: "https://example.com/image.jpg")!
        let small = ArticleImageRequest(url: url, targetSize: CGSize(width: 100, height: 50), displayScale: 1)
        let large = ArticleImageRequest(url: url, targetSize: CGSize(width: 400, height: 200), displayScale: 1)

        _ = try await pipeline.image(for: small)
        _ = try await pipeline.image(for: small)
        XCTAssertNotNil(pipeline.cachedImage(for: small))
        let cachedCalls = await counter.callCount()
        XCTAssertEqual(cachedCalls, 1)

        let image = try await pipeline.image(for: large)
        let largerCalls = await counter.callCount()
        XCTAssertEqual(largerCalls, 2)
        XCTAssertGreaterThan(image.width, small.maxPixelDimension)
    }

    func testArticleImagePipelinePrefetchMakesTheSameCanonicalVisibleRequestAnImmediateMemoryHit() async throws {
        let data = try imageData(width: 800, height: 400)
        let counter = ImageLoadCounter(data: data)
        let pipeline = ArticleImagePipeline { _ in await counter.load() }
        let request = ArticleImageRequest(url: URL(string: "https://example.com/image.jpg")!, targetSize: CGSize(width: 390, height: 215), displayScale: 3)

        _ = try await pipeline.prefetch(request)
        XCTAssertNotNil(pipeline.cachedImage(for: request))

        let metrics = await pipeline.metrics()
        let calls = await counter.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(metrics.prefetchMemoryCacheMisses, 1)
        XCTAssertEqual(metrics.visibleMemoryCacheHits, 1)
        XCTAssertEqual(metrics.memoryCacheInsertions, 1)
        XCTAssertEqual(metrics.startedOperations, 1)
    }

    func testArticleImagePipelineVisibleReuseHitsMemoryWithoutAnotherDecode() async throws {
        let data = try imageData(width: 800, height: 400)
        let counter = ImageLoadCounter(data: data)
        let pipeline = ArticleImagePipeline { _ in await counter.load() }
        let request = ArticleImageRequest(url: URL(string: "https://example.com/image.jpg")!, targetSize: CGSize(width: 100, height: 50), displayScale: 1)

        _ = try await pipeline.image(for: request)
        _ = try await pipeline.image(for: request)

        let metrics = await pipeline.metrics()
        let calls = await counter.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(metrics.visibleMemoryCacheHits, 1)
        XCTAssertEqual(metrics.visibleMemoryCacheMisses, 1)
        XCTAssertEqual(metrics.startedOperations, 1)
        XCTAssertEqual(metrics.memoryCacheCostLimit, ArticleImagePipeline.memoryCacheCostLimit)
        XCTAssertEqual(ArticleImagePipeline.memoryCacheCostLimit, 128 * 1024 * 1024)
    }

    func testArticleImagePipelineCachesTheExactPreparedDisplayGeometry() async throws {
        let pipeline = ArticleImagePipeline { _ in try self.imageData(width: 800, height: 400) }
        let url = URL(string: "https://example.com/image.jpg")!
        let cachedRequest = ArticleImageRequest(url: url, targetSize: CGSize(width: 100, height: 50), displayScale: 1)
        let equivalentRequest = ArticleImageRequest(url: url, targetSize: CGSize(width: 127.9, height: 20), displayScale: 1)
        let differentSizeRequest = ArticleImageRequest(url: url, targetSize: CGSize(width: 128.1, height: 20), displayScale: 1)

        XCTAssertNil(pipeline.cachedImage(for: cachedRequest))
        _ = try await pipeline.image(for: cachedRequest)

        XCTAssertNil(pipeline.cachedImage(for: equivalentRequest))
        XCTAssertNil(pipeline.cachedImage(for: differentSizeRequest))
    }

    func testArticleImagePipelineLRURetainsRecentRastersUntilBudgetRequiresEviction() async throws {
        let data = try imageData(width: 800, height: 400)
        let counter = ImageLoadCounter(data: data)
        let rasterCost = 100 * 50 * 4
        let pipeline = ArticleImagePipeline(
            loader: { _ in await counter.load() },
            memoryCacheCostLimit: rasterCost * 2 + 1
        )

        let first = ArticleImageRequest(
            url: URL(string: "https://example.com/first.jpg")!,
            targetSize: CGSize(width: 100, height: 50),
            displayScale: 1
        )
        let second = ArticleImageRequest(
            url: URL(string: "https://example.com/second.jpg")!,
            targetSize: CGSize(width: 100, height: 50),
            displayScale: 1
        )
        let third = ArticleImageRequest(
            url: URL(string: "https://example.com/third.jpg")!,
            targetSize: CGSize(width: 100, height: 50),
            displayScale: 1
        )

        _ = try await pipeline.image(for: first)
        _ = try await pipeline.image(for: second)
        XCTAssertNotNil(pipeline.cachedImage(for: first)) // promote first to MRU
        _ = try await pipeline.image(for: third)

        XCTAssertNotNil(pipeline.cachedImage(for: first))
        XCTAssertNil(pipeline.cachedImage(for: second))
        XCTAssertNotNil(pipeline.cachedImage(for: third))

        let metrics = await pipeline.metrics()
        let calls = await counter.callCount()
        XCTAssertEqual(metrics.memoryCacheEvictions, 1)
        XCTAssertEqual(calls, 3)
    }

    func testArticleImagePipelineDeduplicatesEquivalentInFlightRequests() async throws {
        let gate = ImageLoadGate(data: try imageData(width: 800, height: 400))
        let pipeline = ArticleImagePipeline { _ in try await gate.load() }
        let request = ArticleImageRequest(url: URL(string: "https://example.com/image.jpg")!, targetSize: CGSize(width: 200, height: 100), displayScale: 1)

        async let first = pipeline.image(for: request)
        await gate.waitUntilStarted()
        async let second = pipeline.image(for: request)
        await Task.yield()
        await gate.release()

        _ = try await first
        _ = try await second
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1)
        let metrics = await pipeline.metrics()
        XCTAssertEqual(metrics.inFlightDedupHits, 1)
    }

    func testArticleImagePipelinePrefetchBatchesDuplicateRequests() async throws {
        let gate = ImageLoadGate(data: try imageData(width: 800, height: 400))
        let pipeline = ArticleImagePipeline { _ in try await gate.load() }
        let request = ArticleImageRequest(url: URL(string: "https://example.com/image.jpg")!, targetSize: CGSize(width: 200, height: 100), displayScale: 1)

        let prefetch = Task { await pipeline.prefetch([request, request]) }
        await gate.waitUntilStarted()
        await gate.release()
        await prefetch.value

        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testArticleImagePipelineBoundsWorkAndPrioritizesVisibleRequests() async throws {
        let gate = PrioritizedImageLoadGate(data: try imageData(width: 800, height: 400))
        let pipeline = ArticleImagePipeline { url in try await gate.load(url: url) }
        let requests = (0...4).map {
            ArticleImageRequest(
                url: URL(string: "https://example.com/\($0).jpg")!,
                targetSize: CGSize(width: 200, height: 100),
                displayScale: 1
            )
        }

        let activePrefetches = requests.prefix(3).map { request in
            Task { try await pipeline.prefetch(request) }
        }
        await gate.waitUntilStarted(count: 2)
        let queuedPrefetch = Task { try await pipeline.prefetch(requests[3]) }
        let visible = Task { try await pipeline.image(for: requests[4]) }

        // A fixed number of yields does not guarantee that newly created tasks
        // have entered the image pipeline on a busy CI simulator. Await the
        // observable saturated queue before asserting priority and bounds.
        var saturated = await pipeline.metrics()
        for _ in 0..<100 {
            if saturated.queuedVisibleRequests == 1 &&
                saturated.queuedPrefetchRequests == 2 &&
                saturated.trackedRequests == 5 { break }
            try await Task.sleep(for: .milliseconds(10))
            saturated = await pipeline.metrics()
        }
        XCTAssertEqual(ArticleImagePipeline.maximumConcurrentOperations, 2)
        XCTAssertEqual(saturated.activeOperations, 2)
        XCTAssertEqual(saturated.queuedVisibleRequests, 1)
        XCTAssertEqual(saturated.queuedPrefetchRequests, 2)
        XCTAssertEqual(saturated.trackedRequests, 5)

        await gate.releaseOne()
        await gate.waitUntilStarted(count: 3)
        let startedURLs = await gate.startedURLs()
        XCTAssertEqual(startedURLs.last, requests[4].url)

        await gate.releaseAll()
        await gate.waitUntilStarted(count: 5)
        await gate.releaseAll()
        for task in activePrefetches { _ = try await task.value }
        _ = try await queuedPrefetch.value
        _ = try await visible.value
        let completed = await pipeline.metrics()
        XCTAssertEqual(completed.trackedRequests, 0)
    }

    func testArticleImagePipelineUsesAspectFillDecodeWithoutExactSlotRaster() throws {
        let data = try imageData(width: 800, height: 400)
        let request = ArticleImageRequest(
            url: URL(string: "https://example.com/image.jpg")!,
            targetSize: CGSize(width: 128, height: 128),
            displayScale: 1
        )
        let decoded = try ArticleImagePipeline.downsample(data: data, request: request)
        XCTAssertEqual(CGSize(width: decoded.width, height: decoded.height), .init(width: 256, height: 128))
    }

    func testArticleImagePipelineDownsamplesAndFailsSafely() async throws {
        let data = try imageData(width: 800, height: 400)
        let url = URL(string: "https://example.com/image.jpg")!
        let displayRequest = ArticleImageRequest(url: url, targetSize: CGSize(width: 128, height: 64), displayScale: 1)
        let image = try ArticleImagePipeline.downsample(data: data, request: displayRequest)
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 64)

        let rotatedRequest = ArticleImageRequest(url: url, targetSize: CGSize(width: 64, height: 128), displayScale: 1)
        let rotated = try ArticleImagePipeline.downsample(data: imageData(width: 800, height: 400, orientation: 6), request: rotatedRequest)
        XCTAssertEqual(rotated.width, 64)
        XCTAssertEqual(rotated.height, 128)

        let corrupt = ArticleImagePipeline { _ in Data("not an image".utf8) }
        let failing = ArticleImagePipeline { _ in throw URLError(.badServerResponse) }
        let request = ArticleImageRequest(url: url, targetSize: CGSize(width: 100, height: 50), displayScale: 1)
        do {
            _ = try await corrupt.image(for: request)
            XCTFail("Corrupt data must fail")
        } catch {}
        do {
            _ = try await failing.image(for: request)
            XCTFail("Network failure must fail")
        } catch {}
    }

    func testDisplayScaleDecodeCoversTargetWithoutExactSlotRaster() throws {
        let representativeTargetSize = IOSUIKitArticleGeometry(mode: .visual, containerWidth: 393).imageSize(hasImage: true)
        let normalRepresentative = ArticleImageRequest(
            url: URL(string: "https://example.com/image.jpg")!,
            targetSize: representativeTargetSize,
            displayScale: 3,
            rasterScale: 3
        )
        XCTAssertEqual(normalRepresentative.rasterScale, 3)
        XCTAssertEqual(normalRepresentative.maxPixelDimension, 1_088)
        XCTAssertEqual(normalRepresentative.targetPixelSize, .init(width: 1_083, height: 609))

        let request = ArticleImageRequest(
            url: URL(string: "https://example.com/image.jpg")!,
            targetSize: .init(width: 20, height: 10),
            displayScale: 1
        )

        // The sole production renderer preserves source aspect ratio and decodes
        // enough pixels for UIImageView aspect-fill. It deliberately does not
        // create an exact-slot CGContext raster or prescribe a bitmap format.
        let portrait = try imageData(width: 100, height: 300)
        let portraitImage = try ArticleImagePipeline.downsample(data: portrait, request: request)
        XCTAssertEqual(portraitImage.width, 20)
        XCTAssertEqual(portraitImage.height, 60)
        XCTAssertGreaterThanOrEqual(portraitImage.width, Int(request.targetPixelSize.width))
        XCTAssertGreaterThanOrEqual(portraitImage.height, Int(request.targetPixelSize.height))

        let landscape = try imageData(width: 300, height: 100)
        let landscapeImage = try ArticleImagePipeline.downsample(data: landscape, request: request)
        XCTAssertEqual(landscapeImage.width, 30)
        XCTAssertEqual(landscapeImage.height, 10)
        XCTAssertGreaterThanOrEqual(landscapeImage.width, Int(request.targetPixelSize.width))
        XCTAssertGreaterThanOrEqual(landscapeImage.height, Int(request.targetPixelSize.height))
    }

    func testArticleImagePipelineCanLoadAfterCacheEvictionAndCancelledWaiter() async throws {
        let data = try imageData(width: 800, height: 400)
        let counter = ImageLoadCounter(data: data)
        let pipeline = ArticleImagePipeline { _ in await counter.load() }
        let request = ArticleImageRequest(url: URL(string: "https://example.com/image.jpg")!, targetSize: CGSize(width: 100, height: 50), displayScale: 1)
        _ = try await pipeline.image(for: request)
        await pipeline.removeAllCachedImages()
        _ = try await pipeline.image(for: request)
        let reloadCalls = await counter.callCount()
        XCTAssertEqual(reloadCalls, 2)

        let gate = ImageLoadGate(data: data)
        let sharedPipeline = ArticleImagePipeline { _ in try await gate.load() }
        let cancelled = Task { try await sharedPipeline.image(for: request) }
        await gate.waitUntilStarted()
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled consumer must not receive an image")
        } catch is CancellationError {}
        let active = Task { try await sharedPipeline.image(for: request) }
        await gate.release()
        await gate.waitUntilStarted(count: 2)
        await gate.release()
        _ = try await active.value
        let sharedCalls = await gate.callCount()
        XCTAssertEqual(sharedCalls, 2)
    }

    func testArticleImagePipelineCancellationAfterLoadSkipsObsoleteRasterCache() async throws {
        let gate = ImageLoadGate(data: try imageData(width: 2_400, height: 1_600))
        let pipeline = ArticleImagePipeline { _ in try await gate.load() }
        let request = ArticleImageRequest(
            url: URL(string: "https://example.com/cancelled.jpg")!,
            targetSize: CGSize(width: 307, height: 173),
            displayScale: 3
        )

        let cancelled = Task { try await pipeline.image(for: request) }
        await gate.waitUntilStarted()
        cancelled.cancel()
        await gate.release()

        do {
            _ = try await cancelled.value
            XCTFail("Cancelled consumer must not receive a raster")
        } catch is CancellationError {}

        XCTAssertNil(pipeline.cachedImage(for: request))

        let active = Task { try await pipeline.image(for: request) }
        await gate.waitUntilStarted(count: 2)
        await gate.release()
        _ = try await active.value

        XCTAssertNotNil(pipeline.cachedImage(for: request))
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testArticleImagePipelineCancellingOneConsumerRetainsTheCompletedSharedImage() async throws {
        let gate = ImageLoadGate(data: try imageData(width: 800, height: 400))
        let pipeline = ArticleImagePipeline { _ in try await gate.load() }
        let request = ArticleImageRequest(url: URL(string: "https://example.com/image.jpg")!, targetSize: CGSize(width: 200, height: 100), displayScale: 1)

        let cancelled = Task { try await pipeline.image(for: request) }
        await gate.waitUntilStarted()
        let retained = Task { try await pipeline.image(for: request) }

        for _ in 0..<100 {
            if (await pipeline.metrics()).inFlightDedupHits == 1 { break }
            await Task.yield()
        }
        guard (await pipeline.metrics()).inFlightDedupHits == 1 else {
            cancelled.cancel()
            retained.cancel()
            await gate.release()
            XCTFail("Retained consumer did not attach to the shared image load")
            return
        }

        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled consumer must not receive an image")
        } catch is CancellationError {}
        await gate.release()
        _ = try await retained.value

        XCTAssertNotNil(pipeline.cachedImage(for: request))
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1)
    }

    private func imageData(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil), let image = context.makeImage() else {
            throw XCTSkip("Unable to create image fixture")
        }
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("Unable to encode image fixture") }
        return data as Data
    }

    private func solidPNGData(width: Int, height: Int, color: UIColor) throws -> Data {
        try pngData(width: width, height: height) { context in
            context.setFillColor(color.cgColor)
            context.fill(.init(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pngData(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("Unable to create PNG fixture context") }
        draw(context)
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw XCTSkip("Unable to create PNG fixture") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("Unable to encode PNG fixture") }
        return data as Data
    }

    private struct BGRAPixel: Equatable {
        let blue: UInt8
        let green: UInt8
        let red: UInt8
        let alpha: UInt8
    }

    private func pixel(at point: CGPoint, in image: CGImage) -> BGRAPixel {
        let x = Int(point.x)
        let y = Int(point.y)
        precondition((0..<image.width).contains(x) && (0..<image.height).contains(y))
        precondition(image.bitsPerPixel == 32)
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { fatalError("Display-ready image did not expose bitmap data") }
        let offset = y * image.bytesPerRow + x * 4
        return .init(blue: bytes[offset], green: bytes[offset + 1], red: bytes[offset + 2], alpha: bytes[offset + 3])
    }

    /// Self-sizing is gone: the table takes each row height from the store, and
    /// the cell never resolves its own size. What must still hold is that the
    /// cell's own constraints agree with the engine — otherwise rows would be
    /// laid out at a height their content does not fit.
    func testVisualCompactPreviewFlowsBesideThenBelowImage() {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let preview = String(repeating: "A readable preview sentence continues into more words. ", count: 7)
        let lineHeight = font.lineHeight + font.leading
        let flow = IOSVisualCompactPreviewFlow.prepare(
            text: preview,
            narrowWidth: 160,
            fullWidth: 340,
            heightBesideImage: lineHeight * 2 + 1,
            maxLines: 5, font: font, displayScale: 3
        )
        XCTAssertFalse(flow.beside.isEmpty)
        XCTAssertFalse(flow.below.isEmpty)
        XCTAssertLessThanOrEqual(
            abs((flow.beside as NSString).length + (flow.below as NSString).length
                - (preview as NSString).length),
            3, "Only whitespace at the boundary may be discarded"
        )
        XCTAssertGreaterThan(flow.besideHeight, 0)
        XCTAssertGreaterThan(flow.belowHeight, 0)

        let noRoom = IOSVisualCompactPreviewFlow.prepare(
            text: preview, narrowWidth: 160, fullWidth: 340,
            heightBesideImage: 0, maxLines: 3, font: font, displayScale: 3
        )
        XCTAssertTrue(noRoom.beside.isEmpty)
        XCTAssertEqual(noRoom.below, preview.trimmingCharacters(in: .whitespacesAndNewlines))

        let short = IOSVisualCompactPreviewFlow.prepare(
            text: "Short preview", narrowWidth: 160, fullWidth: 340,
            heightBesideImage: lineHeight * 3, maxLines: 3, font: font, displayScale: 3
        )
        XCTAssertTrue(short.below.isEmpty)
    }

    func testVisualCompactPreviewUsesLastLineStartingAboveImageBottom() {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let step = font.lineHeight + font.leading
        let preview = String(repeating: "A longer sentence fills the narrow image-side column. ", count: 10)
        let first = IOSVisualCompactPreviewFlow.prepare(
            text: preview,
            narrowWidth: 165, fullWidth: 330,
            heightBesideImage: step * 1.5,
            maxLines: 5, font: font, displayScale: 3
        )
        let second = IOSVisualCompactPreviewFlow.prepare(
            text: preview,
            narrowWidth: 165, fullWidth: 330,
            heightBesideImage: step * 2,
            maxLines: 5, font: font, displayScale: 3
        )
        // The last side line can start before the image ends. This avoids
        // discarding the remaining partial line-height of usable side space.
        XCTAssertEqual(first.beside, second.beside)
        XCTAssertEqual(first.besideHeight, second.besideHeight)
        XCTAssertFalse(first.below.isEmpty)
    }

    func testVisualCompactContinuationFollowsSidePreviewWithoutParagraphGap() {
        let metrics = layoutMetrics(mode: .visualCompact, width: 414, hasImage: true)
        guard let continuation = metrics.previewContinuationFrame,
              let beside = metrics.previewFrame else { return }
        XCTAssertLessThanOrEqual(beside.maxY, continuation.minY + 0.5)
        XCTAssertLessThanOrEqual(
            continuation.minY - beside.maxY,
            IOSUIKitArticleGeometry.textSpacing + 0.5,
            "No artificial image-sized gap between preview segments"
        )
    }

    func testVisualCompactFlowPreparedMetricsAvoidAnImageSizedPreviewGap() {
        let withImage = layoutMetrics(mode: .visualCompact, width: 414, hasImage: true)
        XCTAssertEqual(withImage.variant, .visualSideTitle)
        guard let image = withImage.imageFrame else {
            return XCTFail("Expected side thumbnail")
        }
        if let side = withImage.previewFrame {
            XCTAssertEqual(
                side.minY, withImage.dateFrame.maxY + IOSUIKitArticleGeometry.textSpacing,
                accuracy: 0.5
            )
            XCTAssertLessThan(side.minX, image.minX)
            XCTAssertLessThanOrEqual(side.maxX, image.minX)
        }
        if let continuation = withImage.previewContinuationFrame {
            XCTAssertEqual(continuation.width, withImage.metadataFrame.width)
            XCTAssertGreaterThanOrEqual(continuation.minY, image.maxY)
        }

        let noImage = layoutMetrics(mode: .visualCompact, width: 414, hasImage: false)
        XCTAssertEqual(noImage.variant, .visualSideTitleTextOnly)
        XCTAssertNil(noImage.imageFrame)
        XCTAssertNil(noImage.previewContinuationFrame)
        XCTAssertFalse(noImage.previewSideText.isEmpty)
    }

    @MainActor
    func testVisualCompactVariantFramesMatchTheEngine() {
        assertSideTitleFramesMatchTheEngine(width: 414, expecting: .visualSideTitle)
        // Without an image the metadata bar must still lead, or rows with and
        // without an image would order their content differently.
        assertSideTitleFramesMatchTheEngine(width: 414, expecting: .visualSideTitleTextOnly, hasImage: false)
        // Wide container: the preview joins the column beside the image, so the
        // image can become the lowest element in the row.
        assertSideTitleFramesMatchTheEngine(width: 834, expecting: .visualSideTitleWide)
    }

    @MainActor
    private func assertSideTitleFramesMatchTheEngine(
        width: CGFloat,
        expecting variant: IOSUIKitArticleCellLayoutVariant,
        hasImage: Bool = true,
        line: UInt = #line
    ) {
        let cell = makeUIKitArticleCell(mode: .visualCompact, width: width, hasImage: hasImage)
        let measured = measureUIKitArticleCell(cell, width: width)
        guard let expected = cell.preparedLayoutMetrics else {
            return XCTFail("no prepared metrics", line: line)
        }

        XCTAssertEqual(expected.variant, variant, line: line)
        XCTAssertEqual(measured, expected.cellSize.height, accuracy: 0.5, "cell height", line: line)

        let actual = cell.layoutDiagnosticsForTesting
        XCTAssertEqual(actual.variant, variant, line: line)
        // The date must sit directly under the title, never pushed down by slack
        // the engine budgeted elsewhere.
        XCTAssertEqual(actual.titleFrame.origin.y, expected.titleFrame.origin.y, accuracy: 0.5, "title y", line: line)
        XCTAssertEqual(actual.titleFrame.height, expected.titleFrame.height, accuracy: 0.5, "title height", line: line)
        XCTAssertEqual(actual.dateFrame.origin.y, expected.dateFrame.origin.y, accuracy: 0.5, "date y", line: line)
        XCTAssertEqual(actual.metadataFrame.origin.y, expected.metadataFrame.origin.y, accuracy: 0.5, "metadata y", line: line)
        XCTAssertLessThan(expected.metadataFrame.origin.y, expected.titleFrame.origin.y, "metadata must lead", line: line)
        XCTAssertEqual(actual.metadataFrame.width, expected.metadataFrame.width, accuracy: 0.5, "metadata width", line: line)
        if hasImage {
            XCTAssertEqual(actual.imageFrame.origin.y, expected.imageFrame?.origin.y ?? -1, accuracy: 0.5, "image y", line: line)
            XCTAssertEqual(actual.imageFrame.width, expected.imageFrame?.width ?? -1, accuracy: 0.5, "image width", line: line)
        } else {
            XCTAssertNil(expected.imageFrame, "no image slot", line: line)
            XCTAssertFalse(variant.showsImageSlot, "variant must not show an image", line: line)
        }
        if let previewActual = actual.previewFrame, let previewExpected = expected.previewFrame {
            XCTAssertEqual(previewActual.origin.y, previewExpected.origin.y, accuracy: 0.5, "preview y", line: line)
        } else {
            XCTAssertNil(actual.previewFrame, "no narrow preview frame", line: line)
            XCTAssertNil(expected.previewFrame, "no measured narrow preview", line: line)
        }
        if let continuation = expected.previewContinuationFrame {
            let actualContinuation = actual.previewContinuationFrame
            XCTAssertNotNil(actualContinuation, "expected full-width continuation", line: line)
            XCTAssertEqual(actualContinuation?.origin.y ?? -1, continuation.minY, accuracy: 0.5, "continuation y", line: line)
            XCTAssertEqual(actualContinuation?.width ?? -1, continuation.width, accuracy: 0.5, "continuation width", line: line)
        } else {
            XCTAssertNil(actual.previewContinuationFrame, "no extra continuation view", line: line)
        }
    }

    @MainActor
    func testArticleRowHeightMatchesTheCellConstraintsWithoutSelfSizing() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 390)
        let metrics = IOSUIKitTimelinePerformanceMetrics()
        cell.performanceMetrics = metrics

        let constraintHeight = measureUIKitArticleCell(cell, width: 390)
        XCTAssertEqual(constraintHeight, cell.preparedLayoutMetrics?.cellSize.height ?? 0, accuracy: 0.5)

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.preferredLayoutAttributesFittingCalls, 0)
        XCTAssertEqual(snapshot.systemLayoutSizeFittingCalls, 0)
        XCTAssertEqual(cell.measurementSolveCount, 0)
    }

    @MainActor
    func testRowHeightStoreServesSupersededHeightsUntilTheNewGenerationIsComplete() {
        let store = IOSUIKitArticleRowHeightStore()
        let first = geometryIdentity(width: 390)
        let second = geometryIdentity(width: 780)

        store.beginGeneration(first)
        store.store([1: 100, 2: 200], for: first)
        XCTAssertEqual(store.height(for: 1), 100)
        XCTAssertFalse(store.isServingSupersededHeights)

        store.beginGeneration(second)
        // The old heights keep the table laying out while the new set is measured.
        XCTAssertTrue(store.isServingSupersededHeights)
        XCTAssertEqual(store.height(for: 1), 100)
        XCTAssertFalse(store.hasExactHeight(for: 1))
        XCTAssertEqual(store.missingIDs(in: [1, 2]), [1, 2])

        // A result measured for the stale identity must not be mixed in.
        store.store([1: 999], for: first)
        XCTAssertEqual(store.height(for: 1), 100)

        store.store([1: 150], for: second)
        XCTAssertFalse(store.retireSupersededHeights(ifComplete: [1, 2]))
        store.store([2: 250], for: second)
        XCTAssertTrue(store.retireSupersededHeights(ifComplete: [1, 2]))
        XCTAssertEqual(store.height(for: 1), 150)
        XCTAssertEqual(store.height(for: 2), 250)

        store.remove([1])
        XCTAssertNil(store.height(for: 1))
    }

    /// The property that removes the whole defect class: the table's content
    /// height is the exact sum of the deterministic row heights from the first
    /// frame, so nothing is corrected later while the list is scrolling.
    @MainActor
    func testTableContentHeightEqualsTheSumOfDeterministicRowHeights() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()

        let articles = (1...40).map { timelineArticle(id: Int64($0)) }
        bridge.replaceArticleStates(Dictionary(uniqueKeysWithValues: articles.map { ($0.id, .init(isRead: false, isStarred: false, revision: 0)) }))
        controller.update(
            structuralState: timelineStructuralState(articles, revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        await controller.settleForTesting()

        let table = controller.tableViewForTesting
        table.layoutIfNeeded()

        XCTAssertEqual(controller.preparedRowHeightCountForTesting, articles.count)
        XCTAssertEqual(table.numberOfRows(inSection: 0), articles.count)
        XCTAssertEqual(controller.synchronousRowHeightFallbackCountForTesting, 0)

        let traits = controller.view.traitCollection
        let expected = articles.reduce(CGFloat.zero) { total, article in
            let item = IOSUIKitArticleTimelineItem(article: article, content: ArticleRowContent(article: article), isRead: false, isStarred: false, feedIconImage: nil)
            let input = IOSUIKitArticleLayoutInput(item: item, mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: traits.displayScale, contentSizeCategory: traits.preferredContentSizeCategory, layoutDirection: controller.view.effectiveUserInterfaceLayoutDirection)
            return total + IOSUIKitArticleLayoutEngine.metrics(for: input).cellSize.height
        }
        XCTAssertEqual(table.contentSize.height, expected, accuracy: 1)
    }

    private func geometryIdentity(width: CGFloat) -> IOSUIKitTimelineGeometryIdentity {
        .init(mode: .visual, previewLines: .standard, containerWidth: width, displayScale: 3, contentSizeCategory: .large, layoutDirection: .leftToRight)
    }

    @MainActor
    func testDeterministicHeightFallbackMetricsRemainAvailableWithoutAutoLayout() {
        let metrics = IOSUIKitTimelinePerformanceMetrics()
        let layout = IOSUIKitArticleLayoutEngine.metrics(for: layoutInput(mode: .visual, width: 390, hasImage: true))
        XCTAssertGreaterThan(layout.cellSize.height, 0)
        metrics.recordDeterministicHeightFallback(durationNanoseconds: 17)
        metrics.recordDeterministicHeightRequest(prepared: true)

        let snapshot = metrics.snapshot()
        XCTAssertEqual(snapshot.deterministicHeightRequests, 2)
        XCTAssertEqual(snapshot.deterministicHeightPreparedHits, 1)
        XCTAssertEqual(snapshot.deterministicHeightSynchronousFallbacks, 1)
        XCTAssertEqual(snapshot.deterministicHeightSynchronousFallbackTotalNanoseconds, 17)
        XCTAssertEqual(snapshot.deterministicHeightSynchronousFallbackMaxNanoseconds, 17)
        XCTAssertEqual(snapshot.systemLayoutSizeFittingCalls, 0)
    }

    @MainActor
    func testSameRunloopResizeCoalescesPreparedWindowReplacement() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = makeTimelineController(bridge: bridge)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        for _ in 0..<10 { await Task.yield() }

        controller.resetPerformanceMetrics()
        for width in [391 as CGFloat, 392, 393] {
            controller.view.frame.size.width = width
            controller.view.layoutIfNeeded()
        }
        for _ in 0..<100 where controller.performanceSnapshot().preparedWindowReplacementCount == 0 {
            await Task.yield()
        }

        let snapshot = controller.performanceSnapshot()
        XCTAssertEqual(snapshot.geometryIdentityChanges, 3)
        XCTAssertEqual(snapshot.geometryLayoutInvalidationCount, 3)
        XCTAssertEqual(snapshot.layoutInvalidationCount, 3)
        XCTAssertEqual(snapshot.preparedWindowReplacementCount, 1)
        XCTAssertGreaterThanOrEqual(snapshot.preparedWindowGenerationsSuperseded, 2)
        XCTAssertEqual(snapshot.structuralReconciliationCount, 0)
        XCTAssertEqual(snapshot.snapshotApplyCount, 0)
    }

    @MainActor
    func testGeometryResizeRestoresAnchorCapturedBeforeUIKitChangesOffset() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()

        let articles = (1...80).map { timelineArticle(id: Int64($0)) }
        bridge.replaceArticleStates(Dictionary(uniqueKeysWithValues: articles.map {
            ($0.id, .init(isRead: false, isStarred: false, revision: 0))
        }))
        controller.update(
            structuralState: timelineStructuralState(articles, revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        await controller.settleForTesting()
        controller.view.layoutIfNeeded()

        let targetRow = 30
        controller.tableViewForTesting.scrollToRow(
            at: IndexPath(row: targetRow, section: 0),
            at: .top,
            animated: false
        )
        controller.tableViewForTesting.layoutIfNeeded()
        guard let originalAnchor = controller.scrollAnchorForTesting else {
            return XCTFail("Expected a visible pre-resize anchor")
        }
        XCTAssertEqual(originalAnchor.articleID, articles[targetRow].id)

        // viewWillTransition captures this before UIKit starts adapting its
        // content offset. Simulate UIKit subsequently losing that position
        // before the asynchronous replacement heights are ready.
        controller.captureGeometryScrollAnchorForTesting()
        controller.tableViewForTesting.setContentOffset(
            CGPoint(x: 0, y: -controller.tableViewForTesting.adjustedContentInset.top),
            animated: false
        )

        controller.view.frame.size.width = 760
        controller.view.layoutIfNeeded()
        await controller.settleForTesting()
        controller.view.layoutIfNeeded()

        guard let restoredAnchor = controller.scrollAnchorForTesting else {
            return XCTFail("Expected the pre-resize anchor to be restored")
        }
        XCTAssertEqual(restoredAnchor.articleID, originalAnchor.articleID)
        XCTAssertEqual(restoredAnchor.viewportOffset, originalAnchor.viewportOffset, accuracy: 1)
    }

    func testDeterministicArticleLayoutEngineSelectsCurrentPresentationVariants() {
        XCTAssertEqual(layoutMetrics(mode: .compact, width: 390, hasImage: true).variant, .compact)
        XCTAssertEqual(layoutMetrics(mode: .visual, width: 390, hasImage: false).variant, .visualTextOnly)
        XCTAssertEqual(layoutMetrics(mode: .visual, width: 390, hasImage: true).variant, .visualPortrait)
        XCTAssertEqual(layoutMetrics(mode: .visual, width: 760, hasImage: true).variant, .visualLandscape)
    }

    func testAudioAccessoryReservesFeedTitleWidth() {
        let geometry = IOSUIKitArticleGeometry(
            mode: .visual,
            containerWidth: 390
        )
        let accessories = IOSUIKitArticleAccessoryMetrics(
            contentSizeCategory: .large
        )

        let withoutAudio = geometry.metadataLayout(
            width: 358,
            hasComments: false,
            hasAudio: false,
            height: 22,
            accessories: accessories
        )
        let withAudio = geometry.metadataLayout(
            width: 358,
            hasComments: false,
            hasAudio: true,
            height: 22,
            accessories: accessories
        )

        XCTAssertLessThan(
            withAudio.feedTitleWidth,
            withoutAudio.feedTitleWidth
        )
        XCTAssertEqual(
            withoutAudio.feedTitleWidth - withAudio.feedTitleWidth,
            accessories.comments + IOSUIKitArticleGeometry.metadataAccessorySpacing,
            accuracy: 0.5
        )
    }

    func testArticleAccessoryOrderingIsStableAcrossHorizontalAndVerticalLayouts() {
        XCTAssertEqual(IOSArticleAccessoryOrdering.outerToInner, [.unread, .star, .comments, .audio])
        XCTAssertEqual(IOSArticleAccessoryOrdering.horizontalLeadingToTrailing, [.audio, .comments, .star, .unread])
    }

    func testTemporalUnitSpacingNormalizesOnlyMissingWhitespace() {
        XCTAssertEqual(IOSArticleTemporalPresentation.spacingLocalizedNumberUnits("4Min."), "4 Min.")
        XCTAssertEqual(IOSArticleTemporalPresentation.spacingLocalizedNumberUnits("vor 3Std."), "vor 3 Std.")
        XCTAssertEqual(IOSArticleTemporalPresentation.spacingLocalizedNumberUnits("4 Min."), "4 Min.")
        XCTAssertEqual(IOSArticleTemporalPresentation.spacingLocalizedNumberUnits("4\u{00A0}Min."), "4\u{00A0}Min.")
        XCTAssertEqual(IOSArticleTemporalPresentation.spacingLocalizedNumberUnits("vor 3 Std."), "vor 3 Std.")
    }

    func testTemporalFormatterOutputsNeverJoinNumberDirectlyToUnitLetters() {
        let publishedAt = "2026-09-20T06:00:00Z"
        let published = ISO8601DateFormatter().date(from: publishedAt)!
        let relative = IOSArticleTemporalPresentation.relativePublishedAge(
            publishedAt,
            relativeTo: published.addingTimeInterval(3 * 3_600)
        )
        let reading = try? XCTUnwrap(IOSArticleTemporalPresentation.readingTime(4))

        func hasJoinedNumberAndUnit(_ value: String) -> Bool {
            zip(value, value.dropFirst()).contains { pair in
                pair.0.isNumber && pair.1.isLetter
            }
        }

        XCTAssertFalse(hasJoinedNumberAndUnit(relative))
        if let reading { XCTAssertFalse(hasJoinedNumberAndUnit(reading)) }
    }

    func testArticleTemporalPresentationUsesCoreReadingTime() {
        let article = ArticleSummary(
            id: 77,
            feedId: 10,
            categoryId: 20,
            feedTitle: "Feed",
            title: "Article",
            url: "https://example.com/77",
            commentsUrl: "",
            publishedAt: "2026-09-20T06:00:00Z",
            isRead: false,
            isStarred: false,
            readingTimeMinutes: 4,
            preview: "",
            imageUrl: nil
        )
        let referenceDate = ISO8601DateFormatter().date(from: article.publishedAt)!.addingTimeInterval(3 * 3_600)
        let content = ArticleRowContent(article: article, referenceDate: referenceDate)

        XCTAssertFalse(content.publishedDate.isEmpty)
        XCTAssertEqual(
            content.publishedAge,
            IOSArticleTemporalPresentation.relativePublishedAge(article.publishedAt, relativeTo: referenceDate)
        )
        XCTAssertEqual(content.readingTime, IOSArticleTemporalPresentation.readingTime(4))
        XCTAssertNil(IOSArticleTemporalPresentation.readingTime(0))
    }

    func testArticleTemporalProjectionRefreshesOnlyWithPreparedSnapshotContent() {
        let article = ArticleSummary(
            id: 78,
            feedId: 10,
            categoryId: 20,
            feedTitle: "Feed",
            title: "Article",
            url: "https://example.com/78",
            commentsUrl: "",
            publishedAt: "2026-09-20T06:00:00Z",
            isRead: false,
            isStarred: false,
            readingTimeMinutes: 0,
            preview: "",
            imageUrl: nil
        )
        let publishedDate = ISO8601DateFormatter().date(from: article.publishedAt)!
        let firstReference = publishedDate.addingTimeInterval(3 * 3_600)
        let secondReference = publishedDate.addingTimeInterval(5 * 3_600)
        let first = ArticleRowContent(article: article, referenceDate: firstReference)
        let second = ArticleRowContent(article: article, referenceDate: secondReference)
        let state = ArticleRowPresentationState(article: article, content: first)

        state.reconcile(with: article, content: second)

        XCTAssertEqual(state.content.publishedAge, second.publishedAge)
        XCTAssertNotEqual(first.publishedAge, second.publishedAge)
    }

    @MainActor
    func testTimelinePaginationKeepsOneFrozenRelativeTimeReference() {
        let store = NewsreaderStore(defaults: UserDefaults())
        let first = timelineArticle(id: 101)
        let second = timelineArticle(id: 102)

        store.setArticlesForTesting([first])
        let referenceDate = store.timelineReferenceDateForTesting
        store.appendArticlesForTesting([second])

        let items = store.timelineStructuralState.storage.items
        XCTAssertEqual(items.map(\.article.id), [101, 102])
        XCTAssertEqual(
            items[0].content.publishedAge,
            IOSArticleTemporalPresentation.relativePublishedAge(first.publishedAt, relativeTo: referenceDate)
        )
        XCTAssertEqual(
            items[1].content.publishedAge,
            IOSArticleTemporalPresentation.relativePublishedAge(second.publishedAt, relativeTo: referenceDate)
        )
        XCTAssertEqual(store.timelineReferenceDateForTesting, referenceDate)
    }

    func testEveryArticleLayoutLeadsWithMetadataThenTitleThenPublicationRow() {
        let cases: [(ArticlePresentationMode, CGFloat, Bool, IOSUIKitArticleCellLayoutVariant)] = [
            (.compact, 390, false, .compact),
            (.visual, 390, false, .visualTextOnly),
            (.visual, 390, true, .visualPortrait),
            (.visual, 760, true, .visualLandscape),
            (.visualCompact, 414, true, .visualSideTitle),
            (.visualCompact, 834, true, .visualSideTitleWide),
            (.visualCompact, 414, false, .visualSideTitleTextOnly),
        ]

        for (mode, width, hasImage, expectedVariant) in cases {
            let metrics = layoutMetrics(mode: mode, width: width, hasImage: hasImage, readingTime: "4 min")
            XCTAssertEqual(metrics.variant, expectedVariant)
            XCTAssertLessThan(metrics.metadataFrame.maxY, metrics.titleFrame.minY)
            XCTAssertLessThan(metrics.titleFrame.maxY, metrics.dateFrame.minY)
        }
    }

    func testRelativePublicationTimeUsesLeadingClockWithoutChangingDateRowHeight() {
        let absolute = layoutMetrics(mode: .visual, width: 390, hasImage: true, readingTime: "4 min")
        let relative = layoutMetrics(
            mode: .visual,
            width: 390,
            hasImage: true,
            readingTime: "4 min",
            showsRelativePublicationTime: true
        )

        let icon = try? XCTUnwrap(relative.publicationTimeIconFrame)
        XCTAssertNotNil(icon)
        XCTAssertNil(absolute.publicationTimeIconFrame)
        XCTAssertEqual(relative.dateFrame.height, absolute.dateFrame.height, accuracy: 0.5)
        XCTAssertEqual(relative.cellSize.height, absolute.cellSize.height, accuracy: 0.5)
        if let icon {
            XCTAssertEqual(icon.midY, relative.dateFrame.midY, accuracy: 0.5)
            XCTAssertEqual(
                relative.dateFrame.minX - icon.maxX,
                IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing,
                accuracy: 0.5
            )
        }
    }

    func testVisualPortraitUsesFullWidthImageBeforeMetadataTitleAndDateRow() {
        let metrics = layoutMetrics(mode: .visual, width: 390, hasImage: true, readingTime: "4 min")
        guard
            let image = metrics.imageFrame,
            let readingContainer = metrics.landscapeReadingTimeContainerFrame,
            let readingIcon = metrics.landscapeReadingTimeIconFrame,
            let reading = metrics.landscapeReadingTimeFrame,
            let preview = metrics.previewFrame
        else {
            return XCTFail("Visual portrait should expose full-width image, date-row reading time and preview")
        }

        XCTAssertEqual(metrics.variant, .visualPortrait)
        XCTAssertEqual(image.minX, metrics.contentFrame.minX, accuracy: 0.5)
        XCTAssertEqual(image.width, metrics.contentFrame.width, accuracy: 0.5)
        XCTAssertLessThan(image.maxY, metrics.metadataFrame.minY)
        XCTAssertLessThan(metrics.metadataFrame.maxY, metrics.titleFrame.minY)
        XCTAssertLessThan(metrics.titleFrame.maxY, metrics.dateFrame.minY)
        XCTAssertLessThan(metrics.dateFrame.maxY, preview.minY)
        XCTAssertEqual(readingContainer.minY, metrics.dateFrame.minY, accuracy: 0.5)
        XCTAssertEqual(readingContainer.height, metrics.dateFrame.height, accuracy: 0.5)
        XCTAssertEqual(
            readingContainer.minX - metrics.dateFrame.maxX,
            IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing,
            accuracy: 0.5
        )
        XCTAssertEqual(readingIcon.midY, metrics.dateFrame.midY, accuracy: 0.5)
        XCTAssertEqual(reading.minY, metrics.dateFrame.minY, accuracy: 0.5)
        XCTAssertEqual(reading.height, metrics.dateFrame.height, accuracy: 0.5)
    }

    @MainActor
    func testRelativePublicationTimeUIKitCellMatchesDeterministicGeometryInPortraitAndLandscape() {
        for width in [390 as CGFloat, 760] {
            let item = oracleItem(
                title: "Relative-time UIKit oracle",
                preview: "Preview text below the publication row.",
                hasImage: true,
                hasComments: true,
                readingTimeMinutes: 4
            )
            let cell = configuredOracleCell(
                item: item,
                mode: .visual,
                previewLines: .standard,
                width: width,
                showRelativePublicationTime: true
            )
            let actualHeight = measureUIKitArticleCell(cell, width: width)
            let input = IOSUIKitArticleLayoutInput(
                item: item,
                mode: .visual,
                previewLines: .standard,
                showsRelativePublicationTime: true,
                containerWidth: width,
                displayScale: cell.traitCollection.displayScale,
                contentSizeCategory: .large,
                layoutDirection: .leftToRight
            )
            let expected = IOSUIKitArticleLayoutEngine.metrics(for: input)
            let diagnostics = cell.layoutDiagnosticsForTesting

            XCTAssertEqual(actualHeight, expected.cellSize.height, accuracy: 0.5)
            assertFrameEqual(diagnostics.metadataFrame, expected.metadataFrame)
            assertFrameEqual(diagnostics.titleFrame, expected.titleFrame)
            assertFrameEqual(diagnostics.dateFrame, expected.dateFrame)
            assertOptionalFrameEqual(
                diagnostics.publicationTimeIconFrame,
                expected.publicationTimeIconFrame,
                accuracy: Self.publicationTimeIconFrameAccuracy
            )
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeContainerFrame,
                expected.landscapeReadingTimeContainerFrame
            )
            assertOptionalFrameEqual(diagnostics.previewFrame, expected.previewFrame)
        }
    }

    @MainActor
    func testVisualPortraitUIKitCellMatchesDeterministicGeometry() {
        let item = oracleItem(
            title: "A multiline Visual headline for the full-width portrait layout",
            preview: "Preview text below the date row.",
            hasImage: true,
            hasComments: true,
            readingTimeMinutes: 4
        )
        let cell = configuredOracleCell(item: item, mode: .visual, previewLines: .standard, width: 390)
        let actualHeight = measureUIKitArticleCell(cell, width: 390)
        let input = IOSUIKitArticleLayoutInput(
            item: item,
            mode: .visual,
            previewLines: .standard,
            containerWidth: 390,
            displayScale: cell.traitCollection.displayScale,
            contentSizeCategory: .large,
            layoutDirection: .leftToRight
        )
        let expected = IOSUIKitArticleLayoutEngine.metrics(for: input)
        let diagnostics = cell.layoutDiagnosticsForTesting

        XCTAssertEqual(expected.variant, .visualPortrait)
        XCTAssertEqual(actualHeight, expected.cellSize.height, accuracy: 0.5)
        assertFrameEqual(diagnostics.imageFrame, try! XCTUnwrap(expected.imageFrame))
        assertFrameEqual(diagnostics.metadataFrame, expected.metadataFrame)
        assertFrameEqual(diagnostics.titleFrame, expected.titleFrame)
        assertFrameEqual(diagnostics.dateFrame, expected.dateFrame)
        assertOptionalFrameEqual(diagnostics.landscapeReadingTimeContainerFrame, expected.landscapeReadingTimeContainerFrame)
        assertOptionalFrameEqual(
            diagnostics.landscapeReadingTimeIconFrame,
            expected.landscapeReadingTimeIconFrame,
            accuracy: Self.accessoryFrameAccuracy
        )
        assertOptionalFrameEqual(diagnostics.landscapeReadingTimeFrame, expected.landscapeReadingTimeFrame)
        assertOptionalFrameEqual(diagnostics.previewFrame, expected.previewFrame)
    }

    func testVisualLandscapePlacesReadingTimeInlineAfterDate() {
        let metrics = layoutMetrics(
            mode: .visual,
            width: 760,
            hasImage: true,
            readingTime: "4 min"
        )
        guard
            let container = metrics.landscapeReadingTimeContainerFrame,
            let icon = metrics.landscapeReadingTimeIconFrame,
            let reading = metrics.landscapeReadingTimeFrame
        else {
            return XCTFail("Visual landscape should expose inline reading-time frames")
        }

        XCTAssertEqual(metrics.variant, .visualLandscape)
        XCTAssertEqual(container.minY, metrics.dateFrame.minY, accuracy: 0.5)
        XCTAssertEqual(container.height, metrics.dateFrame.height, accuracy: 0.5)
        XCTAssertEqual(
            container.minX - metrics.dateFrame.maxX,
            IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing,
            accuracy: 0.5
        )
        XCTAssertEqual(icon.midY, metrics.dateFrame.midY, accuracy: 0.5)
        XCTAssertEqual(reading.minY, metrics.dateFrame.minY, accuracy: 0.5)
        XCTAssertEqual(reading.height, metrics.dateFrame.height, accuracy: 0.5)
        XCTAssertEqual(
            reading.minX - icon.maxX,
            IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing,
            accuracy: 0.5
        )
        XCTAssertLessThan(
            container.maxX,
            metrics.textFrame.maxX,
            "Reading time should stay next to the date rather than being pushed to the trailing edge"
        )

        let withoutReadingTime = layoutMetrics(mode: .visual, width: 760, hasImage: true)
        XCTAssertEqual(withoutReadingTime.variant, .visualLandscape)
        XCTAssertNil(withoutReadingTime.landscapeReadingTimeContainerFrame)
        XCTAssertNil(withoutReadingTime.landscapeReadingTimeIconFrame)
        XCTAssertNil(withoutReadingTime.landscapeReadingTimeFrame)
        XCTAssertGreaterThan(withoutReadingTime.dateFrame.width, 0)
        XCTAssertLessThanOrEqual(withoutReadingTime.dateFrame.maxX, withoutReadingTime.textFrame.maxX)
        XCTAssertEqual(withoutReadingTime.cellSize.height, metrics.cellSize.height, accuracy: 0.5)
    }

    func testCompactAndVisualCompactUseInlineReadingTimeWithoutAddingHeight() {
        for (mode, width, hasImage, expectedVariant) in [
            (ArticlePresentationMode.compact, CGFloat(390), false, IOSUIKitArticleCellLayoutVariant.compact),
            (.visualCompact, CGFloat(414), true, .visualSideTitle),
            (.visualCompact, CGFloat(414), false, .visualSideTitleTextOnly),
        ] {
            let withReading = layoutMetrics(
                mode: mode,
                width: width,
                hasImage: hasImage,
                readingTime: "4 min"
            )
            let withoutReading = layoutMetrics(
                mode: mode,
                width: width,
                hasImage: hasImage
            )

            XCTAssertEqual(withReading.variant, expectedVariant)
            XCTAssertGreaterThan(withReading.titleFrame.height, 0)
            guard
                let readingContainer = withReading.landscapeReadingTimeContainerFrame,
                withReading.landscapeReadingTimeIconFrame != nil,
                withReading.landscapeReadingTimeFrame != nil
            else {
                return XCTFail("Date-row reading time should be present for \(expectedVariant)")
            }
            XCTAssertNil(withoutReading.landscapeReadingTimeContainerFrame)
            XCTAssertEqual(withReading.cellSize.height, withoutReading.cellSize.height, accuracy: 0.5)
            XCTAssertEqual(readingContainer.minY, withReading.dateFrame.minY, accuracy: 0.5)
            XCTAssertEqual(readingContainer.height, withReading.dateFrame.height, accuracy: 0.5)
        }
    }

    func testDeterministicArticleLayoutEngineUsesCurrentWidthTransitionsAndPixelRounding() {
        let narrow = layoutMetrics(mode: .visual, width: 401, hasImage: false, scale: 3)
        let wide = layoutMetrics(mode: .visual, width: 402, hasImage: false, scale: 3)
        XCTAssertEqual(narrow.metadataHeight, wide.metadataHeight)
        XCTAssertEqual((narrow.cellSize.height * 3).rounded(), narrow.cellSize.height * 3, accuracy: 0.001)
        XCTAssertEqual(layoutMetrics(mode: .visual, width: 700, hasImage: true).horizontalInset, 16)
        XCTAssertEqual(layoutMetrics(mode: .visual, width: 701, hasImage: true).horizontalInset, 28)
    }

    func testDeterministicArticleLayoutEngineKeyCanonicalizesGeometryIdentity() {
        let input = layoutInput(mode: .visual, width: 390, hasImage: true)
        let key = IOSUIKitArticleLayoutKey(input)
        XCTAssertEqual(key, IOSUIKitArticleLayoutKey(layoutInput(mode: .visual, width: 390.1, hasImage: true)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(layoutInput(mode: .visual, width: 391, hasImage: true)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(layoutInput(mode: .compact, width: 390, hasImage: true)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(.init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: .extraLarge, layoutDirection: input.layoutDirection)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(.init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: .rightToLeft)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(.init(title: "Updated title", feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(.init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: false, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)))
        XCTAssertNotEqual(key, IOSUIKitArticleLayoutKey(.init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: .compact, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)))
    }

    func testLayoutKeyIncludesReadingTimeForEveryRenderedTemporalVariant() {
        let landscape = layoutInput(mode: .visual, width: 760, hasImage: true, readingTime: "4 min")
        let landscapeWithoutReading = IOSUIKitArticleLayoutInput(
            title: landscape.title,
            feedTitle: landscape.feedTitle,
            publishedDate: landscape.publishedDate, readingTime: nil,
            preview: landscape.preview,
            hasImage: landscape.hasImage,
            hasComments: landscape.hasComments,
            mode: landscape.mode,
            previewLines: landscape.previewLines,
            containerWidth: landscape.containerWidth,
            displayScale: landscape.displayScale,
            contentSizeCategory: landscape.contentSizeCategory,
            layoutDirection: landscape.layoutDirection
        )
        XCTAssertNotEqual(
            IOSUIKitArticleLayoutKey(landscape),
            IOSUIKitArticleLayoutKey(landscapeWithoutReading)
        )

        let compact = layoutInput(mode: .compact, width: 390, hasImage: false, readingTime: "4 min")
        let compactWithoutReading = IOSUIKitArticleLayoutInput(
            title: compact.title,
            feedTitle: compact.feedTitle,
            publishedDate: compact.publishedDate, readingTime: nil,
            preview: compact.preview,
            hasImage: compact.hasImage,
            hasComments: compact.hasComments,
            mode: compact.mode,
            previewLines: compact.previewLines,
            containerWidth: compact.containerWidth,
            displayScale: compact.displayScale,
            contentSizeCategory: compact.contentSizeCategory,
            layoutDirection: compact.layoutDirection
        )
        XCTAssertNotEqual(
            IOSUIKitArticleLayoutKey(compact),
            IOSUIKitArticleLayoutKey(compactWithoutReading)
        )
    }

    func testTimelineGeometryIdentityUsesTheDeterministicMeasurementWidth() {
        let input = layoutInput(mode: .visual, width: 390, hasImage: true, scale: 3)
        let samePixels = IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, containerWidth: 390.1, displayScale: 3, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)
        let identity = IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)
        let changedWidth = IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, containerWidth: 390.2, displayScale: 3, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)

        XCTAssertEqual(identity, samePixels)
        XCTAssertNotEqual(identity, changedWidth)
        XCTAssertEqual(identity.containerWidthPixels, IOSUIKitArticleLayoutKey(input).containerWidthPixels)
    }

    func testTimelineGeometryIdentityRekeysEnvironmentInputsWithoutDeviceIdentity() {
        let baseline = IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 3, contentSizeCategory: .large, layoutDirection: .leftToRight)
        XCTAssertNotEqual(baseline, IOSUIKitTimelineGeometryIdentity(mode: .compact, previewLines: .standard, containerWidth: 390, displayScale: 3, contentSizeCategory: .large, layoutDirection: .leftToRight))
        XCTAssertNotEqual(baseline, IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .compact, containerWidth: 390, displayScale: 3, contentSizeCategory: .large, layoutDirection: .leftToRight))
        XCTAssertNotEqual(baseline, IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 3, contentSizeCategory: .extraLarge, layoutDirection: .leftToRight))
        XCTAssertNotEqual(baseline, IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 3, contentSizeCategory: .large, layoutDirection: .rightToLeft))
        XCTAssertNotEqual(baseline, IOSUIKitTimelineGeometryIdentity(mode: .visual, previewLines: .standard, showsRelativePublicationTime: true, containerWidth: 390, displayScale: 3, contentSizeCategory: .large, layoutDirection: .leftToRight))
    }

    @MainActor
    func testPreparedLayoutMetricsReuseCanonicalIdentityAndRekeyLayoutChanges() {
        let cache = IOSUIKitPreparedArticleLayoutMetricsCache(capacity: 4)
        let input = layoutInput(mode: .visual, width: 390, hasImage: true)
        let metrics = IOSUIKitArticleLayoutEngine.metrics(for: input)
        cache.insert(metrics, for: .init(input))
        let mutablePresentationEquivalent = IOSUIKitArticleLayoutInput(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: input.layoutDirection)
        XCTAssertEqual(cache.metrics(for: .init(mutablePresentationEquivalent)), metrics)
        XCTAssertNil(cache.metrics(for: .init(layoutInput(mode: .visual, width: 391, hasImage: true))))
        XCTAssertNil(cache.metrics(for: .init(.init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: .accessibilityExtraExtraExtraLarge, layoutDirection: input.layoutDirection))))
        XCTAssertNil(cache.metrics(for: .init(.init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: .rightToLeft))))
        XCTAssertNil(cache.metrics(for: .init(layoutInput(mode: .compact, width: 390, hasImage: true))))
    }

    @MainActor
    func testPreparedLayoutMetricsCacheHasDeterministicBound() {
        let cache = IOSUIKitPreparedArticleLayoutMetricsCache(capacity: 2)
        let first = layoutInput(mode: .visual, width: 390, hasImage: false)
        let second = IOSUIKitArticleLayoutInput(title: "Second", feedTitle: first.feedTitle, publishedDate: first.publishedDate, readingTime: first.readingTime, preview: first.preview, hasImage: first.hasImage, hasComments: first.hasComments, mode: first.mode, previewLines: first.previewLines, containerWidth: first.containerWidth, displayScale: first.displayScale, contentSizeCategory: first.contentSizeCategory, layoutDirection: first.layoutDirection)
        let third = IOSUIKitArticleLayoutInput(title: "Third", feedTitle: first.feedTitle, publishedDate: first.publishedDate, readingTime: first.readingTime, preview: first.preview, hasImage: first.hasImage, hasComments: first.hasComments, mode: first.mode, previewLines: first.previewLines, containerWidth: first.containerWidth, displayScale: first.displayScale, contentSizeCategory: first.contentSizeCategory, layoutDirection: first.layoutDirection)
        for input in [first, second, third] { cache.insert(IOSUIKitArticleLayoutEngine.metrics(for: input), for: .init(input)) }
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.metrics(for: .init(first)))
        XCTAssertNotNil(cache.metrics(for: .init(second)))
        XCTAssertNotNil(cache.metrics(for: .init(third)))
    }

    @MainActor
    func testSynchronousPreparedLayoutFallbackStoresAndRetiresEquivalentWork() async {
        let gate = LayoutMeasurementGate()
        let cache = IOSUIKitPreparedArticleLayoutMetricsCache(capacity: 8)
        let coordinator = IOSUIKitArticleLayoutPreparationCoordinator(cache: cache, maximumConcurrency: 1) { input in
            await gate.measure(input)
        }
        let input = layoutInput(mode: .visual, width: 390, hasImage: true)
        XCTAssertNil(coordinator.metrics(for: input, priority: .visible))
        await gate.waitUntilStarted(count: 1)

        let fallback = coordinator.measureSynchronously(input, priority: .visible)
        XCTAssertEqual(cache.metrics(for: .init(input)), fallback)
        XCTAssertEqual(coordinator.metrics(for: input, priority: .visible), fallback)
        XCTAssertGreaterThanOrEqual(coordinator.snapshot().cancellations, 1)

        await gate.releaseAll()
        await waitUntil { coordinator.snapshot().discardedResults > 0 }
        XCTAssertEqual(coordinator.snapshot().measurementsCompleted, 0)
    }

    @MainActor
    func testPreparedLayoutWindowIsBoundedAndCoalescesIdenticalKeys() async {
        let gate = LayoutMeasurementGate()
        let coordinator = IOSUIKitArticleLayoutPreparationCoordinator(maximumConcurrency: 2) { input in
            await gate.measure(input)
        }
        let input = layoutInput(mode: .visual, width: 390, hasImage: true)
        coordinator.replaceWindow(with: Array(repeating: input, count: 100), visibleCount: 1)
        await gate.waitUntilStarted(count: 1)
        await gate.releaseAll()
        await waitUntil { coordinator.snapshot().measurementsCompleted > 0 }
        let snapshot = coordinator.snapshot()
        XCTAssertEqual(snapshot.requests, UInt64(IOSUIKitArticleLayoutPreparationCoordinator.nearbyWindowLimit + 1))
        XCTAssertEqual(snapshot.measurementsStarted, 1)
        XCTAssertLessThanOrEqual(snapshot.maximumConcurrentMeasurements, 2)
        XCTAssertEqual(snapshot.measurementsCompleted, 1)
    }

    @MainActor
    func testPreparedLayoutPrioritizesVisibleAndDiscardsReplacedGeneration() async {
        let gate = LayoutMeasurementGate()
        let coordinator = IOSUIKitArticleLayoutPreparationCoordinator(maximumConcurrency: 1) { input in
            await gate.measure(input)
        }
        let far = IOSUIKitArticleLayoutInput(title: "far", feedTitle: "Feed", publishedDate: "Today", preview: "Preview", hasImage: false, hasComments: false, mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 2, contentSizeCategory: .large, layoutDirection: .leftToRight)
        let visible = IOSUIKitArticleLayoutInput(title: "visible", feedTitle: far.feedTitle, publishedDate: far.publishedDate, readingTime: far.readingTime, preview: far.preview, hasImage: far.hasImage, hasComments: far.hasComments, mode: far.mode, previewLines: far.previewLines, containerWidth: far.containerWidth, displayScale: far.displayScale, contentSizeCategory: far.contentSizeCategory, layoutDirection: far.layoutDirection)
        let replacement = IOSUIKitArticleLayoutInput(title: "replacement", feedTitle: far.feedTitle, publishedDate: far.publishedDate, readingTime: far.readingTime, preview: far.preview, hasImage: far.hasImage, hasComments: far.hasComments, mode: far.mode, previewLines: far.previewLines, containerWidth: far.containerWidth, displayScale: far.displayScale, contentSizeCategory: far.contentSizeCategory, layoutDirection: far.layoutDirection)
        coordinator.prepare([far], priority: .prefetch)
        await gate.waitUntilStarted(count: 1)
        coordinator.prepare([visible], priority: .visible)
        await gate.releaseAll()
        await gate.waitUntilStarted(count: 2)
        let startedAfterPriority = await gate.startedTitles()
        XCTAssertEqual(startedAfterPriority, ["far", "visible"])
        coordinator.replaceWindow(with: [replacement], visibleCount: 1)
        await gate.waitUntilStarted(count: 3)
        let startedAfterReplacement = await gate.startedTitles()
        XCTAssertEqual(startedAfterReplacement, ["far", "visible", "replacement"])
        await gate.releaseAll()
        await waitUntil { coordinator.snapshot().discardedResults > 0 }
        await waitUntil { coordinator.snapshot().measurementsCompleted > 0 }
        let snapshot = coordinator.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.cancellations, 1)
        XCTAssertGreaterThanOrEqual(snapshot.discardedResults, 1)
    }

    @MainActor
    func testRapidGeometryPreparationDiscardsSupersededWidthsAndPublishesLatest() async {
        let gate = LayoutMeasurementGate()
        let cache = IOSUIKitPreparedArticleLayoutMetricsCache(capacity: 8)
        let coordinator = IOSUIKitArticleLayoutPreparationCoordinator(cache: cache, maximumConcurrency: 1) { input in
            await gate.measure(input)
        }
        let first = layoutInput(mode: .visual, width: 390, hasImage: true)
        let second = layoutInput(mode: .visual, width: 480, hasImage: true)
        let latest = layoutInput(mode: .visual, width: 600, hasImage: true)

        coordinator.replaceWindow(with: [first], visibleCount: 1)
        await gate.waitUntilStarted(count: 1)
        coordinator.replaceWindow(with: [second], visibleCount: 1)
        coordinator.replaceWindow(with: [latest], visibleCount: 1)

        // Superseded Tasks are cancelled but can still enter the injected
        // measurement closure before observing cancellation. Wait until all
        // three generations have reached the gate before the final release;
        // otherwise releaseAll() can race ahead of the latest generation and
        // leave that fake measurement suspended indefinitely.
        await gate.releaseAll()
        await gate.waitUntilStarted(count: 3)
        await gate.releaseAll()
        await waitUntil { coordinator.snapshot().measurementsCompleted > 0 }

        XCTAssertNil(cache.metrics(for: .init(first)))
        XCTAssertNil(cache.metrics(for: .init(second)))
        XCTAssertNotNil(cache.metrics(for: .init(latest)))
        XCTAssertGreaterThanOrEqual(coordinator.snapshot().discardedResults, 1)
    }

    @MainActor
    func testCoreTextUIKitMetricDiagnostics() {
        let fixtures = [
            ("title-one", "Short title", UIFont.preferredFont(forTextStyle: .headline), 358 as CGFloat, 0),
            ("title-multi", "A deliberately multiline article title for Core Text diagnostics that wraps across the current iPhone width.", UIFont.preferredFont(forTextStyle: .headline), 358 as CGFloat, 0),
            ("preview-three", String(repeating: "A preview line measures UIKit and Core Text semantics. ", count: 8), UIFont.preferredFont(forTextStyle: .subheadline), 358 as CGFloat, 3),
        ]
        for fixture in fixtures {
            let font = fixture.2
            let ctFont = font as CTFont
            let label = UILabel()
            label.font = font
            label.numberOfLines = fixture.4
            label.lineBreakMode = .byWordWrapping
            label.text = fixture.1
            let fitted = label.sizeThatFits(.init(width: fixture.3, height: .greatestFiniteMagnitude))
            let intrinsic = label.intrinsicContentSize
            let text = NSAttributedString(string: fixture.1, attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont])
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            var index = 0
            var lines: [String] = []
            while index < text.length, fixture.4 == 0 || lines.count < fixture.4 {
                let count = CTTypesetterSuggestLineBreak(typesetter, index, Double(fixture.3))
                guard count > 0 else { break }
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: index, length: count))
                var ascent: CGFloat = 0; var descent: CGFloat = 0; var leading: CGFloat = 0
                let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                lines.append(String(format: "line=%d range=%d,%d width=%.6f ascent=%.6f descent=%.6f leading=%.6f", lines.count, index, count, width, ascent, descent, leading))
                index += count
            }
            let frameSize = CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: index), nil, .init(width: fixture.3, height: .greatestFiniteMagnitude), nil)
            print(String(format: "[Text metrics] %@ font=%@ size=%.6f asc=%.6f desc=%.6f lead=%.6f line=%.6f cap=%.6f x=%.6f ctPostScript=%@ ctSize=%.6f ctAsc=%.6f ctDesc=%.6f ctLead=%.6f labelFit=(%.6f,%.6f) intrinsic=(%.6f,%.6f) frame=(%.6f,%.6f) lines=%@", fixture.0, font.fontName, font.pointSize, font.ascender, font.descender, font.leading, font.lineHeight, font.capHeight, font.xHeight, CTFontCopyPostScriptName(ctFont) as String, CTFontGetSize(ctFont), CTFontGetAscent(ctFont), CTFontGetDescent(ctFont), CTFontGetLeading(ctFont), fitted.width, fitted.height, intrinsic.width, intrinsic.height, frameSize.width, frameSize.height, lines.joined(separator: " | ")))
        }
    }

    @MainActor
    func testCoreTextUIKitCompatibleHeightMatrix() {
        let categories: [UIContentSizeCategory] = [.large, .extraExtraLarge, .accessibilityExtraExtraExtraLarge]
        let fixtures: [(String, String, UIFont.TextStyle, Int, CGFloat)] = [
            ("title-one", "Short title", .headline, 0, 358),
            ("title-multi", String(repeating: "A title that wraps using production UIKit font metrics. ", count: 4), .headline, 0, 358),
            ("preview-two", String(repeating: "A preview line wraps with bounded Core Text counting. ", count: 8), .subheadline, 2, 358),
            ("preview-three", String(repeating: "A preview line wraps with bounded Core Text counting. ", count: 8), .subheadline, 3, 358),
            ("preview-five", String(repeating: "A preview line wraps with bounded Core Text counting. ", count: 12), .subheadline, 5, 358),
        ]
        for category in categories {
            let trait = UITraitCollection(preferredContentSizeCategory: category)
            for fixture in fixtures {
                let font = UIFont.preferredFont(forTextStyle: fixture.2, compatibleWith: trait)
                let text = NSAttributedString(string: fixture.1, attributes: [kCTFontAttributeName as NSAttributedString.Key: font as CTFont])
                let typesetter = CTTypesetterCreateWithAttributedString(text)
                var index = 0
                var lineCount = 0
                while index < text.length, fixture.3 == 0 || lineCount < fixture.3 {
                    let count = CTTypesetterSuggestLineBreak(typesetter, index, Double(fixture.4))
                    guard count > 0 else { break }
                    index += count
                    lineCount += 1
                }
                for scale in [2 as CGFloat, 3] {
                    let scaleTrait = trait.modifyingTraits { mutableTraits in
                        mutableTraits.displayScale = scale
                    }
                    var fitted = CGSize.zero
                    scaleTrait.performAsCurrent {
                        let label = UILabel()
                        label.font = font
                        label.numberOfLines = fixture.3
                        label.lineBreakMode = .byWordWrapping
                        label.text = fixture.1
                        fitted = label.sizeThatFits(.init(width: fixture.4, height: .greatestFiniteMagnitude))
                    }
                    let raw = CGFloat(lineCount) * font.lineHeight + CGFloat(max(0, lineCount - 1)) * font.leading
                    let predicted = ceil(raw * scale) / scale
                    let actualScale = 3 as CGFloat // UILabel sizing follows the simulator display, not a synthetic trait scale.
                    let actualPrediction = ceil(raw * actualScale) / actualScale
                    XCTAssertEqual(fitted.height, actualPrediction, accuracy: 0.001, "\(category.rawValue) \(fixture.0) @\(actualScale)x")
                    print(String(format: "[Text matrix] category=%@ fixture=%@ requestedScale=%.0f point=%.6f line=%.6f leading=%.6f lines=%d raw=%.6f predicted=%.6f actualLabelScale=%.0f actual=%.6f delta=%.6f", category.rawValue, fixture.0, scale, font.pointSize, font.lineHeight, font.leading, lineCount, raw, predicted, actualScale, fitted.height, fitted.height - actualPrediction))
                }
            }
        }
    }

    @MainActor
    func testArticleLayoutKeyExcludesMutablePresentationState() {
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: true)
        let updated = IOSUIKitArticleTimelineItem(article: item.article, content: item.content, isRead: true, isStarred: true, feedIconImage: testImage(width: 80, height: 20))
        let input = IOSUIKitArticleLayoutInput(item: item, mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 2, contentSizeCategory: .large, layoutDirection: .leftToRight)
        let updatedInput = IOSUIKitArticleLayoutInput(item: updated, mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 2, contentSizeCategory: .large, layoutDirection: .leftToRight)
        XCTAssertEqual(IOSUIKitArticleLayoutKey(input), IOSUIKitArticleLayoutKey(updatedInput))
    }

    @MainActor
    func testDeterministicArticleLayoutEngineMatchesUIKitCellOracle() {
        let titles = [
            "Short title",
            "A deliberately multiline article title that exercises the exact bounded text measurement used by the production UIKit cell.",
            "Emoji headline \u{1F680} with Arabic \u{0645}\u{0631}\u{062D}\u{0628}\u{0627} and Japanese \u{65E5}\u{672C}\u{8A9E}",
        ]
        let previews = ["", "Short preview", String(repeating: "A longer preview exercises bounded UIKit text wrapping. ", count: 8)]
        let cases: [(ArticlePresentationMode, CGFloat, Bool, ArticlePreviewLines)] = [
            (.compact, 320, false, .standard),
            (.compact, 390, true, .compact),
            (.visual, 390, false, .standard),
            (.visual, 430, false, .standard),
            (.visual, 390, true, .extended),
            (.visual, 760, true, .standard),
            (.visual, 401, false, .standard),
            (.visual, 402, false, .standard),
            (.visual, 700, true, .standard),
            (.visual, 701, true, .standard),
            (.visualCompact, 414, true, .standard),
            (.visualCompact, 414, false, .standard),
        ]
        for (index, testCase) in cases.enumerated() {
            let item = oracleItem(
                title: titles[index % titles.count],
                preview: previews[index % previews.count],
                hasImage: testCase.2,
                hasComments: index.isMultiple(of: 2),
                readingTimeMinutes: [0, 4, 5, 10, 11].contains(index) ? 4 : 0
            )
            let cell = configuredOracleCell(item: item, mode: testCase.0, previewLines: testCase.3, width: testCase.1)
            let actual = measureUIKitArticleCell(cell, width: testCase.1)
            let input = IOSUIKitArticleLayoutInput(item: item, mode: testCase.0, previewLines: testCase.3, containerWidth: testCase.1, displayScale: cell.traitCollection.displayScale, contentSizeCategory: .large, layoutDirection: .leftToRight)
            let expected = IOSUIKitArticleLayoutEngine.metrics(for: input)
            let diagnostics = cell.layoutDiagnosticsForTesting
            XCTAssertEqual(actual, expected.cellSize.height, accuracy: 0.5, "case \(index) variant \(expected.variant) cell=\(diagnostics) engine title=\(expected.titleFrame) metadata=\(expected.metadataFrame) preview=\(String(describing: expected.previewFrame)) image=\(String(describing: expected.imageFrame))")
            assertFrameEqual(diagnostics.titleFrame, expected.titleFrame)
            assertFrameEqual(diagnostics.metadataFrame, expected.metadataFrame)
            assertFrameEqual(diagnostics.unreadFrame, expected.unreadFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.feedIconFrame, expected.feedIconFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.feedTitleFrame, expected.feedTitleFrame)
            assertOptionalFrameEqual(diagnostics.commentsFrame, expected.commentsFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.starFrame, expected.starFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.dateFrame, expected.dateFrame)
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeContainerFrame,
                expected.landscapeReadingTimeContainerFrame
            )
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeIconFrame,
                expected.landscapeReadingTimeIconFrame,
                accuracy: Self.accessoryFrameAccuracy
            )
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeFrame,
                expected.landscapeReadingTimeFrame
            )
            assertOptionalFrameEqual(diagnostics.previewFrame, expected.previewFrame)
        }
    }

    @MainActor
    func testDeterministicArticleLayoutEngineMatchesUIKitCellOracleInRightToLeft() {
        let cases: [(ArticlePresentationMode, CGFloat, Bool, Bool, String)] = [
            (.visual, 390, false, false, "Oracle Feed"),
            (.visual, 390, true, true, "Oracle Feed"),
            (.visual, 390, false, false, String(repeating: "An exceptionally long feed title ", count: 12)),
            (.compact, 320, false, true, "Oracle Feed"),
            (.visual, 760, true, true, "Oracle Feed"),
        ]
        for (index, testCase) in cases.enumerated() {
            let item = oracleItem(title: "A deliberately multiline article title for RTL component geometry.", preview: "A preview long enough to exercise the complete text stack.", hasImage: testCase.2, hasComments: testCase.3, feedTitle: testCase.4)
            let cell = configuredOracleCell(item: item, mode: testCase.0, previewLines: .standard, width: testCase.1, layoutDirection: .rightToLeft)
            let actual = measureUIKitArticleCell(cell, width: testCase.1)
            let input = IOSUIKitArticleLayoutInput(item: item, mode: testCase.0, previewLines: .standard, containerWidth: testCase.1, displayScale: cell.traitCollection.displayScale, contentSizeCategory: .large, layoutDirection: .rightToLeft)
            let expected = IOSUIKitArticleLayoutEngine.metrics(for: input)
            let ltr = IOSUIKitArticleLayoutEngine.metrics(for: .init(title: input.title, feedTitle: input.feedTitle, publishedDate: input.publishedDate, readingTime: input.readingTime, preview: input.preview, hasImage: input.hasImage, hasComments: input.hasComments, mode: input.mode, previewLines: input.previewLines, containerWidth: input.containerWidth, displayScale: input.displayScale, contentSizeCategory: input.contentSizeCategory, layoutDirection: .leftToRight))
            let diagnostics = cell.layoutDiagnosticsForTesting
            XCTAssertEqual(actual, expected.cellSize.height, accuracy: 0.5, "RTL case \(index) cell=\(diagnostics)")
            XCTAssertEqual(expected.cellSize.height, ltr.cellSize.height, accuracy: 0.001)
            assertFrameEqual(diagnostics.titleFrame, expected.titleFrame)
            assertFrameEqual(diagnostics.metadataFrame, expected.metadataFrame)
            assertFrameEqual(diagnostics.unreadFrame, expected.unreadFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.feedIconFrame, expected.feedIconFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.feedTitleFrame, expected.feedTitleFrame)
            assertOptionalFrameEqual(diagnostics.commentsFrame, expected.commentsFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.starFrame, expected.starFrame, accuracy: Self.accessoryFrameAccuracy)
            assertFrameEqual(diagnostics.dateFrame, expected.dateFrame)
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeContainerFrame,
                expected.landscapeReadingTimeContainerFrame
            )
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeIconFrame,
                expected.landscapeReadingTimeIconFrame,
                accuracy: Self.accessoryFrameAccuracy
            )
            assertOptionalFrameEqual(
                diagnostics.landscapeReadingTimeFrame,
                expected.landscapeReadingTimeFrame
            )
            assertOptionalFrameEqual(diagnostics.previewFrame, expected.previewFrame)
        }
    }

    @MainActor
    func testUIKitMetadataMutablePresentationUpdatesAreGeometryNeutral() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 390)
        let baselineHeight = measureUIKitArticleCell(cell, width: 390)
        let baseline = cell.layoutDiagnosticsForTesting

        cell.updateStatus(isRead: true, isStarred: true)
        cell.updateFeedIcon(image: testImage(width: 80, height: 20), title: "Feed")
        XCTAssertEqual(measureUIKitArticleCell(cell, width: 390), baselineHeight, accuracy: 0.5)
        let updated = cell.layoutDiagnosticsForTesting
        assertFrameEqual(updated.titleFrame, baseline.titleFrame)
        assertFrameEqual(updated.metadataFrame, baseline.metadataFrame)
        assertFrameEqual(updated.unreadFrame, baseline.unreadFrame)
        assertFrameEqual(updated.feedIconFrame, baseline.feedIconFrame)
        assertFrameEqual(updated.feedTitleFrame, baseline.feedTitleFrame)
        assertFrameEqual(updated.starFrame, baseline.starFrame)
        assertFrameEqual(updated.dateFrame, baseline.dateFrame)
    }

    @MainActor
    func testUIKitMetadataMutablePresentationUpdatesAreGeometryNeutralInRightToLeft() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 390, layoutDirection: .rightToLeft)
        let baselineHeight = measureUIKitArticleCell(cell, width: 390)
        let baseline = cell.layoutDiagnosticsForTesting

        cell.updateStatus(isRead: true, isStarred: true)
        cell.updateFeedIcon(image: testImage(width: 80, height: 20), title: "Feed")
        XCTAssertEqual(measureUIKitArticleCell(cell, width: 390), baselineHeight, accuracy: 0.5)
        let updated = cell.layoutDiagnosticsForTesting
        assertFrameEqual(updated.unreadFrame, baseline.unreadFrame)
        assertFrameEqual(updated.feedIconFrame, baseline.feedIconFrame)
        assertFrameEqual(updated.feedTitleFrame, baseline.feedTitleFrame)
        assertFrameEqual(updated.starFrame, baseline.starFrame)
    }

    @MainActor
    func testUIKitMetadataCommentsUseFixedAccessorySlotAndLongFeedTitleTruncates() {
        let title = String(repeating: "An exceptionally long feed title ", count: 12)
        let withoutComments = oracleItem(title: "Title", preview: "", hasImage: false, hasComments: false, feedTitle: title)
        let withComments = oracleItem(title: "Title", preview: "", hasImage: false, hasComments: true, feedTitle: title)
        let withoutCell = configuredOracleCell(item: withoutComments, mode: .visual, previewLines: .standard, width: 390)
        let withCell = configuredOracleCell(item: withComments, mode: .visual, previewLines: .standard, width: 390)
        let withoutHeight = measureUIKitArticleCell(withoutCell, width: 390)
        let withHeight = measureUIKitArticleCell(withCell, width: 390)
        let without = withoutCell.layoutDiagnosticsForTesting
        let with = withCell.layoutDiagnosticsForTesting

        XCTAssertEqual(withoutHeight, withHeight, accuracy: 0.5)
        XCTAssertEqual(with.metadataFrame.height, without.metadataFrame.height, accuracy: 0.5)
        assertFrameEqual(with.starFrame, without.starFrame)
        XCTAssertNotNil(with.commentsFrame)
        XCTAssertNil(without.commentsFrame)
        XCTAssertEqual(with.commentsFrame!.width, IOSUIKitArticleGeometry.commentSlotSize, accuracy: 0.5)
        XCTAssertEqual(without.feedTitleFrame.width - with.feedTitleFrame.width, IOSUIKitArticleGeometry.commentSlotSize + IOSUIKitArticleGeometry.metadataAccessorySpacing, accuracy: 0.5)
        XCTAssertEqual(without.feedTitleFrame.height, without.metadataFrame.height, accuracy: 0.5)
        XCTAssertEqual(withoutCell.feedTitlePresentationForTesting.lineCount, 1)
        XCTAssertEqual(withoutCell.feedTitlePresentationForTesting.lineBreakMode, .byTruncatingTail)
    }

    @MainActor
    func testUIKitPortraitAspectFrameResolutionDiagnostics() {
        // These widths deliberately span distinct 16:9 physical-pixel residues.
        var floorMatches = 0; var nearestMatches = 0; var ceilMatches = 0
        for width in [386 as CGFloat, 387, 388, 389, 390, 391, 392, 393, 394, 395] {
            let item = oracleItem(title: "Short", preview: "", hasImage: true, hasComments: false)
            let cell = configuredOracleCell(item: item, mode: .visual, previewLines: .standard, width: width)
            _ = measureUIKitArticleCell(cell, width: width)
            let diagnostics = cell.portraitAspectConstraintDiagnosticsForTesting
            let imageWidth = diagnostics.imageFrame.width
            let exactHeight = imageWidth * 9 / 16
            let scale = diagnostics.displayScale
            let exactPixels = exactHeight * scale
            let resolvedPixels = diagnostics.imageFrame.height * scale
            let floorPixels = floor(exactPixels)
            let nearestPixels = exactPixels.rounded()
            let ceilPixels = ceil(exactPixels)
            floorMatches += resolvedPixels == floorPixels ? 1 : 0
            nearestMatches += resolvedPixels == nearestPixels ? 1 : 0
            ceilMatches += resolvedPixels == ceilPixels ? 1 : 0
            let frame = diagnostics.imageFrame
            print(String(format: "[Portrait aspect] container=%.6f x=[%.6f,%.6f] width=%.6f y=[%.6f,%.6f] height=%.6f scale=%.6f exactHeight=%.9f exactPx=%.9f residue=%.9f resolvedPx=%.6f floor=%.0f nearest=%.0f ceil=%.0f", width, frame.minX, frame.maxX, frame.width, frame.minY, frame.maxY, frame.height, scale, exactHeight, exactPixels, exactPixels - floorPixels, resolvedPixels, floorPixels, nearestPixels, ceilPixels))
            XCTAssertEqual(diagnostics.multiplier, 9 / 16, accuracy: .ulpOfOne * 8)
            XCTAssertEqual(diagnostics.imageFrame.height * scale, (diagnostics.imageFrame.height * scale).rounded(), accuracy: 0.000_001, "width=\(width) exact=\(exactHeight) frame=\(diagnostics.imageFrame) scale=\(scale) px=\(diagnostics.imageFrame.height * scale)")
            XCTAssertEqual(resolvedPixels, nearestPixels, accuracy: 0.000_001, "width=\(width)")
        }
        print("[Portrait aspect] matches floor=\(floorMatches)/10 nearest=\(nearestMatches)/10 ceil=\(ceilMatches)/10")
        XCTAssertEqual(nearestMatches, 10)
    }

    private func layoutMetrics(
        mode: ArticlePresentationMode,
        width: CGFloat,
        hasImage: Bool,
        scale: CGFloat = 2,
        readingTime: String? = nil,
        showsRelativePublicationTime: Bool = false
    ) -> IOSUIKitArticleLayoutMetrics {
        IOSUIKitArticleLayoutEngine.metrics(
            for: layoutInput(
                mode: mode,
                width: width,
                hasImage: hasImage,
                scale: scale,
                readingTime: readingTime,
                showsRelativePublicationTime: showsRelativePublicationTime
            )
        )
    }

    private func assertFrameEqual(_ actual: CGRect, _ expected: CGRect, accuracy: CGFloat = 0.5, file: StaticString = #filePath, line: UInt = #line) {
        let message = "actual=\(actual) expected=\(expected)"
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, message, file: file, line: line)
    }

    private func assertOptionalFrameEqual(_ actual: CGRect?, _ expected: CGRect?, accuracy: CGFloat = 0.5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual == nil, expected == nil, file: file, line: line)
        if let actual, let expected { assertFrameEqual(actual, expected, accuracy: accuracy, file: file, line: line) }
    }

    /// UIKit snaps a view's frame to the display grid. A centred view whose
    /// height is an odd number of device pixels — the 17 pt star and comment
    /// slots are 51 px at 3x — cannot sit centred *and* pixel-aligned, so UIKit
    /// widens the frame by one pixel and shifts an edge. The rule is
    /// undocumented and version-dependent: it resolved differently on iOS 26.5
    /// than on 27.
    ///
    /// The engine owns the logical geometry; reproducing that snapping would be
    /// a second implementation of an unpublished UIKit rule. This tolerance
    /// absorbs one grid step for decorative accessories only — cell height and
    /// every text frame stay at 0.5 pt.
    private static let accessoryFrameAccuracy: CGFloat = 1.0
    /// SF Symbol alignment-rect insets for `clock.arrow.circlepath` differ
    /// slightly across iOS runtimes even though the Auto Layout slot remains
    /// unchanged. Keep this tolerance specific to that decorative symbol.
    private static let publicationTimeIconFrameAccuracy: CGFloat = 1.5

    private func layoutInput(
        mode: ArticlePresentationMode,
        width: CGFloat,
        hasImage: Bool,
        scale: CGFloat = 2,
        readingTime: String? = nil,
        showsRelativePublicationTime: Bool = false
    ) -> IOSUIKitArticleLayoutInput {
        .init(
            title: "A deliberately multiline article title that exercises deterministic bounded text measurement",
            feedTitle: "A feed title",
            publishedDate: showsRelativePublicationTime ? "3 hr. ago" : "January 1",
            showsRelativePublicationTime: showsRelativePublicationTime,
            readingTime: readingTime,
            preview: "A preview long enough to occupy multiple lines and preserve the production card text stack.",
            hasImage: hasImage,
            hasComments: true,
            mode: mode,
            previewLines: .standard,
            containerWidth: width,
            displayScale: scale,
            contentSizeCategory: .large,
            layoutDirection: .leftToRight
        )
    }

    @MainActor
    private func oracleItem(title: String, preview: String, hasImage: Bool, hasComments: Bool, feedTitle: String = "Oracle Feed", articleID: Int64 = 91, imageURL: String? = nil, readingTimeMinutes: UInt32 = 0) -> IOSUIKitArticleTimelineItem {
        let article = ArticleSummary(id: articleID, feedId: 10, categoryId: 20, feedTitle: feedTitle, title: title, url: "https://example.com/article", commentsUrl: hasComments ? "https://example.com/comments" : "", publishedAt: "2026-01-01T00:00:00Z", isRead: false, isStarred: false, readingTimeMinutes: readingTimeMinutes, preview: preview, imageUrl: hasImage ? (imageURL ?? "https://example.com/image.jpg") : nil)
        return .init(article: article, content: .init(article: article), isRead: false, isStarred: false, feedIconImage: nil)
    }

    @MainActor
    private func configuredArticleImageTestCell(item: IOSUIKitArticleTimelineItem, pipeline: ArticleImagePipeline, mode: ArticlePresentationMode = .visual, displayScale: CGFloat = 3, rasterScale: CGFloat? = nil) -> IOSUIKitArticleCell {
        let cell = IOSUIKitArticleCell(frame: CGRect(x: 0, y: 0, width: 390, height: 1_000))
        cell.setArticleImagePipelineForTesting(pipeline)
        cell.articleImageRasterScale = { _ in rasterScale ?? displayScale }
        let input = IOSUIKitArticleLayoutInput(item: item, mode: mode, previewLines: .standard, containerWidth: 390, displayScale: displayScale, contentSizeCategory: .large, layoutDirection: .leftToRight)
        cell.configure(item: item, mode: mode, previewLines: .standard, displayScale: displayScale, preparedLayoutMetrics: IOSUIKitArticleLayoutEngine.metrics(for: input))
        return cell
    }

    /// `Task.yield()` only reschedules on the current executor, so a bounded
    /// yield loop races work that runs elsewhere — it passed most of the time and
    /// failed under load. This waits on the condition in real time instead.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor
    private func waitForArticleImagePresentation(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor
    private func configuredOracleCell(
        item: IOSUIKitArticleTimelineItem,
        mode: ArticlePresentationMode,
        previewLines: ArticlePreviewLines,
        width: CGFloat,
        layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight,
        rasterScale: CGFloat? = nil,
        showRelativePublicationTime: Bool = false
    ) -> IOSUIKitArticleCell {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1_000))
        let cell = IOSUIKitArticleCell(frame: CGRect(x: 0, y: 0, width: width, height: 1_000))
        cell.setArticleImagePipelineForTesting(ArticleImagePipeline { _ in throw CancellationError() })
        cell.articleImageRasterScale = { displayScale in rasterScale ?? displayScale }
        let semanticAttribute: UISemanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        container.semanticContentAttribute = semanticAttribute
        cell.semanticContentAttribute = semanticAttribute
        cell.contentView.semanticContentAttribute = semanticAttribute
        container.addSubview(cell)
        let displayScale = cell.traitCollection.displayScale
        let input = IOSUIKitArticleLayoutInput(
            item: item,
            mode: mode,
            previewLines: previewLines,
            showsRelativePublicationTime: showRelativePublicationTime,
            containerWidth: width,
            displayScale: displayScale,
            contentSizeCategory: .large,
            layoutDirection: layoutDirection
        )
        cell.configure(
            item: item,
            mode: mode,
            previewLines: previewLines,
            showRelativePublicationTime: showRelativePublicationTime,
            displayScale: displayScale,
            preparedLayoutMetrics: IOSUIKitArticleLayoutEngine.metrics(for: input)
        )
        container.layoutIfNeeded()
        return cell
    }

    @MainActor
    private func makeUIKitArticleCell(
        mode: ArticlePresentationMode,
        width: CGFloat,
        articleID: Int64 = 1,
        feedID: Int64 = 10,
        hasImage: Bool = true,
        layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight
    ) -> IOSUIKitArticleCell {
        let article = ArticleSummary(
            id: articleID,
            feedId: feedID,
            categoryId: 20,
            feedTitle: "Feed \(feedID)",
            title: "A deliberately multiline article title that exercises the real UIKit sizing path",
            url: "https://example.com/article",
            commentsUrl: "https://example.com/comments",
            publishedAt: "2026-01-01T00:00:00Z",
            isRead: false,
            isStarred: false, readingTimeMinutes: 0, preview: "A preview long enough to occupy multiple lines and preserve the production card text stack.",
            imageUrl: hasImage ? "https://example.com/image.jpg" : nil
        )
        let item = IOSUIKitArticleTimelineItem(
            article: article,
            content: ArticleRowContent(article: article),
            isRead: false,
            isStarred: false,
            feedIconImage: nil
        )
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1_000))
        let cell = IOSUIKitArticleCell(frame: CGRect(x: 0, y: 0, width: width, height: 1_000))
        cell.setArticleImagePipelineForTesting(ArticleImagePipeline { _ in throw CancellationError() })
        let semanticAttribute: UISemanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        container.semanticContentAttribute = semanticAttribute
        cell.semanticContentAttribute = semanticAttribute
        cell.contentView.semanticContentAttribute = semanticAttribute
        container.addSubview(cell)
        let displayScale = cell.traitCollection.displayScale
        let input = IOSUIKitArticleLayoutInput(item: item, mode: mode, previewLines: .standard, containerWidth: width, displayScale: displayScale, contentSizeCategory: .large, layoutDirection: layoutDirection)
        cell.configure(
            item: item,
            mode: mode,
            previewLines: .standard,
            displayScale: displayScale,
            preparedLayoutMetrics: IOSUIKitArticleLayoutEngine.metrics(for: input)
        )
        container.layoutIfNeeded()
        return cell
    }

    /// The cell no longer resolves its own size — the table asks the controller,
    /// which asks the engine. The oracle therefore measures what the cell's own
    /// constraints would produce and asserts the engine agrees with it. That is
    /// the independent cross-check: if the two ever diverge, rows are laid out at
    /// a height their content does not fit.
    /// The reason the text column is a plain container instead of a
    /// `UIStackView`: setting `isHidden` on an arranged subview makes the stack
    /// add and remove constraints, and `previewLabel.isHidden` is set on every
    /// `configure`. Reuse must not touch the constraint graph at all.
    @MainActor
    func testReconfiguringBetweenArticlesWithAndWithoutPreviewLeavesTheConstraintGraphUnchanged() {
        let cell = IOSUIKitArticleCell(frame: CGRect(x: 0, y: 0, width: 390, height: 1_000))
        cell.setArticleImagePipelineForTesting(ArticleImagePipeline { _ in throw CancellationError() })

        func configure(preview: String) {
            let item = oracleItem(title: "Oracle title", preview: preview, hasImage: false, hasComments: false)
            let input = IOSUIKitArticleLayoutInput(item: item, mode: .visual, previewLines: .standard, containerWidth: 390, displayScale: 3, contentSizeCategory: .large, layoutDirection: .leftToRight)
            cell.configure(item: item, mode: .visual, previewLines: .standard, displayScale: 3, preparedLayoutMetrics: IOSUIKitArticleLayoutEngine.metrics(for: input))
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
        }

        configure(preview: "A preview that occupies the collapsible row.")
        let baseline = totalConstraintCount(cell.contentView)
        XCTAssertGreaterThan(baseline, 0)

        configure(preview: "")
        XCTAssertEqual(totalConstraintCount(cell.contentView), baseline)
        XCTAssertNil(cell.layoutDiagnosticsForTesting.previewFrame)

        configure(preview: "And back to a populated preview.")
        XCTAssertEqual(totalConstraintCount(cell.contentView), baseline)
        XCTAssertNotNil(cell.layoutDiagnosticsForTesting.previewFrame)
    }

    @MainActor
    private func totalConstraintCount(_ view: UIView) -> Int {
        view.constraints.count + view.subviews.reduce(0) { $0 + totalConstraintCount($1) }
    }

    /// A device measurement found 366 synchronous height fallbacks in one
    /// session: the first snapshot arrives before the view has a width, so it
    /// used to be published with no heights at all and the table measured every
    /// visible row while laying out. Exactly the path the height store exists to
    /// avoid.
    @MainActor
    func testFirstSnapshotBeforeLayoutNeverMeasuresHeightsSynchronously() async {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        let articles = (1...30).map { timelineArticle(id: Int64($0)) }
        bridge.replaceArticleStates(Dictionary(uniqueKeysWithValues: articles.map { ($0.id, .init(isRead: false, isStarred: false, revision: 0)) }))

        // No frame yet: this is the order SwiftUI uses on first presentation.
        controller.update(
            structuralState: timelineStructuralState(articles, revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        XCTAssertEqual(controller.tableViewForTesting.numberOfSections, 0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        await controller.settleForTesting()
        controller.tableViewForTesting.layoutIfNeeded()

        XCTAssertEqual(controller.synchronousRowHeightFallbackCountForTesting, 0)
        XCTAssertEqual(controller.preparedRowHeightCountForTesting, articles.count)
        XCTAssertEqual(controller.tableViewForTesting.numberOfRows(inSection: 0), articles.count)
    }


    /// A cached image is set before the cell is displayed, so fading it would
    /// add an animation to every appearing row. Late arrivals fade only while
    /// the timeline is idle; during active movement pixels still appear
    /// immediately but without the Core Animation transition.
    @MainActor
    func testWarmCacheArticleImageUsesFramePacingWhileScrollingButRemainsImmediateWhenIdle() async throws {
        let scheduler = IOSArticleImagePresentationScheduler.shared
        scheduler.setScrolling(false)
        scheduler.resetMetrics()

        let data = try imageData(width: 1_200, height: 700)
        let pipeline = ArticleImagePipeline { _ in data }
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: false)
        let geometry = IOSUIKitArticleGeometry(mode: .visual, containerWidth: 390)
        let request = ArticleImageRequest(
            url: try XCTUnwrap(item.content.imageURL),
            targetSize: geometry.imageSize(hasImage: true),
            displayScale: 3,
            rasterScale: 3
        )
        _ = try await pipeline.prefetch(request)

        scheduler.setScrolling(true)
        let scrollingCell = configuredArticleImageTestCell(item: item, pipeline: pipeline)

        XCTAssertNil(scrollingCell.articleImageForTesting)
        XCTAssertFalse(scrollingCell.articleImagePresentationForTesting.placeholderHidden)
        XCTAssertEqual(scheduler.metrics().queued, 1)

        scheduler.setScrolling(false)

        XCTAssertNotNil(scrollingCell.articleImageForTesting)
        XCTAssertTrue(scrollingCell.articleImagePresentationForTesting.placeholderHidden)

        scheduler.resetMetrics()
        let idleCell = configuredArticleImageTestCell(item: item, pipeline: pipeline)

        XCTAssertNotNil(idleCell.articleImageForTesting)
        XCTAssertTrue(idleCell.articleImagePresentationForTesting.placeholderHidden)
        XCTAssertEqual(scheduler.metrics().queued, 0)
    }

    @MainActor
    func testLateArrivingArticleImagesFadeOnlyWhenEnabled() async throws {
        let data = try imageData(width: 1_200, height: 700)
        let item = oracleItem(title: "Title", preview: "Preview", hasImage: true, hasComments: false)

        let idleCounter = ImageLoadCounter(data: data)
        let idlePipeline = ArticleImagePipeline { _ in await idleCounter.load() }
        let idleArrival = configuredArticleImageTestCell(item: item, pipeline: idlePipeline)
        await waitForArticleImagePresentation { idleArrival.articleImageForTesting != nil }
        XCTAssertEqual(idleArrival.articleImageFadeCountForTesting, 1)

        let scrollingCounter = ImageLoadCounter(data: data)
        let scrollingPipeline = ArticleImagePipeline { _ in await scrollingCounter.load() }
        let scrollingArrival = configuredArticleImageTestCell(item: item, pipeline: scrollingPipeline)
        scrollingArrival.setArticleImageArrivalAnimationsEnabled(false)
        await waitForArticleImagePresentation { scrollingArrival.articleImageForTesting != nil }
        XCTAssertNotNil(scrollingArrival.articleImageForTesting)
        XCTAssertEqual(scrollingArrival.articleImageFadeCountForTesting, 0)

        // Same request, now served from the pipeline cache during `configure`.
        let cached = configuredArticleImageTestCell(item: item, pipeline: idlePipeline)
        XCTAssertNotNil(cached.articleImageForTesting)
        XCTAssertEqual(cached.articleImageFadeCountForTesting, 0)
    }

    @MainActor
    private func measureUIKitArticleCell(_ cell: IOSUIKitArticleCell, width: CGFloat) -> CGFloat {
        cell.frame.size.width = width
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let measured = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        cell.frame.size = CGSize(width: width, height: measured)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        return measured
    }

    @MainActor
    private func testImage(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Icon preparation finishes on a detached task, so a bounded spin over
    /// `Task.yield()` only ever polled the cooperative pool and failed whenever
    /// the machine was busy. The presentation state already exposes a
    /// continuation-based waiter that resumes on the actual transition.
    @MainActor
    private func waitForFeedIconState(_ state: IOSFeedIconPresentationState, matching expected: IOSFeedIconLoadState) async {
        await state.waitForLoadStateForTesting(expected)
    }

    private final class FeedIconLoader: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Result<Data?, Error>]
        private var calls = 0

        init(results: [Result<Data?, Error>]) {
            self.results = results
        }

        func load() throws -> Data? {
            lock.lock()
            defer { lock.unlock() }
            calls += 1
            guard !results.isEmpty else { throw URLError(.badServerResponse) }
            return try results.removeFirst().get()
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }
    }

    func testNavigationGroupsNestFeedsUnderCategoriesAndKeepOrphansVisible() {
        let categories = [NavigationPresentationCategory(id: 1, title: "Tech"), NavigationPresentationCategory(id: 2, title: "World")]
        let feeds = [
            NavigationPresentationFeed(id: 10, categoryID: 1),
            NavigationPresentationFeed(id: 11, categoryID: 1),
            NavigationPresentationFeed(id: 12, categoryID: 99)
        ]

        let groups = NavigationVisibility.groups(categories: categories, feeds: feeds, hidingEmpty: false, counts: [:])

        XCTAssertEqual(groups.map(\.title), ["Tech", "World", "Other Feeds"])
        XCTAssertEqual(groups[0].feeds.map(\.id), [10, 11])
        XCTAssertEqual(groups[0].categoryID, 1)
        XCTAssertEqual(groups[2].feeds.map(\.id), [12])
        XCTAssertNil(groups[2].categoryID)
    }

    func testNavigationGroupsHideEmptyCategoriesAndFeeds() {
        let categories = [NavigationPresentationCategory(id: 1, title: "Tech"), NavigationPresentationCategory(id: 2, title: "World")]
        let feeds = [NavigationPresentationFeed(id: 10, categoryID: 1), NavigationPresentationFeed(id: 11, categoryID: 2)]

        let groups = NavigationVisibility.groups(categories: categories, feeds: feeds, hidingEmpty: true, counts: [10: 0, 11: 2])

        XCTAssertEqual(groups.map(\.title), ["World"])
        XCTAssertEqual(groups[0].feeds.map(\.id), [11])
    }

    func testArticleRoutingUsesValidOriginalURLForUniversalLinkHandoff() {
        let original = URL(string: "https://example.com/article")!
        XCTAssertEqual(
            ArticleOpenRoutingPolicy.destination(originalURL: original.absoluteString, universalLinkSucceeded: true),
            .universalLink(original)
        )
    }

    func testArticleRoutingFallsBackWhenUniversalLinkIsNotHandled() {
        let original = URL(string: "https://example.com/article")!
        XCTAssertEqual(
            ArticleOpenRoutingPolicy.destination(originalURL: original.absoluteString, universalLinkSucceeded: false),
            .browser(original)
        )
    }

    func testArticleRoutingAlwaysUsesOriginalURLForBrowserFallback() {
        let original = URL(string: "https://example.com/article")!
        XCTAssertEqual(ArticleOpenRoutingPolicy.destination(originalURL: original.absoluteString, universalLinkSucceeded: false), .browser(original))
    }

    func testArticleRoutingRejectsInvalidOriginalURL() {
        XCTAssertEqual(ArticleOpenRoutingPolicy.destination(originalURL: "not a URL", universalLinkSucceeded: true), .invalid)
    }

    func testUniversalLinkRoutingDoesNotUseMinifluxEntryURLOrCanOpenURL() {
        let original = URL(string: "https://publisher.example/article")!
        let miniflux = URL(string: "https://miniflux.example/entry/42")!
        XCTAssertEqual(ArticleOpenRoutingPolicy.destination(originalURL: original.absoluteString, universalLinkSucceeded: false), .browser(original))
        XCTAssertNotEqual(ArticleOpenRoutingPolicy.destination(originalURL: miniflux.absoluteString, universalLinkSucceeded: true), .universalLink(original))
    }

    func testOpenInMinifluxRemainsSeparateFromUniversalLinkRouting() {
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openLink, openInMiniflux: true), .miniflux)
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openLink, openInMiniflux: false), .original)
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openDetailView, openInMiniflux: true), .detail)
    }

    @MainActor
    func testUIKitTimelineUsesNativeFullSwipeReadAndStarActions() async throws {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        let article = timelineArticle(id: 1)
        bridge.replaceArticleStates([article.id: .init(isRead: false, isStarred: false, revision: 0)])
        controller.update(
            structuralState: timelineStructuralState([article], revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            showsRefreshControl: false
        )
        await controller.settleForTesting()

        let table = controller.tableViewForTesting
        let indexPath = IndexPath(row: 0, section: 0)
        let leading = try XCTUnwrap(controller.tableView(table, leadingSwipeActionsConfigurationForRowAt: indexPath))
        let trailing = try XCTUnwrap(controller.tableView(table, trailingSwipeActionsConfigurationForRowAt: indexPath))

        XCTAssertTrue(leading.performsFirstActionWithFullSwipe)
        XCTAssertEqual(leading.actions.count, 1)
        XCTAssertEqual(leading.actions.first?.title, String(localized: "Swipe Read"))
        XCTAssertTrue(trailing.performsFirstActionWithFullSwipe)
        XCTAssertEqual(trailing.actions.count, 1)
        XCTAssertEqual(trailing.actions.first?.title, String(localized: "Swipe Star"))
    }

    func testSwipeConfigurationStoresInnerToOuterAndCapsAtTwoActions() {
        let configuration = IOSArticleSwipeConfiguration(
            leading: [.share, .openOriginal, .readUnread],
            trailing: [.starUnstar, .saveToService]
        )

        XCTAssertEqual(configuration.leading, [.openOriginal, .readUnread])
        XCTAssertEqual(configuration.trailing, [.starUnstar, .saveToService])
        XCTAssertEqual(
            configuration.fullSwipeAction(for: .leading),
            .readUnread
        )
        XCTAssertEqual(
            configuration.additionalAction(for: .leading),
            .openOriginal
        )
    }

    func testSwipeConfigurationPreventsDuplicateActionsOnOneSide() {
        let configuration = IOSArticleSwipeConfiguration(
            leading: [.readUnread, .readUnread],
            trailing: []
        )

        XCTAssertEqual(configuration.leading, [.readUnread])
        XCTAssertEqual(
            configuration.fullSwipeAction(for: .leading),
            .readUnread
        )
        XCTAssertNil(configuration.additionalAction(for: .leading))
    }

    @MainActor
    func testSwipeSettingsPersistAndRestoreTwoActionsPerSide() {
        let suiteName = "FluxNews.SwipeSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = NewsreaderStore(defaults: defaults)
        XCTAssertEqual(
            store.articleSwipeConfiguration,
            .defaultConfiguration
        )

        store.setArticleSwipeAction(
            .openOriginal,
            side: .leading,
            slot: .additional
        )
        store.setArticleSwipeAction(
            .share,
            side: .trailing,
            slot: .additional
        )

        let restored = NewsreaderStore(defaults: defaults)
        XCTAssertEqual(
            restored.articleSwipeConfiguration.leading,
            [.openOriginal, .readUnread]
        )
        XCTAssertEqual(
            restored.articleSwipeConfiguration.trailing,
            [.share, .starUnstar]
        )
    }

    @MainActor
    func testUIKitTimelineMapsOuterConfiguredActionToNativeFullSwipe() async throws {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        let article = timelineArticle(id: 1)
        bridge.replaceArticleStates([
            article.id: .init(
                isRead: false,
                isStarred: false,
                revision: 0
            )
        ])

        controller.update(
            structuralState: timelineStructuralState([article], revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            swipeConfiguration: .init(
                leading: [.openOriginal, .readUnread],
                trailing: []
            ),
            showsRefreshControl: false
        )
        await controller.settleForTesting()

        let table = controller.tableViewForTesting
        let leading = try XCTUnwrap(
            controller.tableView(
                table,
                leadingSwipeActionsConfigurationForRowAt: IndexPath(
                    row: 0,
                    section: 0
                )
            )
        )

        XCTAssertTrue(leading.performsFirstActionWithFullSwipe)
        XCTAssertEqual(leading.actions.count, 2)
        XCTAssertEqual(
            leading.actions.first?.title,
            String(localized: "Swipe Read")
        )
        XCTAssertEqual(
            leading.actions.last?.title,
            String(localized: "Swipe Original")
        )
    }

    @MainActor
    func testUIKitTimelineOmitsConditionalCommentSwipeWhenUnavailable() async throws {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        let article = timelineArticle(id: 1)
        bridge.replaceArticleStates([
            article.id: .init(
                isRead: false,
                isStarred: false,
                revision: 0
            )
        ])

        controller.update(
            structuralState: timelineStructuralState([article], revision: 1),
            presentationBridge: bridge,
            feedIconPresentationBridge: bridge,
            mode: .visual,
            previewLines: .standard,
            iconVariant: .normal,
            feedIconRequestRevision: 0,
            scrollResetRevision: 0,
            markReadOnScrolloverEnabled: false,
            swipeConfiguration: .init(
                leading: [.share, .comments],
                trailing: []
            ),
            showsRefreshControl: false
        )
        await controller.settleForTesting()

        let configuration = try XCTUnwrap(
            controller.tableView(
                controller.tableViewForTesting,
                leadingSwipeActionsConfigurationForRowAt: IndexPath(
                    row: 0,
                    section: 0
                )
            )
        )

        XCTAssertEqual(configuration.actions.count, 1)
        XCTAssertEqual(
            configuration.actions.first?.title,
            String(localized: "Swipe Share")
        )
        XCTAssertFalse(configuration.performsFirstActionWithFullSwipe)
    }

    @MainActor
    func testUIKitArticleCellStatusUpdateRefreshesAccessibilityWithoutGeometryChange() {
        let cell = makeUIKitArticleCell(mode: .visual, width: 390, hasImage: false)
        let geometryBefore = cell.layoutDiagnosticsForTesting
        let layoutRevision = cell.layoutVariantRevision

        cell.updateStatus(isRead: true, isStarred: true)

        XCTAssertEqual(cell.layoutVariantRevision, layoutRevision)
        XCTAssertEqual(cell.layoutDiagnosticsForTesting, geometryBefore)
        XCTAssertEqual(cell.accessibilityValue, String(localized: "Read, starred"))
        XCTAssertTrue(cell.accessibilityLabel?.contains(String(localized: "Read")) == true)
        XCTAssertTrue(cell.accessibilityLabel?.contains(String(localized: ", starred")) == true)
    }

    func testListeningListSwipeActionIsConfigurableSemanticAction() {
        XCTAssertTrue(IOSArticleSwipeAction.allCases.contains(.listeningList))
        XCTAssertEqual(
            IOSArticleSwipeAction.listeningList.title,
            String(localized: "Listening List")
        )
        XCTAssertNil(IOSArticleSwipeAction.listeningList.contextAction)

        let configured = IOSArticleSwipeConfiguration.defaultConfiguration
            .setting(
                .listeningList,
                side: .trailing,
                slot: .additional
            )
        XCTAssertEqual(
            configured.additionalAction(for: .trailing),
            .listeningList
        )
        XCTAssertEqual(
            configured.fullSwipeAction(for: .trailing),
            .starUnstar
        )
    }

    @MainActor
    func testUIKitTimelineListeningListSwipeUsesBatchedAudioMembership() async throws {
        let bridge = IOSUIKitArticleTimelinePresentationBridge()
        let controller = IOSUIKitArticleTimelineController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        let article = timelineArticle(id: 1)
        bridge.replaceArticleStates([
            article.id: .init(
                isRead: false,
                isStarred: false,
                revision: 0
            )
        ])
        let enclosure = Enclosure(
            id: 10,
            articleId: article.id,
            url: "https://example.test/audio.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )

        func state(isInListeningList: Bool) -> IOSArticleAudioActionState {
            IOSArticleAudioActionState(
                articleID: article.id,
                enclosures: [enclosure],
                isInListeningList: isInListeningList,
                downloads: [:]
            )
        }

        func update(_ audioState: IOSArticleAudioActionState?) {
            controller.update(
                structuralState: timelineStructuralState([article], revision: 1),
                presentationBridge: bridge,
                feedIconPresentationBridge: bridge,
                mode: .visual,
                previewLines: .standard,
                iconVariant: .normal,
                feedIconRequestRevision: 0,
                scrollResetRevision: 0,
                markReadOnScrolloverEnabled: false,
                swipeConfiguration: .init(
                    leading: [.listeningList],
                    trailing: []
                ),
                audioActionStates: audioState.map { [article.id: $0] } ?? [:],
                showsRefreshControl: false
            )
        }

        update(state(isInListeningList: false))
        await controller.settleForTesting()
        let table = controller.tableViewForTesting
        let addConfiguration = try XCTUnwrap(
            controller.tableView(
                table,
                leadingSwipeActionsConfigurationForRowAt: IndexPath(
                    row: 0,
                    section: 0
                )
            )
        )
        XCTAssertEqual(
            addConfiguration.actions.first?.title,
            String(localized: "Add to Listening List")
        )
        XCTAssertTrue(addConfiguration.performsFirstActionWithFullSwipe)

        update(state(isInListeningList: true))
        let removeConfiguration = try XCTUnwrap(
            controller.tableView(
                table,
                leadingSwipeActionsConfigurationForRowAt: IndexPath(
                    row: 0,
                    section: 0
                )
            )
        )
        XCTAssertEqual(
            removeConfiguration.actions.first?.title,
            String(localized: "Remove from Listening List")
        )

        update(nil)
        XCTAssertNil(
            controller.tableView(
                table,
                leadingSwipeActionsConfigurationForRowAt: IndexPath(
                    row: 0,
                    section: 0
                )
            )
        )
    }

    func testDownloadAudioSwipeActionIsConfigurableSemanticAction() {
        XCTAssertTrue(IOSArticleSwipeAction.allCases.contains(.downloadAudio))
        XCTAssertEqual(
            IOSArticleSwipeAction.downloadAudio.title,
            String(localized: "Download Audio")
        )
        XCTAssertNil(IOSArticleSwipeAction.downloadAudio.contextAction)

        let configured = IOSArticleSwipeConfiguration.defaultConfiguration
            .setting(
                .downloadAudio,
                side: .trailing,
                slot: .additional
            )
        XCTAssertEqual(
            configured.additionalAction(for: .trailing),
            .downloadAudio
        )
        XCTAssertEqual(
            configured.fullSwipeAction(for: .trailing),
            .starUnstar
        )
    }

    func testArticleAudioPresentationFiltersDownloadableEnclosures() {
        func enclosure(_ id: Int64) -> Enclosure {
            Enclosure(
                id: id,
                articleId: 7,
                url: "https://example.test/\(id).mp3",
                mimeType: "audio/mpeg",
                sizeBytes: nil,
                remoteMediaProgressionSeconds: 0,
                mediaKind: .audio
            )
        }

        func download(_ id: Int64, _ state: DownloadState) -> MediaDownload {
            MediaDownload(
                enclosureId: id,
                state: state,
                origin: .manual,
                localFile: nil,
                fileSizeBytes: nil,
                downloadedAt: nil,
                failureKind: nil
            )
        }

        let state = IOSArticleAudioActionState(
            articleID: 7,
            enclosures: [
                enclosure(1),
                enclosure(2),
                enclosure(3),
                enclosure(4),
                enclosure(5),
            ],
            isInListeningList: false,
            downloads: [
                2: download(2, .requested),
                3: download(3, .downloaded),
                4: download(4, .deleteRequested),
                5: download(5, .failed),
            ]
        )

        XCTAssertEqual(
            IOSArticleAudioPresentation.downloadableEnclosures(state).map(\.id),
            [1, 5]
        )
        XCTAssertEqual(
            IOSArticleAudioPresentation.downloadAction(state.downloads[1]),
            .download
        )
        XCTAssertEqual(
            IOSArticleAudioPresentation.downloadAction(state.downloads[2]),
            .pending
        )
        XCTAssertEqual(
            IOSArticleAudioPresentation.downloadAction(state.downloads[3]),
            .delete
        )
        XCTAssertEqual(
            IOSArticleAudioPresentation.downloadAction(state.downloads[4]),
            .pendingDeletion
        )
        XCTAssertEqual(
            IOSArticleAudioPresentation.downloadAction(state.downloads[5]),
            .retry
        )
    }

    func testArticleContextMenuExposesDistinctNativeActions() {
        let actions: [IOSArticleContextAction] = [
            .starred, .read, .original, .reader, .miniflux, .comments, .copyLink, .share, .saveToService
        ]

        XCTAssertEqual(Set(actions).count, 9)
        XCTAssertEqual(actions[2], .original)
        XCTAssertEqual(actions[3], .reader)
        XCTAssertEqual(actions[4], .miniflux)
        XCTAssertEqual(actions[8], .saveToService)
    }

    func testArticleContextMenuOnlyAcceptsHTTPAndHTTPSURLs() {
        XCTAssertEqual(
            IOSArticleContextMenuPolicy.commentsURL("https://example.com/comments")?.absoluteString,
            "https://example.com/comments"
        )
        XCTAssertEqual(
            IOSArticleContextMenuPolicy.originalURL("http://example.com/article")?.absoluteString,
            "http://example.com/article"
        )
        XCTAssertNil(IOSArticleContextMenuPolicy.commentsURL("mailto:comments@example.com"))
        XCTAssertNil(IOSArticleContextMenuPolicy.originalURL("not a URL"))
        XCTAssertNil(IOSArticleContextMenuPolicy.commentsURL("https:///missing-host"))
    }

    func testCommentsIndicatorUsesTheSameValidatedURLContract() {
        XCTAssertNotNil(IOSArticleContextMenuPolicy.commentsURL("https://example.com/comments"))
        XCTAssertNil(IOSArticleContextMenuPolicy.commentsURL(""))
        XCTAssertNil(IOSArticleContextMenuPolicy.commentsURL("mailto:comments@example.com"))
    }

    func testConfiguredDetailModeSelectsReaderBeforeNormalOpenRouting() {
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openDetailView, openInMiniflux: false), .detail)
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openLink, openInMiniflux: false), .original)
    }

    func testReaderPresentationFollowsAdaptivePresentationRatherThanDeviceIdentity() {
        XCTAssertEqual(AdaptivePresentation.compact.readerPresentationKind, .sheet)
        XCTAssertEqual(AdaptivePresentation.regular.readerPresentationKind, .inspector)
        XCTAssertEqual(AdaptivePresentationPolicy.presentation(horizontalSizeClass: .regular, verticalSizeClass: .regular).readerPresentationKind, .inspector)
    }

    func testReaderPresentationExposesTheExplicitDismissAction() {
        XCTAssertEqual(IOSReaderDismissalPresentation.title, String(localized: "Done"))
    }

    func testReaderRequestStateRejectsStaleResponses() {
        var state = ReaderRequestState()
        let first = state.begin()
        let second = state.begin()
        XCTAssertFalse(state.isCurrent(first))
        XCTAssertTrue(state.isCurrent(second))
    }

    func testManualSyncLifecycleAllowsOnlyOneCurrentRun() {
        var lifecycle = IOSManualSyncLifecycle()
        let first = lifecycle.begin()

        XCTAssertNotNil(first)
        XCTAssertNil(lifecycle.begin())
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertTrue(lifecycle.isCurrent(first!))
        XCTAssertTrue(lifecycle.canPublishCompletion(first!))
    }

    func testManualSyncCancellationImmediatelySupersedesPresentationOwnership() {
        var lifecycle = IOSManualSyncLifecycle()
        let request = lifecycle.begin()!

        XCTAssertTrue(lifecycle.requestCancellation(request))
        XCTAssertEqual(lifecycle.state, .cancelling)
        XCTAssertFalse(lifecycle.canPublishCompletion(request))
        XCTAssertTrue(lifecycle.supersedeCancelled(request))

        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertFalse(lifecycle.isCurrent(request))
        XCTAssertFalse(lifecycle.finish(request))
    }

    func testManualSyncSessionInvalidationRejectsLateCompletionAndAllowsFreshRun() {
        var lifecycle = IOSManualSyncLifecycle()
        let stale = lifecycle.begin()!

        lifecycle.invalidateSession()
        XCTAssertFalse(lifecycle.isCurrent(stale))
        XCTAssertFalse(lifecycle.canPublishCompletion(stale))
        XCTAssertFalse(lifecycle.finish(stale))

        let current = lifecycle.begin()!
        XCTAssertTrue(lifecycle.isCurrent(current))
        XCTAssertNotEqual(stale.session, current.session)
        XCTAssertNotEqual(stale.generation, current.generation)
    }

    func testManualSyncCanRestartImmediatelyAfterCancellation() {
        var lifecycle = IOSManualSyncLifecycle()
        let first = lifecycle.begin()!
        XCTAssertTrue(lifecycle.requestCancellation(first))
        XCTAssertTrue(lifecycle.supersedeCancelled(first))

        let second = lifecycle.begin()!
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertTrue(lifecycle.isCurrent(second))
        XCTAssertNotEqual(first.generation, second.generation)
    }

    func testNewerArticleReadSupersedesOlderReadAndOwnsPublication() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let first = lifecycle.beginArticle()
        let second = lifecycle.beginArticle()

        XCTAssertFalse(lifecycle.isCurrentArticle(first))
        XCTAssertFalse(lifecycle.isCurrentSelectionCount(first))
        XCTAssertFalse(lifecycle.ownsError(first))
        XCTAssertTrue(lifecycle.isCurrentArticle(second))
        XCTAssertTrue(lifecycle.isCurrentSelectionCount(second))
        XCTAssertTrue(lifecycle.ownsError(second))
    }

    func testStaleArticleFailureCannotReplaceNewerSuccessOrLoadingOwner() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let stale = lifecycle.beginArticle()
        let current = lifecycle.beginArticle()

        XCTAssertFalse(lifecycle.isCurrentArticle(stale))
        XCTAssertFalse(lifecycle.ownsError(stale))
        XCTAssertTrue(lifecycle.isCurrentArticle(current))
        XCTAssertTrue(lifecycle.ownsError(current))
    }

    func testTimelinePagingOwnershipRejectsStaleRequestsAcrossGenerationReset() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        _ = lifecycle.beginArticle()
        let stale = lifecycle.beginNextArticlePage()
        _ = lifecycle.beginArticle()
        let current = lifecycle.beginNextArticlePage()

        XCTAssertFalse(lifecycle.ownsTimelinePage(stale))
        XCTAssertTrue(lifecycle.ownsTimelinePage(current))
        XCTAssertNotEqual(stale.requestGeneration, current.requestGeneration)
    }

    func testNavigationReadPublishesOnlyForItsCurrentGeneration() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let stale = lifecycle.beginNavigation()
        let current = lifecycle.beginNavigation()

        XCTAssertFalse(lifecycle.isCurrentNavigation(stale))
        XCTAssertFalse(lifecycle.ownsError(stale))
        XCTAssertTrue(lifecycle.isCurrentNavigation(current))
        XCTAssertTrue(lifecycle.ownsError(current))
    }

    func testManualSyncUsesCancellableCoreBoundaryAndSessionOwnedState() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/NewsreaderStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("blockingCancellableResult("))
        XCTAssertTrue(source.contains("core.syncCancellable(reason: .manual, cancellation: cancellation)"))
        XCTAssertTrue(source.contains("func cancelManualSync()"))
        XCTAssertTrue(source.contains("invalidateManualSyncSession()"))
        XCTAssertTrue(source.contains("store.ownsCoreEventSession(session)"))
        XCTAssertFalse(source.contains("blockingResult { try core.sync(reason: .manual) }"))
    }

    func testTimelineFeedIconRetryDoesNotUseMaterializingVisibleCellsAccessor() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/IOSUIKitArticleTimelineController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let helperStart = try XCTUnwrap(source.range(of: "private func requestFeedIconsForVisibleCells()"))
        let helperTail = source[helperStart.lowerBound...]
        let helperEnd = try XCTUnwrap(helperTail.range(of: "\n    private func reconfigureVisibleCells"))
        let helper = helperTail[..<helperEnd.lowerBound]

        XCTAssertTrue(helper.contains("materializedVisibleArticleCells()"))
        XCTAssertFalse(helper.contains("tableView.visibleCells"))
    }

    func testCancellableManualSyncPresentationUsesCancelRestartAndLocalizedAccessibility() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let iosDirectory = testsDirectory.deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: iosDirectory.appendingPathComponent("FluxNews/ContentView.swift"),
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOf: iosDirectory.appendingPathComponent("FluxNews/NewsreaderStore.swift"),
            encoding: .utf8
        )
        let catalogData = try Data(
            contentsOf: iosDirectory.appendingPathComponent("FluxNews/Localizable.xcstrings")
        )
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        XCTAssertTrue(contentSource.contains("case .running:"))
        XCTAssertTrue(contentSource.contains("newsreaderStore.cancelManualSync()"))
        XCTAssertTrue(contentSource.contains("case .idle, .cancelling:"))
        XCTAssertTrue(contentSource.contains("accessibilityIdentifier(\"articleList.sync\")"))
        XCTAssertFalse(contentSource.contains(".disabled(newsreaderStore.isSyncing)"))
        XCTAssertTrue(storeSource.contains("manualSyncPresentationCancellationRequest = request"))
        XCTAssertTrue(storeSource.contains("manualSyncState == .cancelling"))

        XCTAssertNotNil(strings["Cancel sync"])
        XCTAssertNotNil(strings["Cancelling"])
        let cancelSync = try XCTUnwrap(strings["Cancel sync"] as? [String: Any])
        let cancelLocalizations = try XCTUnwrap(cancelSync["localizations"] as? [String: Any])
        let cancelGerman = try XCTUnwrap(cancelLocalizations["de"] as? [String: Any])
        let cancelUnit = try XCTUnwrap(cancelGerman["stringUnit"] as? [String: Any])
        XCTAssertEqual(cancelUnit["value"] as? String, "Synchronisierung abbrechen")

        let cancelling = try XCTUnwrap(strings["Cancelling"] as? [String: Any])
        let cancellingLocalizations = try XCTUnwrap(cancelling["localizations"] as? [String: Any])
        let cancellingGerman = try XCTUnwrap(cancellingLocalizations["de"] as? [String: Any])
        let cancellingUnit = try XCTUnwrap(cancellingGerman["stringUnit"] as? [String: Any])
        XCTAssertEqual(cancellingUnit["value"] as? String, "Synchronisierung wird abgebrochen")
    }

    func testCoreReplacementQuiescenceTracksWindingManualSyncsWithoutSceneBackgroundCancellation() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let iosDirectory = testsDirectory.deletingLastPathComponent()
        let storeSource = try String(
            contentsOf: iosDirectory.appendingPathComponent("FluxNews/NewsreaderStore.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: iosDirectory.appendingPathComponent("FluxNews/FluxNewsApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(storeSource.contains("manualSyncExecutions[request] = (cancellation, task)"))
        XCTAssertTrue(storeSource.contains("func quiesceManualSyncForCoreReplacement() async"))
        XCTAssertTrue(storeSource.contains("while !manualSyncExecutions.isEmpty"))
        XCTAssertTrue(storeSource.contains("await task.value"))
        XCTAssertTrue(appSource.contains("bootstrapper.prepareForCoreReplacement"))
        XCTAssertTrue(appSource.contains("await newsreaderStore.quiesceManualSyncForCoreReplacement()"))

        let sceneLifecycle = appSource.components(separatedBy: ".onChange(of: scenePhase)").last ?? ""
        XCTAssertTrue(sceneLifecycle.contains("flushScrolloverPersistenceForLifecycle()"))
        XCTAssertFalse(sceneLifecycle.contains("quiesceManualSyncForCoreReplacement"))
        XCTAssertFalse(sceneLifecycle.contains("cancelManualSync"))
    }

    func testNavigationRefreshUsesOneCoreProjectionInsteadOfCountFanout() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/NewsreaderStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let navigationStart = try XCTUnwrap(source.range(of: "func loadNavigationAndCounts"))
        let navigationEnd = try XCTUnwrap(source.range(of: "func loadVisibleArticles", range: navigationStart.upperBound..<source.endIndex))
        let navigationRefresh = String(source[navigationStart.lowerBound..<navigationEnd.lowerBound])
        XCTAssertEqual(navigationRefresh.components(separatedBy: "core.navigationProjection").count - 1, 1)
        XCTAssertFalse(navigationRefresh.contains("core.countArticles"))

        let countsStart = try XCTUnwrap(source.range(of: "private func reloadCounts"))
        let countsEnd = try XCTUnwrap(source.range(of: "private func requestScrollReset", range: countsStart.upperBound..<source.endIndex))
        let countRefresh = String(source[countsStart.lowerBound..<countsEnd.lowerBound])
        XCTAssertEqual(countRefresh.components(separatedBy: "core.navigationProjection").count - 1, 1)
        XCTAssertEqual(countRefresh.components(separatedBy: "core.countArticles").count - 1, 1, "selectionTotal remains a separate selected-query count")
    }

    func testArchiveUsesWholeModuleOptimizationWithoutChangingSimulatorOrDiagnosticsPolicy() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let archive = try String(contentsOf: iosRoot.appendingPathComponent("Build/archive.sh"), encoding: .utf8)
        let simulator = try String(contentsOf: iosRoot.appendingPathComponent("Build/run-simulator.sh"), encoding: .utf8)
        let build = try String(contentsOf: iosRoot.appendingPathComponent("Build/build-app.sh"), encoding: .utf8)
        let project = try String(contentsOf: iosRoot.appendingPathComponent("FluxNews.xcodeproj/project.pbxproj"), encoding: .utf8)

        XCTAssertTrue(archive.contains("SWIFT_COMPILATION_MODE=wholemodule"))
        XCTAssertTrue(simulator.contains("CONFIGURATION=\"${CONFIGURATION:-Debug}\""))
        XCTAssertTrue(build.contains("FLUX_PERFORMANCE_DIAGNOSTICS"))
        XCTAssertFalse(project.contains("FLUX_PERFORMANCE_DIAGNOSTICS"))
    }

    func testDuoVerticalToolbarCapabilityGateCoversFutureSDKsWithoutEnablingIOS270() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: iosRoot.appendingPathComponent("FluxNews.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertFalse(project.contains("FLUX_IOS_27_1_SDK"))
        XCTAssertFalse(project.contains("OTHER_SWIFT_FLAGS[sdk=iphoneos27.0"))
        XCTAssertTrue(project.contains("OTHER_SWIFT_FLAGS[sdk=iphoneos27.3*]"))
        XCTAssertTrue(project.contains("OTHER_SWIFT_FLAGS[sdk=iphonesimulator27.9*]"))
        XCTAssertTrue(project.contains("OTHER_SWIFT_FLAGS[sdk=iphoneos28*]"))
        XCTAssertTrue(project.contains("OTHER_SWIFT_FLAGS[sdk=iphoneos29*]"))
        XCTAssertTrue(project.contains("OTHER_SWIFT_FLAGS[sdk=iphoneos3*]"))
        XCTAssertTrue(project.contains("-DFLUX_HAS_VERTICAL_TOOLBAR_API"))
    }

    func testDetachAndReattachInvalidateAllPriorReadRequests() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let article = lifecycle.beginArticle()
        let navigation = lifecycle.beginNavigation()

        lifecycle.invalidateSession()
        let reattachedArticle = lifecycle.beginArticle()

        XCTAssertFalse(lifecycle.isCurrentArticle(article))
        XCTAssertFalse(lifecycle.isCurrentNavigation(navigation))
        XCTAssertFalse(lifecycle.ownsError(article))
        XCTAssertTrue(lifecycle.isCurrentArticle(reattachedArticle))
    }

    func testPresentationResetInvalidatesCurrentArticleAndSelectionCount() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let request = lifecycle.beginArticle()

        lifecycle.invalidateArticle()

        XCTAssertFalse(lifecycle.isCurrentArticle(request))
        XCTAssertFalse(lifecycle.isCurrentSelectionCount(request))
        XCTAssertFalse(lifecycle.ownsError(request))
    }

    func testNewSelectionCountReadInvalidatesOlderArticleCount() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let article = lifecycle.beginArticle()
        let count = lifecycle.beginSelectionCount()

        XCTAssertFalse(lifecycle.isCurrentSelectionCount(article))
        XCTAssertTrue(lifecycle.isCurrentSelectionCount(count))
    }

    func testArticleDataSyncRefreshesEveryCount() {
        XCTAssertEqual(IOSSyncCountRefreshPolicy.resolve(dataChanged: true, navigationChanged: false), .allCounts)
    }

    func testNavigationSyncReloadsCatalogAndEveryCount() {
        XCTAssertEqual(IOSSyncCountRefreshPolicy.resolve(dataChanged: false, navigationChanged: true), .navigationAndAllCounts)
        XCTAssertEqual(IOSSyncCountRefreshPolicy.resolve(dataChanged: true, navigationChanged: true), .navigationAndAllCounts)
    }

    func testSyncWithoutDataOrNavigationChangesDoesNotRefreshCounts() {
        XCTAssertEqual(IOSSyncCountRefreshPolicy.resolve(dataChanged: false, navigationChanged: false), .none)
    }

    func testCountCompletionAfterSelectionChangeCannotPublishAsCurrent() {
        var lifecycle = IOSNewsreaderReadLifecycle()
        let syncCount = lifecycle.beginSelectionCount()
        _ = lifecycle.beginArticle()

        XCTAssertFalse(lifecycle.isCurrentSelectionCount(syncCount))
    }

    @MainActor
    func testInactiveListeningListPlayerPreviewKeepsActivePlaybackSeparate() {
        let activeEnclosure = Enclosure(
            id: 1,
            articleId: 10,
            url: "https://example.test/active.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )
        let previewEnclosure = Enclosure(
            id: 2,
            articleId: 20,
            url: "https://example.test/preview.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )
        let previewItem = ListeningListItem(
            articleId: 20,
            feedId: 2,
            title: "Preview Episode",
            feedTitle: "Preview Feed",
            publishedAt: "2026-09-25T00:00:00Z",
            addedAt: "2026-09-25T00:00:00Z",
            remotePresent: true,
            audioEnclosures: [
                ListeningListEnclosure(
                    enclosure: previewEnclosure,
                    remotePresent: true,
                    playbackState: PlaybackState(
                        enclosureId: 2,
                        positionMs: 12_000,
                        durationMs: 90_000,
                        status: .inProgress,
                        updatedAt: nil
                    ),
                    download: nil,
                    durationMs: 90_000
                )
            ],
            activeEnclosureId: 2
        )
        let runtime = IOSMediaPlaybackPresentationState()
        runtime.setLoadedMedia(
            enclosure: activeEnclosure,
            feedTitle: "Active Feed",
            mediaTitle: "Active Episode",
            artworkSource: nil,
            chapters: [],
            positionMs: 45_000,
            durationMs: 120_000
        )
        runtime.setStatus(.playing)

        XCTAssertEqual(
            IOSMediaPlayerPreviewPresentation.isPreviewingInactiveItem(
                item: previewItem,
                loadedEnclosureID: runtime.loadedEnclosure?.id
            ),
            true
        )
        XCTAssertEqual(
            IOSMediaPlayerPreviewPresentation.positionMs(
                item: previewItem,
                loadedEnclosureID: runtime.loadedEnclosure?.id,
                runtimePositionMs: runtime.positionMs
            ),
            12_000
        )
    }

    func testMediaChapterListPresentationFormatsPositionAndGeneratedTitle() {
        XCTAssertEqual(
            IOSMediaChapterListPresentation.positionLabel(65_000),
            "1:05"
        )
        XCTAssertEqual(
            IOSMediaChapterListPresentation.positionLabel(3_725_000),
            "1:02:05"
        )
        let chapter = MediaChapter(
            enclosureId: 7,
            title: "cp 2",
            startMs: 65_000,
            endMs: nil,
            source: .embedded
        )
        XCTAssertEqual(
            IOSMediaChapterListPresentation.title(chapter, index: 1),
            String(localized: "Chapter \(2)", bundle: .main)
        )
    }

    func testMediaChapterListPresentationResolvesActiveChapter() {
        let chapters = [
            MediaChapter(
                enclosureId: 7,
                title: "Intro",
                startMs: 0,
                endMs: nil,
                source: .embedded
            ),
            MediaChapter(
                enclosureId: 7,
                title: "Topic",
                startMs: 60_000,
                endMs: nil,
                source: .embedded
            )
        ]

        XCTAssertEqual(
            IOSMediaChapterListPresentation.activeIndex(
                positionMs: 30_000,
                chapters: chapters
            ),
            0
        )
        XCTAssertEqual(
            IOSMediaChapterListPresentation.activeIndex(
                positionMs: 90_000,
                chapters: chapters
            ),
            1
        )
    }

    func testMediaPlayerTransportControlsKeepStopAsFourthPermanentControl() {
        XCTAssertEqual(
            IOSMediaPlayerTransportControl.ordered,
            [.back15, .playPause, .forward30, .stop]
        )
    }

    func testMediaPlayerActionPlacementKeepsStatusVisibleAndRareActionsInOverflow() {
        XCTAssertEqual(
            IOSMediaPlayerActionPlacement.persistentStatus,
            [.playbackRate, .sleepTimer]
        )
        XCTAssertEqual(
            IOSMediaPlayerActionPlacement.overflow,
            [.downloads, .restart]
        )
    }

    func testMediaPlayerWaitIndicatorOnlyAppliesToRemoteActivePlayback() {
        XCTAssertFalse(
            IOSMediaPlayerWaitIndicatorPolicy.shouldRequestIndicator(
                isPreviewingInactiveItem: false,
                source: .local,
                isLoading: true,
                isBuffering: true
            )
        )
        XCTAssertTrue(
            IOSMediaPlayerWaitIndicatorPolicy.shouldRequestIndicator(
                isPreviewingInactiveItem: false,
                source: .remote,
                isLoading: true,
                isBuffering: false
            )
        )
        XCTAssertTrue(
            IOSMediaPlayerWaitIndicatorPolicy.shouldRequestIndicator(
                isPreviewingInactiveItem: false,
                source: .remote,
                isLoading: false,
                isBuffering: true
            )
        )
        XCTAssertFalse(
            IOSMediaPlayerWaitIndicatorPolicy.shouldRequestIndicator(
                isPreviewingInactiveItem: true,
                source: .remote,
                isLoading: true,
                isBuffering: true
            )
        )
    }

    func testMediaPlayerShowNotesAreInlineDisclosureNotNestedSheet() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let playerSource = try String(
            contentsOf: testsDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("FluxNews/IOSMediaPlayerView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(playerSource.contains("showNotesExpanded"))
        XCTAssertTrue(playerSource.contains("private var showNotesSection"))
        XCTAssertTrue(
            playerSource.contains(
                "ReaderDocumentContent(\n                            document: showNotesDocument"
            )
        )
        XCTAssertFalse(
            playerSource.contains(".sheet(isPresented: $showNotesPresented)")
        )
    }

    func testMediaTimePresentationAddsHoursOnlyWhenNeeded() {
        XCTAssertEqual(IOSMediaTimePresentation.label(0), "0:00")
        XCTAssertEqual(IOSMediaTimePresentation.label(65_000), "1:05")
        XCTAssertEqual(IOSMediaTimePresentation.label(3_599_000), "59:59")
        XCTAssertEqual(IOSMediaTimePresentation.label(3_725_000), "1:02:05")
    }

    func testMediaPlayerChapterSummaryUsesCurrentChapterAndCount() {
        let chapters = [
            MediaChapter(
                enclosureId: 7,
                title: "Intro",
                startMs: 0,
                endMs: 60_000,
                source: .embedded
            ),
            MediaChapter(
                enclosureId: 7,
                title: "Topic",
                startMs: 60_000,
                endMs: nil,
                source: .embedded
            )
        ]

        XCTAssertEqual(
            IOSMediaPlayerChapterSummary.resolve(
                positionMs: 90_000,
                chapters: chapters
            ),
            .init(index: 1, count: 2, title: "Topic")
        )
    }

    func testMediaPlayerAudioSelectionUsesLoadedEnclosureWhenAvailable() {
        func audio(_ id: Int64, _ name: String) -> ListeningListEnclosure {
            ListeningListEnclosure(
                enclosure: Enclosure(
                    id: id,
                    articleId: 101,
                    url: "https://example.test/\(name).mp3",
                    mimeType: "audio/mpeg",
                    sizeBytes: nil,
                    remoteMediaProgressionSeconds: 0,
                    mediaKind: .audio
                ),
                remotePresent: true,
                playbackState: nil,
                download: nil,
                durationMs: nil
            )
        }

        let first = audio(11, "one")
        let second = audio(12, "two")
        let item = ListeningListItem(
            articleId: 101,
            feedId: 10,
            title: "Episode",
            feedTitle: "Feed",
            publishedAt: "",
            addedAt: "",
            remotePresent: true,
            audioEnclosures: [first, second],
            activeEnclosureId: 11
        )

        let selection = IOSMediaPlayerAudioSelection.resolve(
            item: item,
            loadedEnclosureID: 12
        )

        XCTAssertEqual(selection?.enclosureID, 12)
        XCTAssertEqual(selection?.index, 1)
        XCTAssertEqual(selection?.count, 2)
        XCTAssertTrue(selection?.title.contains("two.mp3") == true)
    }

    func testMediaPlayerLayoutPolicyAdaptsBySizeClass() {
        XCTAssertEqual(
            IOSMediaPlayerLayoutPolicy.mode(
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            .stacked
        )
        XCTAssertEqual(
            IOSMediaPlayerLayoutPolicy.mode(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular
            ),
            .sideBySide
        )
        XCTAssertEqual(
            IOSMediaPlayerLayoutPolicy.mode(
                horizontalSizeClass: .regular,
                verticalSizeClass: .compact
            ),
            .sideBySide
        )
        XCTAssertEqual(
            IOSMediaPlayerLayoutPolicy.mode(
                horizontalSizeClass: .compact,
                verticalSizeClass: .compact
            ),
            .sideBySide
        )
    }

    func testListeningListPlaybackActionReflectsRuntimeState() {
        XCTAssertEqual(
            IOSListeningListPresentation.playbackAction(
                enclosureID: 7,
                loadedEnclosureID: 7,
                status: .playing
            ),
            .pause
        )
        XCTAssertEqual(
            IOSListeningListPresentation.playbackAction(
                enclosureID: 7,
                loadedEnclosureID: 7,
                status: .paused
            ),
            .play
        )
        XCTAssertEqual(
            IOSListeningListPresentation.playbackAction(
                enclosureID: 7,
                loadedEnclosureID: 8,
                status: .playing
            ),
            .play
        )
    }

    @MainActor
    func testListeningListPresentationPrefersActiveEnclosureAndRuntimeProgress() {
        let first = ListeningListEnclosure(
            enclosure: Enclosure(
                id: 11,
                articleId: 101,
                url: "https://example.test/one.mp3",
                mimeType: "audio/mpeg",
                sizeBytes: 100,
                remoteMediaProgressionSeconds: 0,
                mediaKind: .audio
            ),
            remotePresent: true,
            playbackState: nil,
            download: nil,
            durationMs: 60_000
        )
        let second = ListeningListEnclosure(
            enclosure: Enclosure(
                id: 12,
                articleId: 101,
                url: "https://example.test/two.mp3",
                mimeType: "audio/mpeg",
                sizeBytes: 200,
                remoteMediaProgressionSeconds: 0,
                mediaKind: .audio
            ),
            remotePresent: true,
            playbackState: PlaybackState(
                enclosureId: 12,
                positionMs: 5_000,
                durationMs: 100_000,
                status: .inProgress,
                updatedAt: nil
            ),
            download: nil,
            durationMs: 100_000
        )
        let item = ListeningListItem(
            articleId: 101,
            feedId: 10,
            title: "Episode",
            feedTitle: "Feed",
            publishedAt: "2026-09-25T00:00:00Z",
            addedAt: "2026-09-25T00:00:00Z",
            remotePresent: true,
            audioEnclosures: [first, second],
            activeEnclosureId: 12
        )
        let runtime = IOSMediaPlaybackPresentationState()
        runtime.setLoadedMedia(
            enclosure: second.enclosure,
            feedTitle: "Feed",
            mediaTitle: "Episode",
            artworkSource: nil,
            chapters: [],
            positionMs: 25_000,
            durationMs: 100_000
        )
        runtime.setStatus(.playing)

        XCTAssertEqual(
            IOSListeningListPresentation.selectedEnclosure(item)?.enclosure.id,
            12
        )
        let progress = IOSListeningListPresentation.progress(
            item,
            runtime: runtime
        )
        XCTAssertEqual(progress?.positionMs, 25_000)
        XCTAssertEqual(progress?.durationMs, 100_000)
        XCTAssertEqual(progress?.status, .inProgress)
        XCTAssertEqual(progress?.fraction, 0.25)
    }

    @MainActor
    func testListeningListUnplayedIndicatorUsesPlaybackStateAcrossEnclosures() {
        let enclosure = Enclosure(
            id: 77,
            articleId: 101,
            url: "https://example.test/episode.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )
        let newAudio = ListeningListEnclosure(
            enclosure: enclosure,
            remotePresent: true,
            playbackState: nil,
            download: nil,
            durationMs: 60_000
        )
        func item(_ audio: [ListeningListEnclosure]) -> ListeningListItem {
            ListeningListItem(
                articleId: 101,
                feedId: 10,
                title: "Episode",
                feedTitle: "Feed",
                publishedAt: "2026-09-25T00:00:00Z",
                addedAt: "2026-09-25T00:00:00Z",
                remotePresent: true,
                audioEnclosures: audio,
                activeEnclosureId: nil
            )
        }
        let runtime = IOSMediaPlaybackPresentationState()
        XCTAssertTrue(IOSListeningListPresentation.isUnplayed(item([newAudio]), runtime: runtime))
        XCTAssertFalse(IOSListeningListPresentation.isUnplayed(item([]), runtime: runtime))
        let startedAudio = ListeningListEnclosure(
            enclosure: enclosure,
            remotePresent: true,
            playbackState: PlaybackState(
                enclosureId: 77,
                positionMs: 10_000,
                durationMs: 60_000,
                status: .inProgress,
                updatedAt: nil
            ),
            download: nil,
            durationMs: 60_000
        )
        XCTAssertFalse(IOSListeningListPresentation.isUnplayed(item([newAudio, startedAudio]), runtime: runtime))
        runtime.setLoadedMedia(
            enclosure: enclosure,
            feedTitle: "Feed",
            mediaTitle: "Episode",
            artworkSource: nil,
            chapters: [],
            positionMs: 10_000,
            durationMs: 60_000
        )
        runtime.setStatus(.playing)
        XCTAssertFalse(IOSListeningListPresentation.isUnplayed(item([newAudio]), runtime: runtime))
    }

    @MainActor
    func testCarPlayPlaybackIndicatorMapsUnplayedAndCompletedState() {
        let enclosure = Enclosure(
            id: 99,
            articleId: 101,
            url: "https://example.test/episode.mp3",
            mimeType: "audio/mpeg",
            sizeBytes: nil,
            remoteMediaProgressionSeconds: 0,
            mediaKind: .audio
        )
        func entry(_ playback: PlaybackState?) -> ListeningListItem {
            ListeningListItem(
                articleId: 101,
                feedId: 10,
                title: "Episode",
                feedTitle: "Feed",
                publishedAt: "2026-10-21T00:00:00Z",
                addedAt: "2026-10-21T00:00:00Z",
                remotePresent: true,
                audioEnclosures: [
                    ListeningListEnclosure(
                        enclosure: enclosure,
                        remotePresent: true,
                        playbackState: playback,
                        download: nil,
                        durationMs: 60_000
                    )
                ],
                activeEnclosureId: 99
            )
        }

        let runtime = IOSMediaPlaybackPresentationState()
        XCTAssertEqual(
            IOSCarPlayPlaybackIndicator.indicator(for: entry(nil), runtime: runtime),
            .unplayed
        )
        let partial = PlaybackState(
            enclosureId: 99, positionMs: 10_000, durationMs: 60_000,
            status: .inProgress, updatedAt: nil
        )
        XCTAssertNil(IOSCarPlayPlaybackIndicator.indicator(for: entry(partial), runtime: runtime))
        let finished = PlaybackState(
            enclosureId: 99, positionMs: 60_000, durationMs: 60_000,
            status: .completed, updatedAt: nil
        )
        XCTAssertEqual(
            IOSCarPlayPlaybackIndicator.indicator(for: entry(finished), runtime: runtime),
            .completed
        )
        runtime.setLoadedMedia(
            enclosure: enclosure,
            feedTitle: "Feed",
            mediaTitle: "Episode",
            artworkSource: nil,
            chapters: [],
            positionMs: 0,
            durationMs: 60_000
        )
        runtime.setStatus(.playing)
        XCTAssertNil(IOSCarPlayPlaybackIndicator.indicator(for: entry(nil), runtime: runtime))
    }

    func testListeningListDownloadSummarySeparatesDownloadedAndPending() {
        func enclosure(
            id: Int64,
            state: DownloadState?
        ) -> ListeningListEnclosure {
            ListeningListEnclosure(
                enclosure: Enclosure(
                    id: id,
                    articleId: 101,
                    url: "https://example.test/\(id).mp3",
                    mimeType: "audio/mpeg",
                    sizeBytes: nil,
                    remoteMediaProgressionSeconds: 0,
                    mediaKind: .audio
                ),
                remotePresent: true,
                playbackState: nil,
                download: state.map {
                    MediaDownload(
                        enclosureId: id,
                        state: $0,
                        origin: .manual,
                        localFile: nil,
                        fileSizeBytes: nil,
                        downloadedAt: nil,
                        failureKind: nil
                    )
                },
                durationMs: nil
            )
        }

        let item = ListeningListItem(
            articleId: 101,
            feedId: 10,
            title: "Episode",
            feedTitle: "Feed",
            publishedAt: "",
            addedAt: "",
            remotePresent: true,
            audioEnclosures: [
                enclosure(id: 1, state: .downloaded),
                enclosure(id: 2, state: .requested),
                enclosure(id: 3, state: .deleteRequested),
                enclosure(id: 4, state: .failed),
            ],
            activeEnclosureId: nil
        )

        let transfers: [Int64: MediaTransferRuntime] = [
            2: MediaTransferRuntime(
                enclosureID: 2,
                bytesReceived: 40,
                expectedBytes: 100,
                phase: .transferring
            )
        ]
        let summary = IOSListeningListPresentation.downloadSummary(
            item,
            transfers: transfers
        )
        XCTAssertEqual(summary.downloaded, 1)
        XCTAssertEqual(summary.pending, 2)
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(
            IOSListeningListPresentation.downloadAction(
                item.audioEnclosures[1],
                runtime: transfers[2]
            ),
            .downloading
        )
        let transfer = IOSListeningListPresentation.transferProgress(
            item,
            transfers: transfers
        )
        XCTAssertEqual(transfer?.fraction, 0.4)
        XCTAssertEqual(
            transfer?.label,
            String(localized: "\(40)% downloaded", bundle: .main)
        )
    }

    func testReaderDocumentNoticePreservesAllContentStates() {
        XCTAssertNil(ReaderDocumentNotice.text(simplified: false, truncated: false))
        XCTAssertEqual(
            ReaderDocumentNotice.text(simplified: true, truncated: false),
            String(localized: "Some content was simplified", bundle: .main)
        )
        XCTAssertEqual(
            ReaderDocumentNotice.text(simplified: false, truncated: true),
            String(localized: "Some content was truncated", bundle: .main)
        )
        XCTAssertEqual(
            ReaderDocumentNotice.text(simplified: true, truncated: true),
            String(localized: "Some content was simplified and truncated", bundle: .main)
        )
    }

    func testReaderDocumentVariantsAreRepresentedByCoreProjection() {
        let inline: [ReaderInline] = [
            .text(text: "text"),
            .bold(inlines: [.text(text: "bold")]),
            .italic(inlines: [.text(text: "italic")]),
            .code(text: "code"),
            .link(url: "https://example.com", inlines: [.text(text: "link")])
        ]
        let blocks: [ReaderBlock] = [
            .paragraph(inlines: inline),
            .heading(level: 2, inlines: inline),
            .image(url: "https://example.com/image.png", alt: "image", link: nil),
            .listBlock(ordered: false, items: [.init(blocks: [.paragraph(inlines: inline)])]),
            .quote(blocks: [.paragraph(inlines: inline)]),
            .codeBlock(text: "code"),
            .horizontalRule,
            .externalContent(url: "https://example.com", label: "external")
        ]
        XCTAssertEqual(blocks.count, 8)
        XCTAssertEqual(inline.count, 5)
    }


    func testSharedWidgetSnapshotRoundTripsWithoutCorePersistenceTypes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(root: root)
        let snapshot = WidgetSnapshotV1(
            schemaVersion: WidgetSnapshotV1.schemaVersion,
            state: .ready,
            generatedAt: "2026-09-23T12:00:00Z",
            lastSuccessfulSyncAt: "2026-09-23T11:59:00Z",
            feeds: [
                .init(
                    id: 10,
                    categoryID: 20,
                    title: "Feed",
                    normalIconFile: nil,
                    darkIconFile: nil
                ),
            ],
            categories: [.init(id: 20, title: "Category")],
            articles: [
                .init(
                    id: 1,
                    feedID: 10,
                    categoryID: 20,
                    feedTitle: "Feed",
                    title: "Unread",
                    publishedAt: "2026-09-23T11:58:00Z",
                    isRead: false,
                    isStarred: false
                ),
            ],
            counts: .init(
                allUnread: 1,
                bookmarks: 0,
                feedUnread: [.init(id: 10, count: 1)],
                categoryUnread: [.init(id: 20, count: 1)]
            )
        )

        try store.write(snapshot)

        XCTAssertEqual(try store.read(), snapshot)
    }

    func testWidgetContentModelUsesSameSnapshotForHomeAndLockScreenScopes() {
        let snapshot = WidgetSnapshotV1(
            schemaVersion: WidgetSnapshotV1.schemaVersion,
            state: .ready,
            generatedAt: "2026-09-23T12:00:00Z",
            lastSuccessfulSyncAt: "2026-09-23T11:59:00Z",
            feeds: [
                .init(id: 10, categoryID: 20, title: "Feed", normalIconFile: nil, darkIconFile: nil),
            ],
            categories: [.init(id: 20, title: "Category")],
            articles: [
                .init(id: 1, feedID: 10, categoryID: 20, feedTitle: "Feed", title: "Unread", publishedAt: "2026-09-23T11:58:00Z", isRead: false, isStarred: false),
                .init(id: 2, feedID: 10, categoryID: 20, feedTitle: "Feed", title: "Bookmark", publishedAt: "2026-09-23T11:57:00Z", isRead: true, isStarred: true),
            ],
            counts: .init(
                allUnread: 1,
                bookmarks: 1,
                feedUnread: [.init(id: 10, count: 1)],
                categoryUnread: [.init(id: 20, count: 1)]
            )
        )

        let all = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(scope: .allNews, categoryID: nil, feedID: nil)
        )
        let bookmarks = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(scope: .bookmarks, categoryID: nil, feedID: nil)
        )
        let feed = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(scope: .feed, categoryID: nil, feedID: 10)
        )

        XCTAssertEqual(all.articles.map(\.id), [1])
        XCTAssertEqual(bookmarks.articles.map(\.id), [2])
        XCTAssertEqual(feed.count, 1)
        XCTAssertEqual(feed.title, "Feed")
    }

    func testD9WidgetConfigurationFiltersAndSortsTheSharedSnapshot() {
        let snapshot = WidgetSnapshotV1(
            schemaVersion: WidgetSnapshotV1.schemaVersion,
            state: .ready,
            generatedAt: "2026-09-28T12:00:00Z",
            lastSuccessfulSyncAt: "2026-09-28T11:59:00Z",
            feeds: [
                .init(id: 10, categoryID: 20, title: "Feed", normalIconFile: nil, darkIconFile: nil),
            ],
            categories: [.init(id: 20, title: "Category")],
            articles: [
                .init(id: 4, feedID: 10, categoryID: 20, feedTitle: "Feed", title: "Newest read", publishedAt: "2026-09-28T11:00:00Z", isRead: true, isStarred: false),
                .init(id: 3, feedID: 10, categoryID: 20, feedTitle: "Feed", title: "Unread bookmark", publishedAt: "2026-09-28T10:00:00Z", isRead: false, isStarred: true),
                .init(id: 2, feedID: 10, categoryID: 20, feedTitle: "Feed", title: "Read bookmark", publishedAt: "2026-09-28T09:00:00Z", isRead: true, isStarred: true),
                .init(id: 1, feedID: 10, categoryID: 20, feedTitle: "Feed", title: "Oldest unread", publishedAt: "2026-09-28T08:00:00Z", isRead: false, isStarred: false),
            ],
            counts: .init(
                allUnread: 2,
                bookmarks: 2,
                feedUnread: [.init(id: 10, count: 2)],
                categoryUnread: [.init(id: 20, count: 2)]
            ),
            configuration: .init(
                allArticles: 4,
                bookmarksUnread: 1,
                feedAll: [.init(id: 10, count: 4)],
                categoryAll: [.init(id: 20, count: 4)]
            )
        )

        let unreadNewest = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .feed,
                categoryID: nil,
                feedID: 10,
                readFilter: .unread,
                sortOrder: .newestFirst
            )
        )
        XCTAssertEqual(unreadNewest.articles.map(\.id), [3, 1])
        XCTAssertEqual(unreadNewest.count, 2)

        let allOldest = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .feed,
                categoryID: nil,
                feedID: 10,
                readFilter: .all,
                sortOrder: .oldestFirst
            )
        )
        XCTAssertEqual(allOldest.articles.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(allOldest.count, 4)
        XCTAssertEqual(allOldest.countLabel, "articles")

        let unreadBookmarks = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .bookmarks,
                categoryID: nil,
                feedID: nil,
                readFilter: .unread,
                sortOrder: .newestFirst
            )
        )
        XCTAssertEqual(unreadBookmarks.articles.map(\.id), [3])
        XCTAssertEqual(unreadBookmarks.count, 1)
    }

    func testD9WidgetConfigurationIntentExposesReadAndSortParameters() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let widgetSource = try String(
            contentsOf: testsDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("FluxNewsWidgets/FluxNewsWidgets.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(widgetSource.contains("FluxNewsWidgetReadFilter"))
        XCTAssertTrue(widgetSource.contains("FluxNewsWidgetSortOrder"))
        XCTAssertTrue(widgetSource.contains("LocalizedStringResource(\"Read Filter\")"))
        XCTAssertTrue(widgetSource.contains("LocalizedStringResource(\"Sort Order\")"))
        XCTAssertTrue(widgetSource.contains("default: .unread"))
        XCTAssertTrue(widgetSource.contains("default: .newestFirst"))
    }

    func testWidgetActionsAndLockScreenFamiliesUseTheSharedContract() {
        let selection = WidgetContentSelection(scope: .feed, categoryID: nil, feedID: 10)
        let actions: [WidgetAction] = [
            .article(42),
            .open(selection),
            .sync,
        ]

        for action in actions {
            let url = action.url()
            XCTAssertEqual(WidgetAction(url: url), action)
            XCTAssertEqual(url.scheme, WidgetSnapshotConfiguration.widgetURLScheme())
        }

        XCTAssertEqual(
            WidgetFamilyPolicy.lockScreenFamilies,
            [.accessoryInline, .accessoryCircular, .accessoryRectangular]
        )
        XCTAssertTrue(
            WidgetFamilyPolicy.lockScreenFamilies.allSatisfy {
                WidgetFamilyPolicy.statusFamilies.contains($0)
            }
        )
    }

    func testHeadlineWidgetFamiliesExcludeSystemSmall() {
        XCTAssertEqual(
            WidgetFamilyPolicy.headlineFamilies,
            [.systemMedium, .systemLarge, .systemExtraLarge]
        )
        XCTAssertFalse(WidgetFamilyPolicy.headlineFamilies.contains(.systemSmall))
    }

    func testWidgetSyncTimestampAcceptsCoreSQLiteAndISOFormats() throws {
        let sqlite = try XCTUnwrap(WidgetSyncTimestamp.date(from: "2026-09-23 18:42:15"))
        let iso = try XCTUnwrap(WidgetSyncTimestamp.date(from: "2026-09-23T18:42:15Z"))

        XCTAssertEqual(sqlite, iso)
        XCTAssertNil(WidgetSyncTimestamp.date(from: "not-a-timestamp"))
    }

    func testStatusWidgetKeepsProminentBrandAndCompactRectangularCountLayout() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let widgetSource = try String(
            contentsOf: testsDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("FluxNewsWidgets/FluxNewsWidgets.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(widgetSource.contains(".frame(width: 32, height: 32)"))
        XCTAssertTrue(widgetSource.contains(".frame(width: 18, height: 18)"))
        XCTAssertTrue(widgetSource.contains(".font(.system(size: 13"))
        XCTAssertTrue(widgetSource.contains(".font(.system(size: 17"))
        XCTAssertTrue(widgetSource.contains(".font(.system(size: 12"))
    }

}

private final class FeedIconLoadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let result: Result<Data?, Error>
    private var started = false
    private var returned = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var returnWaiters: [CheckedContinuation<Void, Never>] = []

    init(result: Result<Data?, Error>) {
        self.result = result
    }

    func load() throws -> Data? {
        let startedWaiters = withLock {
            started = true
            let waiters = startWaiters
            startWaiters.removeAll()
            return waiters
        }
        startedWaiters.forEach { $0.resume() }
        releaseSemaphore.wait()
        let completedWaiters = withLock {
            returned = true
            let waiters = returnWaiters
            returnWaiters.removeAll()
            return waiters
        }
        completedWaiters.forEach { $0.resume() }
        return try result.get()
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let shouldResume = withLock {
                if started { return true }
                startWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitUntilReturned() async {
        await withCheckedContinuation { continuation in
            let shouldResume = withLock {
                if returned { return true }
                returnWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func release() { releaseSemaphore.signal() }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private actor ImageLoadCounter {
    private let data: Data
    private var calls = 0

    init(data: Data) { self.data = data }

    func load() -> Data {
        calls += 1
        return data
    }

    func callCount() -> Int { calls }
}

private actor LayoutMeasurementGate {
    private var inputs: [IOSUIKitArticleLayoutInput] = []
    private var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func measure(_ input: IOSUIKitArticleLayoutInput) async -> IOSUIKitArticleLayoutMetrics {
        inputs.append(input)
        let readyCounts = startWaiters.keys.filter { inputs.count >= $0 }
        for count in readyCounts { startWaiters.removeValue(forKey: count)?.resume() }
        await withCheckedContinuation { releaseWaiters.append($0) }
        return IOSUIKitArticleLayoutEngine.metrics(for: input)
    }

    func waitUntilStarted(count: Int) async {
        guard inputs.count < count else { return }
        await withCheckedContinuation { startWaiters[count] = $0 }
    }

    func releaseAll() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func startedTitles() -> [String] { inputs.map(\.title) }
}

private actor ImageLoadGate {
    private let data: Data
    private var calls = 0
    private var suspendedLoads = 0
    private var didStart: CheckedContinuation<Void, Never>?
    private var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var suspensionWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(data: Data) { self.data = data }

    func load() async throws -> Data {
        calls += 1
        didStart?.resume()
        didStart = nil
        let readyCounts = startWaiters.keys.filter { calls >= $0 }
        for count in readyCounts { startWaiters.removeValue(forKey: count)?.resume() }
        await withCheckedContinuation { continuation in
            suspendedLoads += 1
            let readyCounts = suspensionWaiters.keys.filter { suspendedLoads >= $0 }
            for count in readyCounts { suspensionWaiters.removeValue(forKey: count)?.resume() }
            releaseWaiters.append(continuation)
        }
        return data
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { didStart = $0 }
    }

    func waitUntilStarted(count: Int) async {
        guard calls < count else { return }
        await withCheckedContinuation { startWaiters[count] = $0 }
    }

    func waitUntilSuspended() async {
        await waitUntilSuspended(count: 1)
    }

    func waitUntilSuspended(count: Int) async {
        guard suspendedLoads < count else { return }
        await withCheckedContinuation { suspensionWaiters[count] = $0 }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func callCount() -> Int { calls }
}

private actor PrioritizedImageLoadGate {
    private let data: Data
    private var urls: [URL] = []
    private var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(data: Data) { self.data = data }

    func load(url: URL) async throws -> Data {
        urls.append(url)
        resumeStartWaiters()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return data
    }

    func waitUntilStarted(count: Int) async {
        guard urls.count < count else { return }
        await withCheckedContinuation { startWaiters[count] = $0 }
    }

    func releaseOne() {
        guard !releaseWaiters.isEmpty else { return }
        releaseWaiters.removeFirst().resume()
    }

    func releaseAll() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func startedURLs() -> [URL] { urls }

    private func resumeStartWaiters() {
        let readyCounts = startWaiters.keys.filter { urls.count >= $0 }
        for count in readyCounts { startWaiters.removeValue(forKey: count)?.resume() }
    }
}
