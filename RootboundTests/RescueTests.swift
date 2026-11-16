import XCTest
import SwiftData
@testable import Rootbound

/// The Nov 15 rescue (HugRescue / GroupStoreRescue): copies must keep every stored field, and reading the stray
/// store must never change it.
@MainActor
final class RescueTests: XCTestCase {

    private func storedNames(_ schema: Schema, _ entity: String) -> Set<String> {
        guard let e = schema.entities.first(where: { $0.name == entity }) else { return [] }
        return Set(e.attributes.map(\.name))
    }

    func testHugCopyCoversEveryStoredProperty() {
        let names = storedNames(Schema([Hug.self]), "Hug")
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names, HugRescue.copiedProperties,
                       "Hug gained or lost a stored field: update HugRescue.copy(of:) and copiedProperties.")
    }

    func testActivityCopyCoversEveryStoredProperty() {
        let names = storedNames(Schema([Activity.self]), "Activity")
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names, Activity.copiedProperties,
                       "Activity gained or lost a stored field: update Activity.copy(of:) and copiedProperties.")
    }

    private func sampleHug() -> Hug {
        let h = Hug()
        h.date = Date(timeIntervalSince1970: 1_794_700_000)
        h.treeID = UUID()
        h.treeName = "Creek Oak"
        h.species = "Valley oak"
        h.latitude = 37.77
        h.longitude = -122.45
        h.placeName = "Golden Gate Park"
        h.treePhoto = Data([1, 2, 3])
        h.selfiePhoto = Data([4, 5])
        h.garminPhoto = Data([6])
        h.tagsRaw = "sober,chill"
        h.barefoot = true
        h.feetInWater = true
        h.waterSetting = "edge"
        h.weather = "Fog"
        h.moodBefore = 2
        h.moodAfter = 5
        h.notes = "Quiet morning"
        h.exercise = "Rooted Breath"
        h.durationMin = 7.5
        h.avgHR = 64
        h.minHR = 58
        h.maxHR = 80
        h.respRate = 6.2
        h.stressStart = 40
        h.stressEnd = 20
        h.bodyBattery = 70
        h.hrStart = 72
        h.hrEnd = 60
        h.hrv = 55
        h.fromWatch = true
        h.linkedSessions = [LinkedSession(start: h.date, end: h.date.addingTimeInterval(300), source: "Still Pointz",
                                          practice: "rooted-breath")]
        h.strollID = UUID()
        h.linkedWalks = []
        h.xp = 185
        h.leafKey = "golden-oak"
        return h
    }

    func testHugCopyKeepsEveryValue() {
        let o = sampleHug()
        let c = HugRescue.copy(of: o)
        XCTAssertEqual(c.id, o.id); XCTAssertEqual(c.date, o.date); XCTAssertEqual(c.treeID, o.treeID)
        XCTAssertEqual(c.treeName, o.treeName); XCTAssertEqual(c.species, o.species)
        XCTAssertEqual(c.latitude, o.latitude); XCTAssertEqual(c.longitude, o.longitude); XCTAssertEqual(c.placeName, o.placeName)
        XCTAssertEqual(c.treePhoto, o.treePhoto); XCTAssertEqual(c.selfiePhoto, o.selfiePhoto); XCTAssertEqual(c.garminPhoto, o.garminPhoto)
        XCTAssertEqual(c.tagsRaw, o.tagsRaw); XCTAssertEqual(c.barefoot, o.barefoot); XCTAssertEqual(c.feetInWater, o.feetInWater)
        XCTAssertEqual(c.waterSetting, o.waterSetting); XCTAssertEqual(c.weather, o.weather)
        XCTAssertEqual(c.moodBefore, o.moodBefore); XCTAssertEqual(c.moodAfter, o.moodAfter); XCTAssertEqual(c.notes, o.notes)
        XCTAssertEqual(c.exercise, o.exercise); XCTAssertEqual(c.durationMin, o.durationMin)
        XCTAssertEqual(c.avgHR, o.avgHR); XCTAssertEqual(c.minHR, o.minHR); XCTAssertEqual(c.maxHR, o.maxHR)
        XCTAssertEqual(c.respRate, o.respRate); XCTAssertEqual(c.stressStart, o.stressStart); XCTAssertEqual(c.stressEnd, o.stressEnd)
        XCTAssertEqual(c.bodyBattery, o.bodyBattery); XCTAssertEqual(c.hrStart, o.hrStart); XCTAssertEqual(c.hrEnd, o.hrEnd)
        XCTAssertEqual(c.hrv, o.hrv); XCTAssertEqual(c.fromWatch, o.fromWatch)
        XCTAssertEqual(c.linkedSessionsData, o.linkedSessionsData); XCTAssertEqual(c.strollID, o.strollID)
        XCTAssertEqual(c.linkedWalksData, o.linkedWalksData); XCTAssertEqual(c.xp, o.xp); XCTAssertEqual(c.leafKey, o.leafKey)
    }

    func testSameHugDetection() {
        let a = sampleHug()
        let twin = HugRescue.copy(of: a)
        XCTAssertTrue(HugRescue.isSame(a, twin))

        let relogged = Hug()                      // logged again by hand from the same photo
        relogged.treeID = a.treeID
        relogged.date = a.date.addingTimeInterval(30)
        XCTAssertTrue(HugRescue.isSame(a, relogged))

        let other = Hug()                         // another tree, an hour later
        other.treeName = "Pine"
        other.date = a.date.addingTimeInterval(3600)
        XCTAssertFalse(HugRescue.isSame(a, other))
    }

    /// Writes a store like the stray shared one and reads it through a private copy in another folder: the hugs
    /// (photos included) come through, and only new ones are added to the main store.
    func testPrivateCopyReadsHugsAndLeavesOriginalAlone() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "rescue-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")
        let schema = Schema([Hug.self, Activity.self])

        var written: [UUID] = []
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none))
            let ctx = ModelContext(container)
            for i in 0..<3 {
                let h = sampleHug()
                h.treeName = "Tree \(i)"
                h.treePhoto = Data(repeating: UInt8(i), count: 200_000)   // big enough to live outside the database
                ctx.insert(h)
                written.append(h.id)
            }
            try ctx.save()
        }
        let copy = try GroupStoreRescue.makePrivateCopy(of: storeURL)
        defer { GroupStoreRescue.discard(copy) }
        XCTAssertNotEqual(copy.deletingLastPathComponent(), dir)
        let old = try GroupStoreRescue.openCopy(copy, schema: schema)
        let hugs = try ModelContext(old).fetch(FetchDescriptor<Hug>())
        XCTAssertEqual(Set(hugs.map(\.id)), Set(written))
        XCTAssertTrue(hugs.allSatisfy { ($0.treePhoto?.count ?? 0) == 200_000 }, "photos kept outside the database must come along")

        // Bring them into another store, skipping ones already there.
        let main = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let mainCtx = ModelContext(main)
        mainCtx.insert(HugRescue.copy(of: hugs[0]))
        var here = try mainCtx.fetch(FetchDescriptor<Hug>())
        var restored = 0
        for h in hugs where !here.contains(where: { HugRescue.isSame($0, h) }) {
            let n = HugRescue.copy(of: h)
            mainCtx.insert(n); here.append(n); restored += 1
        }
        try mainCtx.save()
        XCTAssertEqual(restored, 2)
        XCTAssertEqual(try mainCtx.fetch(FetchDescriptor<Hug>()).count, 3)
    }

    func testActivityCopyKeepsEveryValue() {
        let o = Activity()
        o.kindRaw = "hike"; o.title = "Ridge loop"
        o.start = Date(timeIntervalSince1970: 1_794_700_000); o.end = o.start.addingTimeInterval(3600)
        o.distanceM = 5200; o.movingSec = 3300; o.elevGainM = 240; o.maxSpeed = 2.4
        o.startPlace = "Trailhead"; o.endPlace = "Trailhead"; o.notes = "Windy"; o.avgHR = 118
        o.routeData = Data([9, 9, 9]); o.laneChangesData = Data([1]); o.trimmedSec = 42; o.autoFinished = true
        let c = Activity.copy(of: o)
        XCTAssertEqual(c.id, o.id); XCTAssertEqual(c.kindRaw, o.kindRaw); XCTAssertEqual(c.title, o.title)
        XCTAssertEqual(c.start, o.start); XCTAssertEqual(c.end, o.end); XCTAssertEqual(c.distanceM, o.distanceM)
        XCTAssertEqual(c.movingSec, o.movingSec); XCTAssertEqual(c.elevGainM, o.elevGainM); XCTAssertEqual(c.maxSpeed, o.maxSpeed)
        XCTAssertEqual(c.startPlace, o.startPlace); XCTAssertEqual(c.endPlace, o.endPlace); XCTAssertEqual(c.notes, o.notes)
        XCTAssertEqual(c.avgHR, o.avgHR); XCTAssertEqual(c.routeData, o.routeData); XCTAssertEqual(c.laneChangesData, o.laneChangesData)
        XCTAssertEqual(c.trimmedSec, o.trimmedSec); XCTAssertEqual(c.autoFinished, o.autoFinished)
    }
}
