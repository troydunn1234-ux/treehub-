import XCTest
@testable import StillPoint

/// Still Pointz keeps its session log in UserDefaults ("sp.sessions"). An update must keep reading it.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive);
/// helpers are in TestSupport/DataGuardSupport.swift.
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

    /// Tree hugs from Rootbound and sauna / steam days keep the shapes they were saved in.
    func testTreeAndHeatEntriesStillDecode() throws {
        let trees = try JSONDecoder().decode([TreeEntry].self, from: Data(#"[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A11","start":779000000,"minutes":12,"name":"Grandpa Oak"}]"#.utf8))
        XCTAssertEqual(trees.first?.name, "Grandpa Oak")
        let heat = try JSONDecoder().decode([HeatEntry].self, from: Data(#"[{"start":779000000,"minutes":15,"kind":"sauna"}]"#.utf8))
        XCTAssertEqual(heat.first?.minutes, 15)
    }

    // MARK: What Still Pointz shares with Rootbound

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

    /// Rootbound's hugs drop out of Progress only when Rootbound deleted them, not when its feed trimmed them
    /// (it holds at most 300 hugs).
    func testTreeHugsTrimmedFromAFullFeedStayCounted() {
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        func hug(_ days: Double) -> WellnessBridge.TreeHug {
            WellnessBridge.TreeHug(id: UUID(), date: now.addingTimeInterval(-days * 86400), minutes: 5, tree: "Oak", species: "")
        }
        let window = now.addingTimeInterval(-Double(WellnessBridge.keepDays) * 86400)
        let few = WellnessBridge.RootboundPart(updated: now, streak: 1, hugs: [hug(1), hug(40)])
        XCTAssertEqual(StillPointWellness.treeWindow(few, now: now), window)
        let full = WellnessBridge.RootboundPart(updated: now, streak: 1,
                                                hugs: (0..<WellnessBridge.maxItems).map { hug(Double($0) / 10) })
        let since = StillPointWellness.treeWindow(full, now: now)
        XCTAssertEqual(since.timeIntervalSince1970, now.addingTimeInterval(-29.9 * 86400).timeIntervalSince1970, accuracy: 1)
    }

    /// Rootbound's "Breathe with this tree" link starts a breath tagged with that tree.
    func testBreatheWithATreeLink() throws {
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "stillpoint://session?practice=rooted-breath&minutes=3&context=tree&name=Big%20Oak&tree=\(id.uuidString)"))
        let req = try XCTUnwrap(StillPointWellness.sessionRequest(from: url))
        XCTAssertEqual(req.practiceId, "rooted-breath")
        XCTAssertEqual(req.minutes, 3)
        XCTAssertEqual(req.treeName, "Big Oak")
        XCTAssertEqual(req.treeID, id.uuidString)
        XCTAssertNil(StillPointWellness.sessionRequest(from: URL(string: "stillpoint://journey")!))
    }

    /// Deep links: Rootbound opens stillpoint://, and Still Pointz may ask whether Rootbound is installed.
    func testDeepLinkSchemes() {
        XCTAssertTrue(DataGuardSupport.urlSchemes.contains("stillpoint"), "\(DataGuardSupport.urlSchemes)")
        XCTAssertTrue(DataGuardSupport.querySchemes.contains("rootbound"), "\(DataGuardSupport.querySchemes)")
    }

    // MARK: What the build itself carries

    func testEntitlementsMatchTheAllowlist() throws {
        try DataGuardSupport.assertEntitlements(target: "StillPoint")
        XCTAssertTrue(try DataGuardSupport.appGroups(target: "StillPoint").contains(WellnessBridge.groupID))
    }

    func testEnglishPermissionTexts() {
        DataGuardSupport.assertEnglishInfoPlist()
    }
}
