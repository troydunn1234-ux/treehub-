import Foundation
import WatchConnectivity

/// iPhone side of iPhone ↔ Watch: mirrors settings/favorites, starts practices on the Watch,
/// and receives finished Watch sessions for the Journey tab.
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneLink()

    @Published private(set) var watchPaired = false
    @Published private(set) var watchAppInstalled = false
    @Published private(set) var reachable = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        Prefs.shared.onChange = { [weak self] in self?.pushSettings() }
        SessionLog.shared.onGoalChange = { [weak self] in self?.pushSettings() }
    }

    var canUseWatch: Bool { watchPaired && watchAppInstalled }

    func pushSettings() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, canUseWatch else { return }
        var ctx = Prefs.shared.settings.asDictionary()
        ctx[SyncKey.favorites] = Prefs.shared.favorites
        ctx[SyncKey.pro] = Prefs.shared.pro
        ctx[SyncKey.weekGoal] = SessionLog.shared.weeklyGoal
        try? WCSession.default.updateApplicationContext(ctx)
    }

    /// Ask the Watch to begin a practice now. Falls back to a queued transfer if the Watch app isn't awake.
    func startOnWatch(_ plan: SessionPlan, done: @escaping (Bool) -> Void) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, canUseWatch else { done(false); return }
        var msg: [String: Any] = [SyncKey.command: SyncKey.start, SyncKey.practiceId: plan.practice.id, SyncKey.minutes: plan.minutes]
        if let w = plan.warmUp { msg["warmUpId"] = w.id }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in DispatchQueue.main.async { done(true) } },
                                          errorHandler: { _ in
                                              WCSession.default.transferUserInfo(msg)
                                              DispatchQueue.main.async { done(true) }
                                          })
        } else {
            WCSession.default.transferUserInfo(msg)
            done(true)
        }
    }

    private func refresh(_ s: WCSession) {
        DispatchQueue.main.async {
            self.watchPaired = s.isPaired
            self.watchAppInstalled = s.isWatchAppInstalled
            self.reachable = s.isReachable
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refresh(session)
        DispatchQueue.main.async { self.pushSettings() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { refresh(session) }
    func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let r = SessionLog.record(from: userInfo) {
            DispatchQueue.main.async { SessionLog.shared.add(r) }
        }
    }
}
