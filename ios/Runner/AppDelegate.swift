import ActivityKit
import Flutter
import UIKit

// Shared engine used by both the main window scene and the flutter_carplay plugin.
let sharedFlutterEngine = FlutterEngine(name: "SharedEngine", project: nil, allowHeadlessExecution: true)

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    sharedFlutterEngine.run()
    GeneratedPluginRegistrant.register(with: sharedFlutterEngine)

    if #available(iOS 16.1, *) {
      setupDynamicIslandChannel()
    }

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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @available(iOS 16.1, *)
  private func setupDynamicIslandChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    
    let methodChannel = FlutterMethodChannel(
      name: "dev.kevincfechtel.fluxnews/dynamicisland",
      binaryMessenger: controller.binaryMessenger
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
