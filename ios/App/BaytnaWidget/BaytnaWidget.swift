import WidgetKit
import SwiftUI

private let baytnaGroup = "group.65170c5db5fc6542.1"
private let accent = Color(red: 0.24, green: 0.84, blue: 0.75)
private let onAccent = Color(red: 0.0, green: 0.14, blue: 0.12)
private let soft = Color.white.opacity(0.72)
private let warn = Color(red: 1.0, green: 0.55, blue: 0.61)
private let addURL = URL(string: "baytna://add")!

struct BaytnaItem: Decodable, Identifiable {
    let t: String
    let g: String
    let c: String
    let p: String?
    var id: String { t + "|" + g }
}

struct BaytnaCat: Decodable, Identifiable {
    let n: String
    let c: String
    let x: Int
    var id: String { n }
}

struct BaytnaEntry: TimelineEntry {
    let date: Date
    let items: [BaytnaItem]
    let cats: [BaytnaCat]
    let count: Int
    let billsPaid: Int
    let billsTotal: Int
    let signedIn: Bool
    var urgent: BaytnaItem? { items.first { $0.p == "urgent" } }
}

struct BaytnaProvider: TimelineProvider {
    private func decode<T: Decodable>(_ key: String, _ store: UserDefaults?) -> [T] {
        let raw = store?.string(forKey: key) ?? "[]"
        return (try? JSONDecoder().decode([T].self, from: Data(raw.utf8))) ?? []
    }

    private func load() -> BaytnaEntry {
        let store = UserDefaults(suiteName: baytnaGroup)
        return BaytnaEntry(date: Date(), items: decode("items", store), cats: decode("cats", store),
                           count: store?.integer(forKey: "count") ?? 0,
                           billsPaid: store?.integer(forKey: "billsPaid") ?? 0, billsTotal: store?.integer(forKey: "billsTotal") ?? 0,
                           signedIn: store?.bool(forKey: "signedIn") ?? false)
    }

    func placeholder(in context: Context) -> BaytnaEntry {
        BaytnaEntry(date: Date(), items: [
            BaytnaItem(t: "حليب", g: "البقالة", c: "#1FA862", p: "urgent"),
            BaytnaItem(t: "خبز", g: "البقالة", c: "#1FA862", p: "soon"),
            BaytnaItem(t: "تغيير زيت السيارة", g: "السيارة", c: "#3D83F2", p: "soon"),
            BaytnaItem(t: "لمبات المجلس", g: "البيت", c: "#D9801F", p: "soon")
        ], cats: [
            BaytnaCat(n: "البقالة", c: "#1FA862", x: 7), BaytnaCat(n: "السيارة", c: "#3D83F2", x: 2),
            BaytnaCat(n: "البيت", c: "#D9801F", x: 3), BaytnaCat(n: "البنات", c: "#E0488E", x: 2)
        ], count: 14, billsPaid: 3, billsTotal: 8, signedIn: true)
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

/// The app's night colours: a dark base with four soft pools of colour.
private struct Wash: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07)
            RadialGradient(colors: [Color(red: 0.08, green: 0.23, blue: 0.40), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            RadialGradient(colors: [Color(red: 0.23, green: 0.14, blue: 0.44), .clear], center: .topLeading, startRadius: 0, endRadius: 200)
            RadialGradient(colors: [Color(red: 0.35, green: 0.16, blue: 0.13), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 210)
            RadialGradient(colors: [Color(red: 0.06, green: 0.29, blue: 0.25), .clear], center: .bottomLeading, startRadius: 0, endRadius: 200)
        }
    }
}

private struct PlusButton: View {
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            Circle().fill(accent)
            Image(systemName: "plus").font(.system(size: size * 0.5, weight: .bold)).foregroundColor(onAccent)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("غرض جديد")
    }
}

private struct Header: View {
    let entry: BaytnaEntry
    var body: some View {
        HStack(spacing: 6) {
            Text("بيتنا").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Text(entry.signedIn ? "\(entry.count) ناقص" : "سجّل الدخول").font(.system(size: 12)).foregroundColor(soft)
            Spacer(minLength: 4)
            Link(destination: addURL) { PlusButton() }
        }
    }
}

private struct Rows: View {
    let entry: BaytnaEntry
    let limit: Int
    var body: some View {
        if entry.items.isEmpty {
            Spacer(minLength: 0)
            Text(entry.signedIn ? "ما فيه شيء ناقص" : "افتح التطبيق وسجّل الدخول")
                .font(.system(size: 13)).foregroundColor(soft).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entry.items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) }
                    HStack(spacing: 8) {
                        Circle().strokeBorder(soft, lineWidth: 1.5).frame(width: 14, height: 14)
                        Text(item.t).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                        Spacer(minLength: 4)
                        if item.p == "urgent" { Text("مستعجل").font(.system(size: 11, weight: .bold)).foregroundColor(warn) }
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(hex: item.c)).frame(width: 16, height: 16)
                    }
                    .frame(height: 26)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Cats: View {
    let cats: [BaytnaCat]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(cats.prefix(4)) { cat in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: cat.c)).frame(width: 24, height: 24)
                    Text("\(cat.x)").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(cat.n).font(.system(size: 11)).foregroundColor(soft).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
            }
        }
    }
}

private struct BillsRing: View {
    let paid: Int
    let total: Int
    var lineWidth: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle().trim(from: 0, to: total > 0 ? CGFloat(paid) / CGFloat(total) : 0)
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(paid)/\(total)").font(.system(size: 15, weight: .bold)).foregroundColor(.white).environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct BaytnaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BaytnaEntry

    var body: some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .containerBackground(for: .widget) { Wash() }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.signedIn ? "\(entry.count) ناقص" + (entry.urgent.map { "، \($0.t) مستعجل" } ?? "") : "بيتنا")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(entry.signedIn ? "\(entry.count)" : "–").font(.system(size: 20, weight: .bold))
                    Text("ناقص").font(.system(size: 11))
                }
            }
            .widgetURL(addURL)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.signedIn ? "بيتنا، \(entry.count) ناقص" : "بيتنا").font(.system(size: 13, weight: .semibold))
                ForEach(entry.items.prefix(2)) { item in
                    Text(item.t).font(.system(size: 12)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("بيتنا").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    PlusButton()
                }
                Text(entry.signedIn ? "\(entry.count)" : "–").font(.system(size: 42, weight: .bold)).foregroundColor(.white)
                Text(entry.signedIn ? (entry.count == 0 ? "ما فيه شيء ناقص" : "غرض ناقص") : "سجّل الدخول").font(.system(size: 12)).foregroundColor(soft)
                Spacer(minLength: 0)
                if let hot = entry.urgent {
                    HStack(spacing: 5) {
                        Circle().fill(warn).frame(width: 6, height: 6)
                        Text("\(hot.t)، مستعجل").font(.system(size: 12, weight: .bold)).foregroundColor(warn).lineLimit(1)
                    }
                }
            }
            .widgetURL(addURL)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                Header(entry: entry)
                if !entry.cats.isEmpty { Cats(cats: entry.cats) }
                Rows(entry: entry, limit: entry.cats.isEmpty ? 9 : 6)
            }
        default:
            VStack(alignment: .leading, spacing: 6) { Header(entry: entry); Rows(entry: entry, limit: 3) }
        }
    }
}

struct BillsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BaytnaEntry

    var body: some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .containerBackground(for: .widget) { Wash() }
            .widgetURL(URL(string: "baytna://bills")!)
    }

    @ViewBuilder private var content: some View {
        let left = max(entry.billsTotal - entry.billsPaid, 0)
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.billsPaid), in: 0...Double(max(entry.billsTotal, 1))) {
                Text("فواتير")
            } currentValueLabel: {
                Text("\(entry.billsPaid)/\(entry.billsTotal)").environment(\.layoutDirection, .leftToRight)
            }
            .gaugeStyle(.accessoryCircular)
        default:
            VStack(spacing: 6) {
                HStack {
                    Text("مصاريفي").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    Spacer()
                }
                BillsRing(paid: entry.billsPaid, total: entry.billsTotal).frame(width: 70, height: 70)
                Text(entry.billsTotal == 0 ? "ما فيه فواتير" : left == 0 ? "كلها مسدّدة" : "باقي \(left)").font(.system(size: 12)).foregroundColor(soft)
            }
        }
    }
}

struct BaytnaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BaytnaWidget", provider: BaytnaProvider()) { entry in
            BaytnaWidgetView(entry: entry)
        }
        .configurationDisplayName("بيتنا")
        .description("الأغراض الناقصة وزر إضافة سريعة")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BaytnaBills", provider: BaytnaProvider()) { entry in
            BillsWidgetView(entry: entry)
        }
        .configurationDisplayName("مصاريفي")
        .description("كم فاتورة تسدّدت هذا الشهر")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct BaytnaWidgets: WidgetBundle {
    var body: some Widget {
        BaytnaWidget()
        BillsWidget()
    }
}
