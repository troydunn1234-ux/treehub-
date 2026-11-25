import XCTest
@testable import PulseLab

/// Honest numbers: synthetic Health samples that used to inflate or distort what Pulse Lab showed.
final class AccuracyTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    /// A local time in Los Angeles.
    private func t(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    private func day(_ y: Int, _ mo: Int, _ d: Int) -> Date { cal.startOfDay(for: t(y, mo, d, 12)) }

    private typealias S = SleepMath.Sample

    private func nights(_ s: [S]) -> [SleepMath.Night] { SleepMath.nights(s, source: .watch, calendar: cal) }

    // MARK: Sleep

    /// The 12.8 h report: one Watch night written as stages, again as one long "asleep" (another writer or an
    /// older layer), and again by a second Watch, plus "in bed". Summing them gave ~2× the night.
    func testOverlappingWritersCountEachMinuteOnce() throws {
        let staged: [S] = [
            S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 1, 0), stage: .core),
            S(start: t(2026, 11, 24, 1, 0), end: t(2026, 11, 24, 2, 0), stage: .deep),
            S(start: t(2026, 11, 24, 2, 0), end: t(2026, 11, 24, 3, 0), stage: .rem),
            S(start: t(2026, 11, 24, 3, 0), end: t(2026, 11, 24, 6, 24), stage: .core),
        ]
        let unspecified = [S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 6, 24), stage: .unspecified)]
        let secondWatch = staged.map { S(start: $0.start.addingTimeInterval(120), end: $0.end.addingTimeInterval(-120), stage: $0.stage) }
        let inBed = [S(start: t(2026, 11, 23, 22, 40), end: t(2026, 11, 24, 6, 40), stage: .inBed)]

        let all = nights(staged + unspecified + secondWatch + inBed)
        XCTAssertEqual(all.count, 1)
        let n = try XCTUnwrap(all.first).night
        XCTAssertEqual(n.asleepMin, 7 * 60 + 24, accuracy: 0.01, "asleep is the union, not the sum")
        XCTAssertEqual(n.deepMin, 60, accuracy: 0.01)
        XCTAssertEqual(n.remMin, 60, accuracy: 0.01)
        XCTAssertEqual(n.coreMin + n.unspecifiedMin, 5 * 60 + 24, accuracy: 0.01, "stages add up to the night")
        XCTAssertEqual(n.inBedMin, 8 * 60, accuracy: 0.01)
        XCTAssertEqual(n.night, day(2026, 11, 24))
        XCTAssertEqual(n.start, t(2026, 11, 23, 23, 0))
        XCTAssertEqual(n.end, t(2026, 11, 24, 6, 24))
    }

    func testInBedAndAwakeAreNotSleep() throws {
        let s: [S] = [
            S(start: t(2026, 11, 23, 22, 0), end: t(2026, 11, 24, 7, 30), stage: .inBed),
            S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 3, 0), stage: .core),
            S(start: t(2026, 11, 24, 3, 0), end: t(2026, 11, 24, 3, 30), stage: .awake),
            S(start: t(2026, 11, 24, 3, 30), end: t(2026, 11, 24, 7, 0), stage: .core),
        ]
        let n = try XCTUnwrap(nights(s).first).night
        XCTAssertEqual(n.asleepMin, 7.5 * 60, accuracy: 0.01)
        XCTAssertEqual(n.awakeMin, 30, accuracy: 0.01)
        XCTAssertEqual(n.inBedMin, 9.5 * 60, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(n.efficiency), 7.5 / 9.5 * 100, accuracy: 0.01)
    }

    func testAsleepWinsOverAwakeWhereWritersDisagree() throws {
        let s: [S] = [
            S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 7, 0), stage: .core),
            S(start: t(2026, 11, 24, 2, 0), end: t(2026, 11, 24, 2, 30), stage: .awake),
        ]
        let n = try XCTUnwrap(nights(s).first).night
        XCTAssertEqual(n.asleepMin, 8 * 60, accuracy: 0.01)
        XCTAssertEqual(n.awakeMin, 0, accuracy: 0.01)
    }

    /// A nap the same day and the next night are separate sessions: neither is added to last night.
    func testNapAndNextNightStaySeparate() throws {
        let s: [S] = [
            S(start: t(2026, 11, 22, 23, 30), end: t(2026, 11, 23, 6, 30), stage: .core),  // night 1: 7 h
            S(start: t(2026, 11, 23, 14, 0), end: t(2026, 11, 23, 15, 0), stage: .core),   // nap: 1 h
            S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 6, 0), stage: .core),    // night 2: 7 h
        ]
        let all = nights(s)
        XCTAssertEqual(all.map(\.night.night), [day(2026, 11, 23), day(2026, 11, 24)])
        XCTAssertEqual(all[0].night.asleepMin, 7 * 60, accuracy: 0.01, "the nap isn't part of the night")
        XCTAssertEqual(all[0].otherSessionsMin, 60, accuracy: 0.01)
        XCTAssertEqual(all[1].night.asleepMin, 7 * 60, accuracy: 0.01)
        XCTAssertEqual(all[1].otherSessionsMin, 0, accuracy: 0.01)
    }

    /// Waking for an hour in the night is still one night.
    func testBrokenNightIsOneSession() throws {
        let s: [S] = [
            S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 2, 0), stage: .core),
            S(start: t(2026, 11, 24, 3, 0), end: t(2026, 11, 24, 7, 0), stage: .core),
        ]
        let all = nights(s)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].night.asleepMin, 7 * 60, accuracy: 0.01)
        XCTAssertEqual(all[0].otherSessionsMin, 0)
    }

    /// Nov 1 2026: clocks go back at 2 am in Los Angeles. 11 pm → 7 am is 9 real hours, credited to Nov 1.
    func testDaylightSavingNightUsesRealElapsedTime() throws {
        let s = [S(start: t(2026, 10, 31, 23, 0), end: t(2026, 11, 1, 7, 0), stage: .core)]
        let n = try XCTUnwrap(nights(s).first).night
        XCTAssertEqual(n.asleepMin, 9 * 60, accuracy: 0.01)
        XCTAssertEqual(n.night, day(2026, 11, 1))
        // Spring forward (Mar 8 2026): 11 pm → 7 am is 7 real hours.
        let spring = try XCTUnwrap(nights([S(start: t(2026, 3, 7, 23, 0), end: t(2026, 3, 8, 7, 0), stage: .core)]).first).night
        XCTAssertEqual(spring.asleepMin, 7 * 60, accuracy: 0.01)
    }

    func testNightKeyCreditsTheMorningYouWokeUp() {
        XCTAssertEqual(SleepMath.nightKey(t(2026, 11, 24, 7), calendar: cal), day(2026, 11, 24))
        XCTAssertEqual(SleepMath.nightKey(t(2026, 11, 24, 17, 59), calendar: cal), day(2026, 11, 24))
        XCTAssertEqual(SleepMath.nightKey(t(2026, 11, 24, 18), calendar: cal), day(2026, 11, 25))
    }

    func testHypnogramHasNoOverlaps() throws {
        let s: [S] = [
            S(start: t(2026, 11, 23, 23, 0), end: t(2026, 11, 24, 7, 0), stage: .unspecified),
            S(start: t(2026, 11, 24, 1, 0), end: t(2026, 11, 24, 2, 0), stage: .deep),
            S(start: t(2026, 11, 24, 1, 30), end: t(2026, 11, 24, 2, 30), stage: .rem),
        ]
        let segs = try XCTUnwrap(nights(s).first).segments
        for (a, b) in zip(segs, segs.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start) }
        let total = segs.map { $0.end.timeIntervalSince($0.start) }.reduce(0, +) / 60
        XCTAssertEqual(total, 8 * 60, accuracy: 0.01)
        XCTAssertEqual(segs.map(\.stage), [.core, .deep, .rem, .core])
    }

    func testNoSleepMeansNoNight() {
        XCTAssertTrue(nights([S(start: t(2026, 11, 23, 22), end: t(2026, 11, 24, 7), stage: .inBed)]).isEmpty)
        XCTAssertTrue(nights([]).isEmpty)
    }

    // MARK: Missing days and baselines

    /// Averages skip days with no reading instead of counting them as zero.
    func testAveragesIgnoreMissingDays() {
        let today = Date().dayStart
        let days: [DayStat] = [0, 1, 4].map { i in var d = DayStat(day: today.adding(days: -i)); d.rhr = 60; return d }
            + [2, 3].map { DayStat(day: today.adding(days: -$0)) }
        XCTAssertEqual(Stats.mean(days.compactMap(\.rhr)), 60)
        XCTAssertNil(Stats.mean([]))
    }

    /// Readiness needs a real baseline (3+ earlier readings); missing days are skipped, never zeros.
    func testReadinessSaysNotEnoughDataWithoutABaseline() {
        let today = Date().dayStart
        func stat(_ i: Int) -> DayStat { var d = DayStat(day: today.adding(days: -i)); d.hrv = 50; d.rhr = 55; return d }
        let thin = [stat(0), stat(1), stat(2)]
        XCTAssertNil(Compare.readiness(day: today, watch: thin, sleeps: []), "two earlier days aren't a baseline")
        XCTAssertEqual(Compare.readinessDetail(day: today, watch: thin, sleeps: [], carryOver: false)?.hasBaseline, false)
        // Three earlier readings with gaps between them are enough, and the gaps don't drag the baseline down.
        let gappy = [stat(0), stat(1), stat(4), stat(6)]
        XCTAssertEqual(Compare.readiness(day: today, watch: gappy, sleeps: []), 55)
    }

    // MARK: Calories

    /// Active energy alone is not a total burn.
    func testTotalCaloriesNeedsActiveAndResting() {
        var d = DayStat(day: Date().dayStart)
        d.activeKcal = 600
        XCTAssertNil(d.totalKcal)
        d.basalKcal = 1700
        XCTAssertEqual(d.totalKcal, 2300)
        var w = DayStat(day: Date().dayStart)
        w.activeKcal = 500
        w.totalKcalWhoop = 2600
        XCTAssertEqual(w.totalKcal, 2600, "WHOOP's own cycle total wins")
    }
}
