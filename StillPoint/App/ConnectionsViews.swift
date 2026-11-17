import SwiftUI
import UIKit

// Still Pointz' side of the family connections (Shared/Wellness/WellnessConnect.swift). Read-only on the other
// apps' feeds, re-read whenever Still Pointz comes to the front; taps open the other app (or its App Store page
// when it isn't on this iPhone).

/// Journey: today across the family apps. Calm minutes here, tree hugs from Rootbound, distance on foot from Roamr
/// and readiness from Pulse Lab, each saying how fresh it is. Hidden when none of the other apps is installed.
@MainActor
struct TodayAcrossAppsStrip: View {
    @EnvironmentObject var log: SessionLog
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }

    var body: some View {
        let today = feed.today
        let hugs = feed.has(WellnessConnect.rootbound)
        let moves = feed.has(WellnessConnect.roamr)
        let ready = feed.has(WellnessConnect.pulseLab)
        if hugs || moves || ready {
            VStack(alignment: .leading, spacing: SP.s3) {
                SectionHeader("Today across your apps")
                TimelineView(.everyMinute) { ctx in
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SP.s2, alignment: .top),
                                             count: typeSize.isAccessibilitySize ? 1 : 2),
                              alignment: .leading, spacing: SP.s2) {
                        calmTile
                        if hugs { hugsTile(today.hugs, now: ctx.date) }
                        if moves { movesTile(today.moves, now: ctx.date) }
                        if ready { readyTile(today.ready, now: ctx.date) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    /// This app's own minutes today, straight from the log.
    private var calmTile: AppsTodayTile {
        let list = log.sessions(on: Date())
        let minutes = list.reduce(0) { $0 + $1.minutes }
        return AppsTodayTile(symbol: "leaf", tint: SP.accent, value: "\(Int(minutes.rounded()))", label: "Calm minutes today",
                             caption: list.isEmpty ? "Nothing yet today"
                                 : (list.count == 1 ? "1 session" : "\(list.count) sessions"))
    }

    private func hugsTile(_ h: WellnessConnect.Today.Hugs?, now: Date) -> AppsTodayTile {
        let peer = WellnessConnect.rootbound
        let tint = Color(spHex: "#8CCB7E")
        guard let h else { return notShared(peer, symbol: "tree", tint: tint, label: "Tree hugs", url: WellnessConnect.rootboundHome) }
        var label = h.count == 1 ? "Tree hug today" : "Tree hugs today"
        if let tree = h.lastTree?.trimmingCharacters(in: .whitespacesAndNewlines), !tree.isEmpty, h.count > 0 { label += ", last with \(tree)" }
        return AppsTodayTile(symbol: "tree", tint: tint, value: "\(h.count)", label: label,
                             caption: "Rootbound · " + WellnessConnect.updatedText(h.updated, now: now),
                             hint: "Opens Rootbound") { open(WellnessConnect.rootboundHome, peer) }
    }

    private func movesTile(_ m: WellnessConnect.Today.Moves?, now: Date) -> AppsTodayTile {
        let peer = WellnessConnect.roamr
        let tint = Color(spHex: "#F2A65A")
        guard let m else { return notShared(peer, symbol: "figure.walk", tint: tint, label: "Walks", url: WellnessConnect.roamrHistory) }
        return AppsTodayTile(symbol: "figure.walk", tint: tint,
                             value: WellnessConnect.distance(m.distanceM, metric: WellnessConnect.localeMetric),
                             label: m.trips == 0 ? "Walked today" : (m.trips == 1 ? "On foot today, 1 walk" : "On foot today, \(m.trips) walks"),
                             caption: "Roamr · " + WellnessConnect.updatedText(m.updated, now: now),
                             hint: "Opens your history in Roamr") { open(WellnessConnect.roamrHistory, peer) }
    }

    private func readyTile(_ r: WellnessConnect.Today.Ready?, now: Date) -> AppsTodayTile {
        let peer = WellnessConnect.pulseLab
        let tint = SP.rose
        guard let r else { return notShared(peer, symbol: "waveform.path.ecg", tint: tint, label: "Readiness", url: WellnessConnect.pulseLabToday) }
        var value = "Not yet"
        var label = r.isToday ? "Readiness today" : "Pulse Lab hasn't refreshed today"
        if let v = r.readiness {
            value = "\(Int(v.rounded()))"; label = "Readiness"
        } else if let v = r.recovery {
            value = "\(Int(v.rounded()))%"; label = "WHOOP recovery"
        }
        return AppsTodayTile(symbol: "waveform.path.ecg", tint: tint, value: value, label: label,
                             caption: "Pulse Lab · " + WellnessConnect.updatedText(r.updated, now: now),
                             hint: "Opens Today in Pulse Lab") { open(WellnessConnect.pulseLabToday, peer) }
    }

    /// Installed, but it hasn't shared anything yet (not opened since it learned to share).
    private func notShared(_ peer: WellnessConnect.Peer, symbol: String, tint: Color, label: String, url: URL) -> AppsTodayTile {
        AppsTodayTile(symbol: symbol, tint: tint, value: "Not yet", label: label,
                      caption: "Open \(peer.name) once to share", hint: "Opens \(peer.name)") { open(url, peer) }
    }

    private func open(_ url: URL, _ peer: WellnessConnect.Peer) {
        taps += 1
        WellnessConnect.open(url, in: peer)
    }
}

/// One number from one app, in the Still Pointz card style. Tappable when it opens the app.
@MainActor
struct AppsTodayTile: View {
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
                .buttonStyle(SoftPress())
                .accessibilityHint(hint ?? "")
        } else {
            face
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: SP.s1) {
            HStack(spacing: SP.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.14)))
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SP.faint)
                }
            }
            Text(value)
                .font(SP.numbers(26))
                .foregroundStyle(SP.ink)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption).font(.caption2).foregroundStyle(SP.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .spCard(padding: 14)
        .contentShape(RoundedRectangle(cornerRadius: SP.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value). \(caption)")
    }
}

// MARK: - The tree a session was done with

/// Session page: the tree this breath went with, under the name Rootbound has for it now (renames show), how often
/// it's been hugged, and "Open tree" (rootbound://tree?id=…). Found in Rootbound's feed: the session was linked to
/// a hug there, started from "Breathe with this tree", or a hug of the tree overlaps it. Hidden for other sessions.
@MainActor
struct SessionTreeCard: View {
    let record: SessionRecord
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }
    private let green = Color(spHex: "#8CCB7E")

    var body: some View {
        if let m = match {
            VStack(alignment: .leading, spacing: SP.s3) {
                HStack(alignment: .top, spacing: SP.s3) {
                    Image(systemName: "tree")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(green)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(green.opacity(0.14)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kicker(m.how)).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1.0)
                            .foregroundStyle(SP.faint)
                        Text(m.name).font(SP.serif(22)).foregroundStyle(SP.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let line = detail(m) {
                            Text(line).font(.footnote).foregroundStyle(SP.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                Button {
                    taps += 1
                    WellnessConnect.open(m.treeID.map { WellnessConnect.rootboundTree($0) } ?? WellnessConnect.rootboundHome,
                                         in: WellnessConnect.rootbound)
                } label: {
                    Label(buttonTitle(m), systemImage: feed.has(WellnessConnect.rootbound) ? "arrow.up.forward" : "arrow.down.circle")
                }
                .buttonStyle(SPSecondaryButtonStyle(tint: green, fullWidth: true))
                .accessibilityHint(feed.has(WellnessConnect.rootbound) ? "Opens this tree in Rootbound" : "Opens the App Store")
            }
            .spCard()
            .sensoryFeedback(.selection, trigger: taps)
            .onAppear { feed.refreshIfStale() }
        }
    }

    private var match: WellnessConnect.TreeMatch? {
        WellnessConnect.tree(forSession: record.id, start: record.start, end: record.end,
                             taggedTreeID: record.treeID, taggedName: record.treeName, in: feed.rootbound?.hugs ?? [])
    }

    private func kicker(_ how: WellnessConnect.TreeMatch.How) -> String {
        switch how {
        case .linked: return "Linked to a tree hug"
        case .tagged: return "Breathed with a tree"
        case .sameTime: return "During a tree hug"
        }
    }

    /// "Valley Oak · hugged 7 times · last Nov 14"
    private func detail(_ m: WellnessConnect.TreeMatch) -> String? {
        var parts: [String] = []
        if !m.species.isEmpty { parts.append(m.species) }
        if m.hugCount > 0 { parts.append(m.hugCount == 1 ? "hugged once" : "hugged \(m.hugCount) times") }
        if let last = m.lastHug { parts.append("last " + last.formatted(.dateTime.month(.abbreviated).day())) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func buttonTitle(_ m: WellnessConnect.TreeMatch) -> String {
        guard feed.has(WellnessConnect.rootbound) else { return "Get Rootbound" }
        return m.treeID == nil ? "Open Rootbound" : "Open tree"
    }
}

// MARK: - stillpoint://journey?session=…

/// Roamr's "Breathwork after" rows open stillpoint://journey?session=<id>: Journey, then that session's page.
/// Older links (no session) just open Journey, as before.
enum JourneyLink {
    static var pending: UUID?
    static let note = Notification.Name("sp.journeySession")

    static func handle(_ url: URL) {
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "session" })?.value,
              let id = UUID(uuidString: raw) else { return }
        pending = id
        NotificationCenter.default.post(name: note, object: nil)
    }
}

private struct JourneySessionLink: ViewModifier {
    @Binding var path: NavigationPath
    @EnvironmentObject var log: SessionLog

    func body(content: Content) -> some View {
        content
            .onAppear(perform: openPending)
            .onReceive(NotificationCenter.default.publisher(for: JourneyLink.note)) { _ in openPending() }
    }

    private func openPending() {
        guard let id = JourneyLink.pending else { return }
        JourneyLink.pending = nil
        guard log.record(id) != nil else { return }
        path = NavigationPath()
        path.append(id)
    }
}

extension View {
    /// Journey: push the session a stillpoint://journey?session=… link asked for.
    func journeySessionLink(path: Binding<NavigationPath>) -> some View { modifier(JourneySessionLink(path: path)) }
}
