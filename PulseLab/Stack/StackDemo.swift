import Foundation
import SwiftData

/// Made-up sample stack for `-demo` launches only (simulator QA and App Store screenshots), so the Stack tab shows
/// a filled checklist instead of its empty state.
///
/// DATA SAFETY: the sample lives in its own in-memory container, used only when the app was launched with
/// `-demo`. It is never written to the real Stack store (or iCloud), and a normal launch never builds it.
enum StackDemo {
    static let container: ModelContainer = {
        let schema = Schema([Supplement.self, SuppDose.self])
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let c = try! ModelContainer(for: schema, configurations: memory)
        seed(ModelContext(c))
        return c
    }()

    /// Sample items (name, dose, emoji, time, with food). Generic picks, nobody's real stack.
    private static let items: [(String, String, String, SuppTime, Bool)] = [
        ("Vitamin D3", "2000 IU", "☀️", .morning, true),
        ("Omega-3", "1 softgel", "🐟", .morning, true),
        ("Creatine", "5 g", "💪", .anytime, false),
        ("Electrolytes", "1 packet", "🧂", .midday, false),
        ("Magnesium", "200 mg", "🌙", .night, false),
    ]

    private static func seed(_ context: ModelContext) {
        var supps: [Supplement] = []
        for (i, it) in items.enumerated() {
            let s = Supplement(name: it.0, dose: it.1, emoji: it.2, time: it.3, order: i)
            s.withFood = it.4
            context.insert(s)
            supps.append(s)
        }
        // A 9-day streak before today (the day before it skipped), and a 60-day history. The demo health data
        // (DemoData) has its easy weeks about 17-33 and 50-60 days back, so the stack is mostly taken then and mostly
        // skipped in the hard weeks between: the Stack vs recovery card shows the made-up stack helping.
        let today = Day.key(Date())
        for back in 1...60 {
            let k = Day.shift(today, by: -back)
            for (i, s) in supps.enumerated() {
                let taken: Bool
                switch back {
                case 1...9: taken = true
                case 10...16: taken = false
                case 17...33, 50...60: taken = (back + i) % 7 != 0
                default: taken = (back + i) % 6 == 0
                }
                if taken { context.insert(SuppDose(suppID: s.id, day: k)) }
            }
        }
        for s in supps where s.time == .morning { context.insert(SuppDose(suppID: s.id, day: today)) }
        try? context.save()
    }
}
