import Foundation
import SwiftUI
import UIKit
import WatchConnectivity

/// iPhone side of the Apple Watch remote: the watch sends button presses and app launches,
/// the phone forwards them to the TV (WatchConnectivity wakes the phone app in the background).
@MainActor
final class ClankerrWatchBridge: NSObject {
    static let shared = ClankerrWatchBridge()

    private weak var store: TVStore?
    private var timer: Timer?
    private var lastKey = ""
    private var playing = true

    func attach(_ store: TVStore) {
        guard WCSession.isSupported() else { return }
        self.store = store
        let s = WCSession.default
        s.delegate = self
        s.activate()
        timer?.invalidate()
        // Cheap check every few seconds: push only when the TV, now playing or favorites change.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pushIfChanged() }
        }
    }

    private func pushIfChanged(force: Bool = false) {
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let state = snapshot()
        let key = "\(state["tv"] ?? "")|\(state["now"] ?? "")|\(state["paired"] ?? "")|\((state["apps"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ",") ?? "")"
        guard force || key != lastKey else { return }
        lastKey = key
        try? s.updateApplicationContext(state)
        if s.isReachable { s.sendMessage(state, replyHandler: nil, errorHandler: nil) }
    }

    func snapshot() -> [String: Any] {
        guard let store else { return ["paired": false] }
        let apps: [[String: Any]] = store.favoriteApps.prefix(8).map { app in
            let c = app.colors
            return ["name": app.name, "c1": Self.hex(c.first ?? .purple), "c2": Self.hex(c.last ?? .black)] as [String: Any]
        }
        return ["paired": store.isPaired, "tv": store.tv?.name ?? "", "now": store.nowPlaying ?? "",
                "reachable": store.reachable, "apps": apps]
    }

    private static func hex(_ color: Color) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return (c(r) << 16) | (c(g) << 8) | c(b)
    }

    // MARK: Commands from the watch

    fileprivate func handle(_ msg: [String: Any]) async -> [String: Any] {
        guard let store else { return snapshot() }
        if let k = msg["key"] as? String {
            let key: VizioClient.Key?
            switch k {
            case "up": key = .up
            case "down": key = .down
            case "left": key = .left
            case "right": key = .right
            case "ok": key = .ok
            case "back": key = .back
            case "home": key = .home
            case "menu": key = .menu
            case "volUp": key = .volumeUp
            case "volDown": key = .volumeDown
            case "mute": key = .muteToggle
            case "power": key = .powerToggle
            case "input": key = .inputNext
            case "playPause":
                key = playing ? .pause : .play
                playing.toggle()
            default: key = nil
            }
            if let key { store.press(key) }
        } else if let name = msg["launch"] as? String, let app = store.catalog.first(where: { $0.name == name }) {
            await store.launch(app)
            playing = true
        }
        lastKey = ""
        return snapshot()
    }
}

extension ClankerrWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushIfChanged(force: true) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = await self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if message.isEmpty { replyHandler(self.snapshot()) } else { replyHandler(await self.handle(message)) }
        }
    }
}
