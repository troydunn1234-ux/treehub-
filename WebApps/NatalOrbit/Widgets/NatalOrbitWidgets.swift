import SwiftUI
import WidgetKit

// Natal Orbit on the Home Screen: today's reading headline from your own chart.
// The app works out the next week of readings (web/index.html, syncDaily) and saves them in the App Group;
// the widget shows the one for today and flips to the next at midnight.

@main
struct NatalOrbitWidgets: WidgetBundle {
    var body: some Widget {
        DailyReadingWidget()
    }
}

private enum NOShared {
    static let appGroup = "group.com.troydunn.natalorbit"
    static let key = "shell.widget"
    static let void = Color(red: 0.020, green: 0.027, blue: 0.059)
    static let panel = Color(red: 0.047, green: 0.063, blue: 0.125)
    static let gold = Color(red: 0.949, green: 0.769, blue: 0.427)
    static let ink = Color(red: 0.910, green: 0.922, blue: 0.969)
    static let dim = Color(red: 0.541, green: 0.573, blue: 0.706)
    static let violet = Color(red: 0.486, green: 0.302, blue: 1.0)
    /// Family accent: cosmic violet (matches --accent in web/index.html).
    static let accent = Color(red: 0.655, green: 0.545, blue: 0.980)

    struct Day: Decodable { let d: String; let head: String; let moon: String?; let good: String? }
    struct Payload: Decodable { let name: String?; let days: [Day] }

    static func load() -> Payload? {
        guard let s = UserDefaults(suiteName: appGroup)?.string(forKey: key), let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

struct ReadingEntry: TimelineEntry {
    let date: Date
    let name: String
    let head: String
    let moon: String
    let good: String
    let hasChart: Bool

    static let sample = ReadingEntry(date: Date(), name: "Ava", head: "A good day to say what you mean",
                                     moon: "☽ Moon in Leo · Waxing Gibbous", good: "Good day for: honest talks, making plans", hasChart: true)
    static func empty(_ date: Date) -> ReadingEntry {
        ReadingEntry(date: date, name: "", head: "Open Natal Orbit to set up your chart", moon: "", good: "", hasChart: false)
    }
}

struct ReadingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
        if context.isPreview, NOShared.load() == nil { completion(.sample); return }
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
        let cal = Calendar.current
        var entries = [entry(for: Date())]
        var day = cal.startOfDay(for: Date())
        for _ in 0..<7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            entries.append(entry(for: day))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> ReadingEntry {
        guard let p = NOShared.load(), let d = p.days.first(where: { $0.d == NOShared.dayKey(date) }) else { return .empty(date) }
        return ReadingEntry(date: date, name: p.name ?? "", head: d.head, moon: d.moon ?? "", good: d.good ?? "", hasChart: true)
    }
}

struct DailyReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NatalOrbitDailyReading", provider: ReadingProvider()) { entry in
            ReadingView(entry: entry)
                .widgetURL(URL(string: "natalorbit://today"))
                .containerBackground(for: .widget) {
                    ZStack {
                        NOShared.void
                        RadialGradient(colors: [NOShared.violet.opacity(0.28), .clear], center: .topLeading, startRadius: 4, endRadius: 220)
                        RadialGradient(colors: [NOShared.gold.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 4, endRadius: 180)
                    }
                }
        }
        .configurationDisplayName("Today's Reading")
        .description("Your daily horoscope headline from your own chart.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ReadingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadingEntry

    private var eyebrow: String {
        entry.name.isEmpty ? "TODAY" : "TODAY FOR \(entry.name.uppercased())"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(entry.hasChart ? entry.head : "Set up your chart", systemImage: "sparkles")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(entry.name.isEmpty ? "Today" : "Today for \(entry.name)", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold)).lineLimit(1).widgetAccentable()
                Text(entry.hasChart ? entry.head : "Open Natal Orbit to set up your chart")
                    .font(.system(.footnote, design: .serif).weight(.semibold))
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if entry.hasChart { reading } else { emptyState }
        }
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                Text(eyebrow).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).lineLimit(1)
            }
            .foregroundStyle(NOShared.accent)
            .widgetAccentable()

            Text(entry.head)
                .font(.system(size: family == .systemSmall ? 16 : 19, weight: .semibold, design: .serif))
                .foregroundStyle(NOShared.ink)
                .lineLimit(family == .systemSmall ? 4 : 3)
                .minimumScaleFactor(0.8)
                .shadow(color: NOShared.accent.opacity(0.22), radius: 8)

            Spacer(minLength: 0)

            if family == .systemMedium, !entry.good.isEmpty {
                Text(entry.good)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(NOShared.dim)
                    .lineLimit(1)
            }
            if !entry.moon.isEmpty {
                Text(entry.moon)
                    .font(.system(size: family == .systemSmall ? 10 : 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(NOShared.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// No saved chart yet: a calm prompt instead of an empty card.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(NOShared.accent)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text("Your daily reading")
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold, design: .serif))
                .foregroundStyle(NOShared.ink)
                .lineLimit(2)
            Text("Open Natal Orbit and save your chart.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(NOShared.dim)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
