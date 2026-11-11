import Foundation

/// Which tracker a number came from.
enum Source: String, CaseIterable, Identifiable, Codable {
    case watch, whoop
    var id: String { rawValue }
    var name: String { self == .watch ? "Apple Watch" : "WHOOP" }
    var short: String { self == .watch ? "WATCH" : "WHOOP" }
}

/// One calendar day of numbers from one source. Units are fixed (metric) and converted only for display:
/// bpm, ms, breaths/min, %, °C deviation, kcal, km, minutes, kg.
struct DayStat: Identifiable, Equatable {
    let day: Date            // start of day (local)
    var id: Date { day }
    var rhr: Double?
    var hrv: Double?         // Watch: SDNN ms · WHOOP: RMSSD ms
    var avgHR: Double?
    var walkHR: Double?
    var resp: Double?
    var spo2: Double?        // percent 0–100
    var tempDev: Double?     // °C vs personal baseline
    var activeKcal: Double?
    var basalKcal: Double?
    var steps: Double?
    var distanceKm: Double?
    var flights: Double?
    var exerciseMin: Double?
    var standMin: Double?
    var daylightMin: Double?
    var mindfulMin: Double?
    var audioDb: Double?
    var vo2: Double?
    var weightKg: Double?
    var bodyFat: Double?     // percent
    var hrRecovery: Double?
    var runSpeed: Double?    // m/s
    var runPower: Double?    // W
    var strideM: Double?
    var recovery: Double?    // WHOOP recovery 0–100 (or Pulse Lab readiness for the Watch)
    var strain: Double?      // WHOOP day strain 0–21
    var skinTempC: Double?   // WHOOP absolute skin temperature
    var totalKcalWhoop: Double?  // WHOOP gives one total for the cycle

    var totalKcal: Double? {
        if let t = totalKcalWhoop { return t }
        guard activeKcal != nil || basalKcal != nil else { return nil }
        return (activeKcal ?? 0) + (basalKcal ?? 0)
    }

    init(day: Date) { self.day = day }
}

enum SleepStage: String, CaseIterable, Identifiable {
    case awake, rem, core, deep
    var id: String { rawValue }
    var title: String {
        switch self { case .awake: "Awake"; case .rem: "REM"; case .core: "Light"; case .deep: "Deep" }
    }
    /// Hypnogram row: awake on top, deep at the bottom.
    var level: Int { switch self { case .awake: 3; case .rem: 2; case .core: 1; case .deep: 0 } }
}

/// One night's sleep from one source (attributed to the day you woke up).
struct SleepNight: Identifiable, Equatable {
    let night: Date
    let source: Source
    var id: String { "\(source.rawValue)-\(night.timeIntervalSince1970)" }
    var start: Date?
    var end: Date?
    var inBedMin: Double = 0
    var awakeMin: Double = 0
    var coreMin: Double = 0
    var deepMin: Double = 0
    var remMin: Double = 0
    var unspecifiedMin: Double = 0
    var performance: Double?   // WHOOP sleep performance %
    var respRate: Double?

    var asleepMin: Double { coreMin + deepMin + remMin + unspecifiedMin }
    /// Asleep ÷ time in bed (or asleep + awake when the tracker doesn't log "in bed").
    var efficiency: Double? {
        let bed = max(inBedMin, asleepMin + awakeMin)
        return bed > 0 ? asleepMin / bed * 100 : nil
    }
    func minutes(_ s: SleepStage) -> Double {
        switch s { case .awake: awakeMin; case .rem: remMin; case .core: coreMin + unspecifiedMin; case .deep: deepMin }
    }
}

struct HypnoSegment: Identifiable, Equatable {
    let start: Date
    let end: Date
    let stage: SleepStage
    var id: Date { start }
}

struct WorkoutRec: Identifiable, Equatable {
    let id: String
    let source: Source
    var name: String
    var symbol: String = "figure.mixed.cardio"
    var start: Date
    var end: Date
    var kcal: Double?
    var avgHR: Double?
    var maxHR: Double?
    var strain: Double?
    var distanceKm: Double?
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

extension Date {
    var dayStart: Date { Calendar.current.startOfDay(for: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
}

extension Array where Element == DayStat {
    func stat(on day: Date) -> DayStat? { first { Calendar.current.isDate($0.day, inSameDayAs: day) } }
    func recent(_ n: Int) -> [DayStat] {
        let cut = Date().dayStart.adding(days: -(n - 1))
        return filter { $0.day >= cut }.sorted { $0.day < $1.day }
    }
}

/// Unit preferences (data stays metric; only display converts).
enum Units {
    static var imperial: Bool { UserDefaults.standard.object(forKey: "unitsImperial") as? Bool ?? true }
    static var fahrenheit: Bool { UserDefaults.standard.object(forKey: "unitsF") as? Bool ?? true }

    static func weight(_ kg: Double?) -> (Double?, String) { imperial ? (kg.map { $0 * 2.20462 }, "lb") : (kg, "kg") }
    static func distance(_ km: Double?) -> (Double?, String) { imperial ? (km.map { $0 * 0.621371 }, "mi") : (km, "km") }
    /// Temperature *deviation* (a difference, so no +32).
    static func tempDelta(_ c: Double?) -> (Double?, String) { fahrenheit ? (c.map { $0 * 1.8 }, "°F") : (c, "°C") }
}

func fmtHM(_ minutes: Double?) -> String {
    guard let m = minutes, m > 0 else { return "––" }
    let h = Int(m) / 60, mm = Int(m) % 60
    return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
}
