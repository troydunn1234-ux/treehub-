import XCTest
import SwiftData
@testable import Roamr

/// "Paste fill-ups": the note parser and how pasted tanks feed MPG. All numbers are made up.
final class FillUpPasteTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    /// Nov 19, 2026, 9:00 local.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9))! }

    private func day(_ d: Date) -> DateComponents { cal.dateComponents([.year, .month, .day, .hour, .minute], from: d) }

    /// The four shapes a note line comes in: tank label, $ total, miles and gallons in any order, date, optional time.
    private let note = """
    tank #1 $131.70 298 miles 23.9 gallons 9/14
    tank 2 $139 24.8 gallons 301 miles
    tank 3 $139 24.1 gallons 10/05 309 miles
    tank 5 10/23 6pm $139 25.2 gallons 262 miles
    """

    func testReadsEveryFieldInAnyOrder() throws {
        let lines = FillUpPaste.parse(note, now: now, calendar: cal)
        XCTAssertEqual(lines.count, 4)

        let a = lines[0]
        XCTAssertEqual(a.tank, 1)
        XCTAssertEqual(try XCTUnwrap(a.total), 131.70, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(a.miles), 298, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(a.gallons), 23.9, accuracy: 0.001)
        XCTAssertFalse(a.dateGuessed)
        XCTAssertEqual(day(a.date).year, 2026)
        XCTAssertEqual(day(a.date).month, 9)
        XCTAssertEqual(day(a.date).day, 14)
        XCTAssertEqual(day(a.date).hour, 12, "no time on the line: noon")

        let c = lines[2]
        XCTAssertEqual(c.tank, 3)
        XCTAssertEqual(try XCTUnwrap(c.total), 139, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(c.gallons), 24.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(c.miles), 309, accuracy: 0.001)
        XCTAssertEqual(day(c.date).month, 10)
        XCTAssertEqual(day(c.date).day, 5)

        let d = lines[3]
        XCTAssertEqual(d.tank, 5)
        XCTAssertEqual(day(d.date).month, 10)
        XCTAssertEqual(day(d.date).day, 23)
        XCTAssertEqual(day(d.date).hour, 18, "6pm")
        XCTAssertEqual(try XCTUnwrap(d.gallons), 25.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(d.miles), 262, accuracy: 0.001)
    }

    func testMissingDateIsGuessedBetweenNeighbours() {
        let lines = FillUpPaste.parse(note, now: now, calendar: cal)
        let b = lines[1]
        XCTAssertTrue(b.dateGuessed)
        XCTAssertTrue(b.warnings(calendar: cal).contains(.dateGuessed))
        XCTAssertGreaterThan(b.date, lines[0].date)
        XCTAssertLessThan(b.date, lines[2].date)
        XCTAssertEqual(b.tank, 2)
    }

    func testPricePerGallonAndMPG() throws {
        let a = FillUpPaste.parse(note, now: now, calendar: cal)[0]
        XCTAssertEqual(try XCTUnwrap(a.pricePerGallon), 131.70 / 23.9, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(a.mpg), 298 / 23.9, accuracy: 0.0001)
        XCTAssertTrue(a.warnings(calendar: cal).isEmpty)
    }

    func testUnlikelyMPGFlagsTypo() throws {
        let line = try XCTUnwrap(FillUpPaste.parse("tank 7 $120 22.0 gallons 3.3 miles 11/02", now: now, calendar: cal).first)
        XCTAssertEqual(try XCTUnwrap(line.miles), 3.3, accuracy: 0.001)
        XCTAssertTrue(line.warnings(calendar: cal).contains { if case .unlikelyMPG = $0 { return true } else { return false } })
    }

    func testDateInTheFutureMeansLastYear() throws {
        let line = try XCTUnwrap(FillUpPaste.parse("$90 20 gal 12/28", now: now, calendar: cal).first)
        XCTAssertEqual(day(line.date).year, 2025)
        let explicit = try XCTUnwrap(FillUpPaste.parse("$90 20 gal 3/4/25 7:15 am", now: now, calendar: cal).first)
        XCTAssertEqual(day(explicit.date).year, 2025)
        XCTAssertEqual(day(explicit.date).hour, 7)
        XCTAssertEqual(day(explicit.date).minute, 15)
    }

    func testSkipsLinesThatAreNotFillUps() {
        let lines = FillUpPaste.parse("Gas log\n\nremember oil change\ntank 9 $40 9.8 gal\n$12 coffee", now: now, calendar: cal)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].warnings(calendar: cal).contains(.missingMiles))
    }

    func testDuplicateIsSameDayAndTotal() throws {
        let a = FillUpPaste.parse(note, now: now, calendar: cal)[0]
        let existing = [(date: a.date.addingTimeInterval(3600), total: 131.70)]
        XCTAssertTrue(a.warnings(existing: existing, calendar: cal).contains(.duplicate))
        let otherDay = [(date: a.date.addingTimeInterval(-86_400 * 2), total: 131.70)]
        XCTAssertFalse(a.warnings(existing: otherDay, calendar: cal).contains(.duplicate))
        let otherTotal = [(date: a.date, total: 131.71)]
        XCTAssertFalse(a.warnings(existing: otherTotal, calendar: cal).contains(.duplicate))
    }

    // MARK: Trip miles feed MPG

    /// Models need a container to live in (in memory, test-only).
    private var container: ModelContainer?

    override func setUpWithError() throws {
        container = try ModelContainer(for: Activity.self, GasVehicle.self, FillUp.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    func testTripMilesGiveMPGForEveryTank() throws {
        let car = UUID()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let f1 = FillUp(vehicleID: car, date: base, gallons: 20, pricePerGallon: 0, total: 90, odometer: nil, station: "")
        f1.tripMiles = 300
        let f2 = FillUp(vehicleID: car, date: base.addingTimeInterval(86_400 * 7), gallons: 25, pricePerGallon: 0, total: 110,
                        odometer: nil, station: "")
        f2.tripMiles = 250
        let points = GasMath.mpg(fills: [f2, f1], drives: [])
        XCTAssertEqual(points.count, 2, "the first tank gets an MPG too when its miles are noted")
        XCTAssertEqual(points[0].mpg, 15, accuracy: 0.0001)
        XCTAssertEqual(points[1].mpg, 10, accuracy: 0.0001)
        XCTAssertTrue(points.allSatisfy(\.fromTrip))

        let e = try XCTUnwrap(GasMath.fuelEconomy(fills: [f1, f2], drives: []))
        XCTAssertEqual(e.mpg, 550.0 / 45.0, accuracy: 0.0001)
        XCTAssertEqual(e.pricePerGallon, 110.0 / 25.0, accuracy: 0.0001)
    }

    @MainActor
    func testOdometerFillUpsStillWork() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let a = FillUp(vehicleID: nil, date: base, gallons: 10, pricePerGallon: 4, total: 0, odometer: 1000, station: "")
        let b = FillUp(vehicleID: nil, date: base.addingTimeInterval(86_400), gallons: 10, pricePerGallon: 4, total: 0,
                       odometer: 1300, station: "")
        let points = GasMath.mpg(fills: [a, b], drives: [])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].mpg, 30, accuracy: 0.0001)
        XCTAssertFalse(points[0].fromTrip)
    }

    /// A fill-up whose vehicle isn't on this iPhone (not synced yet, or from an older build) used to show under no
    /// vehicle at all: the Gas & MPG screen, the Stats fuel card and commute costs all lost it.
    @MainActor
    func testFillUpsOfAMissingVehicleStillShow() {
        let truck = GasVehicle(name: "Truck"), van = GasVehicle(name: "Van")
        let vehicles = [truck, van]
        let missing = UUID()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func fill(_ vehicle: UUID?, day: Double) -> FillUp {
            FillUp(vehicleID: vehicle, date: base.addingTimeInterval(day * 86_400), gallons: 10, pricePerGallon: 4,
                   total: 0, odometer: nil, station: "")
        }
        let truckFill = fill(truck.id, day: 0), noVehicle = fill(nil, day: 1), orphan = fill(missing, day: 2)
        let vanFill = fill(van.id, day: 3)
        let all = [truckFill, noVehicle, orphan, vanFill]

        let first = Set(GasMath.fills(for: truck.id, all: all, vehicles: vehicles).map(\.id))
        XCTAssertEqual(first, [truckFill.id, noVehicle.id, orphan.id], "without a known vehicle: the first vehicle's")
        XCTAssertEqual(GasMath.fills(for: van.id, all: all, vehicles: vehicles).map(\.id), [vanFill.id])
        // Every fill-up shows under exactly one vehicle.
        XCTAssertEqual(first.count + 1, all.count)
        // A picked vehicle that isn't there any more means the first, like the screen's picker.
        XCTAssertEqual(Set(GasMath.fills(for: missing, all: all, vehicles: vehicles).map(\.id)), first)
        XCTAssertEqual(Set(GasMath.fills(for: nil, all: all, vehicles: vehicles).map(\.id)), first)
        // No vehicles at all: every fill-up shows.
        XCTAssertEqual(GasMath.fills(for: nil, all: all, vehicles: []).count, all.count)
    }
}
