import SwiftUI
import WidgetKit

// Ride Quest on the Home Screen: how close you are to the dream car.
// The web app (web/index.html, syncWidget) posts {name, saved, goal, left, pct} through the shell bridge;
// ShellNotify.saveWidget stores it in the App Group and reloads this widget.

@main
struct RideQuestWidgets: WidgetBundle {
    var body: some Widget {
        DreamCarWidget()
    }
}

private enum RQShared {
    static let appGroup = "group.com.troydunn.ridequest"
    static let key = "shell.widget"
    // The app's calm look: near-black, soft mint for progress, gray for secondary text.
    static let bg = Color(red: 0.039, green: 0.043, blue: 0.051)        // #0a0b0d
    static let panel = Color(red: 0.149, green: 0.165, blue: 0.188)     // #262a30
    static let neon = Color(red: 0.455, green: 0.847, blue: 0.678)      // #74d8ad
    static let dim = Color(red: 0.663, green: 0.686, blue: 0.722)       // #a9afb8

    struct Payload: Decodable {
        let name: String?
        let saved: Double?
        let goal: Double?
        let left: Double?
        let pct: Double?
        // exact whole cents (newer app versions send these too)
        let savedCents: Int?
        let goalCents: Int?
        let leftCents: Int?
    }

    static func load() -> Payload? {
        guard let s = UserDefaults(suiteName: appGroup)?.string(forKey: key), let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Always exact to the cent: $8,120.55, never $8,121 or $8.1k.
    static func money(_ v: Double, short: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }
}

struct DreamCarEntry: TimelineEntry {
    let date: Date
    let name: String
    let saved: Double
    let goal: Double
    let left: Double
    let pct: Double
    let hasData: Bool

    static let sample = DreamCarEntry(date: Date(), name: "Dream car", saved: 8400, goal: 20000, left: 11600, pct: 0.42, hasData: true)
    static func empty(_ date: Date) -> DreamCarEntry {
        DreamCarEntry(date: date, name: "Dream car", saved: 0, goal: 0, left: 0, pct: 0, hasData: false)
    }
}

struct DreamCarProvider: TimelineProvider {
    func placeholder(in context: Context) -> DreamCarEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DreamCarEntry) -> Void) {
        if context.isPreview, RQShared.load() == nil { completion(.sample); return }
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DreamCarEntry>) -> Void) {
        // The app reloads the widget whenever the numbers change; this is just a fallback refresh.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date().addingTimeInterval(21_600)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> DreamCarEntry {
        guard let p = RQShared.load() else { return .empty(Date()) }
        let goal = max(0, p.goalCents.map { Double($0) / 100 } ?? p.goal ?? 0)
        let saved = p.savedCents.map { Double($0) / 100 } ?? p.saved ?? 0
        let leftExact = p.leftCents.map { Double($0) / 100 } ?? p.left
        let pct = p.pct ?? (goal > 0 ? saved / goal : 0)
        return DreamCarEntry(date: Date(), name: (p.name?.isEmpty == false ? p.name! : "Dream car"),
                             saved: saved, goal: goal, left: max(0, leftExact ?? (goal - saved)),
                             pct: min(1, max(0, pct)), hasData: true)
    }
}

struct DreamCarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RideQuestDreamCar", provider: DreamCarProvider()) { entry in
            DreamCarView(entry: entry)
                .widgetURL(URL(string: "ridequest://home"))
                .containerBackground(for: .widget) {
                    ZStack {
                        RQShared.bg
                        RadialGradient(colors: [RQShared.neon.opacity(0.20), .clear], center: .topTrailing, startRadius: 4, endRadius: 200)
                    }
                }
        }
        .configurationDisplayName("Dream Car")
        .description("How much you've saved toward your dream car, and how much is left.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Chunky, segmented neon bar (the app's pixel style).
struct NeonBar: View {
    let pct: Double
    var segments = 10
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let w = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            let lit = pct * Double(segments)
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    let fill = min(1, max(0, lit - Double(i)))
                    ZStack(alignment: .leading) {
                        Rectangle().fill(RQShared.panel)
                        Rectangle().fill(RQShared.neon).frame(width: w * fill)
                    }
                    .frame(width: w)
                }
            }
            .shadow(color: RQShared.neon.opacity(0.55), radius: 5)
        }
        .overlay(Rectangle().stroke(RQShared.neon.opacity(0.35), lineWidth: 1))
    }
}

struct DreamCarView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DreamCarEntry

    private var pctText: String { "\(Int((entry.pct * 100).rounded(.down)))%" }

    var body: some View {
        if !entry.hasData || entry.goal <= 0 {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Text("Open Ride Quest and set your goal")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(RQShared.dim)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 5) {
                header
                Spacer(minLength: 0)
                Text(pctText)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .foregroundStyle(RQShared.neon)
                    .shadow(color: RQShared.neon.opacity(0.6), radius: 8)
                    .minimumScaleFactor(0.6)
                NeonBar(pct: entry.pct, segments: 8).frame(height: 10)
                Text("\(RQShared.money(entry.saved, short: true)) saved")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(RQShared.money(entry.left, short: true)) to go")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RQShared.dim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    header
                    Spacer()
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(pctText)
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(RQShared.neon)
                        .shadow(color: RQShared.neon.opacity(0.6), radius: 8)
                    Spacer()
                    stat("SAVED", RQShared.money(entry.saved), bright: true)
                    stat("LEFT", RQShared.money(entry.left), bright: false)
                }
                NeonBar(pct: entry.pct, segments: 14).frame(height: 12)
                Text("Goal \(RQShared.money(entry.goal))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RQShared.dim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.checkered").font(.system(size: 11, weight: .bold))
            Text(entry.name.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .lineLimit(1)
        }
        .foregroundStyle(RQShared.neon)
    }

    private func stat(_ label: String, _ value: String, bright: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(RQShared.dim)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(bright ? .white : RQShared.dim)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.leading, 8)
    }
}
