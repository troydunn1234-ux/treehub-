import Foundation

/// Hands today's WHOOP / readiness summary to Still Pointz through the shared wellness App Group
/// (Shared/Wellness/WellnessBridge.swift, file pulselab.json). Still Pointz uses it for its one
/// "Right now" suggestion. Numbers only; nothing leaves the phone. Skipped in demo mode.
enum PulseLabWellness {
    @MainActor
    static func publish(_ store: LabStore) {
        guard !LabStore.isDemo else { return }
        let today = Date().dayStart
        let whoopToday = store.whoopDays.stat(on: today)
        let watchToday = store.watchDays.stat(on: today)
        let b = store.briefing
        let whoopNight = store.lastNight(.whoop)
        let recentNight: (SleepNight?) -> SleepNight? = { n in
            guard let n, n.night >= today.adding(days: -1) else { return nil }
            return n
        }
        let wn = recentNight(whoopNight)
        let anyNight = wn ?? recentNight(store.lastNight(.watch))
        let manual = store.manualEntry(today) != nil
        var part = WellnessBridge.PulseLabPart(date: WellnessBridge.dayKey(today))
        part.whoopRecovery = whoopToday?.recovery
        part.whoopStrain = whoopToday?.strain ?? b.strainYesterday
        part.sleepPerformance = wn?.performance
        part.readiness = store.readinessToday
        part.hrv = b.hrv
        part.rhr = b.rhr
        part.sleepMinutes = anyNight.map(\.asleepMin)
        part.fromWhoopAPI = WhoopAdapter.connected && whoopToday != nil
        part.fromWhoopManual = manual
        part.fromWhoopHealth = whoopToday != nil && !WhoopAdapter.connected && !manual
        part.fromWatch = watchToday != nil
        WellnessBridge.publishPulseLab(part)
    }
}
