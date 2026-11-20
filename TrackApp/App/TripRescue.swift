import Foundation
import SwiftData

/// Brings back trips and fill-ups Roamr saved in the wrong place on Nov 15 (see GroupStoreRescue in
/// Shared/Models/StoreRescue.swift). Reads a private copy of the stray shared store and adds whatever this store
/// is missing, with the original ids, so links from Rootbound (walks under hugs) keep working.
/// Runs once on launch after this update, and any time from Settings > Find missing trips.
@MainActor
enum TripRescue {
    struct Report: Identifiable {
        let id = UUID()
        var checkedOldStore = false
        var trips = 0
        var restoredTrips = 0
        var restoredVehicles = 0
        var restoredFillUps = 0
        var problem: String?

        var restoredAnything: Bool { restoredTrips + restoredVehicles + restoredFillUps > 0 }

        /// One line for an alert.
        var summary: String {
            if let problem { return String(localized: "Couldn't read the old storage: \(problem)") }
            guard checkedOldStore else { return String(localized: "Nothing was saved in the wrong place on this iPhone.") }
            guard restoredAnything else {
                return trips == 0 ? String(localized: "The old storage had no trips left in it.")
                                  : String(localized: "Every trip in the old storage is already here.")
            }
            var parts: [String] = []
            if restoredTrips > 0 { parts.append(restoredTrips == 1 ? String(localized: "1 trip") : String(localized: "\(restoredTrips) trips")) }
            if restoredFillUps > 0 { parts.append(restoredFillUps == 1 ? String(localized: "1 fill-up") : String(localized: "\(restoredFillUps) fill-ups")) }
            if restoredVehicles > 0 { parts.append(restoredVehicles == 1 ? String(localized: "1 vehicle") : String(localized: "\(restoredVehicles) vehicles")) }
            return String(localized: "Brought back \(parts.joined(separator: ", ")) saved in the wrong place on Nov 15.")
        }
    }

    private static let doneKey = "rescue.groupStore.trips.v1"

    /// Once per install, right after this update. Returns a report only when something came back.
    static func runOnce(in context: ModelContext) async -> Report? {
        guard !TrackDemo.isOn, !UserDefaults.standard.bool(forKey: doneKey) else { return nil }
        let report = await run(in: context)
        if report.problem == nil { UserDefaults.standard.set(true, forKey: doneKey) }
        return report.restoredAnything ? report : nil
    }

    /// One rescue at a time (the launch run and Settings > Find missing trips can't overlap).
    private static var running = false

    static func run(in context: ModelContext) async -> Report {
        var r = Report()
        guard !TrackDemo.isOn, !running, let stray = GroupStoreRescue.strayStoreURL else { return r }
        running = true
        defer { running = false }
        r.checkedOldStore = true
        do {
            let scratch = try await Task.detached(priority: .userInitiated) {
                try GroupStoreRescue.makePrivateCopy(of: stray)
            }.value
            defer { GroupStoreRescue.discard(scratch) }
            let old = try GroupStoreRescue.openCopy(scratch, schema: Schema([Activity.self, GasVehicle.self, FillUp.self]))
            let oldContext = ModelContext(old)

            let oldTrips = try oldContext.fetch(FetchDescriptor<Activity>())
            r.trips = oldTrips.count
            var tripIDs = Set(try context.fetch(FetchDescriptor<Activity>()).map(\.id))
            for t in oldTrips where !tripIDs.contains(t.id) {
                context.insert(Activity.copy(of: t))
                tripIDs.insert(t.id)
                r.restoredTrips += 1
            }

            var vehicleIDs = Set(try context.fetch(FetchDescriptor<GasVehicle>()).map(\.id))
            for v in try oldContext.fetch(FetchDescriptor<GasVehicle>()) where !vehicleIDs.contains(v.id) {
                context.insert(copy(of: v))
                vehicleIDs.insert(v.id)
                r.restoredVehicles += 1
            }

            var fillIDs = Set(try context.fetch(FetchDescriptor<FillUp>()).map(\.id))
            for f in try oldContext.fetch(FetchDescriptor<FillUp>()) where !fillIDs.contains(f.id) {
                context.insert(copy(of: f))
                fillIDs.insert(f.id)
                r.restoredFillUps += 1
            }

            if r.restoredAnything {
                try context.save()
                // Rootbound sees the trips again (walks under hugs).
                RoamrWellness.publish(context, force: true)
            }
        } catch {
            r.problem = error.localizedDescription
        }
        return r
    }

    // MARK: Copy

    static let vehicleProperties: Set<String> = ["id", "name", "created"]
    static let fillUpProperties: Set<String> = [
        "id", "vehicleID", "date", "gallons", "pricePerGallon", "total", "odometer", "station", "full", "notes", "tripMiles",
    ]

    static func copy(of o: GasVehicle) -> GasVehicle {
        let v = GasVehicle(name: o.name)
        v.id = o.id
        v.created = o.created
        return v
    }

    static func copy(of o: FillUp) -> FillUp {
        let f = FillUp(vehicleID: o.vehicleID, date: o.date, gallons: o.gallons, pricePerGallon: o.pricePerGallon,
                       total: o.total, odometer: o.odometer, station: o.station, full: o.full)
        f.id = o.id
        f.notes = o.notes
        f.tripMiles = o.tripMiles
        return f
    }
}
