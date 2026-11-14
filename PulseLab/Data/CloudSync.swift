import Foundation
import SwiftData

/// iCloud sync of what you type into Pulse Lab yourself: the Stack (SwiftData → CloudKit private database
/// iCloud.com.troydunn.pulselab) and WHOOP numbers logged by hand (iCloud key-value store). Health and WHOOP API
/// data are never uploaded; every device reads those itself.
///
/// Switched on by the `PLCloudSync` Info.plist flag, which is only set to true together with the iCloud
/// entitlements in project.yml (see the note there). Without it, or when no iCloud account is signed in,
/// everything stays on this iPhone exactly as before.
enum CloudSync {
    static let containerID = "iCloud.com.troydunn.pulselab"
    static let userKey = "iCloudSync"
    private static let kvsKey = "whoopManual.v1"
    private static let tombKey = "whoopManualTombstones"

    /// This build carries the iCloud entitlements.
    static var built: Bool { Bundle.main.object(forInfoDictionaryKey: "PLCloudSync") as? Bool ?? false }
    /// Settings switch (on by default once the build supports it). Applies from the next launch.
    static var userEnabled: Bool {
        get { UserDefaults.standard.object(forKey: userKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: userKey) }
    }
    static var signedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }
    static var active: Bool { built && userEnabled && signedIn && !ProcessInfo.processInfo.arguments.contains("-demo") }

    // MARK: Stack (SwiftData)

    /// The Stack's store. Same file as before either way; with sync on, SwiftData mirrors it to CloudKit
    /// (both models have defaults for every property and no unique constraints, as CloudKit requires).
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Supplement.self, SuppDose.self])
        if active {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(containerID))
            if let c = try? ModelContainer(for: schema, configurations: cloud) { return c }
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: local) { return c }
        // Last resort (disk full, corrupt store): keep the app usable for this session.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: memory)
    }

    // MARK: Manual WHOOP entries (key-value store)

    private static var observer: NSObjectProtocol?

    static func startManualSync() {
        guard active, observer == nil else { return }
        let kvs = NSUbiquitousKeyValueStore.default
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: kvs, queue: .main) { _ in
            pullManual()
        }
        kvs.synchronize()
        pullManual()
    }

    private struct Payload: Codable {
        var entries: [WhoopManualEntry]
        /// Day (seconds since 1970) → when it was deleted, so a delete on one device sticks on the others.
        var deleted: [String: Double]
    }

    static func tombstones() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: tombKey) as? [String: Double] ?? [:]
    }

    /// Called by WhoopManualStore after every local save.
    static func pushManual(_ entries: [Date: WhoopManualEntry], removed: [Date]) {
        var tomb = tombstones()
        let now = Date().timeIntervalSince1970
        for d in removed { tomb[key(d)] = now }
        for d in entries.keys { tomb[key(d)] = nil }
        let cutoff = now - 400 * 86_400
        tomb = tomb.filter { $0.value > cutoff }
        UserDefaults.standard.set(tomb, forKey: tombKey)
        guard active else { return }
        let payload = Payload(entries: entries.values.sorted { $0.day < $1.day }, deleted: tomb)
        guard let data = try? JSONEncoder().encode(payload), data.count < 900_000 else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: kvsKey)
    }

    /// Merge what other devices wrote: newest save per day wins, deletes win over older saves.
    static func pullManual() {
        guard active, let data = NSUbiquitousKeyValueStore.default.data(forKey: kvsKey),
              let remote = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        var local = WhoopManualStore.load()
        var tomb = tombstones()
        var changed = false
        for (k, at) in remote.deleted where (tomb[k] ?? 0) < at { tomb[k] = at }
        for e in remote.entries {
            let d = e.day.dayStart
            if let gone = tomb[key(d)], gone >= e.savedAt.timeIntervalSince1970 { continue }
            if let mine = local[d], mine.savedAt >= e.savedAt { continue }
            local[d] = e
            changed = true
        }
        for (k, at) in tomb {
            guard let t = Double(k) else { continue }
            let d = Date(timeIntervalSince1970: t)
            if let mine = local[d], mine.savedAt.timeIntervalSince1970 <= at { local[d] = nil; changed = true }
        }
        UserDefaults.standard.set(tomb, forKey: tombKey)
        guard changed else { return }
        WhoopManualStore.save(local, push: false)
        Task { @MainActor in LabStore.shared.reloadManual() }
    }

    private static func key(_ d: Date) -> String { String(Int(d.dayStart.timeIntervalSince1970)) }
}
