import Foundation

/// Every metric that has a detail sheet: how to read it from a day, how to show it, and what it means.
enum MetricKey: String, CaseIterable, Identifiable {
    case rhr, hrv, resp, spo2, temp, calories, recovery, sleep, steps, activeKcal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rhr: "Resting heart rate"
        case .hrv: "Heart rate variability"
        case .resp: "Respiratory rate"
        case .spo2: "Blood oxygen"
        case .temp: "Temperature deviation"
        case .calories: "Total calories"
        case .recovery: "Recovery vs readiness"
        case .sleep: "Sleep"
        case .steps: "Steps"
        case .activeKcal: "Active calories"
        }
    }

    /// Name used by `Compare.agreements`, so a detail can show the agreement score.
    var compareName: String? {
        switch self {
        case .rhr: "Resting HR"
        case .hrv: "HRV"
        case .resp: "Respiratory rate"
        case .spo2: "Blood oxygen"
        case .temp: "Temp deviation"
        case .calories: "Calories"
        case .sleep: "Sleep"
        default: nil
        }
    }

    var unit: String {
        switch self {
        case .rhr: "bpm"
        case .hrv: "ms"
        case .resp: "br/min"
        case .spo2: "%"
        case .temp: Units.fahrenheit ? "°F" : "°C"
        case .calories, .activeKcal: "kcal"
        case .recovery: "score"
        case .sleep: "h"
        case .steps: "steps"
        }
    }

    var decimals: Int {
        switch self {
        case .resp, .spo2: 1
        case .temp: 2
        case .sleep: 1
        default: 0
        }
    }

    /// Value for one day, already in display units.
    func value(_ d: DayStat) -> Double? {
        switch self {
        case .rhr: d.rhr
        case .hrv: d.hrv
        case .resp: d.resp
        case .spo2: d.spo2
        case .temp: Units.tempDelta(d.tempDev).0
        case .calories: d.totalKcal
        case .recovery: d.recovery
        case .sleep: nil   // sleep lives on nights, see `nightValue`
        case .steps: d.steps
        case .activeKcal: d.activeKcal
        }
    }

    func nightValue(_ n: SleepNight) -> Double? { self == .sleep && n.asleepMin > 0 ? n.asleepMin / 60 : nil }

    var usesNights: Bool { self == .sleep }

    /// Lower is "better" (for colouring min/max), nil when neither is.
    var lowerIsBetter: Bool? {
        switch self {
        case .rhr, .resp: true
        case .hrv, .spo2, .recovery, .sleep, .steps: false
        default: nil
        }
    }

    var explanation: String {
        switch self {
        case .rhr:
            "Your lowest steady heart rate, a classic fitness and fatigue marker. Apple Watch estimates it from readings during the day while you're still; WHOOP takes it from your last slow-wave sleep. Different moments, so a 1–4 bpm gap is normal. Watch the trend."
        case .hrv:
            "How much the time between heartbeats varies. Higher usually means more recovered. Apple Watch reports SDNN from short spot readings; WHOOP reports RMSSD measured through the night. They're different maths, so WHOOP is usually higher. Compare the shape of the lines, not the numbers."
        case .resp:
            "Breaths per minute while you sleep. It's very stable night to night, so a jump of 1+ can be an early sign of illness or heavy strain. Both trackers measure it overnight and usually agree closely."
        case .spo2:
            "How saturated your blood is with oxygen while asleep. 95–100% is typical. Wrist sensors are less precise than a finger clip; small differences between devices are expected."
        case .temp:
            "Change in skin/wrist temperature from your own average, not body temperature. Rises can come with illness, alcohol, a hot room or the menstrual cycle. Apple Watch measures wrist temp asleep; WHOOP measures skin temp."
        case .calories:
            "Everything you burned in the day (active + resting). WHOOP estimates from heart rate alone; Apple Watch combines heart rate, motion and your profile. Expect gaps of a few hundred kcal."
        case .recovery:
            "WHOOP recovery (0–100) blends HRV, resting HR, sleep and breathing. Readiness is Pulse Lab's own Watch score built the same way from HRV vs your 7-day baseline, resting HR and sleep, so you can put them side by side."
        case .sleep:
            "Time actually asleep (light + deep + REM), credited to the morning you woke up. Trackers disagree most on where light sleep ends and awake begins."
        case .steps:
            "Steps counted from motion. Apple Watch and iPhone count them; WHOOP doesn't report steps through its API."
        case .activeKcal:
            "Calories burned above resting. Apple Watch reports this directly; WHOOP gives one total for the day instead."
        }
    }
}
