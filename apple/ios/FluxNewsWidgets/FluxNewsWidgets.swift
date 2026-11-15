import AppIntents
import SwiftUI
import UIKit
import WidgetKit

enum FluxNewsWidgetScope: String, AppEnum {
    case allNews
    case bookmarks
    case category
    case feed

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Content"))
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .allNews: .init(title: LocalizedStringResource("All News")), .bookmarks: .init(title: LocalizedStringResource("Bookmarks")), .category: .init(title: LocalizedStringResource("Category")), .feed: .init(title: LocalizedStringResource("Feed")),
    ]
}

enum FluxNewsWidgetReadFilter: String, AppEnum {
    case unread
    case all

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Read Filter")
    )
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .unread: .init(title: LocalizedStringResource("Unread")),
        .all: .init(title: LocalizedStringResource("All")),
    ]
}

enum FluxNewsWidgetSortOrder: String, AppEnum {
    case newestFirst
    case oldestFirst

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Sort Order")
    )
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .newestFirst: .init(title: LocalizedStringResource("Newest First")),
        .oldestFirst: .init(title: LocalizedStringResource("Oldest First")),
    ]
}

struct FluxNewsFeedEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Feed"))
    static var defaultQuery = FluxNewsFeedQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
}

struct FluxNewsCategoryEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Category"))
    static var defaultQuery = FluxNewsCategoryQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
}

struct FluxNewsFeedQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FluxNewsFeedEntity] { entities().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [FluxNewsFeedEntity] { entities() }
    private func entities() -> [FluxNewsFeedEntity] {
        do {
            let store = try WidgetSnapshotStore(diagnostics: WidgetSnapshotDiagnostics.logger)
            return try store.read(diagnostics: WidgetSnapshotDiagnostics.logger)?.feeds.map { .init(id: String($0.id), title: $0.title) } ?? []
        } catch {
            WidgetSnapshotDiagnostics.logger.error("Widget feed configuration could not read snapshot error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

struct FluxNewsCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FluxNewsCategoryEntity] { entities().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [FluxNewsCategoryEntity] { entities() }
    private func entities() -> [FluxNewsCategoryEntity] {
        do {
            let store = try WidgetSnapshotStore(diagnostics: WidgetSnapshotDiagnostics.logger)
            return try store.read(diagnostics: WidgetSnapshotDiagnostics.logger)?.categories.map { .init(id: String($0.id), title: $0.title) } ?? []
        } catch {
            WidgetSnapshotDiagnostics.logger.error("Widget category configuration could not read snapshot error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

struct FluxNewsWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "FluxNews Widget"
    static var description = IntentDescription(LocalizedStringResource("Choose the FluxNews content this widget shows."))
    @Parameter(title: LocalizedStringResource("Content"), default: .allNews) var scope: FluxNewsWidgetScope
    @Parameter(title: LocalizedStringResource("Read Filter"), default: .unread) var readFilter: FluxNewsWidgetReadFilter
    @Parameter(title: LocalizedStringResource("Sort Order"), default: .newestFirst) var sortOrder: FluxNewsWidgetSortOrder
    @Parameter(title: LocalizedStringResource("Category")) var category: FluxNewsCategoryEntity?
    @Parameter(title: LocalizedStringResource("Feed")) var feed: FluxNewsFeedEntity?

    init() {
        guard let legacy = WidgetLegacyDefaultStore.load() else { return }

        scope = FluxNewsWidgetScope(rawValue: legacy.scope.rawValue) ?? .allNews
        readFilter = FluxNewsWidgetReadFilter(rawValue: legacy.readFilter.rawValue) ?? .unread
        sortOrder = FluxNewsWidgetSortOrder(rawValue: legacy.sortOrder.rawValue) ?? .newestFirst

        switch legacy.scope {
        case .category:
            if let categoryID = legacy.categoryID {
                category = Self.categoryEntity(id: categoryID)
            }
        case .feed:
            if let feedID = legacy.feedID {
                feed = Self.feedEntity(id: feedID)
            }
        case .allNews, .bookmarks:
            break
        }
    }

    private static func categoryEntity(id: Int64) -> FluxNewsCategoryEntity {
        let title = (try? WidgetSnapshotStore().read()?.categories.first(where: { $0.id == id })?.title)
            ?? String(localized: "Category")
        return .init(id: String(id), title: title)
    }

    private static func feedEntity(id: Int64) -> FluxNewsFeedEntity {
        let title = (try? WidgetSnapshotStore().read()?.feeds.first(where: { $0.id == id })?.title)
            ?? String(localized: "Feed")
        return .init(id: String(id), title: title)
    }
}

struct FluxNewsWidgetEntry: TimelineEntry {
    let date: Date
    let model: WidgetContentModel
    let snapshot: WidgetSnapshotV1?
    let selection: WidgetContentSelection
}

struct FluxNewsWidgetProvider: AppIntentTimelineProvider {
    private static let fallbackRefreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> FluxNewsWidgetEntry {
        .init(date: .now, model: .init(state: .ready, title: "All News", count: 12, countLabel: "unread", articles: [], lastSuccessfulSyncAt: nil), snapshot: nil, selection: .init(scope: .allNews, categoryID: nil, feedID: nil))
    }
    func snapshot(for configuration: FluxNewsWidgetConfigurationIntent, in context: Context) async -> FluxNewsWidgetEntry { entry(configuration) }
    func timeline(for configuration: FluxNewsWidgetConfigurationIntent, in context: Context) async -> Timeline<FluxNewsWidgetEntry> {
        let currentEntry = entry(configuration)
        return .init(
            entries: [currentEntry],
            policy: .after(currentEntry.date.addingTimeInterval(Self.fallbackRefreshInterval))
        )
    }
    private func entry(_ configuration: FluxNewsWidgetConfigurationIntent) -> FluxNewsWidgetEntry {
        let result: Result<WidgetSnapshotV1?, Error> = Result {
            let store = try WidgetSnapshotStore(diagnostics: WidgetSnapshotDiagnostics.logger)
            return try store.read(diagnostics: WidgetSnapshotDiagnostics.logger)
        }
        let scope = WidgetContentScope(rawValue: configuration.scope.rawValue) ?? .allNews
        let selection = WidgetContentSelection(
            scope: scope,
            categoryID: configuration.category.flatMap { Int64($0.id) },
            feedID: configuration.feed.flatMap { Int64($0.id) },
            readFilter: WidgetReadFilter(rawValue: configuration.readFilter.rawValue) ?? .unread,
            sortOrder: WidgetSortOrder(rawValue: configuration.sortOrder.rawValue) ?? .newestFirst
        )
        return .init(date: .now, model: WidgetContentModel.make(snapshotResult: result, selection: selection), snapshot: try? result.get(), selection: selection)
    }
}

struct FluxNewsHeadlinesWidget: Widget {
    let kind = FluxNewsWidgetKind.headlines
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FluxNewsWidgetConfigurationIntent.self, provider: FluxNewsWidgetProvider()) { entry in IOSFluxNewsHeadlinesView(entry: entry) }
            .configurationDisplayName("FluxNews Headlines")
            .description("Shows the latest articles from your selected FluxNews view.")
            .supportedFamilies(WidgetFamilyPolicy.headlineFamilies)
    }
}

struct FluxNewsCompactStatusWidget: Widget {
    let kind = FluxNewsWidgetKind.compactStatus
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FluxNewsWidgetConfigurationIntent.self, provider: FluxNewsWidgetProvider()) { entry in IOSFluxNewsStatusView(entry: entry) }
            .configurationDisplayName("FluxNews Status")
            .description("FluxNews count and last successful sync.")
            .supportedFamilies(WidgetFamilyPolicy.statusFamilies)
    }
}

private struct IOSFluxNewsHeadlinesView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: FluxNewsWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { header; content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.clear }
    }
    private var header: some View {
        HStack(spacing: 6) {
            FluxNewsWidgetBrandIcon()
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            Text("\(entry.model.count)").font(.headline.monospacedDigit())
            Text(LocalizedStringKey(entry.model.countLabel)).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var content: some View {
        switch entry.model.state {
        case .ready, .empty:
            if entry.model.articles.isEmpty { Text(emptyStateText).foregroundStyle(.secondary) }
            else { articleColumn(entry.model.latestArticles(limit: HeadlinesPresentation.capacity(for: family))) }
        case .noAccount: fallback("Open FluxNews to configure")
        case .awaitingSuccessfulSync: fallback("Waiting for first successful sync")
        case .missingSnapshot, .corruptSnapshot: fallback("No widget data available")
        case let .unavailableSelection(message): fallback(message)
        }
    }
    private func articleColumn(_ articles: [WidgetSnapshotV1.Article]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(articles, id: \.id) { article in
                Link(destination: WidgetAction.article(article.id).url()) {
                    HStack(spacing: 6) {
                        IOSWidgetFeedIcon(snapshot: entry.snapshot, feedID: article.feedID, title: article.feedTitle, dark: colorScheme == .dark)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(article.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(article.feedTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.accessibilityLabel("Open \(article.title) in FluxNews")
            }
        }
    }
    private func fallback(_ text: String) -> some View { Text(LocalizedStringKey(text)).font(.subheadline).foregroundStyle(.secondary) }
    private var emptyStateText: LocalizedStringKey {
        switch entry.model.countLabel {
        case "bookmarked": "No bookmarks"
        case "articles": "No articles"
        default: "No unread news"
        }
    }
    private var title: String {
        switch entry.selection.scope {
        case .allNews: String(localized: "All News")
        case .bookmarks: String(localized: "Bookmarks")
        case .category where entry.model.title == "Category": String(localized: "Category")
        case .feed where entry.model.title == "Feed": String(localized: "Feed")
        default: entry.model.title
        }
    }
}

private struct IOSFluxNewsStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FluxNewsWidgetEntry
    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemSmall: smallHomeScreen
            default: homeScreen
            }
        }.widgetURL(scopeURL)
    }
    private var inline: some View { Text("FluxNews · \(entry.model.count) \(localizedCountLabel)") }
    private var circular: some View {
        Gauge(value: min(Double(entry.model.count), 99), in: 0...99) { FluxNewsWidgetBrandIcon() } currentValueLabel: { Text("\(entry.model.count)").font(.headline.monospacedDigit()) }
            .gaugeStyle(.accessoryCircularCapacity)
    }
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .center, spacing: 5) {
                FluxNewsWidgetBrandIcon()
                    .frame(width: 18, height: 18)
                Text("\(entry.model.count)")
                    .font(.system(size: 17, weight: .bold, design: .default).monospacedDigit())
            }
            Text(LocalizedStringKey(entry.model.countLabel))
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var smallHomeScreen: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { FluxNewsWidgetBrandIcon().frame(width: 30, height: 30); Spacer() }
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text("\(entry.model.count)").font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit()
            Text(LocalizedStringKey(entry.model.countLabel)).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(lastSuccessfulSyncDate).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.containerBackground(for: .widget) { Color.clear }
    }
    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { FluxNewsWidgetBrandIcon().frame(width: 32, height: 32); Spacer() }
            Text(title).font(.headline).lineLimit(2)
            Text("\(entry.model.count)").font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
            Text(LocalizedStringKey(entry.model.countLabel)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(lastSuccessfulSync).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.containerBackground(for: .widget) { Color.clear }
    }
    private var scopeURL: URL { WidgetAction.open(entry.selection).url() }
    private var localizedCountLabel: String {
        switch entry.model.countLabel {
        case "bookmarked": String(localized: "bookmarked")
        case "articles": String(localized: "articles")
        default: String(localized: "unread")
        }
    }
    private var title: String {
        switch entry.selection.scope {
        case .allNews: String(localized: "All News")
        case .bookmarks: String(localized: "Bookmarks")
        case .category where entry.model.title == "Category": String(localized: "Category")
        case .feed where entry.model.title == "Feed": String(localized: "Feed")
        default: entry.model.title
        }
    }
    private var lastSuccessfulSyncDate: String {
        guard let value = entry.model.lastSuccessfulSyncAt, let date = WidgetSyncTimestamp.date(from: value) else { return String(localized: "Never") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    private var lastSuccessfulSync: String {
        guard let value = entry.model.lastSuccessfulSyncAt, let date = WidgetSyncTimestamp.date(from: value) else { return String(localized: "Never") }
        return String(format: String(localized: "Last sync: %@"), date.formatted(date: .abbreviated, time: .shortened))
    }
}

private struct FluxNewsWidgetBrandIcon: View {
    var body: some View { Image("FluxNewsTemplate").renderingMode(.template).resizable().scaledToFit().foregroundStyle(.tint).accessibilityHidden(true) }
}

private struct IOSWidgetFeedIcon: View {
    let snapshot: WidgetSnapshotV1?
    let feedID: Int64
    let title: String
    let dark: Bool
    var body: some View {
        Group {
            if let data = iconData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
            else { Text(title.prefix(1).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(.tint, in: RoundedRectangle(cornerRadius: 4)) }
        }.frame(width: 20, height: 20)
    }
    private var iconData: Data? {
        guard let feed = snapshot?.feeds.first(where: { $0.id == feedID }), let store = try? WidgetSnapshotStore() else { return nil }
        return store.readIcon(relativePath: dark ? feed.darkIconFile ?? feed.normalIconFile : feed.normalIconFile)
    }
}

@main
struct FluxNewsWidgetsBundle: WidgetBundle {
    var body: some Widget { FluxNewsHeadlinesWidget(); FluxNewsCompactStatusWidget() }
}
