import ActivityKit
import Flutter
import UIKit
import WidgetKit
import workmanager_apple

let flutterEngine = FlutterEngine(name: "SharedEngine", project: nil, allowHeadlessExecution: true)
private let fluxNewsWidgetGroup = "group.dev.kevincfechtel.fluxNews"
private let fluxNewsBackgroundSyncIdentifier = "dev.kevincfechtel.fluxNews.backgroundSync"
private let fluxNewsBackgroundProcessingSyncIdentifier = "dev.kevincfechtel.fluxNews.backgroundProcessingSync"
var pendingWidgetAction: [String: String]?

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    if #available(iOS 16.1, *) {
      setupDynamicIslandChannel()
    }
    setupWidgetChannel()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: fluxNewsBackgroundSyncIdentifier,
      frequency: NSNumber(value: 30 * 60)
    )
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: fluxNewsBackgroundProcessingSyncIdentifier
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioPlaybackToggle(_:)),
      name: NSNotification.Name("AudioPlaybackToggle"),
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioPlaybackSkip(_:)),
      name: NSNotification.Name("AudioPlaybackSkip"),
      object: nil
    )

    return true
  }

  private func setupWidgetChannel() {
    let methodChannel = FlutterMethodChannel(
      name: "dev.kevincfechtel.fluxnews/widgets",
      binaryMessenger: flutterEngine.binaryMessenger
    )

    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveSnapshot":
        guard let args = call.arguments as? [String: Any],
              let snapshot = args["snapshot"] as? String,
              let defaults = UserDefaults(suiteName: fluxNewsWidgetGroup) else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid widget snapshot", details: nil))
          return
        }
        defaults.set(snapshot, forKey: "snapshot")
        defaults.synchronize()
        result(nil)
      case "reloadWidgets":
        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadTimelines(ofKind: "FluxNewsHeadlinesWidget")
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(nil)
      case "peekPendingAction":
        result(pendingWidgetAction)
      case "takePendingAction":
        result(pendingWidgetAction)
        pendingWidgetAction = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    pendingWidgetAction = parseWidgetAction(url)
    return pendingWidgetAction != nil
  }

  func parseWidgetAction(_ url: URL) -> [String: String]? {
    guard url.scheme == "fluxnews", url.host == "widget" else { return nil }
    if url.path == "/sync" {
      return ["action": "sync"]
    }
    if url.path == "/openNews",
       let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       let newsID = components.queryItems?.first(where: { $0.name == "newsID" })?.value {
      return ["action": "openNews", "newsID": newsID]
    }
    return nil
  }

  @available(iOS 16.1, *)
  private func setupDynamicIslandChannel() {
    let methodChannel = FlutterMethodChannel(
      name: "dev.kevincfechtel.fluxnews/dynamicisland",
      binaryMessenger: flutterEngine.binaryMessenger
    )

    methodChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startActivity":
        self?.startDynamicIslandActivity(call, result)
      case "updateActivity":
        self?.updateDynamicIslandActivity(call, result)
      case "endActivity":
        self?.endDynamicIslandActivity(call, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(iOS 16.1, *)
  private func startDynamicIslandActivity(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
      return
    }

    let itemTitle = args["itemTitle"] as? String ?? "Unknown"
    let feedTitle = args["feedTitle"] as? String ?? "Unknown Feed"
    let isPlaying = args["isPlaying"] as? Bool ?? false
    let currentPosition = args["currentPosition"] as? Int ?? 0
    let duration = args["duration"] as? Int ?? 0
    let artworkUrl = args["artworkUrl"] as? String
    let activityId = args["activityId"] as? String ?? UUID().uuidString

    let attributes = AudioPlaybackActivityAttributes(activityIdentifier: activityId)
    let state = AudioPlaybackActivityAttributes.ContentState(
      itemTitle: itemTitle,
      feedTitle: feedTitle,
      isPlaying: isPlaying,
      currentPosition: currentPosition,
      duration: duration,
      artworkUrl: artworkUrl
    )

    do {
      let activity = try Activity<AudioPlaybackActivityAttributes>.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )

      UserDefaults.standard.set(activity.id, forKey: "currentActivityId")
      result(activity.id)
    } catch {
      result(FlutterError(code: "ACTIVITY_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  @available(iOS 16.1, *)
  private func updateDynamicIslandActivity(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
      return
    }

    let itemTitle = args["itemTitle"] as? String ?? "Unknown"
    let feedTitle = args["feedTitle"] as? String ?? "Unknown Feed"
    let isPlaying = args["isPlaying"] as? Bool ?? false
    let currentPosition = args["currentPosition"] as? Int ?? 0
    let duration = args["duration"] as? Int ?? 0
    let artworkUrl = args["artworkUrl"] as? String

    let newState = AudioPlaybackActivityAttributes.ContentState(
      itemTitle: itemTitle,
      feedTitle: feedTitle,
      isPlaying: isPlaying,
      currentPosition: currentPosition,
      duration: duration,
      artworkUrl: artworkUrl
    )

    Task {
      for activity in Activity<AudioPlaybackActivityAttributes>.activities {
        await activity.update(using: newState)
      }
      result(nil)
    }
  }

  @available(iOS 16.1, *)
  private func endDynamicIslandActivity(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    Task {
      for activity in Activity<AudioPlaybackActivityAttributes>.activities {
        await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
      }
      UserDefaults.standard.removeObject(forKey: "currentActivityId")
      result(nil)
    }
  }

  @objc private func handleAudioPlaybackToggle(_ notification: NSNotification) {
    NotificationCenter.default.post(name: NSNotification.Name("ActivityKitPlayPause"), object: nil)
  }

  @objc private func handleAudioPlaybackSkip(_ notification: NSNotification) {
    NotificationCenter.default.post(name: NSNotification.Name("ActivityKitSkipForward"), object: nil)
  }
}
