import ActivityKit
import Flutter
import MediaPlayer
import UIKit

let flutterEngine = FlutterEngine(name: "SharedEngine", project: nil, allowHeadlessExecution: true)

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
    setupNowPlayingChannel()

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

  // Alternates between two imperceptibly different renders so that consecutive
  // calls with the same artwork file always produce pixel-unique images. This
  // forces iOS to emit a MPNowPlayingInfoCenter change notification even when
  // the source image is identical, preventing OEM infotainment (e.g. VW) from
  // suppressing the artwork update because its cached pixel data matches.
  private var _artworkTick = false

  private func setupNowPlayingChannel() {
    let channel = FlutterMethodChannel(
      name: "dev.kevincfechtel.fluxnews/nowplaying",
      binaryMessenger: flutterEngine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self,
            call.method == "setArtwork",
            let path = call.arguments as? String,
            let image = UIImage(contentsOfFile: path) else {
        result(nil)
        return
      }
      // Render a pixel-unique copy: one 1×1 px overlay at 1/255 opacity
      // (≈ 0.4%) alternating between near-black and near-white each call.
      // Visually indistinguishable from the original but always changes the
      // pixel bytes, so iOS never suppresses the nowPlayingInfo notification.
      self._artworkTick.toggle()
      let tick = self._artworkTick
      let format = UIGraphicsImageRendererFormat()
      format.scale = image.scale
      let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
      let uniqueImage = renderer.image { _ in
        image.draw(at: .zero)
        UIColor(white: tick ? 0.0 : 1.0, alpha: 1.0 / 255.0).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
      }
      let artwork = MPMediaItemArtwork(boundsSize: uniqueImage.size) { _ in uniqueImage }
      var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
      info[MPMediaItemPropertyArtwork] = artwork
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
