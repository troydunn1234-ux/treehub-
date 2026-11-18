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
        // Morning briefing (Siri "Today's recovery", the Watch app).
        static let briefingSpoken = "briefingSpoken"
        static let briefingDay = "briefingDay"
        static let hrv = "hrv"
        static let strain = "strain"
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
        let b = store.briefing
        d.set(b.spoken, forKey: Key.briefingSpoken)
        d.set(Date().dayStart.timeIntervalSince1970, forKey: Key.briefingDay)
        put(b.hrv, Key.hrv)
        put(store.whoopDays.stat(on: Date())?.strain ?? b.strainYesterday, Key.strain)
        // Reload the widgets only when what they show changed: refreshes run on every new Health sample, and each
        // reload spends the widgets' daily budget (then they stop updating until iOS gives more).
        let shown = [Key.recovery, Key.readiness, Key.rhrWatch, Key.rhrWhoop, Key.sleepWatch, Key.sleepWhoop,
                     Key.briefingSpoken, Key.briefingDay, Key.hrv, Key.strain]
            .map { "\(d.object(forKey: $0) ?? "-")" }.joined(separator: "|")
        guard shown != lastShown else { return }
        lastShown = shown
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// What the widgets were last reloaded with (this launch).
    @MainActor private static var lastShown: String?
}
