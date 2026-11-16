import Foundation
import SwiftData

/// Brings back what Rootbound and Roamr saved in the wrong place on Nov 15.
///
/// From the builds that gave both apps the shared App Group `group.com.troydunn.wellness` until the LocalStore fix
/// (90b8f6a), SwiftData's default location moved into that group: `<group>/Library/Application Support/default.store`,
/// one file both apps used. Hugs, trips and fill-ups saved in that window live only there. Each app reads a private
/// COPY of it (never the shared file itself, so nothing the other app still has to bring back can change) and copies
/// over whatever its own store is missing. The shared file is left exactly as it is.
enum GroupStoreRescue {
    static let groupID = "group.com.troydunn.wellness"

    /// The stray store, when this iPhone has one.
    static var strayStoreURL: URL? {
        let fm = FileManager.default
        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        let usual = [
            base.appending(path: "Library/Application Support/default.store"),
            base.appending(path: "default.store"),
        ]
        if let hit = usual.first(where: { fm.fileExists(atPath: $0.path(percentEncoded: false)) }) { return hit }
        // Anywhere else in the group (a few levels deep), just in case.
        guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsPackageDescendants]) else { return nil }
        for case let url as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            if url.lastPathComponent == "default.store" { return url }
        }
        return nil
    }

    /// A private copy of `store` (the database, its -wal / -shm journal and the folder that holds photos and routes
    /// kept outside the database) in a new temporary folder. Remove it with `discard(_:)` when done.
    static func makePrivateCopy(of store: URL) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "store-rescue-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = store.deletingLastPathComponent()
        let name = store.lastPathComponent
        let stem = store.deletingPathExtension().lastPathComponent
        for item in [name, name + "-wal", name + "-shm", ".\(stem)_SUPPORT"] {
            let from = source.appending(path: item)
            guard fm.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            try fm.copyItem(at: from, to: dir.appending(path: item))
        }
        return dir.appending(path: name)
    }

    static func discard(_ copy: URL) {
        try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    }

    /// Opens a private copy with this app's models. Never synced anywhere (no iCloud).
    static func openCopy(_ copy: URL, schema: Schema) throws -> ModelContainer {
        let config = ModelConfiguration("Rescue-\(UUID().uuidString.prefix(8))", schema: schema, url: copy,
                                        cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }
}

extension Activity {
    /// Every stored property of Activity. RootboundTests checks this against the model, so a new field can't be
    /// left out of `copy(of:)` by accident.
    static let copiedProperties: Set<String> = [
        "id", "kindRaw", "title", "start", "end", "distanceM", "movingSec", "elevGainM", "maxSpeed",
        "startPlace", "endPlace", "notes", "avgHR", "routeData", "laneChangesData", "trimmedSec", "autoFinished",
    ]

    /// A new Activity holding every stored value of `o` (same id).
    static func copy(of o: Activity) -> Activity {
        let a = Activity()
        a.id = o.id
        a.kindRaw = o.kindRaw
        a.title = o.title
        a.start = o.start
        a.end = o.end
        a.distanceM = o.distanceM
        a.movingSec = o.movingSec
        a.elevGainM = o.elevGainM
        a.maxSpeed = o.maxSpeed
        a.startPlace = o.startPlace
        a.endPlace = o.endPlace
        a.notes = o.notes
        a.avgHR = o.avgHR
        a.routeData = o.routeData
        a.laneChangesData = o.laneChangesData
        a.trimmedSec = o.trimmedSec
        a.autoFinished = o.autoFinished
        return a
    }
}
