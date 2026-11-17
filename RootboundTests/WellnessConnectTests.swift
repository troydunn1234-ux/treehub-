import XCTest
@testable import Rootbound

/// How the family apps' records line up (Shared/Wellness/WellnessConnect.swift): today across the apps, a walk and
/// its tree hugs / breathwork, a tree and the walks past it, a breath session and its tree, plus the feed staying
/// readable when a newer Rootbound adds fields. Sample places and names only.
final class WellnessConnectTests: XCTestCase {
    private let cal = Calendar.current
    /// Today at noon, local time (every offset used below stays inside one calendar day).
    private var noon: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }

    private func trip(_ kind: String, start: Date, minutes: Double, meters: Double,
                      startAt: (Double, Double)? = nil, endAt: (Double, Double)? = nil) -> WellnessBridge.Trip {
        var t = WellnessBridge.Trip(id: UUID(), kind: kind, start: start, end: start.addingTimeInterval(minutes * 60),
                                    distanceM: meters, movingSec: minutes * 60, elevGainM: 0,
                                    avgSpeed: meters / (minutes * 60), topSpeed: 2)
        t.startLat = startAt?.0
        t.startLng = startAt?.1
        t.endLat = endAt?.0
        t.endLng = endAt?.1
        return t
    }

    private func hug(_ tree: String, at date: Date, minutes: Double, treeID: UUID? = nil) -> WellnessBridge.TreeHug {
        WellnessBridge.TreeHug(id: UUID(), date: date, minutes: minutes, tree: tree, species: "", treeID: treeID)
    }

    // MARK: Today across the apps

    func testTodayAddsUpEachAppForThatDayOnly() {
        let day = noon
        let yesterday = day.addingTimeInterval(-86400)
        let sp = WellnessBridge.StillPointPart(updated: day, streak: 3, sessions: [
            .init(id: UUID(), date: day.addingTimeInterval(-3600), kind: "breath", minutes: 10),
            .init(id: UUID(), date: day.addingTimeInterval(-1800), kind: "mantra", minutes: 5),
            .init(id: UUID(), date: day.addingTimeInterval(-600), kind: "sauna", minutes: 15),
            .init(id: UUID(), date: yesterday, kind: "breath", minutes: 20),
        ])
        let rb = WellnessBridge.RootboundPart(updated: day, streak: 2, hugs: [
            hug("Old Oak", at: day.addingTimeInterval(-7200), minutes: 4),
            hug("Grandpa Oak", at: day.addingTimeInterval(-300), minutes: 2),
            hug("Elm", at: yesterday, minutes: 9),
        ])
        let rr = WellnessBridge.RoamrPart(updated: day, trips: [
            trip("walk", start: day.addingTimeInterval(-5400), minutes: 30, meters: 2000),
            trip("hike", start: day.addingTimeInterval(-9000), minutes: 40, meters: 3000),
            trip("drive", start: day.addingTimeInterval(-1000), minutes: 10, meters: 9000),
            trip("walk", start: yesterday, minutes: 30, meters: 2500),
        ])
        let pl = WellnessBridge.PulseLabPart(updated: day, date: WellnessBridge.dayKey(day), readiness: 71)

        let t = WellnessConnect.today(on: day, stillPoint: sp, rootbound: rb, roamr: rr, pulseLab: pl)
        // Calm minutes leave out sauna / steam and other days.
        XCTAssertEqual(t.calm?.minutes, 15)
        XCTAssertEqual(t.calm?.sessions, 2)
        XCTAssertEqual(t.hugs?.count, 2)
        XCTAssertEqual(t.hugs?.minutes, 6)
        XCTAssertEqual(t.hugs?.lastTree, "Grandpa Oak")
        // On foot only: no drives.
        XCTAssertEqual(t.moves?.distanceM, 5000)
        XCTAssertEqual(t.moves?.trips, 2)
        XCTAssertEqual(t.ready?.readiness, 71)
        XCTAssertEqual(t.ready?.isToday, true)
    }

    func testMissingAppsStayEmptyAndYesterdaysReadinessIsNotToday() {
        let day = noon
        let earlier = day.addingTimeInterval(-86400)
        let old = WellnessBridge.PulseLabPart(updated: earlier, date: WellnessBridge.dayKey(earlier),
                                              whoopRecovery: 80, readiness: 70)
        let t = WellnessConnect.today(on: day, stillPoint: nil, rootbound: nil, roamr: nil, pulseLab: old)
        XCTAssertNil(t.calm)
        XCTAssertNil(t.hugs)
        XCTAssertNil(t.moves)
        XCTAssertEqual(t.ready?.isToday, false)
        XCTAssertNil(t.ready?.readiness)
        XCTAssertNil(t.ready?.recovery)
    }

    // MARK: A walk, its tree hugs and the breathwork after it (Roamr trip detail)

    func testHugsOnATripOverlapItOrAreLinkedToIt() {
        let start = noon.addingTimeInterval(-4 * 3600), end = start.addingTimeInterval(3600)
        let tripID = UUID()
        let before = hug("Before", at: start.addingTimeInterval(-3600), minutes: 10)
        let during = hug("During", at: start.addingTimeInterval(1200), minutes: 3)
        let justAfter = hug("Just after", at: end.addingTimeInterval(600), minutes: 2)
        let later = hug("Later", at: end.addingTimeInterval(2 * 3600), minutes: 2)
        var linked = hug("Linked", at: end.addingTimeInterval(3 * 3600), minutes: 2)
        linked.walkIDs = [tripID]

        let found = WellnessConnect.hugs(onTrip: tripID, start: start, end: end,
                                         in: [later, linked, justAfter, during, before])
        XCTAssertEqual(found.map(\.tree), ["During", "Just after", "Linked"])
    }

    func testBreathworkDuringOrWithinHalfAnHourAfter() {
        let start = noon.addingTimeInterval(-4 * 3600), end = start.addingTimeInterval(3600)
        let sessions: [WellnessBridge.Session] = [
            .init(id: UUID(), date: start.addingTimeInterval(1800), kind: "breath", minutes: 5),
            .init(id: UUID(), date: end.addingTimeInterval(10 * 60), kind: "breath", minutes: 6),
            .init(id: UUID(), date: end.addingTimeInterval(45 * 60), kind: "breath", minutes: 6),
            .init(id: UUID(), date: end.addingTimeInterval(5 * 60), kind: "sauna", minutes: 15),
            .init(id: UUID(), date: end.addingTimeInterval(2 * 60), kind: "breath", minutes: 0.5),
            .init(id: UUID(), date: start.addingTimeInterval(-600), kind: "breath", minutes: 5),
        ]
        let found = WellnessConnect.breaths(forTrip: start, end: end, in: sessions)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.first?.during, true)
        XCTAssertEqual(found.first?.minutesAfter, 0)
        XCTAssertEqual(found.last?.during, false)
        XCTAssertEqual(found.last?.minutesAfter, 10)
    }

    // MARK: A tree and the walks that passed it (Rootbound tree page)

    func testWalksPassingATree() {
        let hugTime = noon.addingTimeInterval(-3 * 3600)
        let hugged = trip("walk", start: hugTime.addingTimeInterval(-600), minutes: 30, meters: 1500)
        let startedNear = trip("hike", start: noon.addingTimeInterval(-86400), minutes: 60, meters: 4000,
                               startAt: (45.001, 7.0), endAt: (45.03, 7.03))
        let endedNear = trip("run", start: noon.addingTimeInterval(-2 * 86400), minutes: 20, meters: 3000,
                             startAt: (45.02, 7.02), endAt: (45.0, 7.002))
        let far = trip("walk", start: noon.addingTimeInterval(-3 * 86400), minutes: 20, meters: 1000,
                       startAt: (45.01, 7.0), endAt: (45.01, 7.0))
        let drive = trip("drive", start: hugTime, minutes: 10, meters: 8000, startAt: (45.0, 7.0), endAt: (45.0, 7.0))

        let found = WellnessConnect.tripsPassing(treeLat: 45.0, treeLng: 7.0, hugTimes: [(start: hugTime, minutes: 5)],
                                                 in: [far, drive, endedNear, startedNear, hugged])
        XCTAssertEqual(found.map(\.id), [hugged.id, startedNear.id, endedNear.id])
        XCTAssertEqual(found.map(\.reason), [.hugged, .startedNear, .endedNear])

        // A tree without a location still finds the walk it was hugged on.
        let noPlace = WellnessConnect.tripsPassing(treeLat: nil, treeLng: nil, hugTimes: [(start: hugTime, minutes: 5)],
                                                   in: [far, endedNear, startedNear, hugged])
        XCTAssertEqual(noPlace.map(\.id), [hugged.id])
    }

    // MARK: A breath session and its tree (Still Pointz session page)

    func testSessionTreeUsesRootboundsCurrentName() {
        let treeID = UUID(), sessionID = UUID()
        let start = noon.addingTimeInterval(-2 * 3600), end = start.addingTimeInterval(300)
        let old = hug("Big Oak", at: noon.addingTimeInterval(-7 * 86400), minutes: 3, treeID: treeID)
        let renamed = hug("Grandpa Oak", at: noon.addingTimeInterval(-86400), minutes: 4, treeID: treeID)

        // Started from "Breathe with this tree" under the old name: shows the name Rootbound uses now.
        let tagged = WellnessConnect.tree(forSession: sessionID, start: start, end: end, taggedTreeID: treeID.uuidString,
                                          taggedName: "Big Oak", in: [old, renamed])
        XCTAssertEqual(tagged?.name, "Grandpa Oak")
        XCTAssertEqual(tagged?.how, .tagged)
        XCTAssertEqual(tagged?.hugCount, 2)
        XCTAssertEqual(tagged?.treeID, treeID)

        // Linked to a hug in Rootbound wins.
        var linkedHug = hug("Willow", at: start.addingTimeInterval(-3600), minutes: 2, treeID: UUID())
        linkedHug.sessionIDs = [sessionID]
        let linked = WellnessConnect.tree(forSession: sessionID, start: start, end: end, taggedTreeID: treeID.uuidString,
                                          taggedName: "Big Oak", in: [old, renamed, linkedHug])
        XCTAssertEqual(linked?.name, "Willow")
        XCTAssertEqual(linked?.how, .linked)

        // Nothing tagged, but a hug at the same time.
        let overlapping = hug("Sycamore", at: start.addingTimeInterval(60), minutes: 5)
        let sameTime = WellnessConnect.tree(forSession: UUID(), start: start, end: end, taggedTreeID: nil,
                                            taggedName: nil, in: [old, overlapping])
        XCTAssertEqual(sameTime?.name, "Sycamore")
        XCTAssertEqual(sameTime?.how, .sameTime)

        // Nothing to go on: no card.
        XCTAssertNil(WellnessConnect.tree(forSession: UUID(), start: start, end: end, taggedTreeID: nil,
                                          taggedName: nil, in: [old]))
    }

    // MARK: Wording and the feed format

    func testUpdatedText() {
        let now = noon
        XCTAssertEqual(WellnessConnect.updatedText(now.addingTimeInterval(-30), now: now), "updated just now")
        XCTAssertEqual(WellnessConnect.updatedText(now.addingTimeInterval(-5 * 60), now: now), "updated 5 min ago")
        XCTAssertEqual(WellnessConnect.updatedText(now.addingTimeInterval(-3 * 3600), now: now), "updated 3 h ago")
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let yesterdayMorning = cal.date(byAdding: .day, value: -1, to: morning)!
        XCTAssertEqual(WellnessConnect.updatedText(yesterdayMorning, now: now), "updated yesterday")
    }

    func testFormatting() {
        XCTAssertEqual(WellnessConnect.distance(0, metric: false), "0 mi")
        XCTAssertEqual(WellnessConnect.distance(50, metric: true), "0.1 km")
        XCTAssertEqual(WellnessConnect.distance(3862.4, metric: false), "2.4 mi")
        XCTAssertEqual(WellnessConnect.distance(3900, metric: true), "3.9 km")
        XCTAssertEqual(WellnessConnect.minutes(12.4), "12 min")
        XCTAssertEqual(WellnessConnect.minutes(65), "1 h 05 min")
    }

    /// Older feeds (no session / walk links) still decode, and the new links round-trip.
    func testTreeHugLinksAreOptionalInTheFeed() throws {
        let id = UUID(), treeID = UUID()
        let json = """
        {"updated": 1700000000, "streak": 2, "hugs": [{"id": "\(id.uuidString)", "date": 1700000000, "minutes": 3,
         "tree": "Oak", "species": "Valley Oak", "treeID": "\(treeID.uuidString)"}]}
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        let part = try dec.decode(WellnessBridge.RootboundPart.self, from: Data(json.utf8))
        XCTAssertEqual(part.hugs.first?.id, id)
        XCTAssertEqual(part.hugs.first?.treeID, treeID)
        XCTAssertNil(part.hugs.first?.sessionIDs)
        XCTAssertNil(part.hugs.first?.walkIDs)

        var linked = try XCTUnwrap(part.hugs.first)
        linked.sessionIDs = [UUID()]
        linked.walkIDs = [UUID()]
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let back = try dec.decode(WellnessBridge.TreeHug.self, from: enc.encode(linked))
        XCTAssertEqual(back, linked)
    }
}
