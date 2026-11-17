import SwiftUI
import UIKit

/// Trip detail: the tree hugs logged in Rootbound on this trip (during it, or attached to it in Rootbound) and the
/// Still Pointz breathwork during it or within 30 minutes after it ended. Read from the shared wellness feed
/// (Shared/Wellness/WellnessConnect.swift), re-read whenever Roamr comes to the front. A hug opens its tree in
/// Rootbound, a session its page in Still Pointz (or the App Store page when that app isn't on this iPhone).
/// Trips with neither look exactly as before.
@MainActor
struct TripConnectionsSection: View {
    let tripID: UUID
    let kind: ActivityKind
    let start: Date
    let end: Date
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }

    var body: some View {
        let hugs = treeHugs
        let breaths = breathwork
        if !hugs.isEmpty || !breaths.isEmpty {
            VStack(alignment: .leading, spacing: Theme.gap + 4) {
                if !hugs.isEmpty { hugsCard(hugs) }
                if !breaths.isEmpty { breathCard(breaths) }
            }
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    private var treeHugs: [WellnessBridge.TreeHug] {
        guard let rb = feed.rootbound else { return [] }
        let found = WellnessConnect.hugs(onTrip: tripID, start: start, end: end, in: rb.hugs)
        // Drives only show hugs Rootbound attached to them (the 15-minute slack is for walks).
        return kind == .drive ? found.filter { $0.walkIDs?.contains(tripID) == true } : found
    }

    private var breathwork: [WellnessConnect.BreathMatch] {
        guard let sp = feed.stillPoint else { return [] }
        return WellnessConnect.breaths(forTrip: start, end: end, in: sp.sessions)
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

    // MARK: Tree hugs

    private func hugsCard(_ hugs: [WellnessBridge.TreeHug]) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Tree hugs on this \(noun)"), symbol: "tree.fill")
                ForEach(hugs) { h in hugRow(h) }
                if let updated = feed.rootbound?.updated { freshness(String(localized: "From Rootbound"), updated) }
            }
        }
    }

    private func hugRow(_ h: WellnessBridge.TreeHug) -> some View {
        let name = h.tree.trimmingCharacters(in: .whitespacesAndNewlines)
        var details = [h.date.formatted(date: .omitted, time: .shortened)]
        if h.minutes >= 1 { details.append(WellnessConnect.minutes(h.minutes)) }
        if !h.species.isEmpty { details.append(h.species) }
        let url = h.treeID.map { WellnessConnect.rootboundTree($0) } ?? WellnessConnect.rootboundHome
        return linkRow(symbol: "tree.fill", tint: Color(red: 0.55, green: 0.80, blue: 0.49),
                       title: name.isEmpty ? String(localized: "A tree") : name, subtitle: details.joined(separator: " · "),
                       hint: String(localized: "Opens this tree in Rootbound")) {
            open(url, WellnessConnect.rootbound)
        }
    }

    // MARK: Breathwork

    private func breathCard(_ breaths: [WellnessConnect.BreathMatch]) -> some View {
        let title: String
        if breaths.allSatisfy({ !$0.during }) { title = String(localized: "Breathwork after") }
        else if breaths.allSatisfy(\.during) { title = String(localized: "Breathwork on this \(noun)") }
        else { title = String(localized: "Breathwork on and after this \(noun)") }
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, symbol: "wind")
                ForEach(breaths) { b in breathRow(b) }
                if let updated = feed.stillPoint?.updated { freshness(String(localized: "From Still Pointz"), updated) }
            }
        }
    }

    private func breathRow(_ b: WellnessConnect.BreathMatch) -> some View {
        let s = b.session
        let when = b.during ? String(localized: "During the \(noun)")
            : (b.minutesAfter < 1 ? String(localized: "Right after") : String(localized: "\(b.minutesAfter) min after"))
        var details = [when, WellnessConnect.minutes(s.minutes)]
        if let tree = s.treeName, !tree.isEmpty { details.append(String(localized: "with \(tree)")) }
        if let drop = s.hrDrop, drop >= 1 { details.append(String(localized: "heart −\(Int(drop.rounded())) bpm")) }
        return linkRow(symbol: "wind", tint: Color(red: 0.56, green: 0.64, blue: 1.0),
                       title: WellnessConnect.practiceName(s.practice) ?? String(localized: "Breath session"),
                       subtitle: details.joined(separator: " · "),
                       hint: String(localized: "Opens this session in Still Pointz")) {
            open(WellnessConnect.stillPointSession(s.id), WellnessConnect.stillPoint)
        }
    }

    // MARK: Building blocks

    private func linkRow(symbol: String, tint: Color, title: String, subtitle: String, hint: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }

    private func freshness(_ source: String, _ updated: Date) -> some View {
        TimelineView(.everyMinute) { ctx in
            Text(source + " · " + WellnessConnect.updatedText(updated, now: ctx.date))
                .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim.opacity(0.8))
        }
    }

    private func open(_ url: URL, _ peer: WellnessConnect.Peer) {
        taps += 1
        WellnessConnect.open(url, in: peer)
    }
}
