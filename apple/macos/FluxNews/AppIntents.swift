import AppIntents

struct FeedAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("entity.feed.type", defaultValue: "Feed"))
    static let defaultQuery = FeedEntityQuery()
    let id: String
    let title: String
    let categoryTitle: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(categoryTitle)") }
}

struct FeedEntityQuery: EntityQuery {
    func entities(for identifiers: [FeedAppEntity.ID]) async throws -> [FeedAppEntity] { await MainActor.run { AppRouter.shared.catalog.feeds.filter { identifiers.contains(String($0.id)) }.map { FeedAppEntity(id: String($0.id), title: $0.title, categoryTitle: $0.categoryTitle) } } }
    func suggestedEntities() async throws -> [FeedAppEntity] { await MainActor.run { AppRouter.shared.catalog.feeds.map { FeedAppEntity(id: String($0.id), title: $0.title, categoryTitle: $0.categoryTitle) } } }
}

struct CategoryAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("entity.category.type", defaultValue: "Category"))
    static let defaultQuery = CategoryEntityQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct CategoryEntityQuery: EntityQuery {
    func entities(for identifiers: [CategoryAppEntity.ID]) async throws -> [CategoryAppEntity] { await MainActor.run { AppRouter.shared.catalog.categories.filter { identifiers.contains(String($0.id)) }.map { CategoryAppEntity(id: String($0.id), title: $0.title) } } }
    func suggestedEntities() async throws -> [CategoryAppEntity] { await MainActor.run { AppRouter.shared.catalog.categories.map { CategoryAppEntity(id: String($0.id), title: $0.title) } } }
}

struct OpenFluxNewsIntent: AppIntent {
    static let title = LocalizedStringResource("intent.open.title", defaultValue: "Open FluxNews")
    static let description = IntentDescription(LocalizedStringResource("intent.open.description", defaultValue: "Open the FluxNews inbox."))
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { await MainActor.run { AppRouter.shared.open(.all) }; return .result() }
}

struct ShowStarredIntent: AppIntent {
    static let title = LocalizedStringResource("intent.starred.title", defaultValue: "Show Starred")
    static let description = IntentDescription(LocalizedStringResource("intent.starred.description", defaultValue: "Open starred articles in FluxNews."))
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { await MainActor.run { AppRouter.shared.open(.starred) }; return .result() }
}

struct RefreshFluxNewsIntent: AppIntent {
    static let title = LocalizedStringResource("intent.refresh.title", defaultValue: "Refresh FluxNews")
    static let description = IntentDescription(LocalizedStringResource("intent.refresh.description", defaultValue: "Refresh FluxNews from Miniflux."))
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { await MainActor.run { AppRouter.shared.refresh() }; return .result() }
}

struct OpenFeedIntent: AppIntent {
    static let title = LocalizedStringResource("intent.feed.title", defaultValue: "Open Feed")
    static let description = IntentDescription(LocalizedStringResource("intent.feed.description", defaultValue: "Open a specific feed in FluxNews."))
    static let openAppWhenRun = true
    @Parameter(title: LocalizedStringResource("intent.feed.parameter", defaultValue: "Feed")) var feed: FeedAppEntity
    init() {}
    init(feed: FeedAppEntity) { self.feed = feed }
    func perform() async throws -> some IntentResult { if let id = Int64(feed.id) { await MainActor.run { AppRouter.shared.open(.feed(id)) } }; return .result() }
}

struct OpenCategoryIntent: AppIntent {
    static let title = LocalizedStringResource("intent.category.title", defaultValue: "Open Category")
    static let description = IntentDescription(LocalizedStringResource("intent.category.description", defaultValue: "Open a specific category in FluxNews."))
    static let openAppWhenRun = true
    @Parameter(title: LocalizedStringResource("intent.category.parameter", defaultValue: "Category")) var category: CategoryAppEntity
    init() {}
    init(category: CategoryAppEntity) { self.category = category }
    func perform() async throws -> some IntentResult { if let id = Int64(category.id) { await MainActor.run { AppRouter.shared.open(.category(id)) } }; return .result() }
}

struct FluxNewsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFluxNewsIntent(), phrases: ["Open \(.applicationName)"], shortTitle: LocalizedStringResource("intent.open.title", defaultValue: "Open FluxNews"), systemImageName: "newspaper")
        AppShortcut(intent: ShowStarredIntent(), phrases: ["Show starred in \(.applicationName)"], shortTitle: LocalizedStringResource("intent.starred.title", defaultValue: "Show Starred"), systemImageName: "star")
        AppShortcut(intent: RefreshFluxNewsIntent(), phrases: ["Refresh \(.applicationName)"], shortTitle: LocalizedStringResource("intent.refresh.title", defaultValue: "Refresh FluxNews"), systemImageName: "arrow.clockwise")
        AppShortcut(intent: OpenFeedIntent(), phrases: ["Open \(\.$feed) in \(.applicationName)"], shortTitle: LocalizedStringResource("intent.feed.title", defaultValue: "Open Feed"), systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: OpenCategoryIntent(), phrases: ["Open \(\.$category) in \(.applicationName)"], shortTitle: LocalizedStringResource("intent.category.title", defaultValue: "Open Category"), systemImageName: "folder")
    }
}
