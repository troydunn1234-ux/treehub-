import XCTest
import SwiftData
import ImageIO
@testable import Rootbound

/// An update must open the store that is already on the phone and show everything in it.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive).
final class DataSafetyTests: XCTestCase {
    private let schema = Schema([Hug.self, Activity.self])

    func testStoreIsPinnedToTheAppsOwnApplicationSupport() {
        let path = LocalStore.url.standardizedFileURL.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/default.store"), path)
        XCTAssertFalse(path.contains("AppGroup"), "the store must never be inside an App Group: \(path)")
        XCTAssertEqual(LocalStore.url.deletingLastPathComponent().standardizedFileURL.path,
                       URL.applicationSupportDirectory.standardizedFileURL.path)
    }

    /// The pinned location is the one SwiftData used before any App Group existed.
    func testPinnedLocationIsTheOriginalDefault() {
        let original = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        XCTAssertEqual(original.url.standardizedFileURL.path, LocalStore.url.standardizedFileURL.path)
    }

    func testAppContainerOpensThePinnedStore() throws {
        let container = TreeHubApp.makeContainer(demo: false)
        let config = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app fell back to a temporary store: saved hugs would be hidden")
        XCTAssertEqual(config.url.standardizedFileURL.path, LocalStore.url.standardizedFileURL.path)
    }

    /// A store written the way an earlier build wrote it opens with the app's own container code,
    /// every record and photo still there.
    func testExistingHugsAndWalksSurviveAnUpdate() throws {
        let hugID = UUID(), walkID = UUID(), tree = UUID()
        let photo = Data((0..<300_000).map { UInt8($0 % 251) })
        do {
            let old = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: LocalStore.url, cloudKitDatabase: .none))
            let ctx = ModelContext(old)
            let h = Hug()
            h.id = hugID; h.treeID = tree; h.treeName = "Guard Oak"; h.species = "Valley Oak"
            h.durationMin = 12; h.treePhoto = photo; h.xp = 85; h.notes = "before the update"
            h.linkedSessions = [LinkedSession(start: h.date, end: h.date.addingTimeInterval(180), source: "Still Pointz")]
            let a = Activity()
            a.id = walkID; a.title = "Guard walk"; a.distanceM = 1234; a.kind = .hike
            ctx.insert(h); ctx.insert(a)
            try ctx.save()
        }
        let ctx = ModelContext(TreeHubApp.makeContainer(demo: false))
        let hugs = try ctx.fetch(FetchDescriptor<Hug>()).filter { $0.id == hugID }
        let walks = try ctx.fetch(FetchDescriptor<Activity>()).filter { $0.id == walkID }
        XCTAssertEqual(hugs.count, 1)
        XCTAssertEqual(walks.count, 1)
        XCTAssertEqual(hugs.first?.treeName, "Guard Oak")
        XCTAssertEqual(hugs.first?.treeID, tree)
        XCTAssertEqual(hugs.first?.treePhoto, photo)
        XCTAssertEqual(hugs.first?.xp, 85)
        XCTAssertEqual(hugs.first?.linkedSessions.count, 1)
        XCTAssertEqual(walks.first?.distanceM, 1234)
        XCTAssertEqual(walks.first?.kind, .hike)
        hugs.forEach { ctx.delete($0) }
        walks.forEach { ctx.delete($0) }
        try ctx.save()
    }

    /// Every field that was ever saved is still in the model (snapshot: .github/data-guard/models.json).
    func testNoStoredFieldWasRenamedOrRemoved() throws {
        try DataGuardSnapshot.assertModels(in: schema)
    }

    // MARK: The shared feed (Rootbound, Still Pointz, Roamr, Pulse Lab)

    private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try dec.decode(T.self, from: Data(json.utf8))
    }

    /// Feeds written by an older build of the other app still decode (new fields are optional).
    func testOlderFeedsStillDecode() throws {
        let sp = try decode(#"{"updated":1763200000,"streak":3,"sessions":[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A10","date":1763190000,"kind":"breath","minutes":3}]}"#,
                            as: WellnessBridge.StillPointPart.self)
        XCTAssertEqual(sp.sessions.first?.minutes, 3)
        XCTAssertNil(sp.sessions.first?.treeID)
        let roamr = try decode(#"{"updated":1763200000,"trips":[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A11","kind":"walk","start":1763190000,"end":1763193600,"distanceM":3200,"movingSec":3000,"elevGainM":40,"avgSpeed":1.1,"topSpeed":2}]}"#,
                               as: WellnessBridge.RoamrPart.self)
        XCTAssertEqual(roamr.trips.first?.isOnFoot, true)
        let rb = try decode(#"{"updated":1763200000,"streak":1,"hugs":[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A12","date":1763190000,"minutes":12,"tree":"Oak","species":""}]}"#,
                            as: WellnessBridge.RootboundPart.self)
        XCTAssertNil(rb.hugs.first?.treeID)
        let pl = try decode(#"{"updated":1763200000,"date":"2026-11-15","whoopRecovery":61,"fromWhoopAPI":true,"fromWhoopManual":false,"fromWhoopHealth":false,"fromWatch":false}"#,
                            as: WellnessBridge.PulseLabPart.self)
        XCTAssertEqual(pl.whoopRecovery, 61)
    }

    /// A Roamr walk around a hug is offered for it; a drive or a walk the day before is not.
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

    @MainActor
    func testDeepLinksBetweenTheApps() {
        let id = UUID()
        let url = WellnessLinks.breatheWithTree("Grandpa Oak", treeID: id, practice: "rooted-breath")
        XCTAssertEqual(url.scheme, "stillpoint")
        XCTAssertEqual(url.host, "session")
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(q.first { $0.name == "tree" }?.value, id.uuidString)
        XCTAssertEqual(q.first { $0.name == "name" }?.value, "Grandpa Oak")
        XCTAssertEqual(WellnessLinks.rootboundTree(id.uuidString).absoluteString, "rootbound://tree?id=\(id.uuidString)")
        XCTAssertEqual(WellnessLinks.roamrHome.absoluteString, "roamr://history")
        // canOpenURL only answers for schemes the app declares.
        let queries = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? []
        XCTAssertTrue(queries.contains("stillpoint") && queries.contains("roamr"), "\(queries)")
    }

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

/// Reads the checked-in snapshot next to the sources (the simulator can see the Mac's files).
enum DataGuardSnapshot {
    static func models(file: StaticString = #filePath) -> [String: [String: String]]? {
        let root = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent(".github/data-guard/models.json")) else { return nil }
        return try? JSONDecoder().decode([String: [String: String]].self, from: data)
    }

    static func assertModels(in schema: Schema) throws {
        guard let snapshot = models() else { throw XCTSkip("models.json is not readable from the simulator") }
        for entity in schema.entities {
            let saved = try XCTUnwrap(snapshot[entity.name], "\(entity.name) is missing from models.json")
            let now = Set(entity.attributes.map(\.name))
            for name in saved.keys {
                XCTAssertTrue(now.contains(name), "\(entity.name).\(name) was renamed or removed: its saved values would be lost")
            }
        }
    }
}
