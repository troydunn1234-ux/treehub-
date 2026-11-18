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
