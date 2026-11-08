import Foundation
import SwiftData

enum Meal: String, CaseIterable, Identifiable, Codable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snacks = "Snacks"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "popcorn.fill"
        }
    }
    /// Best guess from the time of day.
    static var now: Meal {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snacks
        }
    }
}

@Model
final class FoodEntry {
    var id: UUID = UUID()
    var name: String = ""
    var cal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var caffeine: Double = 0
    var servings: Double = 1
    var mealRaw: String = Meal.snacks.rawValue
    var day: String = ""          // yyyy-MM-dd
    var createdAt: Date = Date()

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snacks }

    init(name: String, cal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, caffeine: Double = 0,
         servings: Double = 1, meal: Meal, day: String, createdAt: Date = Date()) {
        self.name = name; self.cal = cal; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.caffeine = caffeine; self.servings = servings; self.mealRaw = meal.rawValue; self.day = day; self.createdAt = createdAt
    }
}

struct QuickFood: Decodable, Hashable, Identifiable {
    var id: String { name + serving }
    let name: String
    let serving: String
    let cal: Int
    let p: Double
    let c: Double
    let f: Double
    let caf: Int
    let tags: [String]

    static let all: [QuickFood] = {
        guard let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([QuickFood].self, from: data)) ?? []
    }()
}

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

/// Brings entries over from the old web version of Food Book (saved on the phone as store.json).
enum LegacyImport {
    static func runOnce(into context: ModelContext) {
        let flag = "importedLegacyStore"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        defer { UserDefaults.standard.set(true, forKey: flag) }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("store.json")
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let settings = store["config/settings"] as? [String: Any], let goal = settings["goal"] as? Double, goal > 0 {
            UserDefaults.standard.set(goal, forKey: "goal")
        }
        for (key, value) in store where key.hasPrefix("food/") {
            guard let f = value as? [String: Any], let name = f["name"] as? String,
                  (f["status"] as? String) != "remove_requested" else { continue }
            func num(_ k: String) -> Double { (f[k] as? Double) ?? Double(f[k] as? Int ?? 0) }
            let created = Date(timeIntervalSince1970: num("createdAt") / 1000)
            let e = FoodEntry(name: name, cal: num("cal"), protein: num("protein"), carbs: num("carbs"), fat: num("fat"),
                              caffeine: num("caffeine"), servings: max(1, num("servings")),
                              meal: Meal(rawValue: f["meal"] as? String ?? "") ?? .snacks,
                              day: f["date"] as? String ?? Day.key(created), createdAt: created)
            context.insert(e)
        }
        try? context.save()
    }
}
