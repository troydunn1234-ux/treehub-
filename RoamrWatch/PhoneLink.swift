import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// What the iPhone tells us about the current recording.
struct RoamrState: Equatable {
    struct Trip: Identifiable, Equatable {
        var id: Double { date }
        var kind: String
        var title: String
        var dist: Double      // meters
        var dur: Double       // seconds
        var date: Double      // since 1970
        var maxSpeed: Double  // m/s
    }

    var tracking = false
    var paused = false
    var kind = "drive"
    var speed: Double = 0          // m/s
    var limit: Double = -1         // m/s
    var limitEstimated = true
    var over = false
    var lane = 1
    var lanes = 2
    var dist: Double = 0           // meters
    var elapsed: Double = 0
    var start: Double?
    var cuts = 0
    var metric = false
    var trips: [Trip] = []

    init() {}

    init(_ d: [String: Any]) {
        tracking = d["tracking"] as? Bool ?? false
        paused = d["paused"] as? Bool ?? false
        kind = d["kind"] as? String ?? "drive"
        speed = d["speed"] as? Double ?? 0
        limit = d["limit"] as? Double ?? -1
        limitEstimated = d["limitEst"] as? Bool ?? true
        over = d["over"] as? Bool ?? false
        lane = d["lane"] as? Int ?? 1
        lanes = max(1, d["lanes"] as? Int ?? 2)
        dist = d["dist"] as? Double ?? 0
        elapsed = d["elapsed"] as? Double ?? 0
        start = d["start"] as? Double
        cuts = d["cuts"] as? Int ?? 0
        metric = d["metric"] as? Bool ?? false
        trips = (d["trips"] as? [[String: Any]] ?? []).map {
            Trip(kind: $0["kind"] as? String ?? "walk", title: $0["title"] as? String ?? "",
                 dist: $0["dist"] as? Double ?? 0, dur: $0["dur"] as? Double ?? 0,
                 date: $0["date"] as? Double ?? 0, maxSpeed: $0["maxSpeed"] as? Double ?? 0)
        }
    }

    // MARK: Display helpers

    var speedValue: Double { speed * (metric ? 3.6 : 2.23694) }
    var limitValue: Double? { limit > 0 ? limit * (metric ? 3.6 : 2.23694) : nil }
    var speedUnit: String { metric ? "km/h" : "mph" }
    var distValue: Double { dist / (metric ? 1000 : 1609.344) }
    var distUnit: String { metric ? "km" : "mi" }
}

/// Watch side of the iPhone link.
@MainActor
@Observable
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    private(set) var state = RoamrState()
    private(set) var reachable = false
    private(set) var lastUpdate: Date?
    var error: String?
    var sending = false

    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")

    func activate() {
        if Self.demo { state = Self.demoState; lastUpdate = Date(); return }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func start(_ kind: String) { send(["cmd": "start", "kind": kind]) }
    func stop() { send(["cmd": "stop"]) }
    func pause() { send(["cmd": state.paused ? "resume" : "pause"]) }

    private func send(_ msg: [String: Any]) {
        if Self.demo { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else {
            error = "Can't reach your iPhone. Keep it nearby and unlocked once."
            WKInterfaceDevice.current().play(.failure)
            return
        }
        sending = true
        s.sendMessage(msg, replyHandler: { reply in
            Task { @MainActor in
                self.sending = false
                self.apply(reply)
                if let e = reply["error"] as? String { self.error = e; WKInterfaceDevice.current().play(.failure) }
                else { WKInterfaceDevice.current().play(.success) }
            }
        }, errorHandler: { err in
            Task { @MainActor in
                self.sending = false
                self.error = "iPhone didn't answer. Try again."
                WKInterfaceDevice.current().play(.failure)
            }
        })
    }

    fileprivate func apply(_ d: [String: Any]) {
        guard d["tracking"] != nil else { return }
        let new = RoamrState(d)
        if new.over && !state.over { WKInterfaceDevice.current().play(.notification) }
        if new.tracking != state.tracking { WKInterfaceDevice.current().play(new.tracking ? .start : .stop) }
        state = new
        lastUpdate = Date()
    }

    fileprivate func setReachable(_ r: Bool) { reachable = r }

    static let demoState: RoamrState = {
        var s = RoamrState()
        s.tracking = true; s.kind = "drive"; s.speed = 29.5; s.limit = 29.06; s.limitEstimated = false
        s.over = false; s.lane = 1; s.lanes = 3; s.dist = 18_200; s.elapsed = 1_420
        s.start = Date().addingTimeInterval(-1_420).timeIntervalSince1970; s.cuts = 2
        let now = Date().timeIntervalSince1970
        s.trips = [
            .init(kind: "drive", title: "Morning drive", dist: 24_100, dur: 1_980, date: now - 86_400, maxSpeed: 33),
            .init(kind: "walk", title: "Evening walk", dist: 3_200, dur: 2_400, date: now - 120_000, maxSpeed: 2),
            .init(kind: "bike", title: "E-bike ride", dist: 11_800, dur: 2_700, date: now - 200_000, maxSpeed: 11),
        ]
        return s
    }()
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        let reach = session.isReachable
        Task { @MainActor in
            self.setReachable(reach)
            if !ctx.isEmpty { self.apply(ctx) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reach = session.isReachable
        Task { @MainActor in self.setReachable(reach) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
}
