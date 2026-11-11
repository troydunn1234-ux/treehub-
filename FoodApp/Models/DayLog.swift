import Foundation
import SwiftData

/// Quick taps that aren't meals: glasses of water and cups of coffee, one record per day.
@Model
final class DayLog {
    var day: String = ""            // yyyy-MM-dd
    var water: Int = 0              // glasses (250 ml each)
    var coffees: Int = 0            // cups (95 mg caffeine each)
    var updatedAt: Date = Date()

    static let glassML: Double = 250
    static let cupMG: Double = 95

    var waterML: Double { Double(water) * Self.glassML }
    var caffeineMG: Double { Double(coffees) * Self.cupMG }

    init(day: String, water: Int = 0, coffees: Int = 0) {
        self.day = day; self.water = water; self.coffees = coffees
    }

    /// The day's record, created on first use.
    static func fetchOrCreate(_ day: String, in context: ModelContext) -> DayLog {
        let fd = FetchDescriptor<DayLog>(predicate: #Predicate { $0.day == day })
        if let existing = try? context.fetch(fd).first { return existing }
        let log = DayLog(day: day)
        context.insert(log)
        return log
    }
}
