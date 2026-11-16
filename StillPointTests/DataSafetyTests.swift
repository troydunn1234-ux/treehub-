import XCTest
@testable import StillPoint

/// Still Pointz keeps its session log in UserDefaults ("sp.sessions"). An update must keep reading it.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive).
final class DataSafetyTests: XCTestCase {
    /// A session saved by the first version (only the original fields) still loads.
    func testOldestSessionFormatStillDecodes() throws {
        let json = #"[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A10","practiceId":"box","title":"Box Breathing","start":779000000,"seconds":300,"cycles":18,"device":"Watch","hrStart":72,"hrEnd":64}]"#
        let list = try JSONDecoder().decode([SessionRecord].self, from: Data(json.utf8))
        XCTAssertEqual(list.first?.practiceId, "box")
        XCTAssertEqual(list.first?.seconds, 300)
        XCTAssertEqual(list.first?.hrDrop, 8)
        XCTAssertNil(list.first?.treeID)
    }

    /// A new session lands under the same key, in the same shape, and comes back out.
    func testSessionsAreSavedUnderTheSameKey() throws {
        let id = UUID()
        var r = SessionRecord(id: id, practiceId: "rooted-breath", title: "Rooted Breath",
                              start: Date(timeIntervalSince1970: 1_500_000_000), seconds: 180, cycles: 15,
                              hrStart: 70, hrEnd: 63, device: "iPhone", kind: "breath")
        r.treeID = UUID().uuidString
        r.treeName = "Guard Oak"
        SessionLog.shared.add(r)
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "sp.sessions"), "sessions are no longer saved under sp.sessions")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let mine = try XCTUnwrap(raw.first { ($0["id"] as? String) == id.uuidString })
        for key in ["id", "practiceId", "title", "start", "seconds", "cycles", "device", "kind", "treeID", "treeName"] {
            XCTAssertNotNil(mine[key], "a saved session lost \"\(key)\"")
        }
        let back = try JSONDecoder().decode([SessionRecord].self, from: data).first { $0.id == id }
        XCTAssertEqual(back?.treeName, "Guard Oak")
        // Take the test session out again without marking it deleted.
        let rest = try JSONDecoder().decode([SessionRecord].self, from: data).filter { $0.id != id }
        UserDefaults.standard.set(try JSONEncoder().encode(rest), forKey: "sp.sessions")
    }

    /// What Still Pointz shares with Rootbound (a breath with a tree) keeps its shape.
    func testFeedSessionKeepsItsShape() throws {
        var s = WellnessBridge.Session(id: UUID(), date: Date(timeIntervalSince1970: 1_794_700_000), kind: "breath", minutes: 3)
        s.treeID = UUID().uuidString; s.treeName = "Guard Oak"; s.practice = "rooted-breath"; s.hrDrop = 6
        XCTAssertTrue(s.isCalm)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: enc.encode(s)) as? [String: Any])
        for key in ["id", "date", "kind", "minutes", "treeID", "treeName", "practice", "hrDrop"] {
            XCTAssertNotNil(obj[key], "stillpoint.json lost \"\(key)\"")
        }
        XCTAssertFalse(WellnessBridge.Session(id: UUID(), date: Date(), kind: "Sauna", minutes: 15).isCalm)
    }

    /// Deep links: Rootbound opens stillpoint://, and Still Pointz may ask whether Rootbound is installed.
    func testDeepLinkSchemes() {
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("stillpoint"), "\(schemes)")
        let queries = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? []
        XCTAssertTrue(queries.contains("rootbound"), "\(queries)")
    }
}
