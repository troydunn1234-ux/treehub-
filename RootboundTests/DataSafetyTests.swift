import XCTest
import SwiftData
@testable import Rootbound

/// An update must open the store that is already on the phone and show everything in it.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive);
/// helpers are in TestSupport/DataGuardSupport.swift.
final class DataSafetyTests: XCTestCase {
    private let schema = Schema([Hug.self, Activity.self])

    // MARK: Where the store is

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

    /// The app's own container code, as it runs on launch, opens LocalStore.url on disk.
    @MainActor
    func testAppContainerOpensThePinnedStore() throws {
        let container = TreeHubApp.makeContainer(demo: false)
        let config = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app fell back to a temporary store: saved hugs would be hidden")
        XCTAssertEqual(config.url.standardizedFileURL.path, LocalStore.url.standardizedFileURL.path)
    }

    // MARK: An existing store survives the update

    /// A store written the way an earlier build wrote it (at a temporary LocalStore-like path) reopens through the
    /// app's own container code with every hug, photo, linked session, walk and stroll still there.
    @MainActor
    func testExistingStoreReopensWithEveryRecord() throws {
        let url = try DataGuardSupport.temporaryStoreURL("rootbound-store")
        defer { DataGuardSupport.removeTemporaryStore(url) }
        let hugID = UUID(), tree = UUID(), walkID = UUID(), feedID = UUID()
        let photo = Data((0..<300_000).map { UInt8($0 % 251) })   // big enough to live outside the database
        let date = Date(timeIntervalSince1970: 1_794_700_000)
        do {
            let old = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let ctx = ModelContext(old)
            let h = Hug()
            h.id = hugID; h.date = date; h.treeID = tree; h.treeName = "Guard Oak"; h.species = "Valley Oak"
            h.latitude = 45.5; h.longitude = 10.5; h.placeName = "Test Grove"
            h.durationMin = 12; h.treePhoto = photo; h.selfiePhoto = Data([1, 2, 3]); h.xp = 85; h.leafKey = "golden-oak"
            h.notes = "before the update"; h.tagsRaw = "sober,chill"; h.barefoot = true; h.hrStart = 72; h.hrEnd = 61
            h.linkedSessions = [LinkedSession(feedID: feedID, start: date, end: date.addingTimeInterval(180),
                                              source: "Still Pointz", practice: "rooted-breath", avgHR: 64)]
            h.linkedWalks = [LinkedWalk(id: walkID, kind: "hike", start: date.addingTimeInterval(-3600), end: date,
                                        distanceM: 4200, movingSec: 3300, elevGainM: 120, avgSpeed: 1.3, topSpeed: 2.1,
                                        avgHR: 112, source: "Roamr", fromRoamr: true)]
            let a = Activity()
            a.id = walkID; a.title = "Guard stroll"; a.distanceM = 1234; a.kind = .hike; a.routeData = Data([7, 7, 7])
            ctx.insert(h); ctx.insert(a)
            try ctx.save()
        }
        let container = TreeHubApp.makeContainer(storeURL: url, demo: false)
        let config = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app could not open the existing store")
        XCTAssertEqual(config.url.standardizedFileURL.path, url.standardizedFileURL.path)
        let ctx = ModelContext(container)
        let hug = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Hug>()).first { $0.id == hugID })
        XCTAssertEqual(hug.treeID, tree)
        XCTAssertEqual(hug.treeName, "Guard Oak")
        XCTAssertEqual(hug.date, date)
        XCTAssertEqual(hug.treePhoto, photo)
        XCTAssertEqual(hug.selfiePhoto, Data([1, 2, 3]))
        XCTAssertEqual(hug.xp, 85)
        XCTAssertEqual(hug.tags, ["sober", "chill"])
        XCTAssertEqual(hug.hrDrop, 11)
        XCTAssertEqual(hug.linkedSessions.first?.feedID, feedID)
        XCTAssertEqual(hug.linkedSessions.first?.practice, "rooted-breath")
        XCTAssertEqual(hug.linkedWalks.first?.id, walkID)
        XCTAssertEqual(hug.linkedWalks.first?.distanceM, 4200)
        let walk = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Activity>()).first { $0.id == walkID })
        XCTAssertEqual(walk.distanceM, 1234)
        XCTAssertEqual(walk.kind, .hike)
        XCTAssertEqual(walk.routeData, Data([7, 7, 7]))
    }

    /// Every field that was ever saved is still in the model (snapshot: .github/data-guard/models.json).
    func testNoStoredFieldWasRenamedOrRemoved() throws {
        try DataGuardSupport.assertNoStoredFieldRemoved(schema)
    }

    // MARK: Data saved inside a hug (JSON in the store)

    /// A walk saved on a hug by the first build that had walks (exactly those fields) still loads.
    func testOldestSavedWalkStillDecodes() throws {
        let json = #"[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A20","kind":"walk","start":779000000,"end":779001800,"distanceM":2100,"movingSec":1700,"elevGainM":12,"source":"Roamr","fromRoamr":true}]"#
        let list = try JSONDecoder().decode([LinkedWalk].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.distanceM, 2100)
        XCTAssertNil(list.first?.avgSpeed)
        // One odd field never empties the hug's list (editing the hug would then save it empty).
        let odd = #"[{"id":"7F1C8C0E-2B0B-4E0A-9D7E-0D0A3C1B2A21","kind":"hike","start":779000000,"end":779001800,"distanceM":"far","source":"Health"}]"#
        let kept = try JSONDecoder().decode([LinkedWalk].self, from: Data(odd.utf8))
        XCTAssertEqual(kept.first?.kind, "hike")
        XCTAssertEqual(kept.first?.distanceM, 0)
    }

    func testPartialLinkedSessionStillDecodes() throws {
        let json = #"[{"start": 700000000, "end": 700000300, "source": "Mindfulness"}]"#
        let list = try JSONDecoder().decode([LinkedSession].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].minutes, 5, accuracy: 1e-9)
        XCTAssertNil(list[0].endHR)
        XCTAssertEqual(list[0].title, "Mindfulness")
        // One value written differently by another build costs only that value, never the hug's whole list.
        let odd = #"[{"start": 700000000, "end": 700000300, "source": "Still Pointz", "avgHR": "64", "practice": "box"}, {"start": 700001000, "end": 700001120, "source": "Mindfulness"}]"#
        let kept = try JSONDecoder().decode([LinkedSession].self, from: Data(odd.utf8))
        XCTAssertEqual(kept.count, 2)
        XCTAssertNil(kept[0].avgHR)
        XCTAssertEqual(kept[0].practice, "box")
    }

    /// Tags are saved on hugs by id: every id ever offered stays.
    func testTagIDsAreNeverRemoved() {
        let ids = Set(HugTag.all.map(\.id))
        for old in ["sober", "chill", "grateful", "meditated", "breathwork", "intention", "journaled", "phonefree",
                    "music", "solo", "company", "dog", "workout", "coldplunge", "sauna", "hike", "trail", "park",
                    "creek", "beach", "mountain", "sunrise", "sunset", "moonlight", "rain", "fog", "sunshine", "birds"] {
            XCTAssertTrue(ids.contains(old), "tag \(old) is saved on older hugs")
        }
        XCTAssertEqual(ids.count, HugTag.all.count, "tag ids are unique")
    }

    /// Editing a hug keeps a tag this build doesn't offer (saved by another build) instead of dropping it.
    func testEditingAHugKeepsTagsThisBuildDoesNotKnow() {
        let h = Hug()
        h.tagsRaw = "sober,from-a-newer-build"
        var d = HugDraft(h)
        d.tags.insert("chill")
        d.apply(to: h)
        XCTAssertEqual(Set(h.tags), ["sober", "chill", "from-a-newer-build"])
    }

    // MARK: Files and settings outside the store

    @MainActor
    func testNatureRollKeepsItsIndexAndFixes() throws {
        let path = NatureRollStore.fileURL.standardizedFileURL.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/NatureRoll/index.json"), path)
        XCTAssertEqual(NatureRollStore.correctionsKey, "natureRoll.corrections")
        // Fixes saved by the first build with fixes, and a partial record, still load.
        let full = try JSONDecoder().decode(NatureCorrections.self,
                                            from: Data(#"{"notNature":["A/L0/001"],"moved":{"B/L0/001":["trees"]}}"#.utf8))
        XCTAssertEqual(full.notNature, ["A/L0/001"])
        XCTAssertEqual(full.moved["B/L0/001"], ["trees"])
        let partial = try JSONDecoder().decode(NatureCorrections.self, from: Data(#"{"notNature":["A/L0/001"]}"#.utf8))
        XCTAssertEqual(partial.notNature, ["A/L0/001"])
        XCTAssertTrue(partial.moved.isEmpty)
    }

    // MARK: What the build itself carries

    func testEntitlementsMatchTheAllowlist() throws {
        try DataGuardSupport.assertEntitlements(target: "Rootbound")
        XCTAssertEqual(try DataGuardSupport.appGroups(target: "Rootbound"), [WellnessBridge.groupID])
    }

    func testEnglishPermissionTexts() {
        DataGuardSupport.assertEnglishInfoPlist()
    }
}
