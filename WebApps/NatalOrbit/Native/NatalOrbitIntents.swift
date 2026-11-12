import AppIntents
import Foundation

// Siri and Shortcuts for Natal Orbit. Each intent opens the app and asks the page to jump to a section
// (ShellLink -> window.__shellOpen -> goSection in web/index.html).

enum NatalSectionOption: String, AppEnum {
    case today, year, sky, compare, chart

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static var caseDisplayRepresentations: [NatalSectionOption: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today's horoscope", image: .init(systemName: "sun.max.fill")),
        .year: DisplayRepresentation(title: "Year ahead", image: .init(systemName: "calendar")),
        .sky: DisplayRepresentation(title: "Transits", image: .init(systemName: "moon.stars.fill")),
        .compare: DisplayRepresentation(title: "Compatibility", image: .init(systemName: "person.2.fill")),
        .chart: DisplayRepresentation(title: "Birth chart", image: .init(systemName: "sparkles")),
    ]
}

struct OpenNatalSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Natal Orbit Section"
    static var description = IntentDescription("Opens Natal Orbit to today's horoscope, your year ahead, transits, compatibility or your birth chart.")
    static var openAppWhenRun = true

    @Parameter(title: "Section", default: .today)
    var section: NatalSectionOption

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$section)") }

    init() {}
    init(section: NatalSectionOption) { self.section = section }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShellLink.queue(section: section.rawValue)
        return .result()
    }
}

struct TodayHoroscopeIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Horoscope"
    static var description = IntentDescription("Opens Natal Orbit to your horoscope for today.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShellLink.queue(section: "today")
        return .result()
    }
}

struct ShareChartCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Share My Chart Card"
    static var description = IntentDescription("Opens Natal Orbit and makes a shareable card of your chart.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShellLink.queue(section: "share")
        return .result()
    }
}

struct NatalOrbitShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayHoroscopeIntent(),
            phrases: [
                "Show my horoscope in \(.applicationName)",
                "What's my horoscope in \(.applicationName)",
                "Read my horoscope with \(.applicationName)",
                "What do the stars say \(.applicationName)",
            ],
            shortTitle: "Today's horoscope",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: OpenNatalSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
                "Show my \(\.$section) in \(.applicationName)",
                "Open my chart in \(.applicationName)",
            ],
            shortTitle: "Open a section",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ShareChartCardIntent(),
            phrases: [
                "Share my chart from \(.applicationName)",
                "Make a chart card in \(.applicationName)",
            ],
            shortTitle: "Share chart card",
            systemImageName: "square.and.arrow.up"
        )
    }
}
