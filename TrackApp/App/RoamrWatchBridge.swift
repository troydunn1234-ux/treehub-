import Foundation
import SwiftData
import UIKit
import WatchConnectivity

/// iPhone side of the Apple Watch link: sends live speed / limit / lane / trip stats to the
/// watch (about once a second while recording) and starts or stops recordings when the watch asks.
@MainActor
final class RoamrWatchBridge: NSObject {
    static let shared = RoamrWatchBridge()

    private weak var tracker: RouteTracker?
    private var container: ModelContainer?
    private var timer: Timer?
    private var lastContextKey = ""
    private var lastContextAt = Date.distantPast
    private var trips: [[String: Any]] = []
    private var tripsFetchedAt = Date.distantPast
    private var wasActive = false
    /// A trip was saved, edited or deleted since the last list sent to the watch.
    private var tripsDirty = true
    private var saveObserver: NSObjectProtocol?

    func attach(tracker: RouteTracker, container: ModelContainer) {
        guard WCSession.isSupported() else { return }
        self.tracker = tracker
        self.container = container
        let s = WCSession.default
        s.delegate = self
        s.activate()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // The recent-trips list only changes when something is saved: re-read it then, not on a timer.
        if saveObserver == nil {
            saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tripsDirty = true }
            }
        }
    }

    // MARK: Sending

    private var watchReady: Bool {
        let s = WCSession.default
        return s.activationState == .activated && s.isPaired && s.isWatchAppInstalled
    }

    private func tick() {
        guard watchReady, let tracker else { return }
        if tracker.isActive != wasActive { wasActive = tracker.isActive; tripsDirty = true }
        let state = snapshot()
        if tracker.isActive, WCSession.default.isReachable {
            var live = state
            live["t"] = Date().timeIntervalSince1970
            WCSession.default.sendMessage(live, replyHandler: nil, errorHandler: nil)
        }
        // Application context is the "latest state" the watch reads when it opens; keep it fresh but light.
        // Idle, it only goes out when something changed (no once-a-minute resend that wakes both devices).
        let key = contextKey(state)
        let stale = tracker.isActive && Date().timeIntervalSince(lastContextAt) > 10
        if key != lastContextKey || stale {
            lastContextKey = key
            lastContextAt = Date()
            try? WCSession.default.updateApplicationContext(state)
        }
    }

    private func contextKey(_ s: [String: Any]) -> String {
        let tracking = s["tracking"] as? Bool ?? false
        let list = (s["trips"] as? [[String: Any]]) ?? []
        // Every trip's date, title and distance, so a renamed or trimmed trip also reaches the watch.
        let trips = list.map { "\($0["date"] ?? "")/\($0["title"] ?? "")/\($0["dist"] ?? "")/\($0["kind"] ?? "")" }.joined(separator: ";")
        return "\(tracking)|\(s["kind"] ?? "")|\(s["paused"] ?? "")|\(s["metric"] ?? "")|\(trips)"
    }

    func snapshot() -> [String: Any] {
        guard let t = tracker else { return [:] }
        refreshTripsIfNeeded()
        var d: [String: Any] = [
            "tracking": t.isActive,
            "paused": t.state == .paused,
            "kind": t.kind.rawValue,
            "speed": max(0, t.currentSpeed),          // m/s
            "limit": t.speedLimit?.mps ?? -1,         // m/s, -1 unknown
            "limitEst": t.speedLimit?.estimated ?? true,
            "over": t.isOverLimit,
            "lane": t.laneIndex,
            "lanes": t.laneCount,
            "dist": t.distance,                       // meters
            "elapsed": t.elapsed,
            "maxSpeed": t.maxSpeed,
            "cuts": t.cutCount,
            "metric": UserDefaults.standard.bool(forKey: "useMetric"),
            "trips": trips,
        ]
        if let start = t.startDate { d["start"] = start.timeIntervalSince1970 }
        return d
    }

    private func refreshTripsIfNeeded() {
        guard let container else { return }
        // Recording: at most every 30 s. Idle: only after a save.
        let due = tripsDirty || (tracker?.isActive == true && Date().timeIntervalSince(tripsFetchedAt) > 30)
        guard due else { return }
        tripsDirty = false
        tripsFetchedAt = Date()
        var fd = FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        fd.fetchLimit = 3
        let list = (try? container.mainContext.fetch(fd)) ?? []
        trips = list.map { a in
            ["kind": a.kind.rawValue, "title": a.displayTitle, "dist": a.distanceM,
             "dur": a.movingSec > 0 ? a.movingSec : a.elapsedSec, "date": a.start.timeIntervalSince1970,
             "maxSpeed": a.maxSpeed]
        }
    }

    // MARK: Commands from the watch

    fileprivate func handle(_ msg: [String: Any]) -> [String: Any] {
        guard let tracker, let cmd = msg["cmd"] as? String else { return snapshot() }
        switch cmd {
        case "start":
            let kind = ActivityKind(rawValue: msg["kind"] as? String ?? "") ?? .drive
            guard !tracker.isActive else { break }
            guard tracker.canTrack else {
                var s = snapshot(); s["error"] = "Open Roamr on your iPhone and allow location first."; return s
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            tracker.start(kind: kind)
        case "stop":
            finishAndSave()
        case "pause":
            if tracker.state == .recording { tracker.pause() }
        case "resume":
            if tracker.state == .paused { tracker.resume() }
        default:
            break
        }
        tripsDirty = true
        lastContextKey = ""
        return snapshot()
    }

    /// Same as tapping Finish in the app: save the activity and fill in place names.
    private func finishAndSave() {
        guard let tracker, let container else { return }
        let suggestion = tracker.suggestedKind
        let originalKind = tracker.kind
        guard let a = tracker.finish() else { return }
        if suggestion != originalKind && (suggestion == .drive || originalKind == .drive)
            && ActivityKind.available.contains(suggestion) { a.kind = suggestion }
        let context = container.mainContext
        context.insert(a)
        try? context.save()
        // Finished from the Watch (often with Roamr in the background): Rootbound sees the walk right away.
        RoamrWellness.publish(context, force: true)
        let pts = a.route
        Task {
            if let s = pts.first { a.startPlace = await Geo.placeName(for: s.coordinate) }
            if let e = pts.last { a.endPlace = await Geo.placeName(for: e.coordinate) }
            try? context.save()
        }
    }
}

extension RoamrWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.lastContextKey = ""; self.tick() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastContextKey = "" }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.handle(message)) }
    }
}
