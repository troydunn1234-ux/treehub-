import Foundation
import WatchConnectivity

/// iPhone side of iPhone ↔ Watch: after every sync, today's numbers go to the Pulse Lab Watch app as the
/// application context (latest wins, delivered even if the Watch app isn't running). The Watch can ask for
/// a fresh sync with a "refresh" message. Keys are mirrored in PulseLabWatch/WatchStore.swift.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    enum Key {
        static let recovery = "recovery"
        static let recoveryKind = "recoveryKind"
        static let sleepMin = "sleepMin"
        static let sleepAvgMin = "sleepAvgMin"
        static let hrv = "hrv"
        static let hrvBase = "hrvBase"
        static let rhr = "rhr"
        static let rhrBase = "rhrBase"
        static let strain = "strain"
        static let strainIsToday = "strainIsToday"
        static let takeaway = "takeaway"
        static let updatedAt = "updatedAt"
        static let command = "command"
    }

    private var activated = false

    func activate() {
        guard WCSession.isSupported(), !activated else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @MainActor
    func push(_ store: LabStore) {
        guard WCSession.isSupported(), !LabStore.isDemo else { return }
        activate()
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(Self.payload(store))
    }

    @MainActor
    static func payload(_ store: LabStore) -> [String: Any] {
        let b = store.briefing
        var p: [String: Any] = [Key.updatedAt: Date().timeIntervalSince1970,
                                Key.recoveryKind: b.recoveryKind.rawValue,
                                Key.takeaway: b.takeaway]
        func put(_ v: Double?, _ k: String) { if let v { p[k] = v } }
        put(b.recovery, Key.recovery)
        put(b.sleepMin, Key.sleepMin)
        put(b.sleepAvgMin, Key.sleepAvgMin)
        put(b.hrv, Key.hrv)
        put(b.hrvBase, Key.hrvBase)
        put(b.rhr, Key.rhr)
        put(b.rhrBase, Key.rhrBase)
        if let t = store.whoopDays.stat(on: Date())?.strain {
            p[Key.strain] = t
            p[Key.strainIsToday] = true
        } else if let y = b.strainYesterday {
            p[Key.strain] = y
            p[Key.strainIsToday] = false
        }
        return p
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.push(LabStore.shared) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    /// The Watch asked for fresh numbers: sync, then answer with them.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[Key.command] as? String == "refresh" else { replyHandler([:]); return }
        Task { @MainActor in
            await LabStore.shared.refresh(.background)
            replyHandler(Self.payload(LabStore.shared))
        }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[Key.command] as? String == "refresh" else { return }
        Task { @MainActor in await LabStore.shared.refresh(.background) }
    }
}
