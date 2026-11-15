import Flutter
import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    window = UIWindow(windowScene: windowScene)
    let controller = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    controller.view.backgroundColor = .systemBackground
    window?.backgroundColor = .systemBackground
    window?.rootViewController = controller
    window?.makeKeyAndVisible()

    if let url = connectionOptions.urlContexts.first?.url,
       let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      pendingWidgetAction = appDelegate.parseWidgetAction(url)
    }
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url,
          let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    pendingWidgetAction = appDelegate.parseWidgetAction(url)
  }
}
