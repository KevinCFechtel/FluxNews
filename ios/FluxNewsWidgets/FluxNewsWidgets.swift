import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private let widgetGroup = "group.dev.kevincfechtel.fluxNews"
private let largePageKey = "largePage"
private let snapshotKey = "snapshot"
private let widgetKind = "FluxNewsHeadlinesWidget"
private let largePageSize = 7

private func updateLargePage(by delta: Int) {
  guard let defaults = UserDefaults(suiteName: widgetGroup) else { return }
  let currentPage = max(0, defaults.integer(forKey: largePageKey))
  let pageCount = max(1, Int(ceil(Double(currentSnapshotItemCount(defaults)) / Double(largePageSize))))
  let clampedCurrentPage = min(currentPage, pageCount - 1)
  defaults.set(min(max(0, clampedCurrentPage + delta), pageCount - 1), forKey: largePageKey)
  WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
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
    updateLargePage(by: -1)
    return .result()
  }
}

struct FluxNewsNextPageIntent: AppIntent {
  static var title: LocalizedStringResource = "Next headlines"

  func perform() async throws -> some IntentResult {
    updateLargePage(by: 1)
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
  let lastUpdated: String
  let items: [FluxNewsWidgetItem]
}

struct FluxNewsEntry: TimelineEntry {
  let date: Date
  let snapshot: FluxNewsWidgetSnapshot
}

struct FluxNewsProvider: TimelineProvider {
  func placeholder(in context: Context) -> FluxNewsEntry {
    FluxNewsEntry(date: Date(), snapshot: FluxNewsWidgetSnapshot(
      displayTitle: nil,
      unreadCount: 0,
      countLabel: nil,
      lastSyncLabel: nil,
      neverLabel: nil,
      syncLabel: nil,
      lastUpdated: "",
      items: []
    ))
  }

  func getSnapshot(in context: Context, completion: @escaping (FluxNewsEntry) -> Void) {
    completion(FluxNewsEntry(date: Date(), snapshot: loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FluxNewsEntry>) -> Void) {
    let entry = FluxNewsEntry(date: Date(), snapshot: loadSnapshot())
    let nextRefresh = Calendar.current.date(
      byAdding: .minute,
      value: 15,
      to: Date()
    ) ?? Date().addingTimeInterval(15 * 60)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }

  private func loadSnapshot() -> FluxNewsWidgetSnapshot {
    guard let defaults = UserDefaults(suiteName: widgetGroup),
          let json = defaults.string(forKey: snapshotKey),
          let data = json.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(FluxNewsWidgetSnapshot.self, from: data) else {
      return FluxNewsWidgetSnapshot(
        displayTitle: nil,
        unreadCount: 0,
        countLabel: nil,
        lastSyncLabel: nil,
        neverLabel: nil,
        syncLabel: nil,
        lastUpdated: "",
        items: []
      )
    }
    return snapshot
  }
}

struct FluxNewsHeadlinesWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  let entry: FluxNewsEntry

  var body: some View {
    VStack(alignment: .leading, spacing: headerSpacing) {
      headerRow
        .layoutPriority(3)

      syncStatusRow
        .layoutPriority(2)

      GeometryReader { geometry in
        VStack(alignment: .leading, spacing: rowSpacing) {
          ForEach(visibleItems) { item in
            itemRow(item)
          }
        }
        .frame(width: geometry.size.width, alignment: .topLeading)
        .clipped()
      }
      .layoutPriority(0)
      .clipped()
    }
    .padding(.horizontal, 12)
    .padding(.top, topPadding)
    .padding(.bottom, 8)
    .containerBackground(widgetBackground, for: .widget)
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

      if family == .systemLarge {
        Button(intent: FluxNewsPreviousPageIntent()) {
          Image(systemName: "chevron.up")
            .font(.caption2)
            .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!hasPreviousPage)
        .opacity(hasPreviousPage ? 1 : 0.35)

        Text("\(effectiveLargePage + 1)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
          .frame(minWidth: 12)

        Button(intent: FluxNewsNextPageIntent()) {
          Image(systemName: "chevron.down")
            .font(.caption2)
            .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!hasNextPage)
        .opacity(hasNextPage ? 1 : 0.35)
      }
    }
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

  private var widgetBackground: Color {
    colorScheme == .dark
      ? Color(red: 0.09, green: 0.15, blue: 0.18)
      : Color(red: 0.95, green: 0.97, blue: 0.98)
  }

  private var widgetForeground: Color {
    colorScheme == .dark ? .white : Color(red: 0.08, green: 0.11, blue: 0.13)
  }

  private var rowSpacing: CGFloat {
    family == .systemLarge ? 7 : 5
  }

  private var headerSpacing: CGFloat {
    family == .systemLarge ? 6 : 5
  }

  private var topPadding: CGFloat {
    family == .systemLarge ? 10 : 14
  }

  private var maxItems: Int {
    family == .systemLarge ? largePageSize : 2
  }

  private var visibleItems: [FluxNewsWidgetItem] {
    let items = entry.snapshot.items
    if family != .systemLarge {
      return Array(items.prefix(maxItems))
    }

    let start = effectiveLargePage * maxItems
    guard start < items.count else { return [] }
    let end = min(start + maxItems, items.count)
    return Array(items[start..<end])
  }

  private var requestedLargePage: Int {
    guard let defaults = UserDefaults(suiteName: widgetGroup) else { return 0 }
    return max(0, defaults.integer(forKey: largePageKey))
  }

  private var effectiveLargePage: Int {
    let pageCount = max(1, Int(ceil(Double(entry.snapshot.items.count) / Double(maxItems))))
    return min(requestedLargePage, pageCount - 1)
  }

  private var hasPreviousPage: Bool {
    effectiveLargePage > 0
  }

  private var hasNextPage: Bool {
    (effectiveLargePage + 1) * maxItems < entry.snapshot.items.count
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

  private static func date(from value: String) -> Date? {
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

  private static let localizedDateTimeFormatter: DateFormatter = {
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

struct FluxNewsHeadlinesWidget: Widget {
  let kind = widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FluxNewsProvider()) { entry in
      FluxNewsHeadlinesWidgetView(entry: entry)
    }
    .configurationDisplayName("Flux News")
    .description("Unread count and latest headlines.")
    .supportedFamilies([.systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

@main
struct FluxNewsWidgetsBundle: WidgetBundle {
  var body: some Widget {
    FluxNewsHeadlinesWidget()
  }
}
