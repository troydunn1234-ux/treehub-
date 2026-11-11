import SwiftUI
import WidgetKit

// Still Point widgets + Watch complications.
// Self-contained: this extension cannot see the app's code, so the palette and the App Group keys live here too.
// Data is written by the app (StillPoint/Shared/WidgetBridge.swift) into the App Group suite below.

@main
struct StillPointWidgets: WidgetBundle {
    var body: some Widget {
        #if os(watchOS)
        StillPointComplication()
        #else
        StillPointWidget()
        StillPointComplication()
        #endif
    }
}

// MARK: - Shared bits (mirrors the app; keep in sync by hand)

private enum Bridge {
    static let suite = "group.com.troydunn.stillpoint"
    static let scheme = "stillpoint"
    static let kind = "StillPointWidget"
    static let complicationKind = "StillPointComplication"

    static func practiceURL(_ id: String) -> URL? {
        guard !id.isEmpty else { return URL(string: "\(scheme)://practice/") }
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "\(scheme)://practice/\(safe)")
    }
}

/// Dusk palette, copied from the app's Theme.swift.
private enum Palette {
    static let nightTop = Color(red: 0x1C / 255, green: 0x18 / 255, blue: 0x44 / 255)
    static let night = Color(red: 0x2A / 255, green: 0x18 / 255, blue: 0x38 / 255)
    static let nightBottom = Color(red: 0x0B / 255, green: 0x09 / 255, blue: 0x12 / 255)
    static let amber = Color(red: 0xE9 / 255, green: 0xB9 / 255, blue: 0x7A / 255)
    static let gold = Color(red: 0xEB / 255, green: 0xC8 / 255, blue: 0x8E / 255)
    static let goldLight = Color(red: 0xF6 / 255, green: 0xDD / 255, blue: 0xA8 / 255)
    static let teal = Color(red: 0x8F / 255, green: 0xD3 / 255, blue: 0xCC / 255)
    static let indigo = Color(red: 0x6A / 255, green: 0x5A / 255, blue: 0xCD / 255)
    static let ink = Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255)
    static let dim = ink.opacity(0.62)
    static let faint = ink.opacity(0.38)

    static var background: LinearGradient {
        LinearGradient(colors: [nightTop, night, nightBottom], startPoint: .top, endPoint: .bottom)
    }
    static let goldGlow = LinearGradient(colors: [gold, goldLight], startPoint: .leading, endPoint: .trailing)
    static let breath = LinearGradient(colors: [teal, indigo], startPoint: .top, endPoint: .bottom)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func numbers(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded).monospacedDigit()
    }
}

// MARK: - Timeline

struct StillEntry: TimelineEntry {
    var date: Date
    var streak: Int
    var weekMinutes: Double
    var weekGoal: Double
    var suggestedTitle: String
    var suggestedId: String

    var progress: Double { weekGoal > 0 ? min(1, weekMinutes / weekGoal) : 0 }
    var goalReached: Bool { weekGoal > 0 && weekMinutes >= weekGoal }
    var url: URL? { Bridge.practiceURL(suggestedId) }

    static let placeholder = StillEntry(date: Date(), streak: 3, weekMinutes: 18, weekGoal: 30,
                                        suggestedTitle: "Resonance Breathing", suggestedId: "resonance")

    /// What the app last wrote; a quiet default before the first session.
    static func current(date: Date = Date()) -> StillEntry {
        let d = UserDefaults(suiteName: Bridge.suite) ?? .standard
        let goal = d.double(forKey: "weekGoal")
        let title = d.string(forKey: "suggestedTitle") ?? ""
        return StillEntry(date: date,
                          streak: max(0, d.integer(forKey: "streak")),
                          weekMinutes: max(0, d.double(forKey: "weekMinutes")),
                          weekGoal: goal > 0 ? goal : 30,
                          suggestedTitle: title.isEmpty ? "Breathe" : title,
                          suggestedId: d.string(forKey: "suggestedId") ?? "")
    }
}

struct StillProvider: TimelineProvider {
    func placeholder(in context: Context) -> StillEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StillEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StillEntry>) -> Void) {
        // The app reloads timelines after every session; this just refreshes at midnight so the streak day rolls over.
        let now = Date()
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [StillEntry.current(date: now)], policy: .after(tomorrow)))
    }
}

// MARK: - iOS home-screen widget (small / medium)

#if !os(watchOS)
struct StillPointWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Bridge.kind, provider: StillProvider()) { entry in
            StillHomeView(entry: entry)
                .containerBackground(for: .widget) { ZStack { Palette.background; WidgetGlow() } }
                .widgetURL(entry.url)
        }
        .configurationDisplayName("Still Point")
        .description("Your streak, this week's minutes, and a practice for right now.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// A warm glow low in the widget, like the app's background.
private struct WidgetGlow: View {
    var body: some View {
        RadialGradient(colors: [Palette.amber.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 1.1),
                       startRadius: 4, endRadius: 220)
    }
}

struct StillHomeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StillEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Flame(lit: entry.streak > 0, size: 15)
                Text("\(entry.streak)").font(Palette.numbers(30)).foregroundStyle(Palette.ink)
                Text(entry.streak == 1 ? "day" : "days").font(Palette.rounded(12)).foregroundStyle(Palette.dim)
                Spacer(minLength: 0)
                GoalRing(entry: entry, size: 36, width: 4, showText: false)
            }
            Spacer(minLength: 4)
            Text(entry.suggestedTitle)
                .font(Palette.serif(16, .regular)).foregroundStyle(Palette.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(entry.goalReached ? "Goal met · tap to begin" : "\(Int(entry.weekMinutes.rounded()))/\(Int(entry.weekGoal)) min · tap to begin")
                .font(Palette.rounded(10)).foregroundStyle(Palette.faint).lineLimit(1)
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STILL POINT").font(Palette.rounded(10, .semibold)).tracking(1.6).foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Flame(lit: entry.streak > 0, size: 18)
                    Text("\(entry.streak)").font(Palette.numbers(36)).foregroundStyle(Palette.ink)
                    Text(entry.streak == 1 ? "day" : "days in a row").font(Palette.rounded(13)).foregroundStyle(Palette.dim)
                }
                Spacer(minLength: 2)
                Text("FOR RIGHT NOW").font(Palette.rounded(9, .semibold)).tracking(1.4).foregroundStyle(Palette.faint)
                Text(entry.suggestedTitle)
                    .font(Palette.serif(18)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                GoalRing(entry: entry, size: 74, width: 7, showText: true)
                Text(entry.goalReached ? "goal met" : "this week").font(Palette.rounded(10)).foregroundStyle(Palette.faint)
            }
        }
        .padding(16)
    }
}
#endif

// MARK: - Lock Screen / Watch complication (accessory families)

struct StillPointComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Bridge.complicationKind, provider: StillProvider()) { entry in
            StillAccessoryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(entry.url)
        }
        .configurationDisplayName("Streak")
        .description("Your streak and this week's minutes. Tap to begin.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StillAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StillEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    private var circular: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            VStack(spacing: -2) {
                Image(systemName: entry.streak > 0 ? "flame.fill" : "flame").font(.system(size: 9))
                Text("\(entry.streak)").font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("\(entry.streak) day streak, \(Int(entry.weekMinutes.rounded())) of \(Int(entry.weekGoal)) minutes this week")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.streak > 0 ? "flame.fill" : "flame").font(.system(size: 12))
                Text("\(entry.streak) \(entry.streak == 1 ? "day" : "days")")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(Int(entry.weekMinutes.rounded()))/\(Int(entry.weekGoal)) min")
                    .font(.system(size: 12, design: .rounded)).monospacedDigit()
                    .opacity(0.8)
            }
            .widgetAccentable()
            Gauge(value: entry.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text(entry.suggestedTitle)
                .font(.system(size: 12, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.85)
                .opacity(0.85)
        }
    }

    private var inline: some View {
        Label {
            Text("\(entry.streak) \(entry.streak == 1 ? "day" : "days") · \(Int(entry.weekMinutes.rounded()))/\(Int(entry.weekGoal)) min")
        } icon: {
            Image(systemName: entry.streak > 0 ? "flame.fill" : "flame")
        }
    }
}

// MARK: - Pieces

private struct Flame: View {
    let lit: Bool
    let size: CGFloat
    var body: some View {
        Image(systemName: lit ? "flame.fill" : "flame")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(lit ? Palette.goldGlow : LinearGradient(colors: [Palette.faint, Palette.faint], startPoint: .top, endPoint: .bottom))
            .shadow(color: lit ? Palette.amber.opacity(0.5) : .clear, radius: 6)
            .accessibilityHidden(true)
    }
}

private struct GoalRing: View {
    let entry: StillEntry
    let size: CGFloat
    let width: CGFloat
    let showText: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: width)
            Circle()
                .trim(from: 0, to: entry.progress)
                .stroke(entry.goalReached ? Palette.goldGlow : Palette.breath, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showText {
                VStack(spacing: 0) {
                    Text("\(Int(entry.weekMinutes.rounded()))").font(Palette.numbers(20)).foregroundStyle(Palette.ink)
                    Text("of \(Int(entry.weekGoal))").font(Palette.rounded(9, .semibold)).foregroundStyle(Palette.faint)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(Int(entry.weekMinutes.rounded())) of \(Int(entry.weekGoal)) minutes this week")
    }
}
