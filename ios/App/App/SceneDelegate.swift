import UIKit
import Capacitor
import WidgetKit
import SafariServices
import Network
import Speech
import AVFoundation

/// App Group shared with the home-screen / lock-screen widgets.
let baytnaGroup = "group.65170c5db5fc6542.1"

/// Voice input for the assistant: listens until the speaker pauses, then hands back the text.
final class Dictation {
    static let shared = Dictation()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var text = ""
    private var done: ((String, String?) -> Void)?

    func start(lang: String, done: @escaping (String, String?) -> Void) {
        finish(nil)
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { DispatchQueue.main.async { done("", "denied") }; return }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted { self.begin(lang: lang, done: done) } else { done("", "denied") }
                }
            }
        }
    }

    private func begin(lang: String, done: @escaping (String, String?) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang)), recognizer.isAvailable else { done("", "unavailable"); return }
        self.done = done
        text = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let made = SFSpeechAudioBufferRecognitionRequest()
            made.shouldReportPartialResults = true
            request = made
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in made.append(buffer) }
            engine.prepare()
            try engine.start()
            task = recognizer.recognitionTask(with: made) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self, self.done != nil else { return }
                    if let result = result {
                        self.text = result.bestTranscription.formattedString
                        if result.isFinal { self.finish(nil) } else { self.wait(1.6) }
                    } else if error != nil {
                        self.finish(nil)
                    }
                }
            }
            wait(7)
        } catch {
            finish("unavailable")
        }
    }

    /// Ends after this much silence.
    private func wait(_ seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.finish(nil) }
    }

    func finish(_ error: String?) {
        timer?.invalidate()
        timer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        guard let deliver = done else { return }
        done = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        deliver(text, error)
    }
}

/// Catches the "Sign in with ChatGPT" callback: one request on 127.0.0.1, while the in-app browser is on screen.
final class AuthLoopback {
    static let shared = AuthLoopback()
    static let prefix = "/auth/callback?"
    static let page = "<!doctype html><html lang=\"ar\" dir=\"rtl\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>بيتنا</title><body style=\"margin:0;min-height:100vh;display:grid;place-items:center;background:#0B0B0C;color:#F5F1E8;font-family:system-ui,sans-serif;text-align:center\"><div><h1>تم الربط</h1><p>ارجع إلى تطبيق بيتنا.</p></div></body></html>"

    private let queue = DispatchQueue(label: "baytna.auth")
    private var listener: NWListener?
    var query: String?
    var onResult: (() -> Void)?

    func start(port: UInt16) throws {
        stop()
        query = nil
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: port) ?? 1455)
        let made = try NWListener(using: params)
        made.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        made.start(queue: queue)
        listener = made
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let parts = (text.components(separatedBy: "\r\n").first ?? "").components(separatedBy: " ")
            let target = parts.count > 1 ? parts[1] : ""
            let ok = target.hasPrefix(AuthLoopback.prefix)
            let body = ok ? AuthLoopback.page : "Not found"
            let head = "HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            guard ok, let self = self else { return }
            self.query = String(target.dropFirst(AuthLoopback.prefix.count))
            self.stop()
            DispatchQueue.main.async { self.onResult?() }
        }
    }
}

/// Hands the current list to the widgets and passes widget taps (baytna://add) back to the web app.
@objc(WidgetBridgePlugin)
public class WidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WidgetBridgePlugin"
    public let jsName = "WidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setItems", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "consumeAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "secureGet", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "secureSet", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openUrl", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authListen", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authResult", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setIcon", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listen", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopListening", returnType: CAPPluginReturnPromise)
    ]
    static var pendingAction: String?
    private weak var browser: SFSafariViewController?

    // The ChatGPT tokens stay in the app's own sandbox, not in the group shared with the widgets.
    @objc func secureGet(_ call: CAPPluginCall) {
        call.resolve(["value": UserDefaults.standard.string(forKey: "secure." + (call.getString("key") ?? "")) ?? ""])
    }

    @objc func secureSet(_ call: CAPPluginCall) {
        UserDefaults.standard.set(call.getString("value") ?? "", forKey: "secure." + (call.getString("key") ?? ""))
        call.resolve()
    }

    /// Opens the sign-in page inside the app, so the app stays in the foreground and can receive the callback.
    @objc func openUrl(_ call: CAPPluginCall) {
        guard let url = URL(string: call.getString("url") ?? ""), url.scheme == "https" else { call.reject("https only"); return }
        DispatchQueue.main.async {
            guard let host = self.bridge?.viewController else { call.reject("no view"); return }
            let safari = SFSafariViewController(url: url)
            self.browser = safari
            (host.presentedViewController ?? host).present(safari, animated: true)
            call.resolve()
        }
    }

    @objc func authListen(_ call: CAPPluginCall) {
        AuthLoopback.shared.onResult = { [weak self] in
            self?.browser?.dismiss(animated: true)
            self?.bridge?.triggerWindowJSEvent(eventName: "baytnaAuth")
        }
        do {
            try AuthLoopback.shared.start(port: UInt16(call.getInt("port") ?? 1455))
            call.resolve()
        } catch {
            call.reject("port busy")
        }
    }

    /// Night is the primary icon; day is the alternate one compiled into the asset catalogue.
    @objc func setIcon(_ call: CAPPluginCall) {
        let name: String? = call.getString("name") == "day" ? "AppIconDay" : nil
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else { call.reject("unsupported"); return }
            UIApplication.shared.setAlternateIconName(name) { error in
                if let error = error { call.reject(error.localizedDescription) } else { call.resolve() }
            }
        }
    }

    @objc func listen(_ call: CAPPluginCall) {
        let lang = call.getString("lang") ?? "ar-SA"
        DispatchQueue.main.async {
            Dictation.shared.start(lang: lang) { text, error in
                if let error = error { call.reject(error) } else { call.resolve(["text": text]) }
            }
        }
    }

    @objc func stopListening(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            Dictation.shared.finish(nil)
            call.resolve()
        }
    }

    @objc func authResult(_ call: CAPPluginCall) {
        let query = AuthLoopback.shared.query ?? ""
        AuthLoopback.shared.query = nil
        call.resolve(["query": query])
    }

    @objc func setItems(_ call: CAPPluginCall) {
        let store = UserDefaults(suiteName: baytnaGroup) ?? UserDefaults.standard
        store.set(call.getString("items") ?? "[]", forKey: "items")
        store.set(call.getInt("count") ?? 0, forKey: "count")
        store.set(call.getBool("signedIn") ?? false, forKey: "signedIn")
        store.set(call.getString("cats") ?? "[]", forKey: "cats")
        store.set(call.getInt("billsPaid") ?? 0, forKey: "billsPaid")
        store.set(call.getInt("billsTotal") ?? 0, forKey: "billsTotal")
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
