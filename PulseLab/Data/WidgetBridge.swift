import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Hands today's headline numbers to the home-screen widget through the shared App Group,
/// then asks WidgetKit to redraw. The widget extension (PulseLabWidgets) reads the same keys.
///
/// INTEGRATOR NOTE: both the app and the widget extension need the App Groups entitlement
/// (`com.apple.security.application-groups`) containing `group.com.troydunn.pulselab`.
enum WidgetBridge {
    static let suite = "group.com.troydunn.pulselab"

    /// Keys (Doubles; -1 means "no value", except the optionals which are simply absent).
    enum Key {
        static let recovery = "recovery"
        static let readiness = "readiness"
        static let rhrWatch = "rhrWatch"
        static let rhrWhoop = "rhrWhoop"
        static let sleepWatch = "sleepWatch"
        static let sleepWhoop = "sleepWhoop"
        static let updatedAt = "updatedAt"
    }

    @MainActor
    static func publish(_ store: LabStore) {
        guard let d = UserDefaults(suiteName: suite) else { return }
        func put(_ v: Double?, _ key: String) { if let v { d.set(v, forKey: key) } else { d.removeObject(forKey: key) } }
        put(store.recoveryToday, Key.recovery)
        put(store.readinessToday, Key.readiness)
        d.set(store.today(.watch)?.rhr ?? -1, forKey: Key.rhrWatch)
        d.set(store.today(.whoop)?.rhr ?? -1, forKey: Key.rhrWhoop)
        d.set(store.lastNight(.watch).map { $0.asleepMin / 60 } ?? -1, forKey: Key.sleepWatch)
        d.set(store.lastNight(.whoop).map { $0.asleepMin / 60 } ?? -1, forKey: Key.sleepWhoop)
        d.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
