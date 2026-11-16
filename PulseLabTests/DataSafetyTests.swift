import XCTest
import SwiftData
@testable import PulseLab

/// An update must open the Stack that is already on the phone and keep hand-typed WHOOP numbers readable.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive).
final class DataSafetyTests: XCTestCase {
    private let schema = Schema([Supplement.self, SuppDose.self])

    /// Pulse Lab keeps SwiftData's default location (its first App Group on a real iPhone). It must not be given
    /// LocalStore.url or any other url: that would open a new, empty Stack.
    func testStackStoreStaysAtSwiftDatasDefaultLocation() throws {
        let expected = ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
        let config = try XCTUnwrap(CloudSync.makeContainer().configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app fell back to a temporary store: the Stack would be hidden")
        XCTAssertEqual(config.url.standardizedFileURL.path, expected.standardizedFileURL.path)
        XCTAssertEqual(config.url.lastPathComponent, "default.store")
    }

    func testExistingStackSurvivesAnUpdate() throws {
        let suppID = UUID()
        do {
            let old = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
            let ctx = ModelContext(old)
            let s = Supplement(name: "Guard magnesium", dose: "2 capsules", emoji: "🌙", time: .night, order: 3)
            s.id = suppID
            ctx.insert(s)
            ctx.insert(SuppDose(suppID: suppID, day: "2026-11-15"))
            try ctx.save()
        }
        let ctx = ModelContext(CloudSync.makeContainer())
        let supps = try ctx.fetch(FetchDescriptor<Supplement>()).filter { $0.id == suppID }
        let doses = try ctx.fetch(FetchDescriptor<SuppDose>()).filter { $0.suppID == suppID }
        XCTAssertEqual(supps.first?.name, "Guard magnesium")
        XCTAssertEqual(supps.first?.time, .night)
        XCTAssertEqual(doses.first?.day, "2026-11-15")
        supps.forEach { ctx.delete($0) }
        doses.forEach { ctx.delete($0) }
        try ctx.save()
    }

    func testNoStoredFieldWasRenamedOrRemoved() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent(".github/data-guard/models.json")),
              let snapshot = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { throw XCTSkip("models.json is not readable from the simulator") }
        for entity in schema.entities {
            let saved = try XCTUnwrap(snapshot[entity.name], "\(entity.name) is missing from models.json")
            let now = Set(entity.attributes.map(\.name))
            for name in saved.keys {
                XCTAssertTrue(now.contains(name), "\(entity.name).\(name) was renamed or removed: its saved values would be lost")
            }
        }
    }

    // MARK: Hand-typed WHOOP numbers (Application Support/whoop-manual.json)

    private var manualFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("whoop-manual.json")
    }

    func testManualWhoopEntriesKeepTheirFileAndShape() throws {
        let before = WhoopManualStore.load()
        defer { WhoopManualStore.save(before, push: false) }
        var e = WhoopManualEntry(day: Date(timeIntervalSince1970: 1_500_000_000))
        e.recovery = 61; e.steps = 9123; e.kcal = 2440
        var all = before
        all[e.day] = e
        WhoopManualStore.save(all, push: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manualFile.path), "whoop-manual.json moved")
        XCTAssertEqual(WhoopManualStore.load()[e.day]?.steps, 9123)
        // The saved shape: a list of entries with these names.
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manualFile)) as? [[String: Any]])
        let mine = try XCTUnwrap(list.first { ($0["steps"] as? Double) == 9123 })
        for key in ["day", "recovery", "steps", "kcal", "savedAt"] {
            XCTAssertNotNil(mine[key], "whoop-manual.json lost \"\(key)\"")
        }
    }

    /// An entry saved by an earlier build (only some fields) still loads.
    func testOlderManualEntryStillDecodes() throws {
        let json = #"[{"day":779000000,"recovery":55,"strain":11.2,"sleepPerformance":80,"savedAt":779003600}]"#
        let list = try JSONDecoder().decode([WhoopManualEntry].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.recovery, 55)
        XCTAssertNil(list.first?.steps)
    }

    /// The summary Still Pointz reads for "Right now" keeps its shape.
    func testPulseLabFeedKeepsItsShape() throws {
        var part = WellnessBridge.PulseLabPart(date: WellnessBridge.dayKey(Date()))
        part.whoopRecovery = 61; part.readiness = 70; part.fromWhoopManual = true
        XCTAssertTrue(part.isToday)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: enc.encode(part)) as? [String: Any])
        for key in ["updated", "date", "whoopRecovery", "readiness", "fromWhoopManual"] {
            XCTAssertNotNil(obj[key], "pulselab.json lost \"\(key)\"")
        }
    }
}
