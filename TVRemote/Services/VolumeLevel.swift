import Foundation

extension TVStore {
    /// Sets the TV to a volume level (0–100). TVs that take an exact level (LG) jump straight there; the rest
    /// only take up/down presses, so this steps all the way down and back up to the level.
    /// Returns true when the level was set exactly, false when it was stepped (close, not guaranteed).
    @discardableResult
    func setVolume(level: Int) async throws -> Bool {
        let level = max(0, min(100, level))
        if Self.demo { show("Volume \(level)"); return true }
        guard let t = tv else { throw CouchRemoteIntentError.noTV }
        let c = controller(for: t.brand)
        do {
            try await c.setVolume(t, level: level)
            return true
        } catch TVControlError.unsupported {
            // Down to zero first (we can't read the current level on most TVs), then up to the level.
            for _ in 0..<60 {
                try await c.press(t, .volumeDown)
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            for _ in 0..<level {
                try await c.press(t, .volumeUp)
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            return false
        }
    }

    /// Turns the TV off and waits for the command to go out (used by the sleep timer, also from the background).
    func powerOffNow() async -> Bool {
        if Self.demo { show("Sleep timer: TV off"); return true }
        guard let t = tv else { return false }
        do {
            try await controller(for: t.brand).press(t, .powerOff)
            return true
        } catch {
            return false
        }
    }
}
