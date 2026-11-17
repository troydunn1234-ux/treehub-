import SwiftUI
import UIKit
import CoreLocation

// Rootbound's side of the family connections (Shared/Wellness/WellnessConnect.swift): what the other apps
// shared about today, and the Roamr walks that passed a tree. Read-only; taps open the other app (or its
// App Store page when it isn't on this iPhone). The feed is re-read whenever Rootbound comes to the front.

/// Home: today's hugs next to calm minutes from Still Pointz (opens Journey), distance on foot from Roamr
/// (opens History) and readiness from Pulse Lab (opens Today). Each tile says how fresh its numbers are.
/// An app that isn't on this iPhone gets no tile; the card hides when none of them is.
@MainActor
struct TodayConnectionsCard: View {
    let hugs: [Hug]
    @State private var taps = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    private var feed: WellnessFeed { WellnessFeed.shared }

    var body: some View {
        let today = feed.today
        let calm = feed.has(WellnessConnect.stillPoint)
        let moves = feed.has(WellnessConnect.roamr)
        let ready = feed.has(WellnessConnect.pulseLab)
        if calm || moves || ready {
            RBCard {
                VStack(alignment: .leading, spacing: RB.m) {
                    RBSectionTitle(title: "Today across your apps", symbol: "sun.max.fill")
                    TimelineView(.everyMinute) { ctx in
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                                                 count: typeSize.isAccessibilitySize ? 1 : 2),
                                  alignment: .leading, spacing: 10) {
                            hugsTile
                            if calm { calmTile(today.calm, now: ctx.date) }
                            if moves { movesTile(today.moves, now: ctx.date) }
                            if ready { readyTile(today.ready, now: ctx.date) }
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    private var hugsTile: ConnectionTile {
        let list = hugs.filter { Calendar.current.isDateInToday($0.date) }
        let minutes = list.reduce(0) { $0 + $1.durationMin }
        return ConnectionTile(symbol: "heart.fill", tint: Theme.glow,
                              value: "\(list.count)", label: list.count == 1 ? "Hug today" : "Hugs today",
                              caption: list.isEmpty ? "None yet. The heart button logs one."
                                  : (minutes > 0 ? "\(Format.minutes(minutes.rounded())) with trees" : "Logged in Rootbound"))
    }

    private func calmTile(_ c: WellnessConnect.Today.Calm?, now: Date) -> ConnectionTile {
        let peer = WellnessConnect.stillPoint
        guard let c else { return notShared(peer, symbol: "wind", tint: Theme.sky, label: "Calm minutes", url: WellnessConnect.stillPointJourney) }
        return ConnectionTile(symbol: "wind", tint: Theme.sky, value: "\(Int(c.minutes.rounded()))",
                              label: "Calm min today",
                              caption: "Still Pointz · " + WellnessConnect.updatedText(c.updated, now: now),
                              hint: "Opens your Journey in Still Pointz") { open(WellnessConnect.stillPointJourney, peer) }
    }

    private func movesTile(_ m: WellnessConnect.Today.Moves?, now: Date) -> ConnectionTile {
        let peer = WellnessConnect.roamr
        guard let m else { return notShared(peer, symbol: "figure.walk", tint: Theme.gold, label: "Walks", url: WellnessConnect.roamrHistory) }
        return ConnectionTile(symbol: "figure.walk", tint: Theme.gold,
                              value: WellnessConnect.distance(m.distanceM, metric: Units.metric),
                              label: m.trips == 0 ? "Walked today" : (m.trips == 1 ? "1 walk today" : "\(m.trips) walks today"),
                              caption: "Roamr · " + WellnessConnect.updatedText(m.updated, now: now),
                              hint: "Opens your history in Roamr") { open(WellnessConnect.roamrHistory, peer) }
    }

    private func readyTile(_ r: WellnessConnect.Today.Ready?, now: Date) -> ConnectionTile {
        let peer = WellnessConnect.pulseLab
        let tint = Color(red: 1.0, green: 0.42, blue: 0.45)
        guard let r else { return notShared(peer, symbol: "waveform.path.ecg", tint: tint, label: "Readiness", url: WellnessConnect.pulseLabToday) }
        var value = "Not yet"
        var label = r.isToday ? "Readiness today" : "Open to refresh"
        if let v = r.readiness {
            value = "\(Int(v.rounded()))"; label = "Readiness"
        } else if let v = r.recovery {
            value = "\(Int(v.rounded()))%"; label = "WHOOP recovery"
        }
        return ConnectionTile(symbol: "waveform.path.ecg", tint: tint, value: value, label: label,
                              caption: "Pulse Lab · " + WellnessConnect.updatedText(r.updated, now: now),
                              hint: "Opens Today in Pulse Lab") { open(WellnessConnect.pulseLabToday, peer) }
    }

    /// Installed, but it hasn't shared anything yet (not opened since it learned to share).
    private func notShared(_ peer: WellnessConnect.Peer, symbol: String, tint: Color, label: String, url: URL) -> ConnectionTile {
        ConnectionTile(symbol: symbol, tint: tint, value: "Not yet", label: label,
                       caption: "Open \(peer.name) once to share", hint: "Opens \(peer.name)") { open(url, peer) }
    }

    private func open(_ url: URL, _ peer: WellnessConnect.Peer) {
        taps += 1
        WellnessConnect.open(url, in: peer)
    }
}

/// One number from one app: symbol, value, what it is, and where / how fresh. Tappable when it opens the app.
@MainActor
struct ConnectionTile: View {
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
                .buttonStyle(.plain)
                .accessibilityHint(hint ?? "")
        } else {
            face
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.16), in: Circle())
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
            }
            Text(value)
                .font(.system(size: Theme.scaled(22), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: Theme.scaled(10), weight: .bold, design: .rounded)).tracking(0.8)
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(Theme.rounded(11, .medium))
                .foregroundStyle(Theme.textDim.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value). \(caption)")
    }
}

// MARK: - Walks that passed a tree

/// A tree's page: Roamr walks that passed this tree and aren't already attached to one of its hugs (those are in
/// "Walks"): a hug of it happened on the walk, or the walk started or ended within about 250 m. Roamr shares only
/// rounded start / end points, never the route. Each row opens the walk in Roamr. Hidden when there are none.
@MainActor
struct TreePassingWalksCard: View {
    let tree: TreeSummary
    private var feed: WellnessFeed { WellnessFeed.shared }

    var body: some View {
        let walks = passing
        if !walks.isEmpty {
            RBCard {
                VStack(alignment: .leading, spacing: RB.m) {
                    RBSectionTitle(title: "Walks past this tree", symbol: "figure.walk.motion")
                    TimelineView(.everyMinute) { ctx in
                        Text(summary(walks, now: ctx.date))
                            .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(walks.prefix(8)) { w in row(w) }
                }
            }
            .onAppear { feed.refreshIfStale() }
        }
    }

    /// Roamr's walks near this tree, minus the ones already attached to its hugs.
    private var passing: [WellnessConnect.PassingTrip] {
        guard !WellnessConnect.isDemo, let trips = feed.roamr?.trips, !trips.isEmpty else { return [] }
        let attached = Set(tree.hugs.flatMap { $0.linkedWalks.map(\.id) })
        return WellnessConnect.tripsPassing(treeLat: tree.coordinate?.latitude, treeLng: tree.coordinate?.longitude,
                                            hugTimes: tree.hugs.map { (start: $0.date, minutes: $0.durationMin) },
                                            in: trips)
            .filter { !attached.contains($0.id) }
    }

    private func summary(_ walks: [WellnessConnect.PassingTrip], now: Date) -> String {
        let total = walks.reduce(0) { $0 + $1.trip.distanceM }
        var parts = [walks.count == 1 ? "1 walk" : "\(walks.count) walks", WellnessConnect.distance(total, metric: Units.metric)]
        if let updated = feed.roamr?.updated { parts.append("Roamr, " + WellnessConnect.updatedText(updated, now: now)) }
        return parts.joined(separator: " · ")
    }

    private func row(_ p: WellnessConnect.PassingTrip) -> some View {
        let t = p.trip
        let w = LinkedWalk(id: t.id, kind: t.kind, start: t.start, end: t.end, distanceM: t.distanceM, movingSec: t.movingSec,
                           elevGainM: t.elevGainM, avgSpeed: nil, topSpeed: nil, avgHR: t.avgHR, source: "Roamr", fromRoamr: true)
        let when = (Calendar.current.isDateInToday(t.start) ? "Today" : Format.day(t.start)) + ", " +
            t.start.formatted(date: .omitted, time: .shortened)
        return Button { WellnessConnect.open(WellnessConnect.roamrTrip(t.id), in: WellnessConnect.roamr) } label: {
            HStack(spacing: 12) {
                Image(systemName: w.symbol)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.glow)
                    .frame(width: 36, height: 36)
                    .background(Theme.glow.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.summary).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(when + " · " + reason(p.reason))
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this walk in Roamr")
    }

    private func reason(_ r: WellnessConnect.PassingTrip.Reason) -> String {
        switch r {
        case .hugged: return "hugged it on this walk"
        case .startedNear: return "started nearby"
        case .endedNear: return "ended nearby"
        }
    }
}
