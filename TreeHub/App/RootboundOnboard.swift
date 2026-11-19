import SwiftUI

/// First-launch welcome (Shared/Store/Onboarding.swift), three pages that lead with what Rootbound is:
/// real tree hugs timed on Apple Watch with heart rate, a personal tree map, and trees with names and species.
/// No permission is asked here: location, camera and photos are asked the first time you log a hug, Health the
/// first time a hug is timed on the Watch or a breath session is linked.
enum RootboundOnboard {
    static let spec = OnboardingSpec(
        appName: "Rootbound", tint: Theme.glow, tint2: Theme.leaf,
        pages: [
            .init(icon: "heart.circle.fill",
                  title: "Hug a real tree.",
                  text: "Start a hug from Rootbound on your Apple Watch and hold on. It shows your heart rate live, taps your wrist at the start and end, and keeps how much it dropped while you were with the tree."),
            .init(icon: "map.fill",
                  title: "Your own tree map.",
                  text: "Every tree you hug gets a pin and a photo. Come back to the same trees, see your friendship grow, and get walking directions back to any of them."),
            .init(icon: "leaf.fill",
                  title: "Know each tree.",
                  text: "Name your trees, get a suggested species from the photo with a fact about it, and see how each one settles you over time. Location, photos and Health are asked only when you first need them."),
        ],
        freeLine: "Logging hugs, Watch timing, the tree map, your grove, XP, badges and leaves are free.",
        proLine: "Pro adds tree selfies, tree insights, CSV and GPX export and the Nature Roll map for",
        version: 1
    )
}
