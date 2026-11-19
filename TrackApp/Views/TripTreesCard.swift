import SwiftUI
import UIKit

/// Trip detail: Rootbound trees this walk, run or hike started or ended near (Rootbound works it out from its own
/// tree locations and Roamr's rounded start / end points, then shares only tree ids and names: rootbound.json
/// tripTrees). Trees hugged on the trip are already under "Tree hugs on this walk" (TripConnections.swift), so
/// they're left out here. A tree opens its page in Rootbound; "Log a hug" opens Rootbound's hug logger (it
/// attaches the walk to the hug by time). Hidden when Rootbound isn't installed or found no trees.
@MainActor
struct TripTreesCard: View {
    let tripID: UUID
    let kind: ActivityKind
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }

    private static let green = Color(red: 0.55, green: 0.80, blue: 0.49)

    var body: some View {
        let trees = nearby
        if !trees.isEmpty {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: String(localized: "Trees along this \(noun)"), symbol: "leaf.fill")
                    Text(trees.count == 1 ? String(localized: "You passed one of your Rootbound trees.")
                                          : String(localized: "You passed \(trees.count) of your Rootbound trees."))
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(trees) { row($0) }
                    Button {
                        open(WellnessLinks.hugLogger)
                    } label: {
                        Label(String(localized: "Log a hug in Rootbound"), systemImage: "heart.fill")
                            .font(Theme.rounded(16, .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Self.green, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Opens the hug logger in Rootbound"))
                    if let updated = feed.rootbound?.updated {
                        TimelineView(.everyMinute) { ctx in
                            Text(String(localized: "From Rootbound") + " · " + WellnessConnect.updatedText(updated, now: ctx.date))
                                .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim.opacity(0.8))
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    /// Trees Rootbound matched to this trip, minus the ones hugged on it (shown with the hugs).
    private var nearby: [WellnessBridge.NearTree] {
        guard kind != .drive, feed.has(WellnessConnect.rootbound) else { return [] }
        if WellnessConnect.isDemo {
            return [.init(treeID: UUID(uuidString: "6E1F1C1A-0000-4000-8000-00000000D3E1")!, name: "Grandpa Oak", species: "Valley Oak")]
        }
        return WellnessConnect.trees(onTrip: tripID, in: feed.rootbound).filter { !$0.hugged }
    }

    private var noun: String {
        switch kind {
        case .walk: return String(localized: "walk")
        case .run: return String(localized: "run")
        case .hike: return String(localized: "hike")
        case .bike: return String(localized: "ride")
        case .drive: return String(localized: "drive")
        }
    }

    private func row(_ t: WellnessBridge.NearTree) -> some View {
        Button { open(WellnessConnect.rootboundTree(t.treeID)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "tree.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Self.green)
                    .frame(width: 38, height: 38)
                    .background(Self.green.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(t.species.isEmpty ? String(localized: "Near the start or end")
                                           : t.species + " · " + String(localized: "near the start or end"))
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Opens this tree in Rootbound"))
    }

    private func open(_ url: URL) {
        taps += 1
        WellnessConnect.open(url, in: WellnessConnect.rootbound)
    }
}
