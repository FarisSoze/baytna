import WidgetKit
import SwiftUI

private let baytnaGroup = "group.65170c5db5fc6542.1"
private let gold = Color(red: 0.86, green: 0.75, blue: 0.54)
private let ink = Color(red: 0.07, green: 0.07, blue: 0.07)
private let addURL = URL(string: "baytna://add")!

struct BaytnaItem: Decodable, Identifiable {
    let t: String
    let g: String
    let c: String
    var id: String { t + "|" + g }
}

struct BaytnaEntry: TimelineEntry {
    let date: Date
    let items: [BaytnaItem]
    let count: Int
    let signedIn: Bool
}

struct BaytnaProvider: TimelineProvider {
    private func load() -> BaytnaEntry {
        let store = UserDefaults(suiteName: baytnaGroup)
        let raw = store?.string(forKey: "items") ?? "[]"
        let items = (try? JSONDecoder().decode([BaytnaItem].self, from: Data(raw.utf8))) ?? []
        return BaytnaEntry(date: Date(), items: items, count: store?.integer(forKey: "count") ?? 0, signedIn: store?.bool(forKey: "signedIn") ?? false)
    }

    func placeholder(in context: Context) -> BaytnaEntry {
        BaytnaEntry(date: Date(), items: [
            BaytnaItem(t: "خبز", g: "البقالة", c: "#34C759"),
            BaytnaItem(t: "تغيير زيت السيارة", g: "صيانة السيارة", c: "#FF9F0A"),
            BaytnaItem(t: "لمبة المجلس", g: "صيانة البيت", c: "#0A84FF")
        ], count: 3, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BaytnaEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BaytnaEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(1800))))
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private struct PlusButton: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.92, green: 0.83, blue: 0.64), Color(red: 0.78, green: 0.65, blue: 0.38)], startPoint: .top, endPoint: .bottom))
            Image(systemName: "plus").font(.system(size: size * 0.5, weight: .bold)).foregroundColor(ink)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("غرض جديد")
    }
}

private struct Header: View {
    let entry: BaytnaEntry
    var body: some View {
        HStack(spacing: 10) {
            Text(entry.signedIn ? "\(entry.count)" : "–").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(gold)
            VStack(alignment: .leading, spacing: 0) {
                Text("بيتنا").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            }
            Spacer(minLength: 4)
            Link(destination: addURL) { PlusButton() }
        }
    }
    private var label: String {
        !entry.signedIn ? "سجّل الدخول" : entry.count == 0 ? "كل شيء منتهي" : "بانتظاركم"
    }
}

private struct Rows: View {
    let entry: BaytnaEntry
    let limit: Int
    var body: some View {
        if entry.items.isEmpty {
            Spacer(minLength: 0)
            Text(entry.signedIn ? "ما فيه أغراض معلّقة" : "افتح التطبيق وسجّل الدخول")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        } else {
            ForEach(entry.items.prefix(limit)) { item in
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: item.c)).frame(width: 7, height: 7)
                    Text(item.t).font(.system(size: 14)).foregroundColor(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.g).font(.system(size: 11)).foregroundColor(Color(hex: item.c)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct BaytnaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BaytnaEntry

    var body: some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.11), ink], startPoint: .top, endPoint: .bottom)
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.signedIn ? "بيتنا: \(entry.count) بانتظاركم" : "بيتنا")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(entry.signedIn ? "\(entry.count)" : "–").font(.system(size: 22, weight: .bold, design: .rounded))
                    Image(systemName: "house.fill").font(.system(size: 9))
                }
            }
            .widgetURL(addURL)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.signedIn ? "بيتنا · \(entry.count) بانتظاركم" : "بيتنا").font(.system(size: 13, weight: .semibold))
                ForEach(entry.items.prefix(2)) { item in
                    Text(item.t).font(.system(size: 12)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.signedIn ? "\(entry.count)" : "–").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(gold)
                Text(entry.signedIn ? (entry.count == 0 ? "كل شيء منتهي" : "غرض بانتظاركم") : "سجّل الدخول")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
                HStack { Spacer(); PlusButton(size: 38) }
            }
            .widgetURL(addURL)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) { Header(entry: entry); Rows(entry: entry, limit: 9) }
        default:
            VStack(alignment: .leading, spacing: 7) { Header(entry: entry); Rows(entry: entry, limit: 3) }
        }
    }
}

@main
struct BaytnaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BaytnaWidget", provider: BaytnaProvider()) { entry in
            BaytnaWidgetView(entry: entry)
        }
        .configurationDisplayName("بيتنا")
        .description("أغراض البيت وزر إضافة سريعة")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
