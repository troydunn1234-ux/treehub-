import SwiftUI
import WidgetKit

// Pulse Lab home-screen widgets: WHOOP recovery vs Apple Watch readiness at a glance.
// Self-contained: the extension does not compile the app's sources, so the palette and the
// App Group keys are duplicated here (keep them in step with PulseLab/Data/WidgetBridge.swift).
//
// INTEGRATOR NOTE (project.yml): an iOS `app-extension` target named PulseLabWidgets with
//   sources: PulseLabWidgets · NSExtensionPointIdentifier: com.apple.widgetkit-extension
//   PRODUCT_BUNDLE_IDENTIFIER: com.troydunn.pulselab.widgets · SKIP_INSTALL: YES
// and the App Groups entitlement (group.com.troydunn.pulselab) on BOTH the app and this target.

@main
struct PulseLabWidgets: WidgetBundle {
    var body: some Widget {
        ReadyDuelWidget()
        if #available(iOS 18.0, *) {
            PulseLabTodayControl()
        }
    }
}

// MARK: - Shared data (App Group)

enum Bridge {
    static let suite = "group.com.troydunn.pulselab"
    static let deepLink = URL(string: "pulselab://today")!

    struct Snapshot {
        var recovery: Double?
        var readiness: Double?
        var rhrWatch: Double?
        var rhrWhoop: Double?
        var sleepWatch: Double?
        var sleepWhoop: Double?
        var updatedAt: Date?

        var isEmpty: Bool { recovery == nil && readiness == nil && rhrWatch == nil && rhrWhoop == nil }

        static let placeholder = Snapshot(recovery: 72, readiness: 64, rhrWatch: 54, rhrWhoop: 51, sleepWatch: 7.2, sleepWhoop: 6.9, updatedAt: Date())
    }

    static func read() -> Snapshot {
        guard let d = UserDefaults(suiteName: suite) else { return Snapshot() }
        func opt(_ key: String) -> Double? { d.object(forKey: key) == nil ? nil : d.double(forKey: key) }
        func signed(_ key: String) -> Double? {
            guard d.object(forKey: key) != nil else { return nil }
            let v = d.double(forKey: key)
            return v < 0 ? nil : v
        }
        var s = Snapshot()
        s.recovery = opt("recovery")
        s.readiness = opt("readiness")
        s.rhrWatch = signed("rhrWatch")
        s.rhrWhoop = signed("rhrWhoop")
        s.sleepWatch = signed("sleepWatch")
        s.sleepWhoop = signed("sleepWhoop")
        if let t = opt("updatedAt") { s.updatedAt = Date(timeIntervalSince1970: t) }
        return s
    }
}

// MARK: - Palette (copied from PulseLab/Design/Lab.swift)

enum Palette {
    static let bg = Color(red: 0.020, green: 0.016, blue: 0.040)
    static let panel = Color(red: 0.060, green: 0.052, blue: 0.105)
    static let text = Color(red: 0.93, green: 0.94, blue: 1.0)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let watch = Color(red: 0.20, green: 0.92, blue: 1.00)
    static let whoop = Color(red: 1.00, green: 0.66, blue: 0.16)
    static let violet = Color(red: 0.58, green: 0.38, blue: 1.00)
    static let good = Color(red: 0.25, green: 0.95, blue: 0.55)
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.30, blue: 0.40)

    static func band(_ score: Double) -> Color { score >= 67 ? good : score >= 34 ? warn : bad }
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded).width(.condensed).monospacedDigit() }
    static func label(_ size: CGFloat = 8) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }
}

// MARK: - Timeline

struct ReadyEntry: TimelineEntry {
    let date: Date
    let snap: Bridge.Snapshot
}

struct ReadyProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadyEntry { ReadyEntry(date: Date(), snap: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (ReadyEntry) -> Void) {
        let snap = Bridge.read()
        completion(ReadyEntry(date: Date(), snap: context.isPreview && snap.isEmpty ? .placeholder : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadyEntry>) -> Void) {
        // The app reloads the timeline after every sync; this is just a safety refresh.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [ReadyEntry(date: Date(), snap: Bridge.read())], policy: .after(next)))
    }
}

// MARK: - Widget

struct ReadyDuelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.troydunn.pulselab.readyduel", provider: ReadyProvider()) { entry in
            ReadyDuelView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
                .widgetURL(Bridge.deepLink)
        }
        .configurationDisplayName("Recovery vs Readiness")
        .description("WHOOP recovery next to your Apple Watch readiness, with resting HR and sleep on the medium size.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct WidgetBackdrop: View {
    var body: some View {
        ZStack {
            Palette.bg
            RadialGradient(colors: [Palette.violet.opacity(0.26), .clear], center: .top, startRadius: 4, endRadius: 220)
            RadialGradient(colors: [Palette.watch.opacity(0.10), .clear], center: .bottomLeading, startRadius: 4, endRadius: 180)
            RadialGradient(colors: [Palette.whoop.opacity(0.10), .clear], center: .bottomTrailing, startRadius: 4, endRadius: 180)
        }
    }
}

struct ReadyDuelView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadyEntry

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .padding(14)
    }

    // MARK: small

    private var small: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 0) {
                score(entry.snap.readiness, "READY", .watch)
                vs
                score(entry.snap.recovery, "RECOV", .whoop)
            }
            Spacer(minLength: 0)
            footer
        }
    }

    // MARK: medium

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                header
                HStack(spacing: 0) {
                    score(entry.snap.readiness, "READY", .watch)
                    vs
                    score(entry.snap.recovery, "RECOV", .whoop)
                }
                Spacer(minLength: 0)
                footer
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            VStack(alignment: .leading, spacing: 8) {
                row("RESTING HR", "bpm", entry.snap.rhrWatch, entry.snap.rhrWhoop, decimals: 0)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                row("SLEEP", "h", entry.snap.sleepWatch, entry.snap.sleepWhoop, decimals: 1)
            }
            .frame(width: 118)
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(spacing: 5) {
            Circle().fill(Palette.watch).frame(width: 5, height: 5)
            Circle().fill(Palette.whoop).frame(width: 5, height: 5)
            Text("PULSE LAB").font(Palette.label(8)).tracking(1.8).foregroundStyle(Palette.dim)
            Spacer()
        }
    }

    private var vs: some View {
        Text("VS")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(LinearGradient(colors: [Palette.watch, Palette.violet, Palette.whoop], startPoint: .leading, endPoint: .trailing))
            .frame(width: 28)
    }

    private enum Side { case watch, whoop }

    private func score(_ v: Double?, _ label: String, _ side: Side) -> some View {
        let base = side == .watch ? Palette.watch : Palette.whoop
        let ring = side == .whoop ? (v.map(Palette.band) ?? base) : base
        return VStack(spacing: 2) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(100, max(0, v ?? 0)) / 100))
                    .stroke(ring, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(v.map { "\(Int($0.rounded()))" } ?? "––")
                    .font(Palette.number(22)).foregroundStyle(v == nil ? Palette.faint : Palette.text)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 50, height: 50)
            Text(label).font(Palette.label(7)).tracking(1.2).foregroundStyle(base)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ unit: String, _ w: Double?, _ h: Double?, decimals: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Palette.label(7)).tracking(1.4).foregroundStyle(Palette.dim)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                value(w, decimals, Palette.watch)
                Text("/").font(Palette.label(10)).foregroundStyle(Palette.faint)
                value(h, decimals, Palette.whoop)
                Text(unit).font(Palette.label(7)).foregroundStyle(Palette.faint)
            }
        }
    }

    private func value(_ v: Double?, _ decimals: Int, _ color: Color) -> some View {
        Text(v.map { String(format: "%.\(decimals)f", $0) } ?? "–")
            .font(Palette.number(18)).foregroundStyle(v == nil ? Palette.faint : color)
    }

    private var footer: some View {
        HStack {
            Text(verdict).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Palette.dim)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let t = entry.snap.updatedAt {
                Text(t, style: .relative).font(Palette.label(7)).foregroundStyle(Palette.faint).lineLimit(1)
            }
        }
    }

    private var verdict: String {
        guard let a = entry.snap.readiness, let r = entry.snap.recovery else { return entry.snap.isEmpty ? "Open Pulse Lab to sync" : "One tracker has a score" }
        if a >= 67 && r >= 67 { return "Both say go" }
        if a < 34 && r < 34 { return "Both say rest" }
        if abs(a - r) <= 10 { return "Both agree today" }
        return a > r ? "Watch is more upbeat" : "WHOOP is more upbeat"
    }
}
