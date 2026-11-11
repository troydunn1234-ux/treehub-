import SwiftUI

enum PulseLabOnboard {
    static let spec = OnboardingSpec(
        appName: "Pulse Lab", tint: Lab.watch, tint2: Lab.whoop,
        pages: [
            .init(icon: "bolt.heart.fill", title: "Watch vs WHOOP.\nFinally side by side.", text: "Pulse Lab pulls everything your Apple Watch and WHOOP record — sleep, HRV, resting HR, SpO₂, strain, calories — and lines them up day by day."),
            .init(icon: "scope", title: "Who's right?", text: "Each metric gets an agreement score, a plain-English read, and the reason the two differ — so a gap reads as expected, not broken."),
            .init(icon: "lock.shield.fill", title: "Your data stays yours.", text: "Health data is read on-device. WHOOP connects through its official login and is stored only on this phone."),
        ],
        freeLine: "Today, Sleep, Heart and Moves with both trackers side by side, 30 days back — free.",
        proLine: "Pro opens the VS lab, 90-day history, share cards and CSV export for"
    )
}
