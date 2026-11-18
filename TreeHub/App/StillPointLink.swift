import SwiftUI
import UIKit

// Rootbound <-> Still Pointz (breathing app). The shared feed and URLs live in Shared/Wellness/WellnessBridge.swift.
//  • publishes tree hugs (date, minutes, tree name, species; no coordinates) + the hug streak for Still Pointz
//  • reads Still Pointz sessions: "Calm minutes" on Home, and Breath & Bark (hug + Still Pointz session, same day)
//  • "Breathe with this tree" opens stillpoint://session?… (or shows the App Store card when it isn't installed)
// Nothing here touches Apple Health: each app keeps saving only its own data there.

enum RootboundWellness {
    /// Publish our half of the feed (call after hugs change and when the app goes to the background).
    static func publish(hugs: [Hug]) {
        let since = Date().addingTimeInterval(-Double(WellnessBridge.keepDays) * 86400)
        let items = hugs.filter { $0.date >= since }.map { h -> WellnessBridge.TreeHug in
            var t = WellnessBridge.TreeHug(id: h.id, date: h.date, minutes: h.durationMin,
                                           tree: h.treeName, species: h.species, treeID: h.treeID)
            // Which Still Pointz sessions and Roamr walks this hug is linked to (Still Pointz / Roamr show the tree).
            let sessions = h.linkedSessions.compactMap(\.feedID)
            if !sessions.isEmpty { t.sessionIDs = sessions }
            let walks = h.linkedWalks.filter(\.fromRoamr).map(\.id)
            if !walks.isEmpty { t.walkIDs = walks }
            return t
        }
        WellnessBridge.publishRootbound(hugs: items, streak: GameEngine.currentStreak(hugs))
    }

    /// Still Pointz guided sessions (not sauna / steam), newest first. Empty when Still Pointz isn't there.
    static func calmSessions() -> [WellnessBridge.Session] {
        (WellnessBridge.stillPoint()?.sessions ?? []).filter(\.isCalm)
    }
}

/// Breath & Bark: a tree hug and a Still Pointz session on the same day. Each such day is worth a small XP bonus,
/// and the first one earns the "Breath & Bark" badge. Days are remembered here (the shared feed only keeps recent ones),
/// so the XP never goes away.
enum BreathBark {
    static let bonusXP = 25
    private static let key = "rb.breathBarkDays"

    static var days: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static var totalBonus: Int { days.count * bonusXP }
    static var earned: Bool { !days.isEmpty }

    /// Record every day that has both a hug and a Still Pointz session. Returns the days that are new.
    @discardableResult
    static func sync(hugs: [Hug]) -> Set<String> {
        let sessions = RootboundWellness.calmSessions()
        guard !sessions.isEmpty, !hugs.isEmpty, !DemoData.isOn else { return [] }
        let hugDays = Set(hugs.map { WellnessBridge.dayKey($0.date) })
        let calmDays = Set(sessions.map { WellnessBridge.dayKey($0.date) })
        let both = hugDays.intersection(calmDays)
        let known = days
        let new = both.subtracting(known)
        if !new.isEmpty { UserDefaults.standard.set(Array(known.union(new)).sorted(), forKey: key) }
        return new
    }

    /// True when today already has a hug and a Still Pointz session.
    static var today: Bool { days.contains(WellnessBridge.dayKey(Date())) }
}

// MARK: - "Breathe with this tree"

/// Opens Still Pointz straight into a short grounding breath named after the tree.
/// When Still Pointz isn't installed it shows a small card with an App Store link instead.
struct BreatheWithTreeButton: View {
    let treeName: String
    /// The tree's stable id: the finished session syncs back under this tree.
    var treeID: UUID? = nil
    @State private var installed = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if installed {
                Button {
                    if !WellnessLinks.open(WellnessLinks.breatheWithTree(treeName, treeID: treeID, practice: "rooted-breath")) { installed = false }
                } label: {
                    Label("Breathe with this tree", systemImage: "wind")
                }
                .buttonStyle(RBSecondaryButtonStyle(tint: Theme.sky))
                .accessibilityHint("Opens a three-minute breath with \(treeName) in Still Pointz")
            } else {
                Self.getCard(title: "Breathe with \(treeName)",
                             text: "Still Pointz guides a short grounding breath. Hug + breathe on the same day for Breath & Bark.",
                             openURL: openURL)
            }
        }
        .onAppear { installed = WellnessLinks.stillPointInstalled }
    }
}

extension BreatheWithTreeButton {
    /// "Get Still Pointz" card with its App Store link (when Still Pointz isn't installed).
    @MainActor
    static func storeCard(title: String, openURL: OpenURLAction) -> some View {
        getCard(title: title, text: "Still Pointz isn't on this iPhone yet. It guides short breaths and keeps your Journey.",
                openURL: openURL)
    }

    /// Wind icon, what Still Pointz would do here, and a "Get" button for its App Store page.
    @MainActor
    fileprivate static func getCard(title: String, text: String, openURL: OpenURLAction) -> some View {
        HStack(spacing: RB.m) {
            Image(systemName: "wind")
                .font(.headline).foregroundStyle(Theme.sky)
                .frame(width: 44, height: 44)
                .background(Theme.sky.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let store = WellnessLinks.storeURL(bundleID: WellnessLinks.stillPointBundleID) {
                Button("Get") { openURL(store) }
                    .font(RB.text(.subheadline, .heavy))
                    .foregroundStyle(Theme.forestDeep)
                    .padding(.horizontal, RB.l)
                    .frame(minHeight: 36)
                    .background(Theme.sky, in: Capsule())
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                    .accessibilityLabel("Get Still Pointz on the App Store")
            }
        }
        .padding(RB.m)
        .rbInner()
    }
}

/// Home: Still Pointz minutes this week and today's Breath & Bark. Hidden entirely when Still Pointz has shared nothing.
struct CalmMinutesCard: View {
    let hugs: [Hug]
    @State private var showGet = false
    /// Still Pointz' part of the feed as last read (WellnessFeed reloads it when the app becomes active and when
    /// Still Pointz saves a session in the background, e.g. one from the Watch), so the card updates live.
    private var feed: WellnessFeed { WellnessFeed.shared }
    private var sessions: [WellnessBridge.Session] { (feed.stillPoint?.sessions ?? []).filter(\.isCalm) }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 8) {
            if !sessions.isEmpty {
                let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                let week = sessions.filter { $0.date >= weekAgo }.reduce(0) { $0 + $1.minutes }
                let todayKey = WellnessBridge.dayKey(Date())
                let breathedToday = sessions.contains { WellnessBridge.dayKey($0.date) == todayKey }
                let huggedToday = hugs.contains { WellnessBridge.dayKey($0.date) == todayKey }
                // Tap: Still Pointz opens on its Journey tab (App Store card when it isn't installed).
                Button {
                    if !WellnessLinks.open(WellnessLinks.stillPointJourney) { showGet = true }
                } label: {
                RBCard(tint: Theme.sky) {
                    HStack(spacing: RB.m) {
                        Image(systemName: "wind")
                            .font(.title3.weight(.bold)).foregroundStyle(Theme.sky)
                            .frame(width: 48, height: 48)
                            .background(Theme.sky.opacity(0.15), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: RB.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(Format.minutes(week))
                                    .font(RB.number(.title2)).monospacedDigit().foregroundStyle(.white)
                                    .contentTransition(.numericText())
                                Text("calm minutes").font(RB.text(.subheadline, .semibold)).foregroundStyle(.white)
                            }
                            Text("This week in Still Pointz · Open Journey")
                                .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let t = latestTree {
                                Text(t).font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.sky)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(line(breathed: breathedToday, hugged: huggedToday))
                                .font(RB.text(.footnote, .bold))
                                .foregroundStyle(breathedToday && huggedToday ? Theme.gold : Theme.glow)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.bold)).foregroundStyle(Theme.textDim)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens your Journey in Still Pointz")
                if showGet { BreatheWithTreeButton.storeCard(title: "Open in Still Pointz", openURL: openURL) }
            }
        }
        .onAppear {
            feed.refreshIfStale()
            reload()
        }
        .onChange(of: feed.stillPoint?.updated) { _, _ in reload() }
    }

    private func line(breathed: Bool, hugged: Bool) -> String {
        switch (breathed, hugged) {
        case (true, true): return "Breath & Bark today: +\(BreathBark.bonusXP) XP"
        case (true, false): return "Breathed today. Hug a tree for Breath & Bark (+\(BreathBark.bonusXP) XP)"
        case (false, true): return "Hugged today. Breathe in Still Pointz for Breath & Bark (+\(BreathBark.bonusXP) XP)"
        default: return "Hug + breathe on the same day for Breath & Bark"
        }
    }

    /// "Latest: 3 min with Grandpa Oak · −6 bpm" for the newest breath done with a tree.
    private var latestTree: String? {
        guard let s = sessions.first(where: { $0.treeID != nil }) else { return nil }
        var parts = ["Latest: \(Format.minutes(s.minutes)) with \(s.treeName ?? "a tree")"]
        if let d = s.hrDrop, d > 0 { parts.append(String(format: "−%.0f bpm", d)) }
        else if let hr = s.avgHR { parts.append(String(format: "%.0f bpm", hr)) }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        _ = TreeBreaths.all()   // keep the per-tree copy current
        BreathBark.sync(hugs: hugs)
    }
}

// MARK: - Breath sessions under a tree

/// One breath session with a tree: from Still Pointz ("Breathe with this tree", tagged with the tree's id),
/// or a mindful session in Apple Health that overlapped one of this tree's hugs (read-only).
struct TreeBreath: Identifiable, Hashable {
    var id: UUID
    var start: Date
    var minutes: Double
    var avgHR: Double?
    var minHR: Double?
    var hrDrop: Double?
    var hrv: Double?
    /// "Still Pointz" or the Health source (Mindfulness, a watch app…).
    var source: String
    var practice: String?
    var tagged: Bool
}

/// Still Pointz sessions tagged with a Rootbound tree. Kept here too (by id), so they stay under the tree after
/// the shared feed trims old entries, and so heart data looked up later isn't lost.
enum TreeBreaths {
    /// rootbound://tree?id=… : the tree page to open (TreesView picks it up).
    static var pendingTreeID: UUID?
    static let openTree = Notification.Name("rb.openTree")
    private static let key = "rb.treeBreaths"

    private static func loadCache() -> [WellnessBridge.Session] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode([WellnessBridge.Session].self, from: d) else { return [] }
        return s
    }

    private static func saveCache(_ s: [WellnessBridge.Session]) {
        if let d = try? JSONEncoder().encode(Array(s.prefix(1000))) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// Every tagged session, newest first (feed merged into the local copy).
    static func all() -> [WellnessBridge.Session] {
        let cache = loadCache()
        guard let feed = WellnessBridge.stillPoint() else { return cache }
        let merged = merge(cache: cache, feed: feed)
        saveCache(merged)
        return merged
    }

    /// The local copy updated from Still Pointz' feed. A session the feed no longer has is dropped only when the
    /// feed still covers its date: the feed keeps 120 days but at most `WellnessBridge.maxItems` sessions, so when
    /// it is full it only reaches back to its oldest session, and older ones here were trimmed, not discarded.
    static func merge(cache: [WellnessBridge.Session], feed: WellnessBridge.StillPointPart,
                      now: Date = Date()) -> [WellnessBridge.Session] {
        var cache = cache
        let incoming = feed.sessions.filter { $0.treeID != nil }
        let ids = Set(incoming.map(\.id))
        let window = now.addingTimeInterval(-Double(WellnessBridge.keepDays) * 86400)
        let full = feed.sessions.count >= WellnessBridge.maxItems
        let oldest = feed.sessions.map(\.date).min() ?? now
        // Discarded in Still Pointz (gone from the feed while the feed still covers its date): drop it here too.
        cache.removeAll { $0.date >= window && (!full || $0.date > oldest) && !ids.contains($0.id) }
        for var s in incoming {
            if let i = cache.firstIndex(where: { $0.id == s.id }) {
                let old = cache[i]
                s.avgHR = s.avgHR ?? old.avgHR; s.minHR = s.minHR ?? old.minHR
                s.startHR = s.startHR ?? old.startHR; s.hrDrop = s.hrDrop ?? old.hrDrop; s.hrv = s.hrv ?? old.hrv
                s.endHR = s.endHR ?? old.endHR; s.respRate = s.respRate ?? old.respRate
                s.calmSeconds = s.calmSeconds ?? old.calmSeconds; s.breathsPerMin = s.breathsPerMin ?? old.breathsPerMin
                cache[i] = s
            } else {
                cache.append(s)
            }
        }
        cache.sort { $0.date > $1.date }
        return cache
    }

    /// Heart data Rootbound looked up itself (when Still Pointz hasn't filled it yet).
    static func fill(_ id: UUID, with st: HealthService.BreathStats) {
        var cache = loadCache()
        guard let i = cache.firstIndex(where: { $0.id == id }) else { return }
        cache[i].avgHR = cache[i].avgHR ?? st.avgHR
        cache[i].minHR = cache[i].minHR ?? st.minHR
        cache[i].startHR = cache[i].startHR ?? st.startHR
        cache[i].hrDrop = cache[i].hrDrop ?? st.hrDrop
        cache[i].hrv = cache[i].hrv ?? st.hrv
        saveCache(cache)
    }

    static func tagged(for treeID: UUID) -> [TreeBreath] {
        let key = treeID.uuidString
        return all().filter { $0.treeID?.uppercased() == key }.map {
            TreeBreath(id: $0.id, start: $0.date, minutes: $0.minutes, avgHR: $0.avgHR, minHR: $0.minHR,
                       hrDrop: $0.hrDrop, hrv: $0.hrv, source: "Still Pointz", practice: $0.practice, tagged: true)
        }
    }

    /// Tagged sessions plus Health mindful sessions overlapping this tree's hugs (read-only), with heart data.
    @MainActor
    static func load(for tree: TreeSummary) async -> [TreeBreath] {
        var out = tagged(for: tree.id)
        let hs = HealthService.shared
        guard hs.isAvailable, !DemoData.isOn else { return out }
        // Still Pointz sessions without heart data yet: look it up here too.
        for i in out.indices where out[i].avgHR == nil {
            let end = out[i].start.addingTimeInterval(out[i].minutes * 60)
            let st = await hs.breathStats(from: out[i].start, to: end)
            if st.avgHR != nil || st.hrv != nil {
                out[i].avgHR = st.avgHR; out[i].minHR = st.minHR; out[i].hrDrop = out[i].hrDrop ?? st.hrDrop
                out[i].hrv = out[i].hrv ?? st.hrv
                fill(out[i].id, with: st)
            }
        }
        // Untagged: sessions that actually overlap a hug of this tree. The hug logger sets the hug's time and length
        // to the session picked for it, so only that one shows here (not the others done the same half hour).
        // Still Pointz' own feed first (practice names; covers sessions not saved to Health), then Apple Health
        // mindful sessions (older Still Pointz builds, Apple Watch) and Mind & Body breathwork workouts.
        var seen = out.map(\.start)
        let feed = (WellnessBridge.stillPoint()?.sessions ?? []).filter { $0.isCalm && $0.treeID == nil && $0.minutes >= 1 }
        for hug in tree.hugs.prefix(15) {
            let from = hug.date.addingTimeInterval(30)
            let to = hug.date.addingTimeInterval(max(hug.durationMin, 1) * 60 - 30)
            var near: [(m: HealthService.MindfulSession, practice: String?)] = feed
                .map { (m: HealthService.MindfulSession(start: $0.date, end: $0.end ?? $0.date.addingTimeInterval($0.minutes * 60),
                                                       source: "Still Pointz"), practice: $0.practice) }
            near += (await hs.mindfulSessions(around: hug.date, hours: 1) + hs.breathworkWorkouts(around: hug.date, hours: 1))
                .map { (m: $0, practice: String?.none) }
            for (m, practice) in near where m.minutes >= 1 && m.end > from && m.start < to {
                guard !seen.contains(where: { abs($0.timeIntervalSince(m.start)) < 120 }) else { continue }
                seen.append(m.start)
                let st = await hs.breathStats(from: m.start, to: m.end)
                out.append(TreeBreath(id: UUID(), start: m.start, minutes: m.minutes, avgHR: st.avgHR, minHR: st.minHR,
                                      hrDrop: st.hrDrop, hrv: st.hrv, source: m.source, practice: practice, tagged: false))
            }
        }
        return out.sorted { $0.start > $1.start }
    }
}
