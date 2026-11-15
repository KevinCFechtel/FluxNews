import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private let widgetGroup = "group.dev.kevincfechtel.fluxNews"
private let largePageKey = "largePage"
private let extraLargePageKey = "extraLargePage"
private let snapshotKey = "snapshot"
private let statusSnapshotKey = "statusSnapshot"
private let headlinesWidgetKind = "FluxNewsHeadlinesWidget"
private let statusWidgetKind = "FluxNewsCompactStatusWidget"
private let iPhoneLargePageSize = 7
private let iPadLargePageSize = 6
private let extraLargePageSize = 12

private func largePageSizeForCurrentDevice() -> Int {
  UIDevice.current.userInterfaceIdiom == .pad ? iPadLargePageSize : iPhoneLargePageSize
}

private func updatePage(key: String, pageSize: Int, by delta: Int) {
  guard let defaults = UserDefaults(suiteName: widgetGroup) else { return }
  let currentPage = max(0, defaults.integer(forKey: key))
  let pageCount = max(1, Int(ceil(Double(currentSnapshotItemCount(defaults)) / Double(pageSize))))
  let clampedCurrentPage = min(currentPage, pageCount - 1)
  defaults.set(min(max(0, clampedCurrentPage + delta), pageCount - 1), forKey: key)
  WidgetCenter.shared.reloadTimelines(ofKind: headlinesWidgetKind)
}

private func currentSnapshotItemCount(_ defaults: UserDefaults) -> Int {
  guard let json = defaults.string(forKey: snapshotKey),
        let data = json.data(using: .utf8),
        let snapshot = try? JSONDecoder().decode(FluxNewsWidgetSnapshot.self, from: data) else {
    return 0
  }
  return snapshot.items.count
}

struct FluxNewsPreviousPageIntent: AppIntent {
  static var title: LocalizedStringResource = "Previous headlines"

  func perform() async throws -> some IntentResult {
    updatePage(key: largePageKey, pageSize: largePageSizeForCurrentDevice(), by: -1)
    return .result()
  }
}

struct FluxNewsNextPageIntent: AppIntent {
  static var title: LocalizedStringResource = "Next headlines"

  func perform() async throws -> some IntentResult {
    updatePage(key: largePageKey, pageSize: largePageSizeForCurrentDevice(), by: 1)
    return .result()
  }
}

struct FluxNewsPreviousExtraLargePageIntent: AppIntent {
  static var title: LocalizedStringResource = "Previous headlines"

  func perform() async throws -> some IntentResult {
    updatePage(key: extraLargePageKey, pageSize: extraLargePageSize, by: -1)
    return .result()
  }
}

struct FluxNewsNextExtraLargePageIntent: AppIntent {
  static var title: LocalizedStringResource = "Next headlines"

  func perform() async throws -> some IntentResult {
    updatePage(key: extraLargePageKey, pageSize: extraLargePageSize, by: 1)
    return .result()
  }
}

struct FluxNewsWidgetItem: Decodable, Identifiable {
  let id: Int
  let title: String
  let feedTitle: String
  let publishedAt: String
  let status: String
  let feedInitial: String?
  let iconData: String?
  let iconMimeType: String?
  let manualAdaptLightModeToIcon: Bool?
  let manualAdaptDarkModeToIcon: Bool?
}

struct FluxNewsWidgetSnapshot: Decodable {
  let displayTitle: String?
  let unreadCount: Int
  let countLabel: String?
  let lastSyncLabel: String?
  let neverLabel: String?
  let syncLabel: String?
  let translucentBackground: Bool?
  let lastUpdated: String
  let items: [FluxNewsWidgetItem]

  static var fallback: FluxNewsWidgetSnapshot {
    FluxNewsWidgetSnapshot(
      displayTitle: "All News",
      unreadCount: 0,
      countLabel: "unread",
      lastSyncLabel: "Last sync",
      neverLabel: "never",
      syncLabel: "Sync",
      translucentBackground: nil,
      lastUpdated: "",
      items: []
    )
  }
}

struct FluxNewsStatusSnapshot: Decodable {
  let displayTitle: String?
  let unreadCount: Int
  let countLabel: String?
  let lastSyncLabel: String?
  let neverLabel: String?
  let syncLabel: String?
  let lastUpdated: String

  static var fallback: FluxNewsStatusSnapshot {
    FluxNewsStatusSnapshot(
      displayTitle: "All News",
      unreadCount: 0,
      countLabel: "unread",
      lastSyncLabel: "Last sync",
      neverLabel: "never",
      syncLabel: "Sync",
      lastUpdated: ""
    )
  }
}

struct FluxNewsEntry: TimelineEntry {
  let date: Date
  let snapshot: FluxNewsWidgetSnapshot
}

struct FluxNewsStatusEntry: TimelineEntry {
  let date: Date
  let snapshot: FluxNewsStatusSnapshot
}

private func loadFluxNewsSnapshot() -> FluxNewsWidgetSnapshot {
  guard let defaults = UserDefaults(suiteName: widgetGroup),
        let json = defaults.string(forKey: snapshotKey),
        let data = json.data(using: .utf8),
        let snapshot = try? JSONDecoder().decode(FluxNewsWidgetSnapshot.self, from: data) else {
    return .fallback
  }
  return snapshot
}

private func loadFluxNewsStatusSnapshot() -> FluxNewsStatusSnapshot {
  guard let defaults = UserDefaults(suiteName: widgetGroup),
        let json = defaults.string(forKey: statusSnapshotKey),
        let data = json.data(using: .utf8),
        let snapshot = try? JSONDecoder().decode(FluxNewsStatusSnapshot.self, from: data) else {
    return .fallback
  }
  return snapshot
}

private func nextWidgetRefreshDate() -> Date {
  Calendar.current.date(
    byAdding: .minute,
    value: 15,
    to: Date()
  ) ?? Date().addingTimeInterval(15 * 60)
}

struct FluxNewsProvider: TimelineProvider {
  func placeholder(in context: Context) -> FluxNewsEntry {
    FluxNewsEntry(date: Date(), snapshot: .fallback)
  }

  func getSnapshot(in context: Context, completion: @escaping (FluxNewsEntry) -> Void) {
    completion(FluxNewsEntry(date: Date(), snapshot: loadFluxNewsSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FluxNewsEntry>) -> Void) {
    let entry = FluxNewsEntry(date: Date(), snapshot: loadFluxNewsSnapshot())
    completion(Timeline(entries: [entry], policy: .after(nextWidgetRefreshDate())))
  }
}

struct FluxNewsStatusProvider: TimelineProvider {
  func placeholder(in context: Context) -> FluxNewsStatusEntry {
    FluxNewsStatusEntry(date: Date(), snapshot: .fallback)
  }

  func getSnapshot(in context: Context, completion: @escaping (FluxNewsStatusEntry) -> Void) {
    completion(FluxNewsStatusEntry(date: Date(), snapshot: loadFluxNewsStatusSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FluxNewsStatusEntry>) -> Void) {
    let entry = FluxNewsStatusEntry(date: Date(), snapshot: loadFluxNewsStatusSnapshot())
    completion(Timeline(entries: [entry], policy: .after(nextWidgetRefreshDate())))
  }
}

struct FluxNewsHeadlinesWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  let entry: FluxNewsEntry

  var body: some View {
    Group {
      VStack(alignment: .leading, spacing: headerSpacing) {
        headerRow
          .layoutPriority(3)

        syncStatusRow
          .layoutPriority(2)

        GeometryReader { geometry in
          itemListView(width: geometry.size.width)
          .clipped()
        }
        .layoutPriority(0)
        .clipped()
      }
      .padding(.horizontal, 12)
      .padding(.top, topPadding)
      .padding(.bottom, 8)
    }
    .containerBackground(for: .widget) {
      widgetBaseBackground
    }
    .foregroundStyle(widgetForeground)
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  }

  private var headerRow: some View {
    HStack(alignment: .center, spacing: 6) {
      Image("FluxNewsWidgetLogo")
        .resizable()
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

      Text(entry.snapshot.displayTitle ?? "All News")
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      Spacer(minLength: 4)

      Text("\(entry.snapshot.unreadCount)")
        .font(.callout)
        .fontWeight(.bold)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      Text(entry.snapshot.countLabel ?? "unread")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      Link(destination: URL(string: "fluxnews://widget/sync")!) {
        Image(systemName: "arrow.clockwise")
          .font(.caption)
          .frame(width: 24, height: 24)
          .background(.blue, in: Circle())
          .foregroundStyle(.white)
      }
      .accessibilityLabel(entry.snapshot.syncLabel ?? "Sync")
    }
  }

  private var syncStatusRow: some View {
    HStack(alignment: .center, spacing: 6) {
      Text(lastUpdatedText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Spacer(minLength: 4)

      if isPagedFamily {
        previousPageButton

        Text("\(effectiveLargePage + 1)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
          .frame(minWidth: 12)

        nextPageButton
      }
    }
  }

  @ViewBuilder
  private var previousPageButton: some View {
    if family == .systemExtraLarge {
      Button(intent: FluxNewsPreviousExtraLargePageIntent()) {
        pageIcon("chevron.up")
      }
      .buttonStyle(.plain)
      .disabled(!hasPreviousPage)
      .opacity(hasPreviousPage ? 1 : 0.35)
    } else {
      Button(intent: FluxNewsPreviousPageIntent()) {
        pageIcon("chevron.up")
      }
      .buttonStyle(.plain)
      .disabled(!hasPreviousPage)
      .opacity(hasPreviousPage ? 1 : 0.35)
    }
  }

  @ViewBuilder
  private var nextPageButton: some View {
    if family == .systemExtraLarge {
      Button(intent: FluxNewsNextExtraLargePageIntent()) {
        pageIcon("chevron.down")
      }
      .buttonStyle(.plain)
      .disabled(!hasNextPage)
      .opacity(hasNextPage ? 1 : 0.35)
    } else {
      Button(intent: FluxNewsNextPageIntent()) {
        pageIcon("chevron.down")
      }
      .buttonStyle(.plain)
      .disabled(!hasNextPage)
      .opacity(hasNextPage ? 1 : 0.35)
    }
  }

  private func pageIcon(_ systemName: String) -> some View {
    Image(systemName: systemName)
      .font(.caption2)
      .frame(width: 22, height: 20)
  }

  private func itemRow(_ item: FluxNewsWidgetItem) -> some View {
    Link(destination: URL(string: "fluxnews://widget/openNews?newsID=\(item.id)")!) {
      HStack(alignment: .center, spacing: 7) {
        FeedIconView(item: item)

        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(item.feedTitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private func itemListView(width: CGFloat) -> some View {
    if family == .systemExtraLarge {
      HStack(alignment: .top, spacing: 12) {
        itemColumn(Array(visibleItems(for: maxItems()).prefix(extraLargeColumnSize)))
          .frame(width: max(0, (width - 12) / 2), alignment: .topLeading)

        itemColumn(Array(visibleItems(for: maxItems()).dropFirst(extraLargeColumnSize)))
          .frame(width: max(0, (width - 12) / 2), alignment: .topLeading)
      }
      .frame(width: width, alignment: .topLeading)
    } else {
      itemColumn(visibleItems(for: maxItems()))
        .frame(width: width, alignment: .topLeading)
    }
  }

  private func itemColumn(_ items: [FluxNewsWidgetItem]) -> some View {
    VStack(alignment: .leading, spacing: rowSpacing) {
      ForEach(items) { item in
        itemRow(item)
      }
    }
  }

  private var widgetBaseBackground: Color {
    colorScheme == .dark
      ? Color(red: 0.09, green: 0.15, blue: 0.18)
      : Color(red: 0.95, green: 0.97, blue: 0.98)
  }

  private var widgetForeground: Color {
    colorScheme == .dark ? .white : Color(red: 0.08, green: 0.11, blue: 0.13)
  }

  private var rowSpacing: CGFloat {
    isPagedFamily ? 7 : 5
  }

  private var headerSpacing: CGFloat {
    isPagedFamily ? 6 : 5
  }

  private var topPadding: CGFloat {
    isPagedFamily ? 10 : 14
  }

  private func maxItems() -> Int {
    if family == .systemExtraLarge {
      return extraLargePageSize
    }
    if family == .systemLarge {
      return largePageSizeForCurrentDevice()
    }
    return 2
  }

  private var extraLargeColumnSize: Int {
    extraLargePageSize / 2
  }

  private func visibleItems(for pageSize: Int) -> [FluxNewsWidgetItem] {
    let items = entry.snapshot.items
    if !isPagedFamily {
      return Array(items.prefix(pageSize))
    }

    let start = effectiveLargePage(for: pageSize) * pageSize
    guard start < items.count else { return [] }
    let end = min(start + pageSize, items.count)
    return Array(items[start..<end])
  }

  private var requestedLargePage: Int {
    guard let defaults = UserDefaults(suiteName: widgetGroup) else { return 0 }
    return max(0, defaults.integer(forKey: pageKey))
  }

  private var effectiveLargePage: Int {
    effectiveLargePage(for: maxItems())
  }

  private func effectiveLargePage(for pageSize: Int) -> Int {
    let pageCount = max(1, Int(ceil(Double(entry.snapshot.items.count) / Double(pageSize))))
    return min(requestedLargePage, pageCount - 1)
  }

  private var hasPreviousPage: Bool {
    effectiveLargePage > 0
  }

  private var hasNextPage: Bool {
    (effectiveLargePage + 1) * maxItems() < entry.snapshot.items.count
  }

  private var isPagedFamily: Bool {
    family == .systemLarge || family == .systemExtraLarge
  }

  private var pageKey: String {
    family == .systemExtraLarge ? extraLargePageKey : largePageKey
  }

  private var lastUpdatedText: String {
    let label = entry.snapshot.lastSyncLabel ?? "Last sync"
    guard !entry.snapshot.lastUpdated.isEmpty else {
      return "\(label): \(entry.snapshot.neverLabel ?? "never")"
    }
    guard let date = Self.date(from: entry.snapshot.lastUpdated) else {
      return "\(label): \(entry.snapshot.lastUpdated)"
    }
    return "\(label): \(Self.localizedDateTimeFormatter.string(from: date))"
  }

  static func date(from value: String) -> Date? {
    for formatter in isoFormatters {
      if let date = formatter.date(from: value) {
        return date
      }
    }
    return nil
  }

  private static let isoFormatters: [DateFormatter] = {
    ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"].map { format in
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      return formatter
    }
  }()

  static let localizedDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
  }()
}

struct FeedIconView: View {
  @Environment(\.colorScheme) private var colorScheme
  let item: FluxNewsWidgetItem

  var body: some View {
    if let image = image {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .padding(1)
        .frame(width: 20, height: 20)
        .background(iconBackground, in: RoundedRectangle(cornerRadius: 4))
    } else {
      Text((item.feedInitial ?? "").prefix(1).uppercased())
        .font(.caption2)
        .fontWeight(.bold)
        .frame(width: 20, height: 20)
        .background(Color(red: 0.2, green: 0.37, blue: 0.42), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.white)
    }
  }

  private var iconBackground: Color {
    if colorScheme == .dark && item.manualAdaptDarkModeToIcon == true {
      return Color.white
    }
    if colorScheme == .light && item.manualAdaptLightModeToIcon == true {
      return Color.black
    }
    return Color.clear
  }

  private var image: UIImage? {
    guard let iconData = item.iconData,
          let data = Data(base64Encoded: iconData) else {
      return nil
    }
    return UIImage(data: data)
  }
}

struct FluxNewsStatusWidgetView: View {
  @Environment(\.colorScheme) private var colorScheme
  let entry: FluxNewsStatusEntry

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .center, spacing: 6) {
          Image("FluxNewsWidgetLogo")
            .resizable()
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

          Spacer(minLength: 0)
        }

        Text(entry.snapshot.displayTitle ?? "All News")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(widgetForeground)
          .lineLimit(2)
          .minimumScaleFactor(0.62)

        VStack(alignment: .leading, spacing: 1) {
          Text("\(entry.snapshot.unreadCount)")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundColor(widgetForeground)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(entry.snapshot.countLabel ?? "unread")
            .font(.caption)
            .foregroundColor(widgetSecondaryForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        Spacer(minLength: 0)

        Text(lastUpdatedText)
          .font(.caption2)
          .foregroundColor(widgetSecondaryForeground)
          .lineLimit(2)
          .minimumScaleFactor(0.65)
      }

      Image(systemName: "arrow.clockwise")
        .font(.caption2)
        .symbolRenderingMode(.monochrome)
        .frame(width: 20, height: 20)
        .background(.blue, in: Circle())
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .accessibilityLabel(entry.snapshot.syncLabel ?? "Sync")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(.horizontal, 10)
    .padding(.top, 10)
    .padding(.bottom, 8)
    .containerBackground(for: .widget) {
      widgetBaseBackground
    }
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .unredacted()
    .widgetURL(URL(string: "fluxnews://widget/sync"))
  }

  private var widgetBaseBackground: Color {
    colorScheme == .dark
      ? Color(red: 0.09, green: 0.15, blue: 0.18)
      : Color(red: 0.95, green: 0.97, blue: 0.98)
  }

  private var widgetForeground: Color {
    colorScheme == .dark ? .white : Color(red: 0.08, green: 0.11, blue: 0.13)
  }

  private var widgetSecondaryForeground: Color {
    colorScheme == .dark
      ? Color(red: 0.78, green: 0.84, blue: 0.86)
      : Color(red: 0.33, green: 0.42, blue: 0.46)
  }

  private var lastUpdatedText: String {
    let label = entry.snapshot.lastSyncLabel ?? "Last sync"
    guard !entry.snapshot.lastUpdated.isEmpty else {
      return "\(label): \(entry.snapshot.neverLabel ?? "never")"
    }
    guard let date = FluxNewsHeadlinesWidgetView.date(from: entry.snapshot.lastUpdated) else {
      return "\(label): \(entry.snapshot.lastUpdated)"
    }
    return "\(label): \(FluxNewsHeadlinesWidgetView.localizedDateTimeFormatter.string(from: date))"
  }
}

struct FluxNewsHeadlinesWidget: Widget {
  let kind = headlinesWidgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FluxNewsProvider()) { entry in
      FluxNewsHeadlinesWidgetView(entry: entry)
    }
    .configurationDisplayName("Flux News")
    .description("Unread count and latest headlines.")
    .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    .contentMarginsDisabled()
  }
}

struct FluxNewsStatusWidget: Widget {
  let kind = statusWidgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FluxNewsStatusProvider()) { entry in
      FluxNewsStatusWidgetView(entry: entry)
    }
    .configurationDisplayName("Flux News Status")
    .description("Unread count and latest sync status.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

@main
struct FluxNewsWidgetsBundle: WidgetBundle {
  var body: some Widget {
    FluxNewsStatusWidget()
    FluxNewsHeadlinesWidget()
  }
}
