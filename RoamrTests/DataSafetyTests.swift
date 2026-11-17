import XCTest
import SwiftData
@testable import Roamr

/// An update must open the store that is already on the phone and show every trip and fill-up in it.
/// The static half of these checks is .github/scripts/data_guard.py (run before every TestFlight archive);
/// helpers are in TestSupport/DataGuardSupport.swift.
final class DataSafetyTests: XCTestCase {
    private let schema = Schema([Activity.self, GasVehicle.self, FillUp.self])

    // MARK: Where the store is

    func testStoreIsPinnedToTheAppsOwnApplicationSupport() {
        let path = LocalStore.url.standardizedFileURL.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/default.store"), path)
        XCTAssertFalse(path.contains("AppGroup"), "the store must never be inside an App Group: \(path)")
        let original = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        XCTAssertEqual(original.url.standardizedFileURL.path, path)
    }

    /// The app's own container code, as it runs on launch, opens LocalStore.url on disk.
    @MainActor
    func testAppContainerOpensThePinnedStore() throws {
        let container = TrackHubApp.makeContainer(demo: false)
        let config = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app fell back to a temporary store: saved trips would be hidden")
        XCTAssertEqual(config.url.standardizedFileURL.path, LocalStore.url.standardizedFileURL.path)
    }

    // MARK: An existing store survives the update

    /// A store written the way an earlier build wrote it (at a temporary LocalStore-like path) reopens through the
    /// app's own container code with every trip (route included), vehicle and fill-up.
    @MainActor
    func testExistingTripsAndFillUpsSurviveAnUpdate() throws {
        let url = try DataGuardSupport.temporaryStoreURL("roamr-store")
        defer { DataGuardSupport.removeTemporaryStore(url) }
        let tripID = UUID(), carID = UUID(), fillID = UUID()
        let route = Data((0..<200_000).map { UInt8($0 % 251) })
        let start = Date(timeIntervalSince1970: 1_794_700_000)
        do {
            let old = try ModelContainer(for: schema, configurations:
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let ctx = ModelContext(old)
            let a = Activity()
            a.id = tripID; a.title = "Guard drive"; a.kind = .drive; a.start = start; a.end = start.addingTimeInterval(1800)
            a.distanceM = 42_000; a.movingSec = 1700; a.maxSpeed = 31; a.routeData = route; a.notes = "before the update"
            let car = GasVehicle(name: "Guard truck")
            car.id = carID
            let fill = FillUp(vehicleID: carID, date: start, gallons: 20, pricePerGallon: 4.5, total: 90,
                              odometer: 201_000, station: "Guard gas")
            fill.id = fillID
            fill.notes = "full tank"
            ctx.insert(a); ctx.insert(car); ctx.insert(fill)
            try ctx.save()
        }
        let container = TrackHubApp.makeContainer(storeURL: url, demo: false)
        let config = try XCTUnwrap(container.configurations.first)
        XCTAssertFalse(config.isStoredInMemoryOnly, "the app could not open the existing store")
        XCTAssertEqual(config.url.standardizedFileURL.path, url.standardizedFileURL.path)
        let ctx = ModelContext(container)
        let trip = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Activity>()).first { $0.id == tripID })
        XCTAssertEqual(trip.distanceM, 42_000)
        XCTAssertEqual(trip.kind, .drive)
        XCTAssertEqual(trip.start, start)
        XCTAssertEqual(trip.routeData, route)
        XCTAssertEqual(trip.notes, "before the update")
        let car = try XCTUnwrap(try ctx.fetch(FetchDescriptor<GasVehicle>()).first { $0.id == carID })
        XCTAssertEqual(car.name, "Guard truck")
        let fill = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FillUp>()).first { $0.id == fillID })
        XCTAssertEqual(fill.vehicleID, carID)
        XCTAssertEqual(fill.odometer, 201_000)
        XCTAssertEqual(fill.total, 90)
        XCTAssertEqual(fill.notes, "full tank")
    }

    /// Every field that was ever saved is still in the model (snapshot: .github/data-guard/models.json).
    func testNoStoredFieldWasRenamedOrRemoved() throws {
        try DataGuardSupport.assertNoStoredFieldRemoved(schema)
    }

    /// The Nov 15 rescue copies every stored field of vehicles and fill-ups (a new field must be added there too).
    @MainActor
    func testRescueCopiesEveryStoredField() {
        func names(_ entity: String) -> Set<String> {
            Set(schema.entities.first { $0.name == entity }?.attributes.map(\.name) ?? [])
        }
        XCTAssertEqual(names("GasVehicle"), TripRescue.vehicleProperties)
        XCTAssertEqual(names("FillUp"), TripRescue.fillUpProperties)
        XCTAssertEqual(names("Activity"), Activity.copiedProperties)
    }

    // MARK: What Roamr shares with Rootbound

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
        XCTAssertEqual(WellnessBridge.coarse(45.50712), 45.507, accuracy: 1e-9)
        XCTAssertTrue(DataGuardSupport.urlSchemes.contains("roamr"), "\(DataGuardSupport.urlSchemes)")
    }

    @MainActor
    func testTripLinksFromRootboundAreAnswered() {
        XCTAssertTrue(RoamrWellness.handle(url: URL(string: "roamr://history")!))
        XCTAssertTrue(RoamrWellness.handle(url: URL(string: "roamr://trip?id=\(UUID().uuidString)")!))
        XCTAssertFalse(RoamrWellness.handle(url: URL(string: "roamr://join?c=ABC")!), "group invites go to GroupSession")
        XCTAssertFalse(RoamrWellness.handle(url: URL(string: "rootbound://tree?id=1")!))
    }

    // MARK: What the build itself carries

    func testEntitlementsMatchTheAllowlist() throws {
        try DataGuardSupport.assertEntitlements(target: "Roamr")
        XCTAssertEqual(try DataGuardSupport.appGroups(target: "Roamr"), [WellnessBridge.groupID])
    }

    func testEnglishPermissionTexts() {
        DataGuardSupport.assertEnglishInfoPlist()
    }
}
