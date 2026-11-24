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
        SaunaComplication()
        SteamComplication()
        #else
        StillPointWidget()
        RightNowWidget()
        StillPointComplication()
        if #available(iOS 18.0, *) {
            BreatheNowControl()
        }
        #endif
    }
}

// MARK: - Shared bits (mirrors the app; keep in sync by hand)

private enum Bridge {
    static let suite = "group.com.troydunn.stillpoint"
    static let scheme = "stillpoint"
    static let kind = "StillPointWidget"
    static let complicationKind = "StillPointComplication"

    static func heatURL(_ kind: HeatChoice) -> URL? { URL(string: "\(scheme)://heat/\(kind.rawValue)") }

    static func practiceURL(_ id: String) -> URL? {
        guard !id.isEmpty else { return URL(string: "\(scheme)://practice/") }
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "\(scheme)://practice/\(safe)")
    }
}

/// Night palette, copied from the app's Theme.swift.
private enum Palette {
    static let nightTop = Color(red: 0x18 / 255, green: 0x21 / 255, blue: 0x4A / 255)
    static let night = Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x36 / 255)
    static let nightBottom = Color(red: 0x07 / 255, green: 0x0A / 255, blue: 0x18 / 255)
    static let amber = Color(red: 0xE9 / 255, green: 0xB9 / 255, blue: 0x7A / 255)
    static let gold = Color(red: 0xEB / 255, green: 0xC8 / 255, blue: 0x8E / 255)
    static let goldLight = Color(red: 0xF6 / 255, green: 0xDD / 255, blue: 0xA8 / 255)
    static let teal = Color(red: 0x8F / 255, green: 0xD3 / 255, blue: 0xD6 / 255)
    static let indigo = Color(red: 0x6C / 255, green: 0x74 / 255, blue: 0xE0 / 255)
    /// Calm periwinkle accent and the deeper fill used for primary buttons (white text).
    static let accent = Color(red: 0xA3 / 255, green: 0xB4 / 255, blue: 0xFF / 255)
    static let accentFill = LinearGradient(colors: [Color(red: 0x5B / 255, green: 0x69 / 255, blue: 0xDE / 255),
                                                    Color(red: 0x46 / 255, green: 0x51 / 255, blue: 0xC4 / 255)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ink = Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xFA / 255)
    static let dim = ink.opacity(0.66)
    static let faint = ink.opacity(0.44)

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

#if !os(watchOS)
/// The app's time-of-day sky (StillPoint/Shared/Vibes.swift, SkyPart), copied here and kept a little softer:
/// deep at the bottom, the hour's light in the top corner. iPhone widgets only (complications stay clear).
private enum WidgetSky {
    case dawn, day, dusk, night

    /// Hours the sky changes (dawn 5, day 8, dusk 17, night 20), for timeline entries.
    static let hours = [5, 8, 17, 20]

    static func at(_ date: Date) -> WidgetSky {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<8: return .dawn
        case 8..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    /// The next `count` sky changes after `date`.
    static func changes(after date: Date, count: Int) -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        var out: [Date] = []
        for dayOffset in 0..<2 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: start) else { continue }
            for h in hours {
                if let d = cal.date(byAdding: .hour, value: h, to: day), d > date.addingTimeInterval(60) { out.append(d) }
            }
        }
        return Array(out.sorted().prefix(count))
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    var colors: [Color] {
        switch self {
        case .dawn: return [Self.rgb(0x26, 0x25, 0x55), Self.rgb(0x1A, 0x1E, 0x4B), Palette.nightBottom]
        case .day: return [Self.rgb(0x1A, 0x28, 0x5E), Self.rgb(0x14, 0x1F, 0x50), Palette.nightBottom]
        case .dusk: return [Self.rgb(0x2D, 0x23, 0x57), Self.rgb(0x1C, 0x1B, 0x49), Palette.nightBottom]
        case .night: return [Palette.nightTop, Palette.night, Palette.nightBottom]
        }
    }

    var glow: Color {
        switch self {
        case .dawn: return Self.rgb(0xF4, 0xB1, 0x83).opacity(0.13)
        case .day: return Palette.teal.opacity(0.10)
        case .dusk: return Self.rgb(0xEB, 0xA2, 0x7C).opacity(0.12)
        case .night: return Self.rgb(0xCF, 0xC6, 0xFF).opacity(0.08)
        }
    }
}

/// Widget background: the sky of the entry's hour, with the app's soft indigo glow low down.
private struct WidgetSkyBackground: View {
    let date: Date
    var body: some View {
        let sky = WidgetSky.at(date)
        ZStack {
            LinearGradient(colors: sky.colors, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [sky.glow, .clear], center: UnitPoint(x: 0.9, y: -0.05), startRadius: 4, endRadius: 200)
            WidgetGlow()
        }
    }
}
#endif

// MARK: - Timeline

struct StillEntry: TimelineEntry {
    var date: Date
    var streak: Int
    var weekMinutes: Double
    var weekGoal: Double
    var suggestedTitle: String
    var suggestedId: String
    var bestStreak: Int = 0
    var practicedToday = false
    var suggestedDetail = ""
    var suggestedSymbol = "wind"

    /// The line under the streak: keeps it alive, or says today is done.
    var streakNote: String {
        if practicedToday { return streak > 1 ? "Done today · keep resting" : "Done for today" }
        return streak > 0 ? "Practice today to keep it" : "Begin a streak today"
    }

    var progress: Double { weekGoal > 0 ? min(1, weekMinutes / weekGoal) : 0 }
    var goalReached: Bool { weekGoal > 0 && weekMinutes >= weekGoal }
    var url: URL? { Bridge.practiceURL(suggestedId) }

    static let placeholder = StillEntry(date: Date(), streak: 3, weekMinutes: 18, weekGoal: 30,
                                        suggestedTitle: "Resonance Breathing", suggestedId: "resonance",
                                        bestStreak: 9, practicedToday: false, suggestedDetail: "Breathe · 5 min",
                                        suggestedSymbol: "wind")

    /// What the app last wrote; a quiet default before the first session.
    static func current(date: Date = Date()) -> StillEntry {
        let d = UserDefaults(suiteName: Bridge.suite) ?? .standard
        let goal = d.double(forKey: "weekGoal")
        let title = d.string(forKey: "suggestedTitle") ?? ""
        // The streak's last day, so a stale value still reads right after midnight (or after a missed day).
        var streak = max(0, d.integer(forKey: "streak"))
        var doneToday = d.bool(forKey: "practicedToday")
        let last = d.double(forKey: "streakDay")
        if last > 0 {
            let cal = Calendar.current
            let gap = cal.dateComponents([.day], from: cal.startOfDay(for: Date(timeIntervalSince1970: last)),
                                         to: cal.startOfDay(for: date)).day ?? 0
            if gap >= 1 { doneToday = false }
            if gap >= 2 { streak = 0 }
        }
        return StillEntry(date: date,
                          streak: streak,
                          weekMinutes: max(0, d.double(forKey: "weekMinutes")),
                          weekGoal: goal > 0 ? goal : 30,
                          suggestedTitle: title.isEmpty ? "Breathe" : title,
                          suggestedId: d.string(forKey: "suggestedId") ?? "",
                          bestStreak: max(0, d.integer(forKey: "bestStreak")),
                          practicedToday: doneToday,
                          suggestedDetail: d.string(forKey: "suggestedDetail") ?? "",
                          suggestedSymbol: d.string(forKey: "suggestedSymbol") ?? "wind")
    }
}

struct StillProvider: TimelineProvider {
    func placeholder(in context: Context) -> StillEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StillEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StillEntry>) -> Void) {
        // The app reloads timelines after every session. Otherwise refresh at the next part of the day (the routine
        // changes at 5, 11, 17 and 21 h, the sky behind it at 5, 8, 17 and 20 h) and at midnight, when "done today" resets.
        let now = Date()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let marks = [5, 8, 11, 17, 20, 21, 24].compactMap { cal.date(byAdding: .hour, value: $0, to: start) }
        let next = marks.first { $0 > now.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [StillEntry.current(date: now)], policy: .after(next)))
    }
}

// MARK: - iOS home-screen widget (small / medium)

#if !os(watchOS)
struct StillPointWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Bridge.kind, provider: StillProvider()) { entry in
            StillHomeView(entry: entry)
                .containerBackground(for: .widget) { WidgetSkyBackground(date: entry.date) }
                .widgetURL(entry.url)
        }
        .configurationDisplayName("Today's routine")
        .description("Your next suggested session and your streak. Tap to start.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// A soft indigo glow low in the widget, like the app's background.
private struct WidgetGlow: View {
    var body: some View {
        RadialGradient(colors: [Palette.indigo.opacity(0.24), .clear], center: UnitPoint(x: 0.5, y: 1.1),
                       startRadius: 4, endRadius: 220)
    }
}

struct StillHomeView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: StillEntry

    /// Tinted Home Screen: the system recolours everything by its opacity, so solid fills turn into soft outlines
    /// (white text on a solid capsule would vanish).
    private var accented: Bool { renderingMode == .accented }

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Flame(lit: entry.streak > 0, size: 15).widgetAccentable()
                Text("\(entry.streak)").font(Palette.numbers(30)).foregroundStyle(Palette.ink).widgetAccentable()
                Text(entry.streak == 1 ? "day" : "days").font(Palette.rounded(12)).foregroundStyle(Palette.dim)
                Spacer(minLength: 0)
                GoalRing(entry: entry, size: 34, width: 4, showText: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.streak) day streak. \(entry.streakNote)")
            Text(entry.streakNote).font(Palette.rounded(10)).foregroundStyle(Palette.faint).lineLimit(1)
            Spacer(minLength: 4)
            Text("TODAY'S ROUTINE").font(Palette.rounded(8, .semibold)).tracking(1.3).foregroundStyle(Palette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: entry.suggestedSymbol).font(.system(size: 12, weight: .light)).foregroundStyle(Palette.teal)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(entry.suggestedTitle)
                    .font(Palette.serif(15)).foregroundStyle(Palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.75)
            }
            Text(entry.suggestedDetail.isEmpty ? "Tap to start" : "\(entry.suggestedDetail) · tap to start")
                .font(Palette.rounded(10)).foregroundStyle(Palette.faint).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STILL POINTZ").font(Palette.rounded(10, .semibold)).tracking(1.6).foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Flame(lit: entry.streak > 0, size: 18).widgetAccentable()
                    Text("\(entry.streak)").font(Palette.numbers(34)).foregroundStyle(Palette.ink).widgetAccentable()
                    Text(entry.streak == 1 ? "day" : "days").font(Palette.rounded(13)).foregroundStyle(Palette.dim)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.streak) day streak")
                Text(entry.bestStreak > entry.streak ? "\(entry.streakNote) · best \(entry.bestStreak)" : entry.streakNote)
                    .font(Palette.rounded(10)).foregroundStyle(Palette.faint).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                WeekBar(entry: entry)
                HStack(spacing: 6) {
                    ForEach(HeatChoice.allCases) { k in
                        if let url = Bridge.heatURL(k) {
                            Link(destination: url) {
                                Label(k.title, systemImage: k.symbol)
                                    .font(Palette.rounded(10, .medium)).foregroundStyle(k.tint)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(k.tint.opacity(0.16)))
                                    .overlay(Capsule().stroke(k.tint.opacity(0.30), lineWidth: 0.8))
                            }
                            .accessibilityLabel("Start \(k.title) timer")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            routineCard
        }
        .padding(14)
    }

    /// The next suggested session, in its own soft card.
    private var routineCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY'S ROUTINE").font(Palette.rounded(9, .semibold)).tracking(1.3).foregroundStyle(Palette.faint)
            Image(systemName: entry.suggestedSymbol)
                .font(.system(size: 15, weight: .light)).foregroundStyle(Palette.teal)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.teal.opacity(0.16)))
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(entry.suggestedTitle)
                .font(Palette.serif(16)).foregroundStyle(Palette.ink)
                .lineLimit(2).minimumScaleFactor(0.75)
            if !entry.suggestedDetail.isEmpty {
                Text(entry.suggestedDetail).font(Palette.rounded(10)).foregroundStyle(Palette.dim).lineLimit(1)
            }
            Spacer(minLength: 2)
            Label("Start", systemImage: "play.fill")
                .font(Palette.rounded(12, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(accented ? AnyShapeStyle(Color.white.opacity(0.18)) : AnyShapeStyle(Palette.accentFill)))
                .widgetAccentable()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's routine: \(entry.suggestedTitle). \(entry.suggestedDetail)")
        .accessibilityHint("Starts the session")
    }
}

/// This week's minutes vs goal as a thin bar.
private struct WeekBar: View {
    let entry: StillEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(entry.goalReached ? Palette.goldGlow : LinearGradient(colors: [Palette.teal, Palette.indigo], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * entry.progress))
                }
            }
            .frame(height: 5)
            Text(entry.goalReached ? "Weekly goal met" : "\(Int(entry.weekMinutes.rounded()))/\(Int(entry.weekGoal)) min this week")
                .font(Palette.rounded(9)).foregroundStyle(Palette.faint).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(entry.weekMinutes.rounded())) of \(Int(entry.weekGoal)) minutes this week")
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
        .description("Your streak and this week's minutes. Tap to start today's routine.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #else
        return [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct StillAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StillEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        #if os(watchOS)
        case .accessoryCorner: corner
        #endif
        default: inline
        }
    }

    #if os(watchOS)
    private var corner: some View {
        Image(systemName: entry.streak > 0 ? "flame.fill" : "flame")
            .font(.system(size: 20, weight: .medium))
            .widgetAccentable()
            .widgetLabel {
                Text("\(entry.streak) \(entry.streak == 1 ? "day" : "days")")
            }
            .accessibilityLabel("\(entry.streak) day streak")
    }
    #endif

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
        .tint(entry.goalReached ? Palette.gold : Palette.accent)
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
                .tint(entry.goalReached ? Palette.gold : Palette.accent)
            Text(entry.practicedToday ? "Done today · \(entry.suggestedTitle)" : entry.suggestedTitle)
                .font(.system(size: 12, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.85)
                .opacity(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.streak) day streak. \(entry.streakNote). Next: \(entry.suggestedTitle)")
    }

    private var inline: some View {
        Label {
            Text("\(entry.streak) \(entry.streak == 1 ? "day" : "days") · \(Int(entry.weekMinutes.rounded()))/\(Int(entry.weekGoal)) min")
        } icon: {
            Image(systemName: entry.streak > 0 ? "flame.fill" : "flame")
        }
    }
}

// MARK: - Sauna / steam (Watch complication)

/// Mirrors the app's HeatKind (the extension can't see app code).
enum HeatChoice: String, CaseIterable, Identifiable {
    case sauna, steam
    var id: String { rawValue }
    var title: String { self == .sauna ? "Sauna" : "Steam" }
    var symbol: String { self == .sauna ? "flame.fill" : "cloud.fog.fill" }
    /// Soft ember / mist blue, as HeatKind.tint in the app.
    var tint: Color {
        self == .sauna ? Color(red: 0xF2 / 255, green: 0xA0 / 255, blue: 0x7B / 255)
                       : Color(red: 0x8E / 255, green: 0xC5 / 255, blue: 0xE8 / 255)
    }
}

struct HeatEntryState: TimelineEntry {
    var date: Date
    /// The kind this complication starts.
    var choice: HeatChoice
    /// A timer running now (any kind), and since when.
    var running: HeatChoice?
    var start: Date?
}

struct HeatProvider: TimelineProvider {
    let choice: HeatChoice

    func placeholder(in context: Context) -> HeatEntryState {
        HeatEntryState(date: Date(), choice: choice, running: nil, start: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeatEntryState) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeatEntryState>) -> Void) {
        let e = current()
        // The app reloads this when a timer starts or stops. A forgotten timer falls back to the quick-start after 3 h.
        if let start = e.start {
            let expiry = start.addingTimeInterval(3 * 3600)
            let after = HeatEntryState(date: expiry, choice: choice, running: nil, start: nil)
            completion(Timeline(entries: [e, after], policy: .never))
        } else {
            completion(Timeline(entries: [e], policy: .never))
        }
    }

    private func current() -> HeatEntryState {
        let d = UserDefaults(suiteName: Bridge.suite) ?? .standard
        let t = d.double(forKey: "heatStart")
        if let k = d.string(forKey: "heatKind").flatMap(HeatChoice.init(rawValue:)), t > 0 {
            let start = Date(timeIntervalSince1970: t)
            if Date().timeIntervalSince(start) < 3 * 3600 {
                return HeatEntryState(date: Date(), choice: choice, running: k, start: start)
            }
        }
        return HeatEntryState(date: Date(), choice: choice, running: nil, start: nil)
    }
}

/// Quick-start for the sauna timer on the Watch face (Widget needs a plain init, so one type per kind).
struct SaunaComplication: Widget {
    var body: some WidgetConfiguration { HeatComplication.configuration(.sauna) }
}

struct SteamComplication: Widget {
    var body: some WidgetConfiguration { HeatComplication.configuration(.steam) }
}

/// Quick-start for the sauna or steam timer on the Watch face; while a timer runs it shows the elapsed time.
enum HeatComplication {
    static func configuration(_ kind: HeatChoice) -> some WidgetConfiguration {
        StaticConfiguration(kind: "StillPointHeat.\(kind.rawValue)", provider: HeatProvider(choice: kind)) { entry in
            HeatAccessoryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(Bridge.heatURL(entry.running ?? entry.choice))
        }
        .configurationDisplayName(kind.title)
        .description("Start the \(kind.title.lowercased()) timer in one tap. Shows the time while you're in.")
        .supportedFamilies(families)
    }

    private static var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #else
        return [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct HeatAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeatEntryState

    private var shown: HeatChoice { entry.running ?? entry.choice }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            #if os(watchOS)
            case .accessoryCorner: corner
            #endif
            default: inline
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if let start = entry.start, let k = entry.running {
            return "\(k.title) timer running since \(start.formatted(date: .omitted, time: .shortened))"
        }
        return "Start \(entry.choice.title) timer"
    }

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: shown.symbol).font(.system(size: entry.start == nil ? 18 : 12, weight: .medium))
                    .foregroundStyle(shown.tint)
                    .widgetAccentable()
                if let start = entry.start {
                    Text(start, style: .timer)
                        .font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                } else {
                    Text(shown.title).font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(4)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(entry.start == nil ? shown.title : "In the \(shown.title.lowercased())")
            } icon: {
                Image(systemName: shown.symbol).foregroundStyle(shown.tint)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .widgetAccentable()
            if let start = entry.start {
                Text(start, style: .timer)
                    .font(.system(size: 24, weight: .light, design: .rounded)).monospacedDigit()
                Text("Tap to open").font(.system(size: 11, design: .rounded)).opacity(0.7)
            } else {
                Text("Tap to start the timer").font(.system(size: 13, design: .rounded)).opacity(0.85)
                Text("Breathing & bench moves inside").font(.system(size: 11, design: .rounded)).opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(watchOS)
    private var corner: some View {
        Image(systemName: shown.symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(shown.tint)
            .widgetAccentable()
            .widgetLabel {
                if let start = entry.start {
                    Text(start, style: .timer)
                } else {
                    Text(shown.title)
                }
            }
    }
    #endif

    @ViewBuilder private var inline: some View {
        if let start = entry.start {
            Label { Text("\(shown.title) ") + Text(start, style: .timer) } icon: { Image(systemName: shown.symbol) }
        } else {
            Label("Start \(shown.title.lowercased())", systemImage: shown.symbol)
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

// MARK: - "Right now" widget (iPhone Home Screen + Lock Screen)

#if !os(watchOS)
/// The single practice Still Pointz picked for this moment from Watch / WHOOP numbers in Health.
/// Written by the app (StillPoint/App/RightNowViews.swift, StillPointRightNow.publishForWidget).
struct RightNowEntry: TimelineEntry {
    var date: Date
    var practiceId: String
    var title: String
    var minutes: Int
    var because: String
    var timeOnly: Bool
    var stress: Int
    var computedAt: Date?

    var hasPick: Bool { !title.isEmpty }
    var url: URL? { Bridge.practiceURL(practiceId) }
    /// Picks are about this moment: older than 3 hours, the widget says so instead of presenting it as current.
    var stale: Bool { computedAt.map { date.timeIntervalSince($0) > 3 * 3600 } ?? true }

    var stressLabel: String? {
        switch stress {
        case 0: return "Calm"
        case 1: return "Balanced"
        case 2: return "Elevated"
        case 3: return "High"
        default: return nil
        }
    }

    static let placeholder = RightNowEntry(date: Date(), practiceId: "resonance", title: "Resonance Breathing", minutes: 5,
                                           because: "Your heart rate is 12 bpm above resting", timeOnly: false, stress: 2,
                                           computedAt: Date())

    static func current(date: Date = Date()) -> RightNowEntry {
        let d = UserDefaults(suiteName: Bridge.suite) ?? .standard
        let at = d.double(forKey: "rightNowAt")
        return RightNowEntry(date: date,
                             practiceId: d.string(forKey: "rightNowId") ?? "",
                             title: d.string(forKey: "rightNowTitle") ?? "",
                             minutes: max(1, d.integer(forKey: "rightNowMinutes")),
                             because: d.string(forKey: "rightNowBecause") ?? "",
                             timeOnly: d.bool(forKey: "rightNowTimeOnly"),
                             stress: d.object(forKey: "rightNowStress") as? Int ?? -1,
                             computedAt: at > 0 ? Date(timeIntervalSince1970: at) : nil)
    }
}

struct RightNowProvider: TimelineProvider {
    func placeholder(in context: Context) -> RightNowEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (RightNowEntry) -> Void) {
        let e = RightNowEntry.current()
        completion(context.isPreview && !e.hasPick ? .placeholder : e)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RightNowEntry>) -> Void) {
        // The app reloads this kind whenever its pick changes; an extra entry marks it stale after 3 hours, and
        // two more repaint the sky when the hour turns to dawn, day, dusk or night.
        let now = Date()
        let e = RightNowEntry.current(date: now)
        var marks = WidgetSky.changes(after: now, count: 2)
        if let at = e.computedAt, !e.stale { marks.append(at.addingTimeInterval(3 * 3600 + 60)) }
        var entries = [e]
        for m in marks.sorted() where m > now {
            var later = e
            later.date = m
            entries.append(later)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct RightNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StillPointRightNow", provider: RightNowProvider()) { entry in
            RightNowWidgetView(entry: entry)
                .widgetURL(entry.hasPick ? entry.url : URL(string: "stillpoint://practice/"))
        }
        .configurationDisplayName("Right now")
        .description("The one practice picked for this moment from your heart rate, HRV and sleep. Tap to start.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct RightNowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: RightNowEntry

    /// Tinted Home Screen: solid fills become soft outlines (as the routine widget's Start pill).
    private var accented: Bool { renderingMode == .accented }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryInline: Label(entry.hasPick ? "\(entry.title) · \(entry.minutes) min" : "Right now", systemImage: "sparkles")
            case .systemMedium: home(medium: true)
            default: home(medium: false)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                WidgetSkyBackground(date: entry.date)
            } else {
                Color.clear
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.hasPick ? "Right now: \(entry.title), \(entry.minutes) minutes. \(entry.because)" : "Right now. Open Still Pointz for a pick.")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Right now", systemImage: "sparkles").font(.caption2.weight(.semibold)).widgetAccentable()
            Text(entry.hasPick ? entry.title : "Open for a pick").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            Text(entry.hasPick ? "\(entry.minutes) min\(entry.stressLabel.map { " · \($0)" } ?? "")" : "From your Watch or WHOOP")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: String {
        guard entry.hasPick else { return "Open Still Pointz once to get a pick from your Watch or WHOOP data." }
        if entry.stale, let at = entry.computedAt {
            return "Picked at \(at.formatted(date: .omitted, time: .shortened)) · open for a fresh one"
        }
        return entry.because
    }

    private func home(medium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("RIGHT NOW", systemImage: "sparkles")
                    .font(Palette.rounded(9, .semibold)).tracking(1.3).foregroundStyle(Palette.faint)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if medium, let s = entry.stressLabel, !entry.stale {
                    Text("Stress: \(s)").font(Palette.rounded(10, .medium)).foregroundStyle(Palette.teal).lineLimit(1)
                }
            }
            Text(entry.hasPick ? entry.title : "Breathe")
                .font(Palette.serif(medium ? 20 : 17)).foregroundStyle(Palette.ink)
                .lineLimit(2).minimumScaleFactor(0.75)
            if entry.hasPick {
                // One clear action, named as in the app ("Start · 5 min").
                Label("Start · \(entry.minutes) min", systemImage: "play.fill")
                    .font(Palette.rounded(10, .semibold)).foregroundStyle(.white).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(accented ? AnyShapeStyle(Color.white.opacity(0.18)) : AnyShapeStyle(Palette.accentFill)))
                    .widgetAccentable()
            }
            Spacer(minLength: 2)
            Text(footnote)
                .font(Palette.rounded(10)).foregroundStyle(Palette.faint)
                .lineLimit(medium ? 2 : 3).minimumScaleFactor(0.85)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
