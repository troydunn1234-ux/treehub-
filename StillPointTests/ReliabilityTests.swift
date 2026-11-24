import XCTest
@testable import StillPoint

/// Logic fixed in the fresh-eyes QA pass: the heat chart's range (it could be upside down and stop the app), the
/// week of minutes (now worked out in one pass), and the cached active days / "Works best for you" following the log.
@MainActor
final class ReliabilityTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func session(_ start: Date, minutes: Double, id: UUID = UUID(), practice: String = "box",
                         hrStart: Double? = nil, hrEnd: Double? = nil) -> SessionRecord {
        SessionRecord(id: id, practiceId: practice, title: "QA check", start: start, seconds: minutes * 60, cycles: 0,
                      hrStart: hrStart, hrEnd: hrEnd, device: "iPhone")
    }

    /// Takes test sessions out of storage again without marking them deleted (as DataSafetyTests does).
    private func unsave(_ ids: Set<UUID>) throws {
        guard let data = UserDefaults.standard.data(forKey: "sp.sessions") else { return }
        let rest = try JSONDecoder().decode([SessionRecord].self, from: data).filter { !ids.contains($0.id) }
        UserDefaults.standard.set(try JSONEncoder().encode(rest), forKey: "sp.sessions")
    }

    // MARK: Heat chart range

    /// Readings all under 32 bpm used to give a range whose bottom (40) sat above its top: Swift Charts stopped the app.
    func testHeatChartRangeIsNeverUpsideDown() {
        XCTAssertEqual(HeartWindow.chartDomain(min: 60, max: 140), 52...148)
        XCTAssertEqual(HeartWindow.chartDomain(min: 100, max: 100), 92...108)
        let low = HeartWindow.chartDomain(min: 25, max: 30)
        XCTAssertEqual(low.lowerBound, 40)
        XCTAssertLessThan(low.lowerBound, low.upperBound)
        let none = HeartWindow.chartDomain(min: .nan, max: .nan)
        XCTAssertLessThan(none.lowerBound, none.upperBound)
    }

    // MARK: Minutes per day

    /// The one-pass week gives the same minutes per day as asking the calendar about each day, edges included.
    func testMinutesPerDayMatchesTheCalendar() throws {
        let c = cal
        let now = try XCTUnwrap(c.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 15, minute: 10)))
        let today = c.startOfDay(for: now)
        func at(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            c.date(byAdding: .minute, value: hour * 60 + minute, to: c.date(byAdding: .day, value: -back, to: today)!)!
        }
        let records = [
            session(at(0, 0), minutes: 5),          // the first moment of today
            session(at(0, 14, 30), minutes: 10),
            session(at(1, 23, 59), minutes: 3),     // the last minute of yesterday
            session(at(6, 0), minutes: 7),          // the first day shown
            session(at(7, 23, 59), minutes: 20),    // the day before: left out
            session(at(-1, 0, 30), minutes: 9),     // tomorrow: left out
            session(at(3, 12), minutes: 4),
            session(at(3, 18), minutes: 6),
        ]
        let week = SessionLog.minutesPerDay(records, days: 7, now: now, calendar: c)
        XCTAssertEqual(week.map(\.day), (0..<7).reversed().map { c.date(byAdding: .day, value: -$0, to: today)! })
        let byCalendar = week.map { d in records.filter { c.isDate($0.start, inSameDayAs: d.day) }.reduce(0) { $0 + $1.minutes } }
        XCTAssertEqual(week.map(\.minutes), byCalendar)
        XCTAssertEqual(week.map(\.minutes), [7, 0, 0, 10, 0, 3, 15])
    }

    /// Across the autumn clock change (a 25-hour day) each session still lands on its own day.
    func testMinutesPerDayAcrossTheClockChange() throws {
        let c = cal
        let now = try XCTUnwrap(c.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10)))
        let late = try XCTUnwrap(c.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30)))
        let early = try XCTUnwrap(c.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 15)))
        let week = SessionLog.minutesPerDay([session(late, minutes: 4), session(early, minutes: 6)], days: 7, now: now, calendar: c)
        XCTAssertEqual(week.count, 7)
        let byDay = Dictionary(uniqueKeysWithValues: week.map { (c.component(.day, from: $0.day), $0.minutes) })
        XCTAssertEqual(byDay[1], 4)
        XCTAssertEqual(byDay[2], 6)
        XCTAssertEqual(week.reduce(0) { $0 + $1.minutes }, 10)
    }

    // MARK: Right now

    /// A sauna session from days ago doesn't make a clock pick look body-based; one just finished does pick.
    func testOldSaunaSessionLeavesATimeOfDayPick() throws {
        let now = try XCTUnwrap(Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()))
        var s = BodySnapshot()
        s.lastHeatKind = "sauna"
        s.lastHeatMinutes = 15
        s.lastHeatEnd = now.addingTimeInterval(-3 * 86_400)
        let old = SuggestionEngine.suggest(s, stress: nil, stressNote: nil, now: now, lastDone: nil, worksBest: [], isLocked: { _ in false })
        XCTAssertEqual(old.rule, "afternoon")
        XCTAssertTrue(old.timeOnly, "an old sauna session hid that the pick came from the time of day")
        s.lastHeatEnd = now.addingTimeInterval(-10 * 60)
        let fresh = SuggestionEngine.suggest(s, stress: nil, stressNote: nil, now: now, lastDone: nil, worksBest: [], isLocked: { _ in false })
        XCTAssertEqual(fresh.rule, "heat")
        XCTAssertFalse(fresh.timeOnly)
    }

    // MARK: Cached answers follow the log

    /// Active days and "Works best for you" are kept between reads; sessions added after a read still count at once.
    func testCachedAnswersFollowTheLog() throws {
        let log = SessionLog.shared
        let c = Calendar.current
        // Far in the past, so the streak, today and this week are untouched.
        var day = c.date(byAdding: .day, value: -400, to: c.startOfDay(for: Date()))!.addingTimeInterval(9 * 3600)
        while log.activeDays.contains(c.startOfDay(for: day)) { day = day.addingTimeInterval(-86_400) }
        let practice = "qa-calm-\(UUID().uuidString.prefix(8))"
        XCTAssertFalse(log.worksBest(limit: 100).contains(practice))

        var ids: Set<UUID> = []
        defer { try? unsave(ids) }
        for n in 0..<3 {
            let r = session(day.addingTimeInterval(Double(n) * 600), minutes: 5, practice: practice, hrStart: 80, hrEnd: 62)
            ids.insert(r.id)
            log.add(r)
        }
        XCTAssertTrue(log.activeDays.contains(c.startOfDay(for: day)), "a kept answer missed a new session")
        XCTAssertEqual(log.activeDays, SessionLog.activeDays(records: log.records, heat: log.heatEntries,
                                                             trees: log.treeEntries, calendar: c))
        XCTAssertTrue(log.worksBest(limit: 100).contains(practice), "a kept answer missed three calm sessions")
    }
}
