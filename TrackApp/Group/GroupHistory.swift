import Foundation
import Combine

// "Go together" history: a small local list of the group trips you took part in, so History can
// say "with Alex, Sam" and jump to your recording of it. Stored only on this phone (UserDefaults),
// never uploaded; the CloudKit records are untouched.

struct GroupTripLog: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Your own recording of the trip (the Activity's id), if one was running.
    var activityID: UUID?
    var code: String
    var kindRaw: String
    var date: Date
    var friends: [String]
    var distanceM: Double
    var hosted: Bool

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .drive }

    /// "with Alex, Sam" / "with Alex, Sam and 2 more".
    var withLabel: String { Self.withLabel(friends) }

    static func withLabel(_ names: [String]) -> String {
        guard !names.isEmpty else { return "Go together" }
        if names.count <= 3 { return "with " + names.joined(separator: ", ") }
        return "with " + names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
    }
}

@MainActor
final class GroupHistory: ObservableObject {
    static let shared = GroupHistory()

    @Published private(set) var trips: [GroupTripLog] = []

    private static let key = "group.history.v1"
    private static let maxKept = 200
    private var token: NSObjectProtocol?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([GroupTripLog].self, from: data) {
            trips = list
        }
        // Demo screenshots: a few made-up group trips (never saved).
        if TrackDemo.isOn && trips.isEmpty {
            let now = Date()
            trips = [
                GroupTripLog(code: "DEMO01", kindRaw: ActivityKind.drive.rawValue, date: now.addingTimeInterval(-86400),
                             friends: ["Alex", "Sam"], distanceM: 48_000, hosted: true),
                GroupTripLog(code: "DEMO02", kindRaw: ActivityKind.hike.rawValue, date: now.addingTimeInterval(-6 * 86400),
                             friends: ["Jordan", "Riley", "Casey", "Morgan"], distanceM: 9300, hosted: false),
            ]
        }
        // When the recording of a group trip is saved, keep its final distance.
        token = NotificationCenter.default.addObserver(forName: .activitySaved, object: nil, queue: .main) { note in
            guard let raw = note.userInfo?["id"] as? String, let id = UUID(uuidString: raw),
                  let d = note.userInfo?["distanceM"] as? Double else { return }
            MainActor.assumeIsolated { GroupHistory.shared.updateDistance(activityID: id, distanceM: d) }
        }
    }

    /// The group trip a recording belongs to, if any.
    func log(for activityID: UUID) -> GroupTripLog? {
        trips.first { $0.activityID == activityID }
    }

    func add(_ log: GroupTripLog) {
        // One entry per recording: a second group during the same recording merges into it.
        if let aid = log.activityID, let i = trips.firstIndex(where: { $0.activityID == aid }) {
            var merged = trips[i]
            for n in log.friends where !merged.friends.contains(n) { merged.friends.append(n) }
            merged.distanceM = max(merged.distanceM, log.distanceM)
            trips[i] = merged
        } else {
            trips.insert(log, at: 0)
        }
        trips.sort { $0.date > $1.date }
        if trips.count > Self.maxKept { trips = Array(trips.prefix(Self.maxKept)) }
        save()
    }

    func remove(_ id: UUID) {
        trips.removeAll { $0.id == id }
        save()
    }

    private func updateDistance(activityID: UUID, distanceM: Double) {
        guard let i = trips.firstIndex(where: { $0.activityID == activityID }) else { return }
        trips[i].distanceM = distanceM
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(trips) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
