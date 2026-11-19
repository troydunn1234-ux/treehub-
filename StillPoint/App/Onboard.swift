import SwiftUI

/// First-launch welcome (Shared/Store/Onboarding.swift): Right now from Watch / WHOOP data, sauna & steam,
/// the two daily reminders.
/// Permissions are not asked for here: Health is requested the first time a session or sauna timer runs
/// (or the recovery chart opens), notifications when a reminder or sauna check-in is first needed.
enum StillPointOnboard {
    static let spec = OnboardingSpec(
        appName: "Still Pointz", tint: SP.accent, tint2: Color(spHex: "#CFC6FF"),
        pages: [
            .init(icon: "sparkles",
                  title: String(localized: "One practice, right now."),
                  text: String(localized: "Still Pointz reads your heart rate, HRV, breathing rate and last night's sleep from your Apple Watch or WHOOP in Health, and picks the one practice that fits this moment. Why this? shows every number behind it.")),
            .init(icon: "flame.fill",
                  title: String(localized: "Made for the sauna and steam room."),
                  text: String(localized: "Tap Sauna or Steam as you walk in. Heat-safe breathing, bench moves and a timer, with your heart rate for each session.")),
            .init(icon: "sunrise.fill",
                  title: String(localized: "Gentle 6 AM and bedtime picks."),
                  text: String(localized: "Two quiet notifications a day, each with that moment's practice: a morning pick from your night, a wind-down shaped by your day. Health and notifications are asked the first time they're needed. Nothing leaves your devices.")),
        ],
        freeLine: String(localized: "\(PracticeLibrary.shared.freeCount) practices, including Calm SOS, body scan and Tree Hugs, free forever."),
        proLine: String(localized: "Pro opens every practice, routine and the sauna & steam guide for"),
        version: 2
    )
}
