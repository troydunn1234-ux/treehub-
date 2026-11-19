import XCTest
@testable import Rootbound

/// The family connections built from several feed parts (Shared/Wellness/WellnessFamily.swift) and the new optional
/// tripTrees field of rootbound.json, which older Rootbound, Still Pointz and Roamr builds must keep decoding.
final class WellnessFamilyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_794_700_000)

    private func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
    private func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }

    private func trip(_ kind: String = "walk", start: Date, minutes: Double = 40, startAt: (Double, Double)? = nil,
                      endAt: (Double, Double)? = nil, id: UUID = UUID()) -> WellnessBridge.Trip {
        var t = WellnessBridge.Trip(id: id, kind: kind, start: start, end: start.addingTimeInterval(minutes * 60),
                                    distanceM: 3000, movingSec: minutes * 60, elevGainM: 10, avgSpeed: 1.2, topSpeed: 2)
        if let s = startAt { t.startLat = s.0; t.startLng = s.1 }
        if let e = endAt { t.endLat = e.0; t.endLng = e.1 }
        return t
    }

    // MARK: Feed decoding

    func testRootboundFeedWithoutTripTreesDecodes() throws {
        let json = #"{"updated":1794700000,"streak":2,"hugs":[{"id":"6E1F1C1A-0000-4000-8000-000000000004","date":1794690000,"minutes":4,"tree":"Grandpa Oak","species":"Valley Oak"}]}"#
        let part = try decoder().decode(WellnessBridge.RootboundPart.self, from: Data(json.utf8))
        XCTAssertNil(part.tripTrees)
        XCTAssertEqual(part.hugs.count, 1)
        XCTAssertTrue(WellnessConnect.trees(onTrip: UUID(), in: part).isEmpty)
    }

    func testRootboundFeedWithTripTreesRoundTrips() throws {
        let trip = UUID(), tree = UUID()
        let part = WellnessBridge.RootboundPart(updated: t0, streak: 1, hugs: [],
                                                tripTrees: [.init(tripID: trip, trees: [.init(treeID: tree, name: "Grandpa Oak", species: "Valley Oak", hugged: true)])])
        let back = try decoder().decode(WellnessBridge.RootboundPart.self, from: encoder().encode(part))
        XCTAssertEqual(back.tripTrees, part.tripTrees)
        XCTAssertEqual(WellnessConnect.trees(onTrip: trip, in: back).first?.name, "Grandpa Oak")
    }

    func testNearTreeWithOnlyIDAndNameDecodes() throws {
        let json = #"{"updated":1794700000,"streak":0,"hugs":[],"tripTrees":[{"tripID":"6E1F1C1A-0000-4000-8000-000000000010","trees":[{"treeID":"6E1F1C1A-0000-4000-8000-000000000011","name":"Elm"}]}]}"#
        let part = try decoder().decode(WellnessBridge.RootboundPart.self, from: Data(json.utf8))
        let t = try XCTUnwrap(part.tripTrees?.first?.trees.first)
        XCTAssertEqual(t.species, "")
        XCTAssertFalse(t.hugged)
    }

    /// The new field never carries a coordinate (the public feed shares tree ids and names only).
    func testTripTreesCarryNoCoordinates() throws {
        let part = WellnessBridge.RootboundPart(updated: t0, streak: 0, hugs: [],
                                                tripTrees: [.init(tripID: UUID(), trees: [.init(treeID: UUID(), name: "Oak")])])
        let text = String(decoding: try encoder().encode(part), as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("lat"))
        XCTAssertFalse(text.contains("lng"))
    }

    // MARK: Trees a trip passed

    func testTripTreesMatchesNearbyAndHuggedTrees() {
        let near = WellnessConnect.TreeSpot(id: UUID(), name: "Zelkova", species: "", lat: 37.2870, lng: -121.9500, hugTimes: [])
        let hugged = WellnessConnect.TreeSpot(id: UUID(), name: "Alder", species: "Red Alder", lat: nil, lng: nil,
                                              hugTimes: [(start: t0.addingTimeInterval(10 * 60), minutes: 3)])
        let far = WellnessConnect.TreeSpot(id: UUID(), name: "Far Pine", species: "", lat: 37.40, lng: -121.80, hugTimes: [])
        let walk = trip(start: t0, startAt: (37.287, -121.950), endAt: (37.30, -121.96))
        let drive = trip("drive", start: t0, startAt: (37.287, -121.950))
        let out = WellnessConnect.tripTrees(trees: [near, hugged, far], trips: [walk, drive])
        XCTAssertEqual(out.count, 1, "drives never pass trees")
        XCTAssertEqual(out.first?.tripID, walk.id)
        XCTAssertEqual(out.first?.trees.map(\.name), ["Alder", "Zelkova"], "hugged first, then by name")
        XCTAssertEqual(out.first?.trees.first?.hugged, true)
        XCTAssertEqual(out.first?.trees.last?.hugged, false)
    }

    func testTripTreesEmptyWithoutTrips() {
        let spot = WellnessConnect.TreeSpot(id: UUID(), name: "Oak", species: "", lat: 1, lng: 1, hugTimes: [])
        XCTAssertTrue(WellnessConnect.tripTrees(trees: [spot], trips: []).isEmpty)
    }

    // MARK: From your other apps

    func testFamilyItemsLeaveOutOwnAppOldItemsAndMissingApps() {
        let now = t0
        let sp = WellnessBridge.StillPointPart(updated: now, streak: 1, sessions: [
            .init(id: UUID(), date: now.addingTimeInterval(-3600), kind: "breath", minutes: 5),
            .init(id: UUID(), date: now.addingTimeInterval(-7200), kind: "breath", minutes: 4),
            .init(id: UUID(), date: now.addingTimeInterval(-9000), kind: "breath", minutes: 6),
            .init(id: UUID(), date: now.addingTimeInterval(-5 * 86400), kind: "breath", minutes: 9),
        ])
        let rb = WellnessBridge.RootboundPart(updated: now, streak: 1, hugs: [
            .init(id: UUID(), date: now.addingTimeInterval(-600), minutes: 6, tree: "Grandpa Oak", species: "Valley Oak", treeID: UUID()),
        ])
        let walk = trip(start: now.addingTimeInterval(-4000), minutes: 30)
        let rr = WellnessBridge.RoamrPart(updated: now, trips: [walk])

        let inRoamr = WellnessConnect.familyItems(for: WellnessConnect.roamr, now: now, metric: true,
                                                  stillPoint: sp, rootbound: rb, roamr: rr, pulseLab: nil)
        XCTAssertFalse(inRoamr.contains { $0.peer == WellnessConnect.roamr }, "never its own app")
        XCTAssertEqual(inRoamr.filter { $0.peer == WellnessConnect.stillPoint }.count, 2, "at most two per app")
        XCTAssertEqual(inRoamr.first?.title, "Hugged Grandpa Oak", "newest first")
        XCTAssertTrue(inRoamr.first?.url.absoluteString.hasPrefix("rootbound://tree?id=") == true)

        let inStillPoint = WellnessConnect.familyItems(for: WellnessConnect.stillPoint, now: now, metric: false,
                                                       installed: { $0 != WellnessConnect.roamr },
                                                       stillPoint: sp, rootbound: rb, roamr: rr, pulseLab: nil)
        XCTAssertEqual(inStillPoint.map(\.peer), [WellnessConnect.rootbound], "Roamr not installed, own sessions left out")
        XCTAssertTrue(inStillPoint.first?.detail.contains("grounding time here") == true)
    }

    func testFamilyWalkNamesTheTreesItPassed() {
        let walk = trip(start: t0.addingTimeInterval(-3600))
        let rb = WellnessBridge.RootboundPart(updated: t0, streak: 0, hugs: [],
                                              tripTrees: [.init(tripID: walk.id, trees: [.init(treeID: UUID(), name: "Oak"), .init(treeID: UUID(), name: "Elm")])])
        let items = WellnessConnect.familyItems(for: WellnessConnect.pulseLab, now: t0, metric: true, stillPoint: nil, rootbound: rb,
                                                roamr: .init(updated: t0, trips: [walk]), pulseLab: nil)
        XCTAssertEqual(items.first(where: { $0.peer == WellnessConnect.roamr })?.detail, "passed Oak +1")
    }

    func testFamilyPulseLabOnlyForToday() {
        var p = WellnessBridge.PulseLabPart(updated: t0, date: WellnessBridge.dayKey(t0))
        p.readiness = 74
        let today = WellnessConnect.familyItems(for: WellnessConnect.rootbound, now: t0, metric: true,
                                                stillPoint: nil, rootbound: nil, roamr: nil, pulseLab: p)
        XCTAssertEqual(today.first?.title, "Readiness 74")
        p.date = "2000-01-01"
        XCTAssertTrue(WellnessConnect.familyItems(for: WellnessConnect.rootbound, now: t0, metric: true,
                                                  stillPoint: nil, rootbound: nil, roamr: nil, pulseLab: p).isEmpty)
    }

    // MARK: Grounded time and time on foot

    func testDayLoadsDontCountLinkedHugsTwice() {
        let session = UUID()
        let sp = WellnessBridge.StillPointPart(updated: t0, streak: 0, sessions: [
            .init(id: session, date: t0, kind: "breath", minutes: 5),
            .init(id: UUID(), date: t0, kind: "sauna", minutes: 15),
        ])
        var linked = WellnessBridge.TreeHug(id: UUID(), date: t0, minutes: 5, tree: "Oak", species: "")
        linked.sessionIDs = [session]
        let alone = WellnessBridge.TreeHug(id: UUID(), date: t0, minutes: 3, tree: "Elm", species: "")
        let rb = WellnessBridge.RootboundPart(updated: t0, streak: 0, hugs: [linked, alone])
        let rr = WellnessBridge.RoamrPart(updated: t0, trips: [trip(start: t0, minutes: 30), trip("drive", start: t0, minutes: 60)])
        let loads = WellnessConnect.dayLoads(7, endingOn: t0, stillPoint: sp, rootbound: rb, roamr: rr)
        XCTAssertEqual(loads.count, 7)
        let today = try? XCTUnwrap(loads.last)
        XCTAssertEqual(today?.calmMin, 5, "sauna isn't calm practice")
        XCTAssertEqual(today?.hugMin, 3, "the linked hug is already in the session")
        XCTAssertEqual(today?.onFootMin, 30, "drives aren't on foot")
        XCTAssertEqual(loads.first?.groundedMin, 0)
    }

    func testCalmEffectNeedsEnoughDaysOnEachSide() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: t0)
        var loads: [WellnessConnect.DayLoad] = []
        var hrv: [Date: Double] = [:]
        for i in 0..<8 {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            loads.append(.init(day: d, calmMin: i.isMultiple(of: 2) ? 15 : 0))
            hrv[cal.date(byAdding: .day, value: 1, to: d)!] = i.isMultiple(of: 2) ? 60 : 50
        }
        let e = try? XCTUnwrap(WellnessConnect.calmEffect(loads, hrv: hrv))
        XCTAssertEqual(e?.afterCalm, 60)
        XCTAssertEqual(e?.afterOther, 50)
        XCTAssertEqual(e?.calmDays, 4)
        XCTAssertNil(WellnessConnect.calmEffect(Array(loads.prefix(4)), hrv: hrv), "two days a side says nothing")
    }
}
