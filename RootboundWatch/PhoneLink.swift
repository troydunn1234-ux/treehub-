import Foundation
import WatchConnectivity

/// Watch -> iPhone: finished hugs go over WatchConnectivity (transferUserInfo is queued and delivered even when
/// the iPhone app isn't running). Hugs not yet confirmed as sent are kept here so nothing is lost.
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()
    private var waiting: [[String: Any]] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ hug: WatchHugRecord) {
        let info = hug.payload
        DispatchQueue.main.async {
            guard WCSession.isSupported() else { return }
            if WCSession.default.activationState == .activated {
                WCSession.default.transferUserInfo(info)
            } else {
                self.waiting.append(info)
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            let queued = self.waiting
            self.waiting = []
            for info in queued { session.transferUserInfo(info) }
        }
    }
}
