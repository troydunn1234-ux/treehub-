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
    /// Set when Rootbound started the session for a tree: that tree's stable id (UUID string) and name.
    var treeID: String? = nil
    var treeName: String? = nil
    /// Seconds spent below the starting heart rate (the "calm zone"). Filled once heart data is in.
    var calmSeconds: Double? = nil
    /// Last time Apple Health was asked for this session's heart data (so the screen can say "waiting…").
    var healthCheckedAt: Date? = nil

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
        case treeID, treeName, calmSeconds, healthCheckedAt
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
        treeID = try? c.decode(String.self, forKey: .treeID)
        treeName = try? c.decode(String.self, forKey: .treeName)
        calmSeconds = try? c.decode(Double.self, forKey: .calmSeconds)
        healthCheckedAt = try? c.decode(Date.self, forKey: .healthCheckedAt)
    }

    // MARK: Derived health stats (none of these are medical measures)

    /// Lowest heart rate: the kept low, or the lowest sample.
    var hrLow: Double? { hrMin ?? hrSamples?.map(\.bpm).min() }

    /// Start → end (positive = lower at the end).
    var hrEndDrop: Double? {
        guard let a = hrStart, let b = hrEnd ?? hrSamples?.last?.bpm else { return nil }
        return a - b
    }

    /// Time spent below the starting heart rate, from the stored value or the curve.
    var calmZoneSeconds: Double? {
        if let c = calmSeconds { return c }
        return Self.calmSeconds(samples: hrSamples, start: hrStart, total: seconds)
    }

    /// Share of the session in the calm zone, 0…1.
    var calmZoneFraction: Double? {
        guard let c = calmZoneSeconds, seconds > 0 else { return nil }
        return min(1, max(0, c / seconds))
    }

    static func calmSeconds(samples: [HRSample]?, start: Double?, total: Double) -> Double? {
        guard let s = samples, s.count >= 2 else { return nil }
        let base = start ?? s[0].bpm
        var calm = 0.0
        for (a, b) in zip(s, s.dropFirst()) where a.bpm < base {
            calm += max(0, min(b.t, total) - a.t)
        }
        if let last = s.last, last.bpm < base { calm += max(0, total - last.t) }
        return min(total, calm)
    }

    /// One friendly line about how the body responded.
    var takeaway: String? {
        guard let d = hrDrop else { return nil }
        let n = Int(abs(d).rounded())
        let zone = calmZoneFraction.map { Int(($0 * 100).rounded()) }
        if d >= 10 {
            return String(localized: "Your heart rate dropped \(n) bpm. Nicely settled.")
        } else if d >= 5 {
            if let z = zone, z >= 50 { return String(localized: "Your heart rate dropped \(n) bpm and stayed below your starting rate for most of the session.") }
            return String(localized: "Your heart rate dropped \(n) bpm. A good, steady settle.")
        } else if d >= 1 {
            return String(localized: "Your heart rate eased \(n) bpm. Gentle progress; longer sessions often settle more.")
        } else if d <= -3 && isMovement {
            return String(localized: "Your heart rate rose \(n) bpm, as expected when you move.")
        } else if d <= -3 {
            return String(localized: "Your heart rate rose \(n) bpm. Energizing breaths and talking can do that; try a longer exhale next time.")
        }
        return String(localized: "Your heart rate held steady.")
    }
}

/// One practice's history, for its detail page.
struct PracticeStats {
    let sessions: [SessionRecord]   // newest first
    var count: Int { sessions.count }
    var totalMinutes: Double { sessions.reduce(0) { $0 + $1.minutes } }
    var lastDone: Date? { sessions.map(\.start).max() }
    var withHeart: [SessionRecord] { sessions.filter { $0.hrDrop != nil } }
    var avgDrop: Double? {
        let d = withHeart.compactMap(\.hrDrop)
        return d.isEmpty ? nil : d.reduce(0, +) / Double(d.count)
    }
    /// The session where the heart settled most.
    var best: SessionRecord? { withHeart.max { ($0.hrDrop ?? 0) < ($1.hrDrop ?? 0) } }
    /// Oldest → newest drops, for the trend chart.
    var dropTrend: [(date: Date, drop: Double)] {
        withHeart.sorted { $0.start < $1.start }.suffix(20).compactMap { r in r.hrDrop.map { (r.start, $0) } }
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
        if let d = UserDefaults.standard.data(forKey: heatKey),
           let h = try? JSONDecoder().decode([HeatEntry].self, from: d) {
            heatEntries = h
        }
        if let d = UserDefaults.standard.data(forKey: treeKey),
           let t = try? JSONDecoder().decode([TreeEntry].self, from: d) {
            treeEntries = t
        }
        if ProcessInfo.processInfo.arguments.contains("-demo") && records.isEmpty {
            records = Self.demo()
            if heatEntries.isEmpty { heatEntries = Self.demoHeat() }
        }
    }

    // MARK: - Sauna / steam days (for the streak and Progress)

    /// Finished heat sessions (≥ 1 min). The iPhone mirrors its heat log here; the Watch adds the ones it times.
    @Published private(set) var heatEntries: [HeatEntry] = []
    private let heatKey = "sp.heatEntries"

    /// Replace with the iPhone's heat log (HeatStore is the source of truth there).
    func replaceHeat(_ items: [HeatEntry]) {
        let kept = items.filter { $0.minutes >= 1 }.sorted { $0.start > $1.start }
        guard kept != heatEntries else { return }
        heatEntries = Array(kept.prefix(500))
        persistHeat()
    }

    /// Add one finished heat session (Watch).
    func addHeat(_ e: HeatEntry) {
        guard e.minutes >= 1, !heatEntries.contains(where: { abs($0.start.timeIntervalSince(e.start)) < 5 }) else { return }
        heatEntries.insert(e, at: 0)
        if heatEntries.count > 500 { heatEntries = Array(heatEntries.prefix(500)) }
        persistHeat()
    }

    private func persistHeat() {
        if let d = try? JSONEncoder().encode(heatEntries) { UserDefaults.standard.set(d, forKey: heatKey) }
        WidgetBridge.publish()
        onActivityChange?()
    }

    // MARK: - Tree hugs from Rootbound (iPhone only, via the shared wellness feed)

    /// Tree hugs of a minute or more logged in Rootbound: they count as mindful moments here (Progress "Trees"
    /// and the streak). Never written to Apple Health from Still Pointz; Rootbound owns that data.
    @Published private(set) var treeEntries: [TreeEntry] = []
    private let treeKey = "sp.treeEntries"

    /// Merge what Rootbound published (kept by id, so older hugs stay counted after the feed trims them).
    /// `window` = the period the feed covers: hugs in it that are no longer in the feed were deleted in Rootbound.
    func mergeTrees(_ items: [TreeEntry], window since: Date) {
        let incoming = items.filter { $0.minutes >= 1 }
        let ids = Set(incoming.map(\.id))
        var merged = treeEntries.filter { $0.start < since || ids.contains($0.id) }
        for t in incoming {
            if let i = merged.firstIndex(where: { $0.id == t.id }) { merged[i] = t } else { merged.append(t) }
        }
        merged.sort { $0.start > $1.start }
        merged = Array(merged.prefix(500))
        guard merged != treeEntries else { return }
        treeEntries = merged
        if let d = try? JSONEncoder().encode(merged) { UserDefaults.standard.set(d, forKey: treeKey) }
        WidgetBridge.publish()
        onActivityChange?()
    }

    /// Called after sessions or heat change (the iPhone uses it to send its streak to the Watch).
    var onActivityChange: (() -> Void)?

    // MARK: - Streak from the other device

    /// The Watch only sees its own sessions; the iPhone sends its streak so the wrist shows the real one.
    private let remoteKey = "sp.remoteStreak"
    private struct RemoteStreak: Codable { var count: Int; var best: Int; var lastDay: Date }
    private lazy var remote: RemoteStreak? = {
        guard let d = UserDefaults.standard.data(forKey: remoteKey) else { return nil }
        return try? JSONDecoder().decode(RemoteStreak.self, from: d)
    }()

    func applyRemoteStreak(count: Int, best: Int, lastDay: Date) {
        let r = RemoteStreak(count: count, best: best, lastDay: lastDay)
        remote = r
        if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: remoteKey) }
        objectWillChange.send()
        WidgetBridge.publish()
    }

    /// The other device's streak, if it is still alive today.
    private var remoteCurrent: Int {
        guard let r = remote, r.count > 0 else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let last = cal.startOfDay(for: r.lastDay)
        guard let gap = cal.dateComponents([.day], from: last, to: today).day, gap <= 1, gap >= 0 else { return 0 }
        return r.count
    }

    /// Last day with any activity on this device (sent to the Watch with the streak).
    var lastActiveDay: Date? { activeDays.max() }

    /// Sessions the person discarded; ignored if the other device sends them again.
    private let deletedKey = "sp.sessions.deleted"
    private lazy var deleted: Set<String> = Set(UserDefaults.standard.stringArray(forKey: deletedKey) ?? [])

    /// Throw a session away (and its Mindful Minutes in Apple Health, if this device saved them).
    func remove(_ id: UUID) {
        guard let r = record(id) else { return }
        records.removeAll { $0.id == id }
        deleted.insert(id.uuidString)
        UserDefaults.standard.set(Array(deleted.suffix(300)), forKey: deletedKey)
        MindfulHealth.shared.deleteMindful(start: r.start, end: r.end)
        persist()
    }

    func add(_ r: SessionRecord) {
        guard !deleted.contains(r.id.uuidString) else { return }
        if let i = records.firstIndex(where: { $0.id == r.id }) {
            // Same session arriving again (e.g. the Watch re-sent it with HRV filled in): keep the fuller one.
            var merged = r
            if merged.notes == nil { merged.notes = records[i].notes }
            if merged.hrv == nil { merged.hrv = records[i].hrv }
            if merged.respiratoryRate == nil { merged.respiratoryRate = records[i].respiratoryRate }
            if merged.calmSeconds == nil { merged.calmSeconds = records[i].calmSeconds }
            if merged.healthCheckedAt == nil { merged.healthCheckedAt = records[i].healthCheckedAt }
            if merged.hrSamples == nil { merged.hrSamples = records[i].hrSamples }
            if merged.treeID == nil { merged.treeID = records[i].treeID; merged.treeName = records[i].treeName }
            if merged.hrAvg == nil { merged.hrAvg = records[i].hrAvg; merged.hrMin = merged.hrMin ?? records[i].hrMin }
            if merged.hrStart == nil { merged.hrStart = records[i].hrStart; merged.hrEnd = merged.hrEnd ?? records[i].hrEnd }
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
        guard r != records[i] else { return }
        records[i] = r
        persist(wait: false)
    }

    func record(_ id: UUID) -> SessionRecord? { records.first { $0.id == id } }

    /// Writes go through one serial queue, so an older snapshot can never land after a newer one.
    private static let saveQueue = DispatchQueue(label: "sp.sessions.save", qos: .userInitiated)

    /// `wait`: a new or removed session is on disk before this returns. Heart-data patches (update) are
    /// encoded off the main thread: with hundreds of sessions and their heart curves the whole log is a few MB of
    /// JSON, and encoding it on every late Health answer made the results screen stutter.
    private func persist(wait: Bool = true) {
        let snapshot = records
        let key = self.key
        let write = {
            if let d = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(d, forKey: key) }
        }
        if wait { Self.saveQueue.sync(execute: write) } else { Self.saveQueue.async(execute: write) }
        WidgetBridge.publish()
        onActivityChange?()
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
        if activeDays.contains(Calendar.current.startOfDay(for: Date())) { return true }
        guard let r = remote else { return false }
        return Calendar.current.isDateInToday(r.lastDay)
    }

    /// Days (start of day) with at least one finished session of a minute or more, sauna, steam and Rootbound tree hugs included.
    var activeDays: Set<Date> {
        let cal = Calendar.current
        var days = Set(records.filter { $0.seconds >= 60 }.map { cal.startOfDay(for: $0.start) })
        for h in heatEntries where h.minutes >= 1 { days.insert(cal.startOfDay(for: h.start)) }
        for t in treeEntries where t.minutes >= 1 { days.insert(cal.startOfDay(for: t.start)) }
        return days
    }

    /// Longest run of consecutive days ever.
    var bestStreak: Int {
        let cal = Calendar.current
        let days = activeDays.sorted()
        var best = remote?.best ?? 0
        var run = 0
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
    var streak: Int { max(localStreak, remoteCurrent) }

    /// The streak from this device's own sessions and heat log.
    var localStreak: Int {
        let cal = Calendar.current
        let days = activeDays
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
    /// Everything about one practice across all sessions: for the practice page.
    func stats(for practiceId: String) -> PracticeStats {
        let mine = records.filter { $0.practiceId == practiceId }
        return PracticeStats(sessions: mine)
    }

    /// Average heart-rate drop per practice, for practices done at least `minSessions` times with heart data.
    func dropByPractice(minSessions: Int = 3) -> [String: Double] {
        var sums: [String: (Double, Int)] = [:]
        for r in records { if let d = r.hrDrop { let c = sums[r.practiceId] ?? (0, 0); sums[r.practiceId] = (c.0 + d, c.1 + 1) } }
        var out: [String: Double] = [:]
        for (k, v) in sums where v.1 >= minSessions { out[k] = v.0 / Double(v.1) }
        return out
    }

    /// The practices that settle this person's heart the most (3+ sessions, average drop of at least 2 bpm), best first.
    func worksBest(limit: Int = 3) -> [String] {
        Array(dropByPractice().filter { $0.value >= 2 }.sorted { $0.value > $1.value }.prefix(limit).map(\.key))
    }

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

    private static func demoHeat() -> [HeatEntry] {
        let cal = Calendar.current
        return [1, 4, 8, 15, 22].compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: Date()) else { return nil }
            return HeatEntry(start: d.addingTimeInterval(-7200), minutes: back % 2 == 0 ? 15 : 18, kind: back % 3 == 0 ? .steam : .sauna)
        }
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
