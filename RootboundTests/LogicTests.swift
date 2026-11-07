import XCTest
import CoreLocation
@testable import Rootbound

final class GeoTests: XCTestCase {
    func testPlainCoordinates() {
        let c = Geo.parseCoordinates("37.2872, -121.9500")
        XCTAssertEqual(c?.latitude ?? 0, 37.2872, accuracy: 1e-6)
        XCTAssertEqual(c?.longitude ?? 0, -121.95, accuracy: 1e-6)
    }

    func testAppleMapsLink() {
        let c = Geo.parseCoordinates("https://maps.apple.com/?ll=37.28,-121.95&q=Dropped%20Pin")
        XCTAssertEqual(c?.latitude ?? 0, 37.28, accuracy: 1e-6)
        XCTAssertEqual(c?.longitude ?? 0, -121.95, accuracy: 1e-6)
    }

    func testGoogleMapsLinks() {
        XCTAssertEqual(Geo.parseCoordinates("https://www.google.com/maps/@37.2801,-121.9502,17z")?.latitude ?? 0, 37.2801, accuracy: 1e-6)
        XCTAssertEqual(Geo.parseCoordinates("https://maps.google.com/?q=37.1,-122.2")?.longitude ?? 0, -122.2, accuracy: 1e-6)
        XCTAssertEqual(Geo.parseCoordinates("https://www.google.com/maps/search/?api=1&query=37.5%2C-122.1")?.latitude ?? 0, 37.5, accuracy: 1e-6)
    }

    func testDMS() {
        let c = Geo.parseCoordinates("37°17'13.9\"N 121°57'00.0\"W")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.latitude ?? 0, 37.28719, accuracy: 1e-4)
        XCTAssertEqual(c?.longitude ?? 0, -121.95, accuracy: 1e-4)
    }

    func testRejectsJunk() {
        XCTAssertNil(Geo.parseCoordinates("https://maps.app.goo.gl/AbCdEf"))
        XCTAssertNil(Geo.parseCoordinates("hello"))
        XCTAssertNil(Geo.parseCoordinates("0, 0"))
        XCTAssertNil(Geo.parseCoordinates("95, 10"))
    }
}

final class GameTests: XCTestCase {
    func testLevelCurve() {
        XCTAssertEqual(GameEngine.level(for: 0).level, 1)
        XCTAssertEqual(GameEngine.level(for: 149).level, 1)
        XCTAssertEqual(GameEngine.level(for: 150).level, 2)
        XCTAssertEqual(GameEngine.level(for: 450).level, 3)
        let l = GameEngine.level(for: 600)
        XCTAssertEqual(l.level, 3)
        XCTAssertEqual(l.xpIntoLevel, 150)
        XCTAssertEqual(l.xpForNext, 450)
        XCTAssertEqual(GameEngine.level(for: 1_000_000).title, "Ancient One")
    }

    private func hug(daysAgo: Int, tree: UUID = UUID(), minutes: Double = 12, barefoot: Bool = false) -> Hug {
        let h = Hug()
        h.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        h.treeID = tree
        h.durationMin = minutes
        h.barefoot = barefoot
        return h
    }

    func testStreaks() {
        let hugs = [hug(daysAgo: 0), hug(daysAgo: 1), hug(daysAgo: 2), hug(daysAgo: 5)]
        XCTAssertEqual(GameEngine.currentStreak(hugs), 3)
        XCTAssertEqual(GameEngine.bestStreak(hugs), 3)
        XCTAssertEqual(GameEngine.currentStreak([hug(daysAgo: 1), hug(daysAgo: 2)]), 2, "yesterday still counts")
        XCTAssertEqual(GameEngine.currentStreak([hug(daysAgo: 3)]), 0)
        XCTAssertEqual(GameEngine.currentStreak([]), 0)
    }

    func testXPRewardsNewTreeAndBreathwork() {
        let tree = UUID()
        let first = hug(daysAgo: 0, tree: tree, minutes: 12, barefoot: true)
        let xp1 = GameEngine.xp(for: first, existing: [])
        XCTAssertTrue(xp1.lines.contains { $0.0 == "New tree friend" })
        XCTAssertTrue(xp1.lines.contains { $0.0 == "Barefoot grounding" })
        XCTAssertEqual(xp1.lines.first { $0.0.hasPrefix("Breathwork") }?.1, 60)
        let second = hug(daysAgo: 0, tree: tree, minutes: 0)
        let xp2 = GameEngine.xp(for: second, existing: [first])
        XCTAssertFalse(xp2.lines.contains { $0.0 == "New tree friend" })
        XCTAssertGreaterThan(xp1.total, xp2.total)
    }

    func testLeafDropIsStablePerHug() {
        let h = hug(daysAgo: 0)
        let a = GameEngine.rollLeaf(for: h).id
        for _ in 0..<5 { XCTAssertEqual(GameEngine.rollLeaf(for: h).id, a) }
        XCTAssertNotNil(LeafType.find(a))
    }

    func testLeafOddsAreSane() {
        var counts: [Rarity: Int] = [:]
        for _ in 0..<4000 { counts[GameEngine.rollLeaf(for: hug(daysAgo: 0)).rarity, default: 0] += 1 }
        XCTAssertGreaterThan(counts[.common] ?? 0, counts[.rare] ?? 0)
        XCTAssertGreaterThan(counts[.rare] ?? 0, counts[.epic] ?? 0)
        XCTAssertGreaterThan(counts[.epic] ?? 0, counts[.legendary] ?? 0)
        XCTAssertGreaterThan(counts[.legendary] ?? 0, 0)
    }

    func testBadgesUnlock() {
        let tree = UUID()
        let hugs = (0..<3).map { hug(daysAgo: $0, tree: tree, barefoot: true) }
        let badges = GameEngine.badges(hugs: hugs, activities: [])
        func earned(_ id: String) -> Bool { badges.first { $0.id == id }?.earned ?? false }
        XCTAssertTrue(earned("first-hug"))
        XCTAssertTrue(earned("barefoot"))
        XCTAssertTrue(earned("same-3"))
        XCTAssertTrue(earned("streak-3"))
        XCTAssertTrue(earned("twelve"))
        XCTAssertFalse(earned("hugs-25"))
        XCTAssertEqual(Set(badges.map(\.id)).count, badges.count, "badge ids must be unique")
    }
}

final class TrackingTests: XCTestCase {
    func testRoutePointSurvivesUnknownAltitude() throws {
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122), altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date())
        let p = RoutePoint(loc)
        XCTAssertTrue(p.alt.isNaN)
        let data = try JSONEncoder().encode([p])
        let back = try JSONDecoder().decode([RoutePoint].self, from: data)
        XCTAssertEqual(back.first?.lat, 37)
        XCTAssertTrue(back.first?.alt.isNaN ?? false)
    }

    func testSimplifyKeepsEnds() {
        let pts = (0..<10_000).map { i in
            RoutePoint(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37 + Double(i) * 1e-5, longitude: -122),
                                  altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                                  timestamp: Date(timeIntervalSince1970: Double(i))))
        }
        let s = RouteTracker.simplify(pts, maxCount: 4000)
        XCTAssertEqual(s.count, 4000)
        XCTAssertEqual(s.first, pts.first)
        XCTAssertEqual(s.last, pts.last)
        XCTAssertEqual(RouteTracker.simplify(Array(pts.prefix(10)), maxCount: 4000).count, 10)
    }

    func testFormatting() {
        UserDefaults.standard.set(false, forKey: "useMetric")
        XCTAssertEqual(Format.distance(1609.344), "1.00 mi")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.duration(65), "1:05")
        XCTAssertEqual(Format.paceOrSpeed(distance: 1609.344, seconds: 480, kind: .run), "8:00 /mi")
        XCTAssertEqual(Format.minutes(12), "12 min")
        XCTAssertEqual(Format.minutes(75), "1h 15m")
    }
}
