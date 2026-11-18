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
        guard s.activationState == .activated else { pushWhenActivated = true; return }
        guard s.isPaired, s.isWatchAppInstalled else { return }
        let payload = Self.payload(store)
        // Refreshes run on every new Health sample: only send when the numbers changed (or hourly, so the
        // Watch's "updated" time stays honest). Each send wakes the Watch.
        var numbers = payload
        numbers.removeValue(forKey: Key.updatedAt)
        let same = (lastSent?.isEqual(numbers as NSDictionary) ?? false) && Date().timeIntervalSince(lastSentAt) < 3600
        guard !same else { return }
        do {
            try s.updateApplicationContext(payload)
            lastSent = numbers as NSDictionary
            lastSentAt = Date()
        } catch {}
    }

    /// The numbers (without the time) last handed to the Watch, and when.
    private var lastSent: NSDictionary?
    private var lastSentAt = Date.distantPast
    /// A refresh finished before the session was ready: send its numbers once it is.
    private var pushWhenActivated = false

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
        // Only numbers a refresh has built (at launch the briefing is still empty and would blank the Watch).
        Task { @MainActor in
            guard self.pushWhenActivated else { return }
            self.pushWhenActivated = false
            self.push(LabStore.shared)
        }
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
