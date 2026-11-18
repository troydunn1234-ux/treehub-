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

    /// Tell the iPhone a session was discarded on the Watch.
    func sendDelete(_ id: UUID) {
        transfer(["deleteSession": id.uuidString])
    }

    /// User-info transfers asked for before the session finished activating (e.g. a heat timer started from a
    /// complication tap on a cold launch). Sent once activation completes. Main thread only.
    private var waiting: [[String: Any]] = []

    /// transferUserInfo, or queue it until the session is activated (it would be dropped otherwise).
    func transfer(_ info: [String: Any]) {
        guard WCSession.isSupported() else { return }
        if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(info)
        } else {
            waiting.append(info)
            if waiting.count > 20 { waiting.removeFirst(waiting.count - 20) }
        }
    }

    func send(_ record: SessionRecord) {
        transfer(SessionLog.shared.toDictionary(record))
    }

    private func handle(_ dict: [String: Any]) {
        DispatchQueue.main.async {
            if let s = SessionSettings.from(dict) {
                Prefs.shared.applyRemote(s, favorites: dict[SyncKey.favorites] as? [String], pro: dict[SyncKey.pro] as? Bool)
            }
            if let g = dict[SyncKey.weekGoal] as? Double { SessionLog.shared.applyRemoteGoal(g) }
            if let n = dict[SyncKey.streak] as? Int, let day = dict[SyncKey.streakDay] as? Double {
                SessionLog.shared.applyRemoteStreak(count: n, best: dict[SyncKey.bestStreak] as? Int ?? n,
                                                    lastDay: Date(timeIntervalSince1970: day))
            }
            if let d = dict[SyncKey.rightNow] as? Data, let s = try? JSONDecoder().decode(Suggestion.self, from: d) {
                MainActor.assumeIsolated { RightNow.shared.applyRemote(s) }
            }
            if dict[SyncKey.command] as? String == SyncKey.start, let id = dict[SyncKey.practiceId] as? String,
               !SyncKey.isStaleStart(dict) {
                let mins = dict[SyncKey.minutes] as? Int ?? Prefs.shared.settings.defaultMinutes
                self.pendingStart = (id, mins, dict["warmUpId"] as? String)
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, !session.receivedApplicationContext.isEmpty {
            handle(session.receivedApplicationContext)
        }
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            let queued = self.waiting
            self.waiting = []
            for info in queued { session.transferUserInfo(info) }
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
