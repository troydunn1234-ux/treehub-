import SwiftUI

/// Rootbound Pro: one payment ($4.99), no subscription.
/// Free forever: logging hugs with a tree photo, the map and grove, strolls and hikes, XP, every badge and leaf,
/// Siri and widgets, and the JSON export of everything. Photos and data people already have are never locked.
enum RootboundPro {
    static let spec = PaywallSpec(
        appName: "Rootbound",
        headline: "Grow deeper roots.",
        tagline: "Add tree selfies, see what each tree does for you and take your whole history anywhere. One payment, no subscription.",
        tint: Theme.glow, tint2: Theme.leaf,
        features: [
            .init(icon: "person.crop.square.fill", title: "Tree selfies",
                  detail: "A second photo on every hug: you and your tree, side by side with the tree shot."),
            .init(icon: "chart.line.uptrend.xyaxis", title: "Tree insights",
                  detail: "Mood lift, stress drop, heart rate and your favorite time of day with each tree."),
            .init(icon: "square.and.arrow.up.on.square", title: "CSV and GPX export",
                  detail: "Spreadsheet-ready hug history, and every stroll and hike route as GPX for maps and trail apps."),
            .init(icon: "photo.stack.fill", title: "\(NatureRoll.title) map and albums",
                  detail: "Your nature photos on a map, and saved into albums in the Photos app."),
            .init(icon: "heart.fill", title: "Support an indie app",
                  detail: "No ads, no tracking, no accounts. Pro keeps it that way."),
        ],
        freeNote: "Logging hugs with a tree photo, the map, your grove, strolls, XP, every badge and leaf, and the JSON export stay free. Photos you already added never get locked.",
        privacyURL: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/rootbound/PRIVACY.md")
    )
}

/// A small inline teaser shown where a Pro feature would be.
struct RootboundProLock: View {
    let symbol: String
    let title: String
    let message: String
    var context: String
    @State private var showPlans = false

    var body: some View {
        Button { showPlans = true } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.leafGradient)
                        .frame(width: 44, height: 44)
                        .background(Theme.glow.opacity(0.12), in: Circle())
                    ProLockBadge(tint: Theme.gold).offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                    Text(message).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.gold.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: context)
    }
}
