import XCTest
import CoreLocation
@testable import Roamr

/// Pinned places and commutes: pure math, made-up coordinates.
final class CommuteTests: XCTestCase {
    private let home = CommutePin(role: .home, place: NavPlace(name: "Home", subtitle: "", coordinate: .init(latitude: 37.70, longitude: -122.40)))
    private let work = CommutePin(role: .work, place: NavPlace(name: "Work", subtitle: "", coordinate: .init(latitude: 37.75, longitude: -122.35)))
    private let gym = CommutePin(role: .custom, place: NavPlace(name: "Gym", subtitle: "", coordinate: .init(latitude: 37.72, longitude: -122.45)))
    private var pins: [CommutePin] { [home, work, gym] }

    /// ~100 m north-east of a coordinate: still "at" the pin.
    private func near(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D { .init(latitude: c.latitude + 0.0007, longitude: c.longitude + 0.0005) }

    private func trip(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D, start: Date, minutes: Double, miles: Double) -> CommuteMath.Trip {
        CommuteMath.Trip(id: UUID(), start: start, seconds: minutes * 60, meters: miles * 1609.344, from: from, to: to)
    }

    func testTitles() {
        XCTAssertEqual(CommuteMath.title(from: near(home.coordinate), to: work.coordinate, pins: pins), "Home → Work")
        XCTAssertEqual(CommuteMath.title(from: work.coordinate, to: gym.coordinate, pins: pins), "Work → Gym")
        let elsewhere = CLLocationCoordinate2D(latitude: 37.60, longitude: -122.20)
        XCTAssertEqual(CommuteMath.title(from: elsewhere, to: work.coordinate, pins: pins), "To Work")
        XCTAssertEqual(CommuteMath.title(from: home.coordinate, to: elsewhere, pins: pins), "From Home")
        XCTAssertNil(CommuteMath.title(from: home.coordinate, to: near(home.coordinate), pins: pins), "a loop from home isn't a commute")
        XCTAssertNil(CommuteMath.title(from: elsewhere, to: elsewhere, pins: pins))
    }

    func testRoutesGroupBothDirectionsWithStats() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 20))!   // a Thursday
        let mon = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 8))!
        let trips = [
            trip(home.coordinate, work.coordinate, start: mon, minutes: 20, miles: 9),
            trip(near(work.coordinate), home.coordinate, start: mon.addingTimeInterval(9 * 3600), minutes: 30, miles: 10),
            trip(home.coordinate, near(work.coordinate), start: mon.addingTimeInterval(86_400), minutes: 16, miles: 8),
            trip(home.coordinate, work.coordinate, start: mon.addingTimeInterval(-7 * 86_400), minutes: 22, miles: 9),   // last week
            trip(home.coordinate, gym.coordinate, start: mon, minutes: 10, miles: 3),
            trip(home.coordinate, .init(latitude: 37.6, longitude: -122.2), start: mon, minutes: 40, miles: 20),          // not a commute
        ]
        let routes = CommuteMath.routes(trips, pins: pins)
        XCTAssertEqual(routes.count, 2)
        let r = routes[0]
        XCTAssertEqual(r.a.id, home.id, "Home reads first")
        XCTAssertEqual(r.b.id, work.id)
        XCTAssertEqual(r.title, "Home ⇄ Work")
        XCTAssertEqual(r.legs.count, 4)
        XCTAssertEqual(r.legs(from: home).count, 3)
        XCTAssertEqual(r.legs(from: work).count, 1)

        let s = r.stats(now: now, calendar: cal)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.thisWeek, 3)
        XCTAssertEqual(try XCTUnwrap(s.bestSeconds), 16 * 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.avgSeconds), (20 + 30 + 16 + 22) / 4.0 * 60, accuracy: 0.001)
        XCTAssertEqual(s.weekMeters, 27 * 1609.344, accuracy: 0.01)
        XCTAssertEqual(routes[1].title, "Home ⇄ Gym")
    }

    func testFuelCost() throws {
        // 10 miles at 20 MPG and $5/gal = $2.50
        XCTAssertEqual(try XCTUnwrap(CommuteMath.fuelCost(meters: 10 * 1609.344, mpg: 20, pricePerGallon: 5)), 2.5, accuracy: 0.0001)
        XCTAssertNil(CommuteMath.fuelCost(meters: 1000, mpg: 0, pricePerGallon: 5))
    }

    func testSuggestsASpotAfterThreeVisits() {
        let spot = CLLocationCoordinate2D(latitude: 37.80, longitude: -122.30)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var trips = [
            trip(home.coordinate, spot, start: start, minutes: 15, miles: 7),
            trip(near(spot), home.coordinate, start: start.addingTimeInterval(3600), minutes: 15, miles: 7),
        ]
        XCTAssertTrue(CommuteMath.frequentSpots(trips, pins: pins).isEmpty, "twice isn't a habit yet")
        trips.append(trip(work.coordinate, spot, start: start.addingTimeInterval(86_400), minutes: 12, miles: 5))
        let spots = CommuteMath.frequentSpots(trips, pins: pins)
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots[0].count, 3)
        XCTAssertLessThan(CommuteMath.meters(spots[0].coordinate, spot), 100)
        // Once it's pinned it isn't suggested again.
        let pinned = CommutePin(role: .custom, place: NavPlace(name: "Her place", subtitle: "", coordinate: spot))
        XCTAssertTrue(CommuteMath.frequentSpots(trips, pins: pins + [pinned]).isEmpty)
    }

    /// A trip's ends are remembered by end time and distance (no route read on a repeat call), and a trim, which
    /// changes both, gives the new end.
    @MainActor
    func testTripEndsFollowATrim() throws {
        let t0 = 1_790_000_000.0
        let pts: [RoutePoint] = (0..<40).map { (i: Int) -> RoutePoint in
            RoutePoint(CLLocation(coordinate: .init(latitude: 37.70 + Double(i) * 0.001, longitude: -122.40), altitude: 10,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 10,
                                  timestamp: Date(timeIntervalSince1970: t0 + Double(i) * 10)))
        }
        let a = Activity()
        a.kind = .drive
        a.route = pts
        a.start = Date(timeIntervalSince1970: t0)
        a.end = Date(timeIntervalSince1970: t0 + 390)
        a.distanceM = 4300
        let first = try XCTUnwrap(CommuteStore.trip(a))
        XCTAssertEqual(first.to.latitude, pts[39].lat, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(CommuteStore.trip(a)).to.latitude, pts[39].lat, accuracy: 1e-9)

        a.trim(endT: pts[19].t)
        let trimmed = try XCTUnwrap(CommuteStore.trip(a))
        XCTAssertEqual(trimmed.to.latitude, pts[19].lat, accuracy: 1e-9, "a trim moves the end")
        XCTAssertEqual(trimmed.from.latitude, pts[0].lat, accuracy: 1e-9)

        let noRoute = Activity()
        noRoute.kind = .drive
        XCTAssertNil(CommuteStore.trip(noRoute))
    }
}
