import SwiftUI

/// Roamr Pro: monthly / yearly (with a free week) or lifetime. Recording, History, Stats,
/// the Watch app and joining a friend's group stay free.
enum RoamrPro {
    static let spec = PaywallSpec(
        appName: "Roamr",
        headline: "Go further together.",
        tagline: "Start group drives with friends and get your month-by-month recap.",
        tint: Theme.glow, tint2: Theme.leaf,
        features: [
            .init(icon: "person.2.fill", title: "Start group drives",
                  detail: "Drive with friends and see everyone live on one map."),
            .init(icon: "calendar", title: "Monthly recap",
                  detail: "Miles, hours, average speed and your longest drive, month by month."),
            .init(icon: "heart.fill", title: "Support an indie app",
                  detail: "No ads, no tracking, no accounts. Pro keeps it that way."),
        ],
        freeNote: "Recording every trip, History, Stats, the Watch app and joining a friend's group stay free.",
        privacyURL: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/roamr/PRIVACY.md")
    )
}

/// Shown in place of a Pro screen: what it is, and the plans button.
struct RoamrProLock: View {
    let symbol: String
    let title: String
    let message: String
    var context: String
    @State private var showPlans = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.leafGradient)
            Text(title).font(Theme.rounded(24, .heavy)).foregroundStyle(.white)
            Text(message)
                .font(Theme.rounded(15, .medium)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            Button { showPlans = true } label: {
                Label("See Roamr Pro", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .paywall(isPresented: $showPlans, spec: RoamrPro.spec, context: context)
    }
}
