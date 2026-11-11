import Foundation
import Combine

struct DayMinutes: Identifiable {
    var day: Date
    var minutes: Double
    var id: Date { day }
}

/// One heart-rate reading during a session: seconds since the session started, and bpm.
struct HRSample: Codable, Hashable {
    var t: Double
    var bpm: Double
}

struct SessionRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var practiceId: String
    var title: String
    var start: Date
    var seconds: Double
    var cycles: Int
    var hrStart: Double? = nil
    var hrEnd: Double? = nil
    var hrv: Double? = nil
    var device: String

    // Added later; all optional so records saved by earlier versions still decode.
    var kind: String? = nil
    var minutesPlanned: Int? = nil
    var warmUpId: String? = nil
    var hrSamples: [HRSample]? = nil
    var hrMin: Double? = nil
    var hrAvg: Double? = nil
    var respiratoryRate: Double? = nil
    var notes: String? = nil

    var minutes: Double { seconds / 60 }
    var end: Date { start.addingTimeInterval(seconds) }
    var hasHeartRate: Bool { hrStart != nil && (hrEnd != nil || hrMin != nil) }

    /// Start → lowest (or end if no lowest was kept).
    var hrDrop: Double? {
        guard let a = hrStart, let b = hrMin ?? hrEnd else { return nil }
        return a - b
    }

    /// Breaths per minute, when breaths were counted.
    var breathsPerMinute: Double? {
        guard cycles > 0, seconds >= 30 else { return nil }
        return Double(cycles) / (seconds / 60)
    }

    /// A simple estimate of how much the body settled: how far the heart rate fell from the start, 0–100.
    /// Not a medical measure; a 10% drop reads as 100.
    var calmScore: Int? {
        guard let a = hrStart, a > 0, let b = hrMin ?? hrEnd else { return nil }
        let frac = (a - b) / a
        return Int((min(max(frac / 0.10, 0), 1) * 100).rounded())
    }

    var isMovement: Bool { (kind ?? "").lowercased() == "movement" }

    init(id: UUID = UUID(), practiceId: String, title: String, start: Date, seconds: Double, cycles: Int,
         hrStart: Double? = nil, hrEnd: Double? = nil, hrv: Double? = nil, device: String,
         kind: String? = nil, minutesPlanned: Int? = nil, warmUpId: String? = nil,
         hrSamples: [HRSample]? = nil, hrMin: Double? = nil, hrAvg: Double? = nil,
         respiratoryRate: Double? = nil, notes: String? = nil) {
        self.id = id; self.practiceId = practiceId; self.title = title; self.start = start
        self.seconds = seconds; self.cycles = cycles; self.hrStart = hrStart; self.hrEnd = hrEnd
        self.hrv = hrv; self.device = device; self.kind = kind; self.minutesPlanned = minutesPlanned
        self.warmUpId = warmUpId; self.hrSamples = hrSamples; self.hrMin = hrMin; self.hrAvg = hrAvg
        self.respiratoryRate = respiratoryRate; self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, practiceId, title, start, seconds, cycles, hrStart, hrEnd, hrv, device
        case kind, minutesPlanned, warmUpId, hrSamples, hrMin, hrAvg, respiratoryRate, notes
    }

    // Tolerant decoding: anything missing in an old record is simply nil.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        practiceId = (try? c.decode(String.self, forKey: .practiceId)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? "Practice"
        start = try c.decode(Date.self, forKey: .start)
        seconds = (try? c.decode(Double.self, forKey: .seconds)) ?? 0
        cycles = (try? c.decode(Int.self, forKey: .cycles)) ?? 0
        hrStart = try? c.decode(Double.self, forKey: .hrStart)
        hrEnd = try? c.decode(Double.self, forKey: .hrEnd)
        hrv = try? c.decode(Double.self, forKey: .hrv)
        device = (try? c.decode(String.self, forKey: .device)) ?? "iPhone"
        kind = try? c.decode(String.self, forKey: .kind)
        minutesPlanned = try? c.decode(Int.self, forKey: .minutesPlanned)
        warmUpId = try? c.decode(String.self, forKey: .warmUpId)
        hrSamples = try? c.decode([HRSample].self, forKey: .hrSamples)
        hrMin = try? c.decode(Double.self, forKey: .hrMin)
        hrAvg = try? c.decode(Double.self, forKey: .hrAvg)
        respiratoryRate = try? c.decode(Double.self, forKey: .respiratoryRate)
        notes = try? c.decode(String.self, forKey: .notes)
    }
}

/// A per-practice summary for the weekly card.
struct PracticeDrop: Identifiable {
    var practiceId: String
    var title: String
    var avgDrop: Double
    var count: Int
    var id: String { practiceId }
}

/// Local history of sessions from this device (and, on iPhone, the ones the Watch sends over).
final class SessionLog: ObservableObject {
    static let shared = SessionLog()
    @Published private(set) var records: [SessionRecord] = []
    private let key = "sp.sessions"

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode([SessionRecord].self, from: d) {
            records = r
        }
        if ProcessInfo.processInfo.arguments.contains("-demo") && records.isEmpty { records = Self.demo() }
    }

    func add(_ r: SessionRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) {
            // Same session arriving again (e.g. the Watch re-sent it with HRV filled in): keep the fuller one.
            var merged = r
            if merged.notes == nil { merged.notes = records[i].notes }
            if merged.hrv == nil { merged.hrv = records[i].hrv }
            if merged.hrSamples == nil { merged.hrSamples = records[i].hrSamples }
            records[i] = merged
        } else {
            records.insert(r, at: 0)
        }
        records.sort { $0.start > $1.start }
        if records.count > 500 { records = Array(records.prefix(500)) }
        persist()
    }

    /// Patch fields on an existing record (used for late-arriving HRV, notes).
    func update(_ id: UUID, _ change: (inout SessionRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        var r = records[i]
        change(&r)
        records[i] = r
        persist()
    }

    func record(_ id: UUID) -> SessionRecord? { records.first { $0.id == id } }

    private func persist() {
        if let d = try? JSONEncoder().encode(records) { UserDefaults.standard.set(d, forKey: key) }
        WidgetBridge.publish()
    }

    // MARK: - Streak & weekly goal

    static let defaultWeeklyGoal: Double = 30
    private static let goalKey = "sp.weekGoal"

    /// Minutes of practice the person aims for each calendar week. Default 30; editable in Settings.
    @Published var weeklyGoal: Double = {
        let v = UserDefaults.standard.double(forKey: SessionLog.goalKey)
        return v > 0 ? v : SessionLog.defaultWeeklyGoal
    }() {
        didSet {
            guard weeklyGoal != oldValue else { return }
            UserDefaults.standard.set(weeklyGoal, forKey: Self.goalKey)
            WidgetBridge.publish()
            onGoalChange?()
        }
    }

    /// Called after the goal changes locally (used to sync it to the other device).
    var onGoalChange: (() -> Void)?

    /// Apply a goal received from the other device without echoing it back.
    func applyRemoteGoal(_ minutes: Double) {
        guard minutes > 0, minutes != weeklyGoal else { return }
        let saved = onGoalChange
        onGoalChange = nil
        weeklyGoal = minutes
        onGoalChange = saved
    }

    /// Start of the current calendar week (follows the locale's first weekday).
    var weekStartDate: Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
    }

    /// Minutes since the start of this calendar week: what counts toward the weekly goal.
    var calendarWeekMinutes: Double {
        let start = weekStartDate
        return records.filter { $0.start >= start }.reduce(0.0) { $0 + $1.minutes }
    }

    /// 0…1 progress toward the weekly goal.
    var weekProgress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1, calendarWeekMinutes / weeklyGoal)
    }

    var goalReached: Bool { weeklyGoal > 0 && calendarWeekMinutes >= weeklyGoal }

    /// Minutes still to go this week (0 once the goal is met).
    var minutesToGoal: Double { max(0, weeklyGoal - calendarWeekMinutes) }

    /// At least one session today, so the streak is safe for another day.
    var practicedToday: Bool {
        let cal = Calendar.current
        return records.contains { cal.isDateInToday($0.start) }
    }

    /// Longest run of consecutive days ever.
    var bestStreak: Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.start) }).sorted()
        var best = 0, run = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev, let next = cal.date(byAdding: .day, value: 1, to: p), cal.isDate(next, inSameDayAs: d) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            prev = d
        }
        return max(best, streak)
    }

    /// A short, warm line for the streak card.
    var streakLine: String {
        switch streak {
        case 0: return practicedToday ? "A fresh start." : "Begin a streak today."
        case 1: return practicedToday ? "One day. Come back tomorrow." : "Practice today to keep it going."
        default: return practicedToday ? "\(streak) days in a row." : "\(streak) days. Keep it alive today."
        }
    }

    /// Consecutive days (ending today or yesterday) with at least one session.
    var streak: Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.start) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while days.contains(day) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    var totalMinutes: Double { records.reduce(0) { $0 + $1.minutes } }

    /// Minutes per day for the last 7 days, oldest first.
    func lastWeek() -> [DayMinutes] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { back -> DayMinutes? in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let m = records.filter { cal.isDate($0.start, inSameDayAs: d) }.reduce(0.0) { $0 + $1.minutes }
            return DayMinutes(day: d, minutes: m)
        }
    }

    var weekMinutes: Double { lastWeek().reduce(0) { $0 + $1.minutes } }

    /// Minutes in the 7 days before the last 7 (for "vs last week").
    var previousWeekMinutes: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let thisStart = cal.date(byAdding: .day, value: -6, to: today),
              let prevStart = cal.date(byAdding: .day, value: -13, to: today) else { return 0 }
        return records.filter { $0.start >= prevStart && $0.start < thisStart }.reduce(0.0) { $0 + $1.minutes }
    }

    func sessions(on day: Date) -> [SessionRecord] {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.start, inSameDayAs: day) }
    }

    /// Practices with the biggest average heart-rate drop over the last 30 days, best first.
    func bestPractices(limit: Int = 3) -> [PracticeDrop] {
        let since = Date().addingTimeInterval(-30 * 86400)
        var sums: [String: (title: String, total: Double, n: Int)] = [:]
        for r in records where r.start >= since {
            guard let d = r.hrDrop else { continue }
            let cur = sums[r.practiceId] ?? (r.title, 0, 0)
            sums[r.practiceId] = (cur.title, cur.total + d, cur.n + 1)
        }
        let out = sums.map { PracticeDrop(practiceId: $0.key, title: $0.value.title,
                                          avgDrop: $0.value.total / Double(max(1, $0.value.n)), count: $0.value.n) }
        return Array(out.sorted { $0.avgDrop > $1.avgDrop }.prefix(limit))
    }

    private static func demo() -> [SessionRecord] {
        let lib = PracticeLibrary.shared.practices
        guard !lib.isEmpty else { return [] }
        var out: [SessionRecord] = []
        let cal = Calendar.current
        for back in 0..<12 where back != 5 {
            guard let day = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let p = lib[back % lib.count]
            let mins = [5.0, 10, 7, 12, 5, 15][back % 6]
            let hrStart = 72 - Double(back % 4)
            let hrEnd = 63 - Double(back % 3)
            let hasHR = back % 2 == 0
            out.append(SessionRecord(practiceId: p.id, title: p.title,
                                     start: day.addingTimeInterval(-Double(back % 3) * 3600),
                                     seconds: mins * 60, cycles: Int(mins * 6),
                                     hrStart: hasHR ? hrStart : nil, hrEnd: hasHR ? hrEnd : nil,
                                     hrv: hasHR ? 48 + Double(back % 5) * 3 : nil,
                                     device: hasHR ? "Watch" : "iPhone",
                                     kind: p.isMovement ? "movement" : "breath",
                                     minutesPlanned: Int(mins),
                                     hrSamples: hasHR ? demoCurve(seconds: mins * 60, from: hrStart, to: hrEnd, seed: back) : nil,
                                     hrMin: hasHR ? hrEnd - 1 : nil,
                                     hrAvg: hasHR ? (hrStart + hrEnd) / 2 - 1 : nil,
                                     respiratoryRate: hasHR ? 6 + Double(back % 3) : nil))
        }
        return out
    }

    /// A gentle, slightly wobbly descent for demo screenshots.
    private static func demoCurve(seconds: Double, from a: Double, to b: Double, seed: Int) -> [HRSample] {
        var out: [HRSample] = []
        var t = 0.0
        while t <= seconds {
            let p = t / max(1, seconds)
            let eased = 1 - pow(1 - p, 2)
            let wobble = sin(t / 9 + Double(seed)) * 1.4 + cos(t / 23) * 0.8
            out.append(HRSample(t: t, bpm: a + (b - a) * eased + wobble))
            t += 5
        }
        return out
    }

    func toDictionary(_ r: SessionRecord) -> [String: Any] {
        guard let d = try? JSONEncoder().encode(r) else { return [:] }
        return [SyncKey.session: d]
    }

    static func record(from dict: [String: Any]) -> SessionRecord? {
        guard let d = dict[SyncKey.session] as? Data else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: d)
    }
}
