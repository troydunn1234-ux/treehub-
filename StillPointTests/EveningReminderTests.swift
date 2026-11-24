import XCTest
@testable import StillPoint

/// One evening notification, not two: the daily reminder folds into the bedtime "Right now" pick when both are on.
final class EveningReminderTests: XCTestCase {
    func testEveningReminderFoldsIntoBedtimePick() {
        XCTAssertTrue(EveningReminder.folded(reminderOn: true, reminderHour: 21, bedtimeOn: true))
        XCTAssertFalse(EveningReminder.reminderSchedulesOwn(reminderOn: true, reminderHour: 21, bedtimeOn: true))
        XCTAssertTrue(EveningReminder.folded(reminderOn: true, reminderHour: 17, bedtimeOn: true))
        XCTAssertTrue(EveningReminder.folded(reminderOn: true, reminderHour: 23, bedtimeOn: true))
    }

    func testBedtimePickOffKeepsReminderAsBefore() {
        XCTAssertFalse(EveningReminder.folded(reminderOn: true, reminderHour: 21, bedtimeOn: false))
        XCTAssertTrue(EveningReminder.reminderSchedulesOwn(reminderOn: true, reminderHour: 21, bedtimeOn: false))
    }

    func testDaytimeReminderIsNotAnEveningDuplicate() {
        for h in [0, 6, 8, 12, 16] {
            XCTAssertFalse(EveningReminder.folded(reminderOn: true, reminderHour: h, bedtimeOn: true), "hour \(h)")
            XCTAssertTrue(EveningReminder.reminderSchedulesOwn(reminderOn: true, reminderHour: h, bedtimeOn: true), "hour \(h)")
        }
    }

    func testReminderOffSchedulesNothingAndAddsNoNudge() {
        XCTAssertFalse(EveningReminder.folded(reminderOn: false, reminderHour: 21, bedtimeOn: true))
        XCTAssertFalse(EveningReminder.reminderSchedulesOwn(reminderOn: false, reminderHour: 21, bedtimeOn: true))
        XCTAssertFalse(EveningReminder.reminderSchedulesOwn(reminderOn: false, reminderHour: 21, bedtimeOn: false))
        XCTAssertFalse(EveningReminder.bedtimeNudge(reminderOn: false, reminderHour: 21, bedtimeOn: true, practicedThatDay: false))
    }

    /// Every combination: at most one evening notification (own reminder XOR bedtime pick, never both).
    func testNeverTwoEveningNotifications() {
        for reminderOn in [false, true] {
            for bedtimeOn in [false, true] {
                for hour in 0..<24 {
                    let own = EveningReminder.reminderSchedulesOwn(reminderOn: reminderOn, reminderHour: hour, bedtimeOn: bedtimeOn)
                    let eveningCount = (own && EveningReminder.isEvening(hour: hour) ? 1 : 0) + (bedtimeOn ? 1 : 0)
                    XCTAssertLessThanOrEqual(eveningCount, 1, "on \(reminderOn) bed \(bedtimeOn) hour \(hour)")
                }
            }
        }
    }

    func testNudgeOnlyWhenFoldedAndNotPracticed() {
        XCTAssertTrue(EveningReminder.bedtimeNudge(reminderOn: true, reminderHour: 21, bedtimeOn: true, practicedThatDay: false))
        XCTAssertFalse(EveningReminder.bedtimeNudge(reminderOn: true, reminderHour: 21, bedtimeOn: true, practicedThatDay: true))
        XCTAssertFalse(EveningReminder.bedtimeNudge(reminderOn: true, reminderHour: 8, bedtimeOn: true, practicedThatDay: false))
    }

    func testBedtimeBodyText() {
        let plain = EveningReminder.bedtimeBody(because: "A calm day", title: "4-7-8", minutes: 5, nudge: false)
        XCTAssertTrue(plain.contains("A calm day"))
        XCTAssertTrue(plain.contains("4-7-8"))
        XCTAssertFalse(plain.contains("practiced"))
        let nudged = EveningReminder.bedtimeBody(because: "A calm day", title: "4-7-8", minutes: 5, nudge: true)
        XCTAssertTrue(nudged.contains("practiced"))
        XCTAssertTrue(nudged.contains("4-7-8"))
        XCTAssertTrue(nudged.contains("5"))
    }

    /// Reads the saved bedtime switch the same way DailyMoments does (default on), without writing it.
    func testBedtimeOnSavedDefaultsOn() {
        let d = UserDefaults(suiteName: "EveningReminderTests")!
        d.removePersistentDomain(forName: "EveningReminderTests")
        XCTAssertTrue(EveningReminder.bedtimeOnSaved(d))
        d.set(false, forKey: "sp.moment.bedOn")
        XCTAssertFalse(EveningReminder.bedtimeOnSaved(d))
        d.removePersistentDomain(forName: "EveningReminderTests")
    }
}
