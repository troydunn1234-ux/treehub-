import Foundation
import Combine

struct DayMinutes: Identifiable {
    var day: Date
    var minutes: Double
    var id: Date { day }
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

    var minutes: Double { seconds / 60 }
    var end: Date { start.addingTimeInterval(seconds) }
    var hrDrop: Double? {
        guard let a = hrStart, let b = hrEnd else { return nil }
        return a - b
    }
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
        guard !records.contains(where: { $0.id == r.id }) else { return }
        records.insert(r, at: 0)
        records.sort { $0.start > $1.start }
        if records.count > 500 { records = Array(records.prefix(500)) }
        if let d = try? JSONEncoder().encode(records) { UserDefaults.standard.set(d, forKey: key) }
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

    private static func demo() -> [SessionRecord] {
        let lib = PracticeLibrary.shared.practices
        guard !lib.isEmpty else { return [] }
        var out: [SessionRecord] = []
        let cal = Calendar.current
        for back in 0..<12 where back != 5 {
            guard let day = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let p = lib[back % lib.count]
            let mins = [5.0, 10, 7, 12, 5, 15][back % 6]
            out.append(SessionRecord(practiceId: p.id, title: p.title,
                                     start: day.addingTimeInterval(-Double(back % 3) * 3600),
                                     seconds: mins * 60, cycles: Int(mins * 6),
                                     hrStart: 72 - Double(back % 4), hrEnd: 63 - Double(back % 3),
                                     hrv: 48 + Double(back % 5) * 3, device: back % 2 == 0 ? "Watch" : "iPhone"))
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
