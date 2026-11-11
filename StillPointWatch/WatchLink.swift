import Foundation
import WatchConnectivity

/// Watch side of iPhone ↔ Watch: receives settings/favorites and "start this practice", sends finished sessions.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchLink()

    /// Set when the iPhone asks to begin a practice; the UI presents it.
    @Published var pendingStart: (practiceId: String, minutes: Int, warmUpId: String?)? = nil

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ record: SessionRecord) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(SessionLog.shared.toDictionary(record))
    }

    private func handle(_ dict: [String: Any]) {
        DispatchQueue.main.async {
            if let s = SessionSettings.from(dict) {
                Prefs.shared.applyRemote(s, favorites: dict[SyncKey.favorites] as? [String], pro: dict[SyncKey.pro] as? Bool)
            }
            if let g = dict[SyncKey.weekGoal] as? Double { SessionLog.shared.applyRemoteGoal(g) }
            if dict[SyncKey.command] as? String == SyncKey.start, let id = dict[SyncKey.practiceId] as? String {
                let mins = dict[SyncKey.minutes] as? Int ?? Prefs.shared.settings.defaultMinutes
                self.pendingStart = (id, mins, dict["warmUpId"] as? String)
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, !session.receivedApplicationContext.isEmpty {
            handle(session.receivedApplicationContext)
        }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message)
        replyHandler(["ok": true])
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
}
