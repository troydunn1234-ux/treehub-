import SwiftUI

/// First-launch welcome (Shared/Store/Onboarding.swift): what it does, sauna & steam, Health & Watch.
/// Permissions are not asked for here: Health is requested the first time a session or sauna timer runs
/// (or the recovery chart opens), notifications when a reminder or sauna check-in is first needed.
enum StillPointOnboard {
    static let spec = OnboardingSpec(
        appName: "Still Pointz", tint: SP.accent, tint2: Color(spHex: "#CFC6FF"),
        pages: [
            .init(icon: "leaf.fill",
                  title: String(localized: "Stillness from everywhere."),
                  text: String(localized: "Breathwork, stillness and gentle warm-ups from \(PracticeLibrary.shared.traditions.count) traditions, sorted by goal, each saying in plain words what it does and how. Turn on the voice guide and just listen.")),
            .init(icon: "flame.fill",
                  title: String(localized: "Made for the sauna and steam room."),
                  text: String(localized: "Tap Sauna or Steam as you walk in. Heat-safe breathing, bench moves and a timer, then see how your mornings look after a heat day.")),
            .init(icon: "applewatch",
                  title: String(localized: "Health and Watch, when you want them."),
                  text: String(localized: "Sessions can go to Health as Mindful Minutes, with heart rate from your Watch or WHOOP. You'll be asked the first time it's needed. Nothing leaves your devices.")),
        ],
        freeLine: String(localized: "\(PracticeLibrary.shared.freeCount) practices, including Calm SOS, body scan and Tree Hugs, free forever."),
        proLine: String(localized: "Pro opens every practice, routine and the sauna & steam guide for"),
        version: 2
    )
}
