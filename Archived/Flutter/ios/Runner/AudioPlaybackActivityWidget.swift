import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
#Preview("AudioPlayback", as: .dynamicIsland(.compact)) {
  AudioPlaybackActivityWidget()
} timeline: {
  let attributes = AudioPlaybackActivityAttributes(activityIdentifier: "preview")
  let state = AudioPlaybackActivityAttributes.ContentState(
    itemTitle: "Test Episode",
    feedTitle: "Test Feed",
    isPlaying: true,
    currentPosition: 30,
    duration: 3600,
    artworkUrl: nil
  )
  return [.init(state: state, stateEvents: [])]
}

@available(iOS 16.1, *)
struct AudioPlaybackActivityWidget: Widget {
  let kind: String = "AudioPlaybackWidget"

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AudioPlaybackActivityAttributes.self) { context in
      AudioPlaybackLiveActivityView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 4) {
            Text(context.state.itemTitle)
              .font(.system(.headline, design: .default))
              .lineLimit(2)
              .fontWeight(.bold)

            Text(context.state.feedTitle)
              .font(.system(.subheadline, design: .default))
              .lineLimit(1)
              .opacity(0.7)
          }
          .padding(.leading)
        }

        DynamicIslandExpandedRegion(.trailing) {
          HStack(spacing: 12) {
            Button(intent: AudioPlaybackToggleIntent(id: context.attributes.activityIdentifier)) {
              Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Button(intent: AudioPlaybackSkipIntent(id: context.attributes.activityIdentifier)) {
              Image(systemName: "forward.30")
                .font(.system(size: 14))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
          }
          .padding(.trailing)
        }

        DynamicIslandExpandedRegion(.center) {
          ProgressView(value: Double(context.state.currentPosition), total: Double(max(context.state.duration, 1)))
            .tint(.white)
            .padding(.horizontal)
        }

        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(formatTime(context.state.currentPosition))
              .font(.caption2)
              .foregroundColor(.gray)

            Spacer()

            Text(formatTime(context.state.duration))
              .font(.caption2)
              .foregroundColor(.gray)
          }
          .padding(.horizontal)
        }
      } compactLeading: {
        Image(systemName: context.state.isPlaying ? "play.circle.fill" : "pause.circle.fill")
          .font(.system(size: 16))
          .foregroundColor(.white)
      } compactTrailing: {
        HStack(spacing: 6) {
          Button(intent: AudioPlaybackToggleIntent(id: context.attributes.activityIdentifier)) {
            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 10))
              .foregroundColor(.white)
          }
          .buttonStyle(.plain)
        }
      } minimal: {
        Image(systemName: context.state.isPlaying ? "play.circle.fill" : "pause.circle.fill")
          .foregroundColor(.white)
      }
    }
  }

  private func formatTime(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%d:%02d", minutes, secs)
    }
  }
}

@available(iOS 16.1, *)
struct AudioPlaybackLiveActivityView: View {
  let context: ActivityViewContext<AudioPlaybackActivityAttributes>

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
        .font(.system(size: 12))
        .foregroundColor(.white)

      VStack(alignment: .leading, spacing: 2) {
        Text(context.state.itemTitle)
          .font(.system(.caption, design: .default))
          .lineLimit(1)
          .fontWeight(.semibold)

        Text(context.state.feedTitle)
          .font(.system(.caption2, design: .default))
          .lineLimit(1)
          .opacity(0.7)
      }

      Spacer()

      HStack(spacing: 8) {
        Button(intent: AudioPlaybackToggleIntent(id: context.attributes.activityIdentifier)) {
          Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)

        Button(intent: AudioPlaybackSkipIntent(id: context.attributes.activityIdentifier)) {
          Image(systemName: "forward.30")
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }
}

// MARK: - Intents für Steuerung
@available(iOS 16.1, *)
struct AudioPlaybackToggleIntent: AppIntent {
  static let title: LocalizedStringResource = "Play/Pause"
  static let description: IntentDescription = IntentDescription("Toggle playback of the audio")

  @Parameter(title: "Activity ID")
  var id: String

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: NSNotification.Name("AudioPlaybackToggle"), object: id)
    return .result()
  }
}

@available(iOS 16.1, *)
struct AudioPlaybackSkipIntent: AppIntent {
  static let title: LocalizedStringResource = "Skip Forward"
  static let description: IntentDescription = IntentDescription("Skip forward 30 seconds")

  @Parameter(title: "Activity ID")
  var id: String

  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: NSNotification.Name("AudioPlaybackSkip"), object: id)
    return .result()
  }
}
