import SwiftUI
import WidgetKit

// Ride Quest on the Home Screen: how close you are to the car you're saving for, as a tachometer.
// The web app (web/index.html, syncWidget) posts {name, saved, goal, left, pct, savedCents, goalCents, leftCents,
// nextName?, nextDate?, nextCents?, pace?} through the shell bridge; ShellNotify.saveWidget stores it in the App Group
// and reloads this widget. Older app versions send only the first fields; the rest is optional.

@main
struct RideQuestWidgets: WidgetBundle {
    var body: some Widget {
        DreamCarWidget()
    }
}

private enum RQShared {
    static let appGroup = "group.com.troydunn.ridequest"
    static let key = "shell.widget"
    // Blacked out: matte black, graphite track, tail-light red, smoked silver.
    static let bg = Color(red: 0.027, green: 0.027, blue: 0.031)        // #070708
    static let panel = Color(red: 0.145, green: 0.153, blue: 0.173)     // #25272c
    static let red = Color(red: 1.0, green: 0.165, blue: 0.165)         // #ff2a2a
    static let silver = Color(red: 0.765, green: 0.784, blue: 0.812)    // #c3c8cf
    static let dim = Color(red: 0.557, green: 0.580, blue: 0.612)       // #8e949c

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
        // the next charge from Subscriptions (Ride Quest 2)
        let nextName: String?
        let nextDate: String?
        let nextCents: Int?
        let pace: String?
    }

    static func load() -> Payload? {
        guard let s = UserDefaults(suiteName: appGroup)?.string(forKey: key), let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Always exact to the cent: $8,120.55, never $8,121 or $8.1k.
    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    /// "2026-11-24" -> "Tomorrow", "Today" or "Nov 24"
    static func day(_ iso: String?, from now: Date) -> String? {
        guard let iso = iso, iso.count == 10 else { return nil }
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        p.dateFormat = "yyyy-MM-dd"
        guard let d = p.date(from: iso) else { return nil }
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "Today" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "Tomorrow" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f.string(from: d)
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
    var nextName: String? = nil
    var nextDate: String? = nil
    var nextAmount: Double? = nil

    static let sample = DreamCarEntry(date: Date(), name: "Dream car", saved: 18100, goal: 59495, left: 41395, pct: 0.304, hasData: true,
                                      nextName: "Gym", nextDate: nil, nextAmount: 29.99)
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
                             pct: min(1, max(0, pct)), hasData: true,
                             nextName: p.nextName, nextDate: p.nextDate, nextAmount: p.nextCents.map { Double($0) / 100 })
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
                        RadialGradient(colors: [RQShared.red.opacity(0.18), .clear], center: .bottomLeading, startRadius: 2, endRadius: 170)
                    }
                }
        }
        .configurationDisplayName("Dream Car")
        .description("How much you've saved toward your car, on a tachometer, and your next charge.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// A 240° tach, open at the bottom: graphite track, redline in the last 15%, the saved share lit, a red needle tip.
struct TachGauge: View {
    let pct: Double
    var lineWidth: CGFloat = 7
    private let span: CGFloat = 240.0 / 360.0

    var body: some View {
        let p = CGFloat(min(1, max(0, pct)))
        ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(RQShared.panel, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: span * 0.85, to: span)
                .stroke(RQShared.red.opacity(0.75), style: StrokeStyle(lineWidth: max(1.5, lineWidth * 0.3), lineCap: .round))
                .padding(-lineWidth * 1.05)
            if p > 0.002 {
                Circle()
                    .trim(from: 0, to: span * p)
                    .stroke(LinearGradient(colors: [RQShared.dim, Color.white], startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .widgetAccentable()
            }
            Circle()
                .trim(from: max(0, span * p - 0.01), to: min(span, span * p + 0.004))
                .stroke(RQShared.red, style: StrokeStyle(lineWidth: lineWidth + 3, lineCap: .round))
                .shadow(color: RQShared.red.opacity(0.85), radius: 4)
        }
        .rotationEffect(.degrees(150))
    }
}

struct DreamCarView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DreamCarEntry

    private var pctText: String {
        let tenths = (entry.pct * 1000).rounded(.down) / 10
        return tenths.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(tenths))%" : String(format: "%.1f%%", tenths)
    }

    var body: some View {
        if !entry.hasData || entry.goal <= 0 {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Text("Open Ride Quest and set the car you're saving for")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RQShared.silver)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    dial(size: 62, line: 6, font: 15)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                Text(RQShared.money(entry.saved))
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(RQShared.money(entry.left)) to go")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(RQShared.dim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            HStack(spacing: 14) {
                dial(size: 104, line: 8, font: 20)
                VStack(alignment: .leading, spacing: 5) {
                    header
                    Spacer(minLength: 0)
                    stat("Saved", RQShared.money(entry.saved), bright: true)
                    stat("To go", RQShared.money(entry.left), bright: false)
                    Spacer(minLength: 0)
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func dial(size: CGFloat, line: CGFloat, font: CGFloat) -> some View {
        ZStack {
            TachGauge(pct: entry.pct, lineWidth: line)
            Text(pctText)
                .font(.system(size: font, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, line + 4)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pctText) of the goal saved")
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "gauge.open.with.lines.needle.67percent.and.arrowtriangle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(RQShared.red)
                .widgetAccentable()
            Text(entry.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(RQShared.silver)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var footer: some View {
        if let n = entry.nextName, let a = entry.nextAmount {
            let when = RQShared.day(entry.nextDate, from: entry.date)
            let soon = when == "Today" || when == "Tomorrow"
            Text("Next: " + n + (when.map { ", " + $0 } ?? "") + ", " + RQShared.money(a))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(soon ? RQShared.red : RQShared.dim)
                .lineLimit(1).minimumScaleFactor(0.75)
        } else {
            Text("Goal " + RQShared.money(entry.goal))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(RQShared.dim)
                .lineLimit(1)
        }
    }

    private func stat(_ label: String, _ value: String, bright: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RQShared.dim)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: bright ? 18 : 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(bright ? Color.white : RQShared.silver)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}
