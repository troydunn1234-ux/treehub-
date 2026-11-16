import XCTest
import SwiftData
@testable import Roamr

/// An update must open the store that is already on the phone and show every trip and fill-up in it.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive).
final class DataSafetyTests: XCTestCase {
    private let schema = Schema([Activity.self, GasVehicle.self, FillUp.self])

    func testStoreIsPinnedToTheAppsOwnApplicationSupport() {
        let path = LocalStore.url.standardizedFileURL.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/default.store"), path)
        XCTAssertFalse(path.contains("AppGroup"), "the store must never be inside an App Group: \(path)")
        let original = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        XCTAssertEqual(original.url.standardizedFileURL.path, path)
    }

    func testAppContainerOpensThePinnedStore() throws {
        let container = TrackHubApp.makeContainer(demo: false)
        let config = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app fell back to a temporary store: saved trips would be hidden")
        XCTAssertEqual(config.url.standardizedFileURL.path, LocalStore.url.standardizedFileURL.path)
    }

    /// A store written the way an earlier build wrote it opens with the app's own container code.
    func testExistingTripsAndFillUpsSurviveAnUpdate() throws {
        let tripID = UUID(), carID = UUID(), fillID = UUID()
        let route = Data((0..<200_000).map { UInt8($0 % 251) })
        do {
            let old = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: LocalStore.url, cloudKitDatabase: .none))
            let ctx = ModelContext(old)
            let a = Activity()
            a.id = tripID; a.title = "Guard drive"; a.kind = .drive; a.distanceM = 42_000; a.routeData = route
            let car = GasVehicle(name: "Guard truck")
            car.id = carID
            let fill = FillUp(vehicleID: carID, date: Date(), gallons: 20, pricePerGallon: 4.5, total: 90,
                              odometer: 201_000, station: "Guard gas")
            fill.id = fillID
            ctx.insert(a); ctx.insert(car); ctx.insert(fill)
            try ctx.save()
        }
        let ctx = ModelContext(TrackHubApp.makeContainer(demo: false))
        let trips = try ctx.fetch(FetchDescriptor<Activity>()).filter { $0.id == tripID }
        let cars = try ctx.fetch(FetchDescriptor<GasVehicle>()).filter { $0.id == carID }
        let fills = try ctx.fetch(FetchDescriptor<FillUp>()).filter { $0.id == fillID }
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.distanceM, 42_000)
        XCTAssertEqual(trips.first?.kind, .drive)
        XCTAssertEqual(trips.first?.routeData, route)
        XCTAssertEqual(cars.first?.name, "Guard truck")
        XCTAssertEqual(fills.first?.vehicleID, carID)
        XCTAssertEqual(fills.first?.odometer, 201_000)
        trips.forEach { ctx.delete($0) }
        cars.forEach { ctx.delete($0) }
        fills.forEach { ctx.delete($0) }
        try ctx.save()
    }

    /// Every field that was ever saved is still in the model (snapshot: .github/data-guard/models.json).
    func testNoStoredFieldWasRenamedOrRemoved() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent(".github/data-guard/models.json")),
              let snapshot = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { throw XCTSkip("models.json is not readable from the simulator") }
        for entity in schema.entities {
            let saved = try XCTUnwrap(snapshot[entity.name], "\(entity.name) is missing from models.json")
            let now = Set(entity.attributes.map(\.name))
            for name in saved.keys {
                XCTAssertTrue(now.contains(name), "\(entity.name).\(name) was renamed or removed: its saved values would be lost")
            }
        }
    }

    /// What Roamr shares with Rootbound keeps its shape (walks under tree hugs), and its link opens a trip.
    func testFeedTripKeepsItsShape() throws {
        let trip = WellnessBridge.Trip(id: UUID(), kind: "hike", start: Date(timeIntervalSince1970: 1_794_700_000),
                                       end: Date(timeIntervalSince1970: 1_794_703_600), distanceM: 5000, movingSec: 3300,
                                       elevGainM: 120, avgSpeed: 1.5, topSpeed: 2.4)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: enc.encode(trip)) as? [String: Any])
        for key in ["id", "kind", "start", "end", "distanceM", "movingSec", "elevGainM", "avgSpeed", "topSpeed"] {
            XCTAssertNotNil(obj[key], "roamr.json lost \"\(key)\": Rootbound could not read the walk")
        }
        XCTAssertTrue(trip.isOnFoot)
        XCTAssertEqual(WellnessBridge.coarse(37.28712), 37.287, accuracy: 1e-9)
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("roamr"), "\(schemes)")
    }
}
