import SwiftUI
import UIKit

/// Today, next to readiness: calm minutes from Still Pointz, tree hugs from Rootbound and distance on foot from
/// Roamr, read from the family's shared feed (Shared/Wellness/WellnessConnect.swift) and re-read whenever Pulse Lab
/// comes to the front. Numbers only, each with the app it came from and how fresh it is; a tap opens that app
/// (its App Store page when it isn't on this iPhone). Hidden when none of the three is installed.
@MainActor
struct CalmMovementCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }

    // Each app's own accent (not Lab.good / Lab.whoop, which mean "good" and "WHOOP" everywhere else here).
    private static let stillPointBlue = Color(red: 0.56, green: 0.64, blue: 1.0)
    private static let rootboundGreen = Color(red: 0.45, green: 0.80, blue: 0.45)
    private static let roamrOrange = Color(red: 1.0, green: 0.50, blue: 0.24)

    var body: some View {
        let today = feed.today
        let calm = feed.has(WellnessConnect.stillPoint)
        let hugs = feed.has(WellnessConnect.rootbound)
        let moves = feed.has(WellnessConnect.roamr)
        if calm || hugs || moves {
            LabPanel {
                VStack(alignment: .leading, spacing: Lab.S.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTag("Calm & movement")
                        Text("Today, from your other apps")
                            .font(.footnote).foregroundStyle(Lab.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TimelineView(.everyMinute) { ctx in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s, alignment: .top),
                                                 count: columns),
                                  alignment: .leading, spacing: Lab.S.s) {
                            if calm { calmTile(today.calm, now: ctx.date) }
                            if hugs { hugsTile(today.hugs, now: ctx.date) }
                            if moves { movesTile(today.moves, now: ctx.date) }
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    /// Three across at standard sizes, two at the larger ones, one at accessibility sizes (no clipped numbers).
    private var columns: Int {
        if typeSize.isAccessibilitySize { return 1 }
        return typeSize > .large ? 2 : 3
    }

    private func calmTile(_ c: WellnessConnect.Today.Calm?, now: Date) -> LabPeerTile {
        let peer = WellnessConnect.stillPoint
        let tint = Self.stillPointBlue
        guard let c else { return notShared(peer, symbol: "wind", tint: tint, label: String(localized: "Calm min"), url: WellnessConnect.stillPointJourney) }
        return LabPeerTile(symbol: "wind", tint: tint, value: "\(Int(c.minutes.rounded()))", label: String(localized: "Calm min"),
                              caption: "Still Pointz · " + WellnessConnect.updatedText(c.updated, now: now),
                              hint: String(localized: "Opens your Journey in Still Pointz")) { open(WellnessConnect.stillPointJourney, peer) }
    }

    private func hugsTile(_ h: WellnessConnect.Today.Hugs?, now: Date) -> LabPeerTile {
        let peer = WellnessConnect.rootbound
        let tint = Self.rootboundGreen
        guard let h else { return notShared(peer, symbol: "tree.fill", tint: tint, label: String(localized: "Tree hugs"), url: WellnessConnect.rootboundHome) }
        let mins = Int(h.minutes.rounded())
        let label = h.count == 0 ? String(localized: "Tree hugs")
            : (h.count == 1 ? String(localized: "Tree hug, \(mins) min") : String(localized: "Tree hugs, \(mins) min"))
        return LabPeerTile(symbol: "tree.fill", tint: tint, value: "\(h.count)", label: label,
                              caption: "Rootbound · " + WellnessConnect.updatedText(h.updated, now: now),
                              hint: String(localized: "Opens Rootbound")) { open(WellnessConnect.rootboundHome, peer) }
    }

    private func movesTile(_ m: WellnessConnect.Today.Moves?, now: Date) -> LabPeerTile {
        let peer = WellnessConnect.roamr
        let tint = Self.roamrOrange
        guard let m else { return notShared(peer, symbol: "figure.walk", tint: tint, label: String(localized: "On foot"), url: WellnessConnect.roamrHistory) }
        return LabPeerTile(symbol: "figure.walk", tint: tint,
                              value: WellnessConnect.distance(m.distanceM, metric: !Units.imperial),
                              label: m.trips == 1 ? String(localized: "On foot, 1 walk")
                                  : (m.trips == 0 ? String(localized: "On foot") : String(localized: "On foot, \(m.trips) walks")),
                              caption: "Roamr · " + WellnessConnect.updatedText(m.updated, now: now),
                              hint: String(localized: "Opens your history in Roamr")) { open(WellnessConnect.roamrHistory, peer) }
    }

    /// Installed, but it hasn't shared anything yet (not opened since it learned to share).
    private func notShared(_ peer: WellnessConnect.Peer, symbol: String, tint: Color, label: String, url: URL) -> LabPeerTile {
        LabPeerTile(symbol: symbol, tint: tint, value: String(localized: "Not yet"), label: label,
                       caption: String(localized: "Open \(peer.name) once to share"), hint: String(localized: "Opens \(peer.name)")) { open(url, peer) }
    }

    private func open(_ url: URL, _ peer: WellnessConnect.Peer) {
        taps += 1
        WellnessConnect.open(url, in: peer)
    }
}

/// One number from another family app, in the Lab tile style. Tappable when it opens the app.
@MainActor
struct LabPeerTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String
    let caption: String
    var hint: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { face }
                .buttonStyle(PressScale())
                .accessibilityHint(hint ?? "")
        } else {
            face
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: Lab.S.xs) {
            HStack(spacing: Lab.S.xs) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Lab.faint)
                }
            }
            Text(value)
                .font(Lab.number(22))
                .foregroundStyle(Lab.text)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.caption.weight(.semibold)).foregroundStyle(Lab.dim)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(.caption2).foregroundStyle(Lab.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Lab.S.sm)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.inset))
        .contentShape(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value). \(caption)")
    }
}
