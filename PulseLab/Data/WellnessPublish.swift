import Foundation
import UIKit

/// Hands today's WHOOP / readiness summary to Still Pointz and Rootbound through the shared wellness App Group
/// (Shared/Wellness/WellnessBridge.swift, file pulselab.json). Still Pointz uses it for its one "Right now"
/// suggestion; both show today's readiness. Numbers only; nothing leaves the phone. Skipped in demo mode.
/// Written after every refresh: launch, foreground, pull to refresh, new Health samples (background delivery),
/// the background refresh task and manual WHOOP entries, so a new day's file appears without opening the app.
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
        // A background wake that read less (iPhone locked, so Health isn't readable yet) must not blank out numbers
        // already shared for today: keep today's earlier values where this pass found none. In the foreground,
        // what Pulse Lab shows is what it shares.
        if UIApplication.shared.applicationState == .background,
           let shared = WellnessBridge.pulseLab(), shared.date == part.date {
            part = keepingEarlier(part, shared)
        }
        WellnessBridge.publishPulseLab(part)
    }

    /// `new` with each missing number (and its source flag) taken from `old`, the same day's earlier summary.
    static func keepingEarlier(_ new: WellnessBridge.PulseLabPart, _ old: WellnessBridge.PulseLabPart) -> WellnessBridge.PulseLabPart {
        guard new.date == old.date else { return new }
        var p = new
        p.whoopRecovery = p.whoopRecovery ?? old.whoopRecovery
        p.whoopStrain = p.whoopStrain ?? old.whoopStrain
        p.sleepPerformance = p.sleepPerformance ?? old.sleepPerformance
        p.readiness = p.readiness ?? old.readiness
        p.hrv = p.hrv ?? old.hrv
        p.rhr = p.rhr ?? old.rhr
        p.sleepMinutes = p.sleepMinutes ?? old.sleepMinutes
        p.fromWhoopAPI = p.fromWhoopAPI || old.fromWhoopAPI
        p.fromWhoopManual = p.fromWhoopManual || old.fromWhoopManual
        p.fromWhoopHealth = p.fromWhoopHealth || old.fromWhoopHealth
        p.fromWatch = p.fromWatch || old.fromWatch
        return p
    }
}
