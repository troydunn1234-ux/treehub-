import SwiftUI

enum StillPointOnboard {
    static let spec = OnboardingSpec(
        appName: "Still Point", tint: SP.gold, tint2: SP.amber,
        pages: [
            .init(icon: "leaf.fill", title: "Stillness from everywhere.", text: "39 practices from 11 traditions — Zen, Sufi, Vedic, Taoist, Stoic, Christian, Jewish and more — each with where it comes from and why it works."),
            .init(icon: "applewatch", title: "Breathe by feel.", text: "Your Apple Watch taps the rhythm: one tap in, two out, three to hold. Eyes closed, no sound, no screen needed."),
            .init(icon: "heart.text.square.fill", title: "Kept in Health.", text: "Every session lands in Apple Health as Mindful Minutes, with your heart rate during the sit. Nothing leaves your phone."),
        ],
        freeLine: "One practice from every tradition and two warm-up routines, free forever.",
        proLine: "Pro opens all 39 practices and every routine for"
    )
}
