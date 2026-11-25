import UIKit
import Capacitor
import WidgetKit

/// App Group shared with the home-screen / lock-screen widgets.
let baytnaGroup = "group.65170c5db5fc6542.1"

/// Hands the current list to the widgets and passes widget taps (baytna://add) back to the web app.
@objc(WidgetBridgePlugin)
public class WidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WidgetBridgePlugin"
    public let jsName = "WidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setItems", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "consumeAction", returnType: CAPPluginReturnPromise)
    ]
    static var pendingAction: String?

    @objc func setItems(_ call: CAPPluginCall) {
        let store = UserDefaults(suiteName: baytnaGroup) ?? UserDefaults.standard
        store.set(call.getString("items") ?? "[]", forKey: "items")
        store.set(call.getInt("count") ?? 0, forKey: "count")
        store.set(call.getBool("signedIn") ?? false, forKey: "signedIn")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }

    @objc func consumeAction(_ call: CAPPluginCall) {
        let action = WidgetBridgePlugin.pendingAction ?? ""
        WidgetBridgePlugin.pendingAction = nil
        call.resolve(["action": action])
    }
}

class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(WidgetBridgePlugin())
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        capture(connectionOptions.urlContexts)
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = MainViewController()
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if capture(URLContexts) {
            (window?.rootViewController as? CAPBridgeViewController)?.bridge?.triggerWindowJSEvent(eventName: "baytnaAction")
        }
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    @discardableResult
    private func capture(_ contexts: Set<UIOpenURLContext>) -> Bool {
        guard let url = contexts.first?.url, url.scheme == "baytna" else { return false }
        WidgetBridgePlugin.pendingAction = url.host
        return true
    }
}
