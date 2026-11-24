import XCTest
@testable import PulseLab

/// Pure logic behind syncing and sharing (no Health, no network).
final class LogicTests: XCTestCase {

    // MARK: WHOOP sign-in survives a bad moment

    func testOnlyADeadRefreshTokenDisconnects() {
        XCTAssertTrue(WhoopAuth.refreshTokenIsDead(status: 400, error: "invalid_grant"))
        XCTAssertTrue(WhoopAuth.refreshTokenIsDead(status: 401, error: nil))
        XCTAssertFalse(WhoopAuth.refreshTokenIsDead(status: 400, error: "invalid_request"))
        XCTAssertFalse(WhoopAuth.refreshTokenIsDead(status: 401, error: "invalid_client"))
        XCTAssertFalse(WhoopAuth.refreshTokenIsDead(status: 400, error: nil))
        XCTAssertFalse(WhoopAuth.refreshTokenIsDead(status: 503, error: nil))
        XCTAssertFalse(WhoopAuth.refreshTokenIsDead(status: 429, error: nil))
    }

    // MARK: Health sync splices without duplicating days

    func testHealthMergeKeepsOneEntryPerDayAndTakesTheNewerValues() {
        let today = Date().dayStart
        var old = HealthPull.Result()
        old.watch = (0..<10).map { i in var d = DayStat(day: today.adding(days: -i)); d.rhr = 60; return d }.sorted { $0.day < $1.day }
        old.sleeps = (0..<10).map { SleepNight(night: today.adding(days: -$0), source: .watch) }.sorted { $0.night < $1.night }
        let cutoff = today.adding(days: -2)
        var fresh = HealthPull.Result()
        fresh.watch = (0...2).map { i in var d = DayStat(day: today.adding(days: -i)); d.rhr = 55; return d }
        // A pull reads sleep from the day before its cutoff too: that night must not be doubled.
        fresh.sleeps = (0...3).map { SleepNight(night: today.adding(days: -$0), source: .watch) }

        let merged = old.merged(with: fresh, from: cutoff)
        XCTAssertEqual(merged.watch.count, 10)
        XCTAssertEqual(Set(merged.watch.map(\.day)).count, 10, "a day appears twice")
        XCTAssertEqual(merged.sleeps.count, 10)
        XCTAssertEqual(merged.watch.first { $0.day == today }?.rhr, 55)
        XCTAssertEqual(merged.watch.first { $0.day == today.adding(days: -5) }?.rhr, 60)
        // Merging the same pull again changes nothing (idempotent).
        let again = merged.merged(with: fresh, from: cutoff)
        XCTAssertEqual(again.watch.map(\.day), merged.watch.map(\.day))
        XCTAssertEqual(again.watch.map(\.rhr), merged.watch.map(\.rhr))
        XCTAssertEqual(again.sleeps.map(\.night), merged.sleeps.map(\.night))
    }

    // MARK: Today's Watch vs WHOOP card speaks plainly

    func testAgreementHeadlineAndReasonInPlainWords() {
        // Resting HR 1 bpm apart, HRV and strain both near their week, sleep 42 min apart.
        let mostly = TodayAgreement(rows: [
            TodayAgreement.rhr(52, 51),
            TodayAgreement.trend(.hrv, 1.0, 1.02),
            TodayAgreement.sleep(432, 390),
            TodayAgreement.trend(.strain, 1.01, 0.97),
        ])
        XCTAssertEqual(mostly.compared, 4)
        XCTAssertEqual(mostly.agreeing, 3)
        XCTAssertEqual(mostly.score, 75)
        XCTAssertEqual(mostly.headline, "They agree on 3 of 4")
        XCTAssertEqual(mostly.reason, "Sleep is off by 42 min.")
        XCTAssertFalse(mostly.fullAgreement)

        // Two splits are both named; over an hour reads as hours and minutes.
        let two = TodayAgreement(rows: [TodayAgreement.rhr(60, 52), TodayAgreement.sleep(480, 408), TodayAgreement.trend(.hrv, 1.0, 1.0)])
        XCTAssertEqual(two.headline, "They agree on 1 of 3")
        XCTAssertEqual(two.reason, "Resting HR is off by 8 bpm and sleep is off by 1h 12m.")

        // Everything compared agrees: the small celebration is due.
        let all = TodayAgreement(rows: [TodayAgreement.rhr(52, 51), TodayAgreement.sleep(430, 420)])
        XCTAssertEqual(all.headline, "They agree on both")
        XCTAssertEqual(all.reason, "Same story on every number today.")
        XCTAssertTrue(all.fullAgreement)

        // One comparison names the metric; nothing compared waits.
        XCTAssertEqual(TodayAgreement(rows: [TodayAgreement.rhr(60, 52), TodayAgreement.sleep(nil, 400)]).headline, "They split on resting HR")
        let none = TodayAgreement(rows: [TodayAgreement.rhr(nil, 51), TodayAgreement.sleep(nil, nil)])
        XCTAssertEqual(none.headline, "Waiting for both trackers")
        XCTAssertNil(none.score)
        XCTAssertFalse(none.fullAgreement)
    }

    // MARK: Today's agreement compares like with like

    func testSleepIsComparedOnTheSameNightOnly() {
        let today = Date().dayStart
        func night(_ s: Source, _ daysAgo: Int, _ minutes: Double) -> SleepNight {
            var n = SleepNight(night: today.adding(days: -daysAgo), source: s)
            n.coreMin = minutes
            return n
        }
        // WHOOP hasn't logged last night yet: the night before is compared from both (10 min apart, agree), never
        // Watch's last night against WHOOP's night before (72 min apart, a split that isn't there).
        let lagging = TodayAgreement.sleep(nights: [night(.watch, 0, 432), night(.watch, 1, 370), night(.whoop, 1, 360)], today: today)
        XCTAssertEqual(lagging.agree, true)
        XCTAssertEqual(lagging.watch, "6h 10m")
        XCTAssertEqual(lagging.whoop, "6h 0m")
        XCTAssertTrue(lagging.detail.hasPrefix("Night before last"), lagging.detail)

        // No night in common: both shown, not compared (so not a split either).
        let apart = TodayAgreement.sleep(nights: [night(.watch, 0, 432), night(.whoop, 1, 360)], today: today)
        XCTAssertNil(apart.agree)
        XCTAssertEqual(apart.watch, "7h 12m")
        XCTAssertEqual(apart.whoop, "6h 0m")
        XCTAssertNil(apart.why)

        // Both have last night: that's the one compared.
        let both = TodayAgreement.sleep(nights: [night(.watch, 0, 432), night(.whoop, 0, 390), night(.watch, 1, 300), night(.whoop, 1, 300)], today: today)
        XCTAssertEqual(both.agree, false)
        XCTAssertEqual(both.why, "sleep is off by 42 min")

        // Nights older than the night before last don't count.
        let old = TodayAgreement.sleep(nights: [night(.watch, 2, 400), night(.whoop, 2, 400)], today: today)
        XCTAssertNil(old.watch)
        XCTAssertNil(old.agree)
    }

    func testHRVIsComparedOnTheSameDayOnly() {
        let today = Date().dayStart
        func days(_ hrv: [Int: Double]) -> [DayStat] {
            hrv.map { ago, v in var d = DayStat(day: today.adding(days: -ago)); d.hrv = v; return d }.sorted { $0.day < $1.day }
        }
        let week = Dictionary(uniqueKeysWithValues: (1...8).map { ($0, 50.0) })
        var watch = week
        watch[0] = 60   // today's Watch HRV is in (20% over its week); WHOOP's newest is yesterday's
        // Compared on yesterday, when both sat at their usual, not Watch's today against WHOOP's yesterday.
        let lagging = TodayAgreement.hrv(watch: days(watch), whoop: days(week), today: today)
        XCTAssertEqual(lagging.agree, true)
        XCTAssertEqual(lagging.watch, "Usual")
        XCTAssertTrue(lagging.detail.hasPrefix("Yesterday"), lagging.detail)

        // Both have today: today it is (Watch up 20%, WHOOP usual: they split).
        var whoopToday = week
        whoopToday[0] = 50
        let fresh = TodayAgreement.hrv(watch: days(watch), whoop: days(whoopToday), today: today)
        XCTAssertEqual(fresh.agree, false)
        XCTAssertEqual(fresh.watch, "Up 20%")

        // No day in common (Watch skipped yesterday, WHOOP has no today): shown, not compared.
        var gappy = watch
        gappy[1] = nil
        let apart = TodayAgreement.hrv(watch: days(gappy), whoop: days(week), today: today)
        XCTAssertNil(apart.agree)
        XCTAssertNotNil(apart.watch)
        XCTAssertNotNil(apart.whoop)
    }

    // MARK: WHOOP cycles land on the right day

    func testAWhoopCycleBelongsToTheDayYouWakeUpInto() throws {
        let cal = Calendar.current
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        let next = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: day))
        let lateNight = try XCTUnwrap(cal.date(bySettingHour: 22, minute: 45, second: 0, of: day))
        let afterMidnight = try XCTUnwrap(cal.date(bySettingHour: 0, minute: 40, second: 0, of: day))
        let morning = try XCTUnwrap(cal.date(bySettingHour: 7, minute: 0, second: 0, of: day))
        // Asleep at 10:45 pm on the 20th: that cycle (and its strain) is the 21st's.
        XCTAssertEqual(WhoopAdapter.cycleDay(lateNight), next)
        // Asleep after midnight: the same day.
        XCTAssertEqual(WhoopAdapter.cycleDay(afterMidnight), day)
        XCTAssertEqual(WhoopAdapter.cycleDay(morning), day)
    }

    // MARK: Log WHOOP stores only what was typed

    @MainActor
    func testUntouchedPrefilledWhoopFieldsAreNotSavedAsManual() {
        // WHOOP's HRV in Health is 61.4 ms and the field shows "61": saving without touching it stores nothing
        // (it used to store 61 as a hand-typed number, which then beat Health's own value and was badged MANUAL).
        XCTAssertTrue(LogWhoopSheet.isUnchanged(61, from: 61.4, decimals: 0))
        XCTAssertTrue(LogWhoopSheet.isUnchanged(15.2, from: 15.234, decimals: 1))
        XCTAssertTrue(LogWhoopSheet.isUnchanged(432, from: 431.7, decimals: 0))
        // A number typed over it is kept.
        XCTAssertFalse(LogWhoopSheet.isUnchanged(62, from: 61.4, decimals: 0))
        XCTAssertFalse(LogWhoopSheet.isUnchanged(15.3, from: 15.234, decimals: 1))
        // Nothing known for the field: whatever is in it was typed.
        XCTAssertFalse(LogWhoopSheet.isUnchanged(61, from: nil, decimals: 0))
    }

    // MARK: Recovery vs readiness says "same zone" only when it is

    @MainActor
    func testReadinessVerdictOnlyClaimsTheSameZoneWhenTheRingsMatch() {
        func verdict(_ readiness: Double, _ recovery: Double) -> String {
            ReadyDuelCard.verdictLine(readiness: readiness, recovery: recovery, sleepHours: 7.5)
        }
        XCTAssertEqual(verdict(80, 72), "Both say you're ready. Go.")
        XCTAssertEqual(verdict(20, 30), "Both say rest. Keep today easy.")
        XCTAssertTrue(verdict(50, 58).hasPrefix("Both land in the same zone"))
        // 70 is green and 62 yellow: close, but not the same zone.
        XCTAssertFalse(verdict(70, 62).contains("same zone"))
        XCTAssertTrue(verdict(70, 62).contains("green line"))
        XCTAssertTrue(verdict(36, 30).contains("red line"))
        // Far apart: a split, with last night's sleep as the tie-break.
        XCTAssertEqual(verdict(80, 40), "WHOOP says take it easy, Watch says go — trust sleep: 7h 30m last night, lean toward go.")
    }

    // MARK: Background refresh keeps what was shared

    func testABackgroundPassKeepsEarlierNumbersForTheSameDay() {
        var earlier = WellnessBridge.PulseLabPart(date: "2026-11-15")
        earlier.whoopRecovery = 71
        earlier.readiness = 64
        earlier.fromWhoopAPI = true
        var later = WellnessBridge.PulseLabPart(date: "2026-11-15")
        later.readiness = 66
        let kept = PulseLabWellness.keepingEarlier(later, earlier)
        XCTAssertEqual(kept.whoopRecovery, 71)
        XCTAssertEqual(kept.readiness, 66, "a newer number wins")
        XCTAssertTrue(kept.fromWhoopAPI)
        // A new day never borrows yesterday's numbers.
        let nextDay = WellnessBridge.PulseLabPart(date: "2026-11-16")
        XCTAssertNil(PulseLabWellness.keepingEarlier(nextDay, earlier).whoopRecovery)
    }
}
