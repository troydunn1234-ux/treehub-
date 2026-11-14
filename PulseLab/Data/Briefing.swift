import Foundation
import UserNotifications

/// This morning in one card: recovery (WHOOP, or Pulse Lab readiness from the Watch), last night's sleep
/// against the 7 nights before, HRV and resting HR against the 30 days before, yesterday's strain and
/// one plain-English takeaway. Pure numbers from LabStore; no medical claims.
struct Briefing: Equatable {
    enum RecoveryKind: String { case whoop, readiness }

    var recovery: Double?
    var recoveryKind: RecoveryKind = .whoop
    /// Tracker the sleep / HRV / resting HR numbers come from.
    var source: Source = .watch
    var sleepMin: Double?
    var sleepAvgMin: Double?
    var hrv: Double?
    var hrvBase: Double?
    var rhr: Double?
    var rhrBase: Double?
    var strainYesterday: Double?
    /// WHOOP is in use but today's recovery hasn't arrived (API, Health or typed in).
    var whoopMissing = false

    var isEmpty: Bool { recovery == nil && sleepMin == nil && hrv == nil && rhr == nil && strainYesterday == nil }

    /// Signed % change of HRV vs its baseline.
    var hrvDeltaPct: Double? {
        guard let h = hrv, let b = hrvBase, b > 0 else { return nil }
        return (h - b) / b * 100
    }
    var rhrDelta: Double? {
        guard let r = rhr, let b = rhrBase else { return nil }
        return r - b
    }
    var sleepDeltaMin: Double? {
        guard let s = sleepMin, let a = sleepAvgMin else { return nil }
        return s - a
    }

    var recoveryLabel: String {
        recoveryKind == .whoop ? String(localized: "WHOOP recovery") : String(localized: "Watch readiness")
    }

    // MARK: Build

    @MainActor
    static func build(_ store: LabStore, now: Date = Date()) -> Briefing {
        var b = Briefing()
        let today = now.dayStart
        let whoopToday = store.whoopDays.stat(on: today)
        if let r = whoopToday?.recovery {
            b.recovery = r
            b.recoveryKind = .whoop
        } else if let r = store.readinessToday {
            b.recovery = r
            b.recoveryKind = .readiness
        }
        let usesWhoop = store.whoopConnected || !store.whoopDays.isEmpty || store.manualEntry(today.adding(days: -1)) != nil
        b.whoopMissing = usesWhoop && whoopToday?.recovery == nil

        // Numbers from the tracker behind the recovery score; the other one fills in what's missing.
        let primary: Source = b.recoveryKind == .whoop ? .whoop : .watch
        let order: [Source] = primary == .whoop ? [.whoop, .watch] : [.watch, .whoop]
        b.source = primary

        for s in order {
            let nights = store.sleeps.filter { $0.source == s && $0.asleepMin > 0 }
            guard let last = nights.last(where: { $0.night == today }) ?? nights.last(where: { $0.night == today.adding(days: -1) })
            else { continue }
            b.sleepMin = last.asleepMin
            let prior = nights.filter { $0.night < last.night && $0.night >= last.night.adding(days: -7) }.map(\.asleepMin)
            if prior.count >= 3 { b.sleepAvgMin = Stats.mean(prior) }
            break
        }

        func metric(_ kp: KeyPath<DayStat, Double?>) -> (Double, Double?)? {
            for s in order {
                let days = store.days(s)
                // Today's value, or yesterday's when the tracker hasn't written today's yet.
                guard let d = days.last(where: { $0.day >= today.adding(days: -1) && $0[keyPath: kp] != nil }),
                      let v = d[keyPath: kp] else { continue }
                let base = days.filter { $0.day < d.day && $0.day >= d.day.adding(days: -30) }.compactMap { $0[keyPath: kp] }
                return (v, base.count >= 7 ? Stats.mean(base) : nil)
            }
            return nil
        }
        if let h = metric(\.hrv) { b.hrv = h.0; b.hrvBase = h.1 }
        if let r = metric(\.rhr) { b.rhr = r.0; b.rhrBase = r.1 }
        b.strainYesterday = store.whoopDays.stat(on: today.adding(days: -1))?.strain
        return b
    }

    // MARK: Words

    /// One plain-English line. Describes the numbers; never diagnoses.
    var takeaway: String {
        if isEmpty { return String(localized: "No numbers yet this morning. Sync after you wake up and the briefing fills in.") }
        let hrvD = hrvDeltaPct ?? 0, rhrD = rhrDelta ?? 0, sleepD = sleepDeltaMin ?? 0
        let low = (recovery.map { $0 < 34 } ?? false) || (hrvD <= -15 && rhrD >= 3)
        let high = (recovery.map { $0 >= 67 } ?? false) && hrvD >= -5 && rhrD <= 2
        if low {
            return String(localized: "Your numbers are running below your usual today. An easier session and an earlier night are worth considering.")
        }
        if sleepD <= -45, let s = sleepMin {
            return String(localized: "Short night: \(fmtHM(s)), about \(fmtHM(-sleepD)) under your 7-night average. Expect today to feel it.")
        }
        if let st = strainYesterday, st >= 15 {
            return String(localized: "Big day yesterday (strain \(st.formatted(.number.precision(.fractionLength(1))))). Recovery often trails a hard day by one morning.")
        }
        if high {
            return String(localized: "Green light: recovery is high and HRV and resting HR sit at or better than your baseline.")
        }
        if hrvD >= 10 {
            return String(localized: "HRV is above your 30-day baseline this morning, a sign you're well rested by your own standard.")
        }
        return String(localized: "Steady morning: your numbers are close to your usual baseline.")
    }

    /// Short lines for the notification body and Siri.
    var spoken: String {
        var parts: [String] = []
        if let r = recovery {
            parts.append(recoveryKind == .whoop
                         ? String(localized: "WHOOP recovery is \(Int(r.rounded())) percent")
                         : String(localized: "Watch readiness is \(Int(r.rounded()))"))
        }
        if let s = sleepMin {
            if let d = sleepDeltaMin, abs(d) >= 10 {
                parts.append(d > 0 ? String(localized: "you slept \(fmtHM(s)), \(fmtHM(d)) more than your weekly average")
                                   : String(localized: "you slept \(fmtHM(s)), \(fmtHM(-d)) less than your weekly average"))
            } else {
                parts.append(String(localized: "you slept \(fmtHM(s))"))
            }
        }
        if let h = hrv {
            if let p = hrvDeltaPct {
                parts.append(String(localized: "HRV is \(Int(h.rounded())) milliseconds, \(Int(abs(p).rounded())) percent \(p >= 0 ? String(localized: "above") : String(localized: "below")) your baseline"))
            } else {
                parts.append(String(localized: "HRV is \(Int(h.rounded())) milliseconds"))
            }
        }
        if let st = strainYesterday {
            parts.append(String(localized: "yesterday's strain was \(st.formatted(.number.precision(.fractionLength(1))))"))
        }
        guard !parts.isEmpty else { return takeaway }
        var text = parts.joined(separator: ", ") + "."
        text = text.prefix(1).uppercased() + text.dropFirst()
        return text + " " + takeaway
    }

    /// Compact notification body: "Recovery 72% · Slept 7h 12m (+20m) · HRV 61 ms (+8%)".
    var compactLine: String {
        var parts: [String] = []
        if let r = recovery { parts.append(recoveryKind == .whoop ? String(localized: "Recovery \(Int(r.rounded()))%") : String(localized: "Readiness \(Int(r.rounded()))")) }
        if let s = sleepMin {
            var t = String(localized: "Slept \(fmtHM(s))")
            if let d = sleepDeltaMin, abs(d) >= 10 { t += " (\(d > 0 ? "+" : "−")\(fmtHM(abs(d))))" }
            parts.append(t)
        }
        if let h = hrv {
            var t = String(localized: "HRV \(Int(h.rounded())) ms")
            if let p = hrvDeltaPct { t += " (\(p >= 0 ? "+" : "−")\(Int(abs(p).rounded()))%)" }
            parts.append(t)
        }
        if let st = strainYesterday { parts.append(String(localized: "Strain yday \(st.formatted(.number.precision(.fractionLength(1))))")) }
        return parts.joined(separator: " · ")
    }
}

/// The one morning notification. Replaces the separate "Log WHOOP" reminder so nobody gets two:
/// when today's WHOOP numbers are missing it asks for them; otherwise it carries the briefing.
enum MorningBriefing {
    static let key = "morningBriefing"
    static let url = URL(string: "pulselab://today")!

    /// "Morning briefing" notification. Off until turned on (Settings or onboarding).
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Ask for notification permission and turn the briefing on. False when notifications are denied.
    @discardableResult
    static func enable(loggedToday: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        enabled = granted
        await WhoopPrompt.reschedule(loggedToday: loggedToday)
        return granted
    }

    /// Latest briefing and WHOOP state, handed over by LabStore after each sync so the scheduler
    /// (which runs off the main actor) can write today's text.
    nonisolated(unsafe) static var latest: Briefing?
    nonisolated(unsafe) static var whoopAPI = false
    nonisolated(unsafe) static var usesWhoop = true

    /// Briefing text published for Siri and the Watch (WidgetBridge writes it to the App Group).
    @MainActor
    static func current(_ store: LabStore) -> Briefing { Briefing.build(store) }
}
