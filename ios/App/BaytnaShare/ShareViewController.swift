import UIKit
import UniformTypeIdentifiers

/// "Share" from Google Maps (or anywhere) → «بيتنا». Keeps what was shared for the app (in the App Group, and in the link that
/// opens the app), opens the app on its Places tab, and says so. If the app cannot be opened from here, it picks the link up next time.
private let baytnaGroup = "group.65170c5db5fc6542.1"

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let card = UIView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        card.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 0.97)
        card.layer.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        label.text = "جاري الإضافة إلى أماكن…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        card.addSubview(label)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 270),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -26),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])
        Task { await collect() }
    }

    private func collect() async {
        var parts: [String] = []
        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            if let t = item.attributedContentText?.string, !t.isEmpty { parts.append(t) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    parts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    parts.append(text)
                }
            }
        }
        var seen = Set<String>()
        let text = parts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        await MainActor.run { self.finish(text) }
    }

    private func finish(_ text: String) {
        guard !text.isEmpty else { label.text = "ما لقيت رابط مكان"; close(after: 1.2); return }
        if let store = UserDefaults(suiteName: baytnaGroup) {
            var list = store.stringArray(forKey: "pendingShares") ?? []
            list.append(text)
            store.set(list, forKey: "pendingShares")
        }
        label.text = "✓ انضاف إلى أماكن بيتنا"
        var c = URLComponents()
        c.scheme = "baytna"; c.host = "places"
        c.queryItems = [URLQueryItem(name: "t", value: text)]
        if let url = c.url { openApp(url) }
        close(after: 0.9)
    }

    /// Extensions may not open other apps directly; walking up to the application object is the usual way around it.
    private func openApp(_ url: URL) {
        var r: UIResponder? = self
        while let next = r {
            if let app = next as? UIApplication { app.open(url, options: [:], completionHandler: nil); return }
            r = next.next
        }
    }

    private func close(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
