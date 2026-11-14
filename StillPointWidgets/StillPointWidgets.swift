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
        HeatComplication(kind: .sauna)
        HeatComplication(kind: .steam)
        #else
        StillPointWidget()
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
        // changes at 5, 11, 17 and 21 h) and at midnight, when "done today" resets.
        let now = Date()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let marks = [5, 11, 17, 21, 24].compactMap { cal.date(byAdding: .hour, value: $0, to: start) }
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
                .containerBackground(for: .widget) { ZStack { Palette.background; WidgetGlow() } }
                .widgetURL(entry.url)
        }
        .configurationDisplayName("Today's routine")
        .description("Your next suggested session and your streak. Tap to begin.")
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
                GoalRing(entry: entry, size: 34, width: 4, showText: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.streak) day streak. \(entry.streakNote)")
            Text(entry.streakNote).font(Palette.rounded(10)).foregroundStyle(Palette.faint).lineLimit(1)
            Spacer(minLength: 4)
            Text("TODAY'S ROUTINE").font(Palette.rounded(8, .semibold)).tracking(1.3).foregroundStyle(Palette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: entry.suggestedSymbol).font(.system(size: 12, weight: .light)).foregroundStyle(Palette.teal)
                    .accessibilityHidden(true)
                Text(entry.suggestedTitle)
                    .font(Palette.serif(15)).foregroundStyle(Palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.75)
            }
            Text(entry.suggestedDetail.isEmpty ? "Tap to begin" : "\(entry.suggestedDetail) · tap to begin")
                .font(Palette.rounded(10)).foregroundStyle(Palette.faint).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STILL POINT").font(Palette.rounded(10, .semibold)).tracking(1.6).foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Flame(lit: entry.streak > 0, size: 18)
                    Text("\(entry.streak)").font(Palette.numbers(34)).foregroundStyle(Palette.ink)
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
                .accessibilityHidden(true)
            Text(entry.suggestedTitle)
                .font(Palette.serif(16)).foregroundStyle(Palette.ink)
                .lineLimit(2).minimumScaleFactor(0.75)
            if !entry.suggestedDetail.isEmpty {
                Text(entry.suggestedDetail).font(Palette.rounded(10)).foregroundStyle(Palette.dim).lineLimit(1)
            }
            Spacer(minLength: 2)
            Text("Begin")
                .font(Palette.rounded(12, .semibold)).foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(Palette.goldGlow))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
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
        .description("Your streak and this week's minutes. Tap to begin today's routine.")
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
    var tint: Color {
        self == .sauna ? Color(red: 0xF2 / 255, green: 0x9A / 255, blue: 0x5B / 255)
                       : Color(red: 0x7F / 255, green: 0xC8 / 255, blue: 0xD9 / 255)
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

/// Quick-start for the sauna or steam timer on the Watch face; while a timer runs it shows the elapsed time.
struct HeatComplication: Widget {
    let kind: HeatChoice

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StillPointHeat.\(kind.rawValue)", provider: HeatProvider(choice: kind)) { entry in
            HeatAccessoryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(Bridge.heatURL(entry.running ?? entry.choice))
        }
        .configurationDisplayName(kind.title)
        .description("Start the \(kind.title.lowercased()) timer in one tap. Shows the time while you're in.")
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
            Label(entry.start == nil ? shown.title : "In the \(shown.title.lowercased())", systemImage: shown.symbol)
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
