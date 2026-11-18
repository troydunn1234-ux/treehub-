import XCTest
@testable import StillPoint

/// The hops of the owner's routine that Still Pointz handles, as pure logic: Rootbound's "Breathe with this tree"
/// link, the session as it goes out in stillpoint.json, and the iPhone -> Watch start.
@MainActor
final class ConnectionTests: XCTestCase {
    /// Rootbound's link starts a 3-minute breath named after the tree, tagged with the tree's id.
    func testBreatheWithTreeLinkRoundTrips() throws {
        let tree = UUID()
        let url = WellnessLinks.breatheWithTree("Grandpa Oak", treeID: tree, practice: "rooted-breath")
        let req = try XCTUnwrap(StillPointWellness.sessionRequest(from: url))
        XCTAssertEqual(req.practiceId, "rooted-breath")
        XCTAssertEqual(req.minutes, 3)
        XCTAssertEqual(req.treeName, "Grandpa Oak")
        XCTAssertEqual(req.treeID, tree.uuidString)
    }

    /// A plain session link isn't a tree session, and a bad tree id is dropped rather than kept.
    func testSessionLinkWithoutTree() throws {
        let plain = try XCTUnwrap(StillPointWellness.sessionRequest(from: URL(string: "stillpoint://session?practice=box&minutes=99")!))
        XCTAssertNil(plain.treeName)
        XCTAssertNil(plain.treeID)
        XCTAssertEqual(plain.minutes, 20, "clamped")
        let bad = try XCTUnwrap(StillPointWellness.sessionRequest(from: URL(string: "stillpoint://session?context=tree&name=%20&tree=nope")!))
        XCTAssertEqual(bad.treeName, "a tree")
        XCTAssertNil(bad.treeID)
        XCTAssertNil(StillPointWellness.sessionRequest(from: URL(string: "stillpoint://journey")!))
    }

    /// A finished tree session goes out with its tree and all its heart data, and still decodes after the trip.
    func testTreeSessionGoesOutWithTreeAndHeartData() throws {
        var r = SessionRecord(practiceId: "rooted-breath", title: "Rooted Breath", start: Date(timeIntervalSince1970: 1_794_700_000),
                              seconds: 180, cycles: 18, hrStart: 72, hrEnd: 63, hrv: 51, device: "iPhone", kind: "breath",
                              hrSamples: [HRSample(t: 0, bpm: 72), HRSample(t: 60, bpm: 66), HRSample(t: 120, bpm: 61), HRSample(t: 170, bpm: 63)],
                              hrAvg: 65.5, respiratoryRate: 6.2)
        r.treeID = UUID().uuidString
        r.treeName = "Grandpa Oak"
        let s = StillPointWellness.feedSession(r)
        XCTAssertEqual(s.id, r.id)
        XCTAssertEqual(s.kind, "breath")
        XCTAssertTrue(s.isCalm)
        XCTAssertEqual(s.minutes, 3, accuracy: 1e-9)
        XCTAssertEqual(s.end, r.end)
        XCTAssertEqual(s.treeID, r.treeID)
        XCTAssertEqual(s.treeName, "Grandpa Oak")
        XCTAssertEqual(s.startHR, 72)
        XCTAssertEqual(s.minHR, 61, "lowest from the curve when no low was kept")
        XCTAssertEqual(s.endHR, 63)
        XCTAssertEqual(s.avgHR, 65.5)
        XCTAssertEqual(s.hrv, 51)
        XCTAssertEqual(s.respRate, 6.2)
        XCTAssertEqual(s.breathsPerMin ?? 0, 6, accuracy: 1e-9)
        XCTAssertNotNil(s.calmSeconds)

        // stillpoint.json round trip (the same encoder settings the bridge uses).
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        let part = WellnessBridge.StillPointPart(updated: Date(), streak: 2, sessions: [s])
        let back = try dec.decode(WellnessBridge.StillPointPart.self, from: enc.encode(part))
        XCTAssertEqual(back.sessions.first, s)
    }

    /// Rootbound renamed the tree: the session page shows the current name, linked through the hug.
    func testSessionShowsTheTreesCurrentName() {
        let sessionID = UUID(), tree = UUID()
        let start = Date(timeIntervalSince1970: 1_794_700_000)
        var hug = WellnessBridge.TreeHug(id: UUID(), date: start, minutes: 3, tree: "Old Friend", species: "Coast Live Oak", treeID: tree)
        hug.sessionIDs = [sessionID]
        let m = WellnessConnect.tree(forSession: sessionID, start: start, end: start.addingTimeInterval(180),
                                     taggedTreeID: tree.uuidString, taggedName: "Grandpa Oak", in: [hug])
        XCTAssertEqual(m?.name, "Old Friend")
        XCTAssertEqual(m?.how, .linked)
        XCTAssertEqual(m?.hugCount, 1)
    }

    /// A start the Watch only receives long after it was sent (it was off) doesn't start by surprise.
    func testStaleWatchStartIsIgnored() {
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        XCTAssertFalse(SyncKey.isStaleStart([SyncKey.sentAt: now.timeIntervalSince1970 - 5], now: now))
        XCTAssertTrue(SyncKey.isStaleStart([SyncKey.sentAt: now.timeIntervalSince1970 - 3600], now: now))
        XCTAssertFalse(SyncKey.isStaleStart([SyncKey.command: SyncKey.start], now: now), "older iPhone builds still start")
    }
}
