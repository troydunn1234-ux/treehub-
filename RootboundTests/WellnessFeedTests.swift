import XCTest
import ImageIO
@testable import Rootbound

/// The shared wellness feed (Shared/Wellness/WellnessBridge.swift), the links between the apps and the hug logger's
/// photo time must keep working across app versions: Still Pointz, Rootbound, Roamr and Pulse Lab update on their
/// own schedules.
final class WellnessFeedTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e
    }
    private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try decoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: Older feeds still decode (new fields are optional)

    func testOldStillPointFeedDecodes() throws {
        // A feed from a Still Pointz build before the session stats (no endHR / respRate / calmSeconds / breathsPerMin).
        let part = try decode(#"{"updated":1763200000,"streak":3,"sessions":[{"id":"6E1F1C1A-0000-4000-8000-000000000001","date":1763190000,"kind":"breath","minutes":5,"treeID":"6E1F1C1A-0000-4000-8000-0000000000AA","practice":"rooted-breath","avgHR":64}]}"#,
                              as: WellnessBridge.StillPointPart.self)
        XCTAssertEqual(part.sessions.count, 1)
        XCTAssertNil(part.sessions[0].endHR)
        XCTAssertNil(part.sessions[0].respRate)
        XCTAssertEqual(part.sessions[0].avgHR, 64)
        XCTAssertTrue(part.sessions[0].isCalm)
        // The very first shape: id, date, kind, minutes only.
        let first = try decode(#"{"updated":1763200000,"streak":0,"sessions":[{"id":"6E1F1C1A-0000-4000-8000-000000000002","date":1763190000,"kind":"sauna","minutes":15}]}"#,
                               as: WellnessBridge.StillPointPart.self)
        XCTAssertFalse(first.sessions[0].isCalm, "sauna / steam are not calm minutes")
    }

    func testNewStillPointFeedRoundTrips() throws {
        var s = WellnessBridge.Session(id: UUID(), date: Date(timeIntervalSince1970: 1_763_190_000), kind: "breath", minutes: 6)
        s.endHR = 61; s.respRate = 6.2; s.calmSeconds = 240; s.breathsPerMin = 5.5; s.practice = "bark-breath"
        let data = try encoder().encode(WellnessBridge.StillPointPart(updated: Date(), streak: 2, sessions: [s]))
        let back = try decoder().decode(WellnessBridge.StillPointPart.self, from: data)
        XCTAssertEqual(back.sessions.first, s)
    }

    func testRoamrTripWithoutGPSDecodes() throws {
        let part = try decode(#"{"updated":1763200000,"trips":[{"id":"6E1F1C1A-0000-4000-8000-000000000003","kind":"walk","start":1763180000,"end":1763182400,"distanceM":2100,"movingSec":2200,"elevGainM":30,"avgSpeed":0.95,"topSpeed":1.8}]}"#,
                              as: WellnessBridge.RoamrPart.self)
        XCTAssertEqual(part.trips.count, 1)
        XCTAssertTrue(part.trips[0].isOnFoot)
        XCTAssertNil(part.trips[0].startLat)
        XCTAssertNil(part.trips[0].avgHR)
    }

    func testRootboundFeedWithoutTreeIDDecodes() throws {
        let part = try decode(#"{"updated":1763200000,"streak":1,"hugs":[{"id":"6E1F1C1A-0000-4000-8000-000000000004","date":1763190000,"minutes":4,"tree":"Grandpa Oak","species":"Valley Oak"}]}"#,
                              as: WellnessBridge.RootboundPart.self)
        XCTAssertNil(part.hugs.first?.treeID)
    }

    func testPulseLabSummaryDecodes() throws {
        let part = try decode(#"{"updated":1763200000,"date":"2026-11-15","whoopRecovery":61,"fromWhoopAPI":true,"fromWhoopManual":false,"fromWhoopHealth":false,"fromWatch":false}"#,
                              as: WellnessBridge.PulseLabPart.self)
        XCTAssertEqual(part.whoopRecovery, 61)
        XCTAssertNil(part.readiness)
    }

    // MARK: Tree sessions kept under the tree

    private func session(_ day: Double, tree: Bool = true, now: Date) -> WellnessBridge.Session {
        var s = WellnessBridge.Session(id: UUID(), date: now.addingTimeInterval(-day * 86400), kind: "breath", minutes: 3)
        if tree { s.treeID = UUID().uuidString; s.treeName = "Guard Oak" }
        return s
    }

    /// A tree session Still Pointz discarded goes; one the feed only trimmed (it holds at most 300 sessions)
    /// stays under its tree with the heart data Rootbound looked up.
    func testTreeBreathCacheKeepsSessionsTheFeedOnlyTrimmed() {
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        var trimmed = session(90, now: now)
        trimmed.avgHR = 63
        let discarded = session(5, now: now)
        let kept = session(2, now: now)
        // A full feed: 300 sessions from the last 30 days.
        var full = (0..<WellnessBridge.maxItems).map { i in session(Double(i) / 10, tree: false, now: now) }
        full[0] = kept
        let merged = TreeBreaths.merge(cache: [trimmed, discarded, kept],
                                       feed: WellnessBridge.StillPointPart(updated: now, streak: 1, sessions: full), now: now)
        XCTAssertTrue(merged.contains { $0.id == trimmed.id && $0.avgHR == 63 }, "trimmed by the feed, not discarded")
        XCTAssertFalse(merged.contains { $0.id == discarded.id }, "discarded in Still Pointz")
        XCTAssertTrue(merged.contains { $0.id == kept.id })
        // A feed that isn't full covers its whole 120 days: the 90-day-old one was discarded too.
        let small = TreeBreaths.merge(cache: [trimmed, kept],
                                      feed: WellnessBridge.StillPointPart(updated: now, streak: 1, sessions: [kept]), now: now)
        XCTAssertEqual(small.map(\.id), [kept.id])
    }

    /// Feed data and data Rootbound looked up itself are merged, never lost.
    func testTreeBreathCacheKeepsHeartDataTheFeedLacks() {
        let now = Date(timeIntervalSince1970: 1_794_700_000)
        var old = session(1, now: now)
        old.avgHR = 62; old.endHR = 58; old.calmSeconds = 120
        var fresh = old
        fresh.avgHR = nil; fresh.endHR = nil; fresh.calmSeconds = nil; fresh.hrv = 48
        let merged = TreeBreaths.merge(cache: [old], feed: WellnessBridge.StillPointPart(updated: now, streak: 1, sessions: [fresh]), now: now)
        XCTAssertEqual(merged.first?.avgHR, 62)
        XCTAssertEqual(merged.first?.endHR, 58)
        XCTAssertEqual(merged.first?.calmSeconds, 120)
        XCTAssertEqual(merged.first?.hrv, 48)
    }

    /// Feed sessions linked to a hug carry every number Still Pointz shares.
    @MainActor
    func testLinkedSessionTakesEverythingFromTheFeed() {
        var f = WellnessBridge.Session(id: UUID(), date: Date(timeIntervalSince1970: 1_794_700_000), kind: "breath", minutes: 4)
        f.practice = "rooted-breath"; f.avgHR = 64; f.minHR = 58; f.startHR = 70; f.hrDrop = 12; f.hrv = 51
        f.endHR = 60; f.respRate = 6.1; f.calmSeconds = 150; f.breathsPerMin = 5.5
        let s = HugSessions.linked(from: f)
        XCTAssertEqual(s.feedID, f.id)
        XCTAssertEqual(s.minutes, 4, accuracy: 1e-9)
        XCTAssertEqual(s.endHR, 60)
        XCTAssertEqual(s.respRate, 6.1)
        XCTAssertEqual(s.calmSeconds, 150)
        XCTAssertEqual(s.pacedBPM, 5.5)
        XCTAssertEqual(s.practiceName, "Rooted Breath")
    }

    // MARK: Walks under hugs

    /// A Roamr walk around a hug is offered for it; a walk the day before is not.
    @MainActor
    func testWalksMatchHugsWithinTwoHours() {
        let h = Hug()
        h.date = Date(timeIntervalSince1970: 1_763_190_000); h.durationMin = 10
        func walk(_ offset: TimeInterval, _ length: TimeInterval) -> LinkedWalk {
            LinkedWalk(id: UUID(), kind: "walk", start: h.date.addingTimeInterval(offset),
                       end: h.date.addingTimeInterval(offset + length), distanceM: 1000, movingSec: length, elevGainM: 0,
                       avgSpeed: nil, topSpeed: nil, avgHR: nil, source: "Roamr", fromRoamr: true)
        }
        let before = walk(-5400, 1800), during = walk(-600, 3600), yesterday = walk(-86_400, 1800)
        let m = RoamrWalks.matches(h, in: [before, during, yesterday])
        XCTAssertEqual(Set(m.map(\.id)), [before.id, during.id])
    }

    // MARK: Links between the apps

    @MainActor
    func testDeepLinks() {
        let id = UUID()
        let breathe = WellnessLinks.breatheWithTree("Big Oak", treeID: id, practice: "rooted-breath")
        let items = URLComponents(url: breathe, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(breathe.scheme, "stillpoint")
        XCTAssertEqual(breathe.host, "session")
        XCTAssertEqual(items.first { $0.name == "tree" }?.value, id.uuidString)
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "Big Oak")
        XCTAssertEqual(items.first { $0.name == "practice" }?.value, "rooted-breath")
        XCTAssertEqual(items.first { $0.name == "context" }?.value, "tree")
        XCTAssertEqual(WellnessLinks.rootboundTree(id.uuidString).absoluteString, "rootbound://tree?id=\(id.uuidString)")
        XCTAssertEqual(WellnessLinks.hugLogger.absoluteString, "rootbound://hug")
        XCTAssertEqual(WellnessLinks.stillPointJourney.absoluteString, "stillpoint://journey")
        XCTAssertEqual(WellnessLinks.roamrHome.absoluteString, "roamr://history")
        // Rootbound answers rootbound://, and canOpenURL only works for the schemes it declares.
        XCTAssertTrue(DataGuardSupport.urlSchemes.contains("rootbound"), "\(DataGuardSupport.urlSchemes)")
        let queries = DataGuardSupport.querySchemes
        XCTAssertTrue(queries.contains("stillpoint") && queries.contains("roamr"), "\(queries)")
    }

    // MARK: Camera-roll photo time

    /// EXIF capture time with its own UTC offset is read as that instant, whatever the phone's time zone.
    @MainActor
    func testPhotoTimeFromEXIF() {
        let props: [String: Any] = [kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifDateTimeOriginal as String: "2026:11:15 10:30:00",
            kCGImagePropertyExifOffsetTimeOriginal as String: "-08:00",
        ]]
        XCTAssertEqual(HugLogView.photoDate(props)?.timeIntervalSince1970, 1_794_767_400)
        XCTAssertNil(HugLogView.photoDate([:]))
    }
}
