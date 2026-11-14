import SwiftUI

/// The Stack's styling, mapped onto Pulse Lab's palette so it feels native here.
/// (The Stack came over from Food Book; keeping these names keeps that code untouched.)
enum Ember {
    static let bg = Lab.bg
    static let card = Color.white.opacity(0.06)
    static let line = Lab.line
    static let cream = Lab.text
    static let dim = Lab.dim
    static let orange = Lab.whoop
    static let pink = Lab.violet
    static let gold = Lab.warn
    static let protein = Lab.watch
    static let carbs = Lab.warn
    static let fat = Lab.bad
    static let fire = Lab.duel
    static func font(_ s: CGFloat, _ w: Font.Weight = .bold) -> Font { .system(size: s, weight: w, design: .rounded) }
}

/// Pulse Lab already draws its own background behind every tab.
struct EmberBackground: View {
    var body: some View { Color.clear }
}

struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Day keys like "2026-11-13".
enum Day {
    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func key(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ k: String) -> Date { fmt.date(from: k) ?? Date() }
    static func shift(_ k: String, by days: Int) -> String {
        key(Calendar.current.date(byAdding: .day, value: days, to: date(k)) ?? Date())
    }
    static func title(_ k: String) -> String {
        let d = date(k)
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
