import SwiftUI
import UIKit
import WidgetKit

private let widgetGroup = "group.dev.kevincfechtel.fluxNews"

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
  let unreadCount: Int
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
      unreadCount: 0,
      lastUpdated: "",
      items: []
    ))
  }

  func getSnapshot(in context: Context, completion: @escaping (FluxNewsEntry) -> Void) {
    completion(FluxNewsEntry(date: Date(), snapshot: loadSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FluxNewsEntry>) -> Void) {
    let entry = FluxNewsEntry(date: Date(), snapshot: loadSnapshot())
    completion(Timeline(entries: [entry], policy: .never))
  }

  private func loadSnapshot() -> FluxNewsWidgetSnapshot {
    guard let defaults = UserDefaults(suiteName: widgetGroup),
          let json = defaults.string(forKey: "snapshot"),
          let data = json.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(FluxNewsWidgetSnapshot.self, from: data) else {
      return FluxNewsWidgetSnapshot(unreadCount: 0, lastUpdated: "", items: [])
    }
    return snapshot
  }
}

struct FluxNewsHeadlinesWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  let entry: FluxNewsEntry

  var body: some View {
    VStack(alignment: .leading, spacing: rowSpacing) {
      HStack(alignment: .center, spacing: 6) {
        Text("Flux News")
          .font(.subheadline)
          .fontWeight(.semibold)
          .lineLimit(1)
          .minimumScaleFactor(0.85)

        Spacer(minLength: 4)

        Text("\(entry.snapshot.unreadCount)")
          .font(.callout)
          .fontWeight(.bold)
          .lineLimit(1)

        Text("unread")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Link(destination: URL(string: "fluxnews://widget/sync")!) {
          Image(systemName: "arrow.clockwise")
            .font(.caption)
            .frame(width: 24, height: 24)
            .background(.blue, in: Circle())
            .foregroundStyle(.white)
        }
      }

      Text(lastUpdatedText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      ForEach(Array(entry.snapshot.items.prefix(maxItems))) { item in
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

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.top, topPadding)
    .padding(.bottom, 8)
    .containerBackground(widgetBackground, for: .widget)
    .foregroundStyle(widgetForeground)
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

  private var topPadding: CGFloat {
    family == .systemLarge ? 10 : 14
  }

  private var maxItems: Int {
    family == .systemLarge ? 7 : 3
  }

  private var lastUpdatedText: String {
    guard !entry.snapshot.lastUpdated.isEmpty else { return "Last sync: never" }
    guard let date = Self.isoFormatter.date(from: entry.snapshot.lastUpdated) else {
      return "Last sync: \(entry.snapshot.lastUpdated)"
    }
    return "Last sync: \(Self.localizedDateTimeFormatter.string(from: date))"
  }

  private static let isoFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return formatter
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
  let kind = "FluxNewsHeadlinesWidget"

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
