import XCTest
@testable import Rootbound

/// The shared wellness feed (Shared/Wellness/WellnessBridge.swift) and the data saved on hugs must keep decoding
/// across app versions: Still Pointz, Rootbound and Roamr update on their own schedules.
final class WellnessFeedTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e
    }

    func testOldStillPointFeedDecodes() throws {
        // A feed from a Still Pointz build before the session stats (no endHR / respRate / calmSeconds / breathsPerMin).
        let json = """
        {"updated": 1763200000, "streak": 3, "sessions": [
          {"id": "6E1F1C1A-0000-4000-8000-000000000001", "date": 1763190000, "kind": "breath", "minutes": 5,
           "treeID": "6E1F1C1A-0000-4000-8000-0000000000AA", "practice": "rooted-breath", "avgHR": 64}
        ]}
        """
        let part = try decoder().decode(WellnessBridge.StillPointPart.self, from: Data(json.utf8))
        XCTAssertEqual(part.sessions.count, 1)
        XCTAssertNil(part.sessions[0].endHR)
        XCTAssertNil(part.sessions[0].respRate)
        XCTAssertEqual(part.sessions[0].avgHR, 64)
        XCTAssertTrue(part.sessions[0].isCalm)
    }

    func testNewStillPointFeedRoundTrips() throws {
        var s = WellnessBridge.Session(id: UUID(), date: Date(timeIntervalSince1970: 1_763_190_000), kind: "breath", minutes: 6)
        s.endHR = 61; s.respRate = 6.2; s.calmSeconds = 240; s.breathsPerMin = 5.5; s.practice = "bark-breath"
        let data = try encoder().encode(WellnessBridge.StillPointPart(updated: Date(), streak: 2, sessions: [s]))
        let back = try decoder().decode(WellnessBridge.StillPointPart.self, from: data)
        XCTAssertEqual(back.sessions.first, s)
        // Sauna / steam are not calm minutes.
        XCTAssertFalse(WellnessBridge.Session(id: UUID(), date: Date(), kind: "Sauna", minutes: 15).isCalm)
    }

    func testRoamrTripWithoutGPSDecodes() throws {
        let json = """
        {"updated": 1763200000, "trips": [
          {"id": "6E1F1C1A-0000-4000-8000-000000000002", "kind": "walk", "start": 1763180000, "end": 1763182400,
           "distanceM": 2100, "movingSec": 2200, "elevGainM": 30, "avgSpeed": 0.95, "topSpeed": 1.8}
        ]}
        """
        let part = try decoder().decode(WellnessBridge.RoamrPart.self, from: Data(json.utf8))
        XCTAssertEqual(part.trips.count, 1)
        XCTAssertTrue(part.trips[0].isOnFoot)
        XCTAssertNil(part.trips[0].startLat)
        XCTAssertNil(part.trips[0].avgHR)
    }

    func testRootboundFeedWithoutTreeIDDecodes() throws {
        let json = """
        {"updated": 1763200000, "streak": 1, "hugs": [
          {"id": "6E1F1C1A-0000-4000-8000-000000000003", "date": 1763190000, "minutes": 4, "tree": "Grandpa Oak", "species": "Valley Oak"}
        ]}
        """
        let part = try decoder().decode(WellnessBridge.RootboundPart.self, from: Data(json.utf8))
        XCTAssertNil(part.hugs.first?.treeID)
    }

    func testLinkedSessionDecodesPartialRecords() throws {
        // Saved on a hug by an earlier build: only the times and a source.
        let json = #"[{"start": 700000000, "end": 700000300, "source": "Mindfulness"}]"#
        let list = try JSONDecoder().decode([LinkedSession].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].minutes, 5, accuracy: 1e-9)
        XCTAssertNil(list[0].endHR)
        XCTAssertEqual(list[0].title, "Mindfulness")
    }

    func testOldTagIDsStillExist() {
        let ids = Set(HugTag.all.map(\.id))
        for old in ["hike", "chill", "park", "sober", "solo", "company", "sunrise", "sunset", "trail", "beach"] {
            XCTAssertTrue(ids.contains(old), "tag \(old) is saved on older hugs")
        }
        XCTAssertEqual(ids.count, HugTag.all.count, "tag ids are unique")
    }

    @MainActor
    func testDeepLinks() {
        let id = UUID()
        let breathe = WellnessLinks.breatheWithTree("Big Oak", treeID: id)
        let items = URLComponents(url: breathe, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(breathe.scheme, "stillpoint")
        XCTAssertEqual(breathe.host, "session")
        XCTAssertEqual(items.first { $0.name == "tree" }?.value, id.uuidString)
        XCTAssertEqual(items.first { $0.name == "context" }?.value, "tree")
        let tree = WellnessLinks.rootboundTree(id.uuidString)
        XCTAssertEqual(tree.absoluteString, "rootbound://tree?id=\(id.uuidString)")
        XCTAssertEqual(WellnessLinks.hugLogger.absoluteString, "rootbound://hug")
        XCTAssertEqual(WellnessLinks.stillPointJourney.absoluteString, "stillpoint://journey")
        XCTAssertEqual(WellnessLinks.roamrHome.absoluteString, "roamr://history")
    }
}
