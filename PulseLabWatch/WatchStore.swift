import Foundation
import WatchConnectivity
import WidgetKit

/// Watch side of iPhone ↔ Watch. The iPhone sends today's numbers as the application context after
/// every sync (PulseLab/Data/WatchSync.swift, same keys); they're kept in the Watch's App Group so the
/// complications (PulseLabWatchWidgets) can draw them too.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()
    static let suite = "group.com.troydunn.pulselab"
    static let snapshotKey = "watchSnapshot"

    @Published private(set) var snap: Snapshot = WatchStore.load()
    @Published private(set) var refreshing = false
    @Published var phoneUnreachable = false

    struct Snapshot {
        var recovery: Double?
        var isWhoop = true
        var sleepMin: Double?
        var sleepAvgMin: Double?
        var hrv: Double?
        var hrvBase: Double?
        var rhr: Double?
        var rhrBase: Double?
        var strain: Double?
        var strainIsToday = false
        var takeaway: String?
        var updatedAt: Date?
        /// Today's Watch vs WHOOP agreement (0–100), metrics agreeing / compared, and the ones they split on.
        var agreeScore: Double?
        var agreeOn = 0
        var agreeOf = 0
        var agreeSplit = ""

        init() {}
        init(_ d: [String: Any]) {
            recovery = d["recovery"] as? Double
            isWhoop = (d["recoveryKind"] as? String ?? "whoop") == "whoop"
            sleepMin = d["sleepMin"] as? Double
            sleepAvgMin = d["sleepAvgMin"] as? Double
            hrv = d["hrv"] as? Double
            hrvBase = d["hrvBase"] as? Double
            rhr = d["rhr"] as? Double
            rhrBase = d["rhrBase"] as? Double
            strain = d["strain"] as? Double
            strainIsToday = d["strainIsToday"] as? Bool ?? false
            takeaway = d["takeaway"] as? String
            if let t = d["updatedAt"] as? Double { updatedAt = Date(timeIntervalSince1970: t) }
            agreeScore = d["agreeScore"] as? Double
            agreeOn = d["agreeOn"] as? Int ?? 0
            agreeOf = d["agreeOf"] as? Int ?? 0
            agreeSplit = d["agreeSplit"] as? String ?? ""
        }
        var isEmpty: Bool { recovery == nil && sleepMin == nil && hrv == nil && strain == nil }
    }

    static func load() -> Snapshot {
        guard let d = UserDefaults(suiteName: suite)?.dictionary(forKey: snapshotKey) else { return Snapshot() }
        return Snapshot(d)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Ask the iPhone to sync now and send fresh numbers back.
    func refresh() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isReachable else { phoneUnreachable = true; return }
        refreshing = true
        phoneUnreachable = false
        WCSession.default.sendMessage(["command": "refresh"], replyHandler: { [weak self] reply in
            self?.apply(reply)
            DispatchQueue.main.async { self?.refreshing = false }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async { self?.refreshing = false; self?.phoneUnreachable = true }
        })
    }

    private func apply(_ dict: [String: Any]) {
        guard !dict.isEmpty else { return }
        UserDefaults(suiteName: Self.suite)?.set(dict, forKey: Self.snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async { self.snap = Snapshot(dict) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { apply(applicationContext) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { apply(userInfo) }
}
