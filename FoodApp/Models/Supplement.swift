import Foundation
import SwiftData

enum SuppTime: String, CaseIterable, Identifiable, Codable {
    case morning = "Morning", midday = "Midday", evening = "Evening", night = "Bedtime", anytime = "Anytime"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .midday: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.zzz.fill"
        case .anytime: return "clock.fill"
        }
    }
    /// Reminder hour for this part of the day.
    var hour: Int {
        switch self { case .morning: return 8; case .midday: return 12; case .evening: return 18; case .night: return 22; case .anytime: return 14 }
    }
}

@Model
final class Supplement {
    var id: UUID = UUID()
    var name: String = ""
    var dose: String = ""
    var emoji: String = "💊"
    var timeRaw: String = SuppTime.morning.rawValue
    var order: Int = 0
    var createdAt: Date = Date()
    var time: SuppTime { SuppTime(rawValue: timeRaw) ?? .anytime }

    init(name: String, dose: String, emoji: String, time: SuppTime, order: Int) {
        self.name = name; self.dose = dose; self.emoji = emoji; self.timeRaw = time.rawValue; self.order = order
    }
}

/// One check-off: supplement X taken on day Y.
@Model
final class SuppDose {
    var suppID: UUID = UUID()
    var day: String = ""
    var takenAt: Date = Date()
    init(suppID: UUID, day: String) { self.suppID = suppID; self.day = day }
}

/// Common picks to add in one tap (dose left for you to edit).
struct SuppPreset: Hashable {
    let name: String, dose: String, emoji: String, time: SuppTime
    static let all: [SuppPreset] = [
        .init(name: "Multivitamin", dose: "1 tablet", emoji: "💊", time: .morning),
        .init(name: "Vitamin D3", dose: "1 softgel", emoji: "☀️", time: .morning),
        .init(name: "Omega-3 / Fish oil", dose: "1 softgel", emoji: "🐟", time: .morning),
        .init(name: "Vitamin C", dose: "1 tablet", emoji: "🍊", time: .morning),
        .init(name: "B12", dose: "1 tablet", emoji: "⚡️", time: .morning),
        .init(name: "Creatine", dose: "1 scoop", emoji: "💪", time: .anytime),
        .init(name: "Protein powder", dose: "1 scoop", emoji: "🥤", time: .anytime),
        .init(name: "Electrolytes", dose: "1 packet", emoji: "🧂", time: .midday),
        .init(name: "Greens powder", dose: "1 scoop", emoji: "🥬", time: .morning),
        .init(name: "Collagen", dose: "1 scoop", emoji: "✨", time: .morning),
        .init(name: "Pre-workout", dose: "1 scoop", emoji: "🔥", time: .midday),
        .init(name: "Probiotic", dose: "1 capsule", emoji: "🦠", time: .morning),
        .init(name: "Zinc", dose: "1 tablet", emoji: "🛡️", time: .evening),
        .init(name: "Magnesium", dose: "1 capsule", emoji: "🌙", time: .night),
        .init(name: "Ashwagandha", dose: "1 capsule", emoji: "🌿", time: .night),
        .init(name: "Melatonin", dose: "1 tablet", emoji: "😴", time: .night),
        .init(name: "Iron", dose: "1 tablet", emoji: "🧲", time: .morning),
        .init(name: "Turmeric", dose: "1 capsule", emoji: "🟡", time: .evening),
    ]
}
