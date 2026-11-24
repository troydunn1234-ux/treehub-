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
