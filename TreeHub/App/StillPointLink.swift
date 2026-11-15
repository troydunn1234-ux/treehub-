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
        let items = hugs.map {
            WellnessBridge.TreeHug(id: $0.id, date: $0.date, minutes: $0.durationMin,
                                   tree: $0.treeName, species: $0.species, treeID: $0.treeID)
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
                        .font(Theme.rounded(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.sky.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.sky.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a three-minute breath with \(treeName) in Still Pointz")
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "wind")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.sky)
                        .frame(width: 40, height: 40)
                        .background(Theme.sky.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Breathe with \(treeName)").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        Text("Still Pointz guides a short grounding breath. Hug + breathe on the same day for Breath & Bark.")
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if let store = WellnessLinks.storeURL(bundleID: WellnessLinks.stillPointBundleID) {
                        Button("Get") { openURL(store) }
                            .font(Theme.rounded(14, .heavy))
                            .foregroundStyle(Theme.forestDeep)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Theme.sky, in: Capsule())
                            .accessibilityLabel("Get Still Pointz on the App Store")
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .onAppear { installed = WellnessLinks.stillPointInstalled }
    }
}

/// Home: Still Pointz minutes this week and today's Breath & Bark. Hidden entirely when Still Pointz has shared nothing.
struct CalmMinutesCard: View {
    let hugs: [Hug]
    @State private var sessions: [WellnessBridge.Session] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !sessions.isEmpty {
                let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                let week = sessions.filter { $0.date >= weekAgo }.reduce(0) { $0 + $1.minutes }
                let todayKey = WellnessBridge.dayKey(Date())
                let breathedToday = sessions.contains { WellnessBridge.dayKey($0.date) == todayKey }
                let huggedToday = hugs.contains { WellnessBridge.dayKey($0.date) == todayKey }
                GlassCard(padding: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "wind")
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.sky)
                            .frame(width: 46, height: 46)
                            .background(Theme.sky.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(Format.minutes(week)) calm minutes")
                                .font(Theme.rounded(17, .bold)).foregroundStyle(.white)
                            Text("This week in Still Pointz")
                                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            if let t = latestTree {
                                Text(t).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.sky)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(line(breathed: breathedToday, hugged: huggedToday))
                                .font(Theme.rounded(12, .bold))
                                .foregroundStyle(breathedToday && huggedToday ? Theme.gold : Theme.glow)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, p in if p == .active { reload() } }
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
        sessions = RootboundWellness.calmSessions()
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
    /// "Still Pointz" or the Health source (Garmin Connect, Mindfulness…).
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
        var cache = loadCache()
        guard let feed = WellnessBridge.stillPoint() else { return cache }
        let incoming = feed.sessions.filter { $0.treeID != nil }
        let ids = Set(incoming.map(\.id))
        let window = Date().addingTimeInterval(-Double(WellnessBridge.keepDays) * 86400)
        // Discarded in Still Pointz (gone from the feed while still inside its window): drop it here too.
        cache.removeAll { $0.date >= window && !ids.contains($0.id) }
        for var s in incoming {
            if let i = cache.firstIndex(where: { $0.id == s.id }) {
                let old = cache[i]
                s.avgHR = s.avgHR ?? old.avgHR; s.minHR = s.minHR ?? old.minHR
                s.startHR = s.startHR ?? old.startHR; s.hrDrop = s.hrDrop ?? old.hrDrop; s.hrv = s.hrv ?? old.hrv
                cache[i] = s
            } else {
                cache.append(s)
            }
        }
        cache.sort { $0.date > $1.date }
        saveCache(cache)
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
        // Untagged: mindful sessions in Health that overlap a hug of this tree.
        var seen = out.map(\.start)
        for hug in tree.hugs.prefix(15) {
            let from = hug.date.addingTimeInterval(-20 * 60)
            let to = hug.date.addingTimeInterval(max(hug.durationMin, 1) * 60 + 20 * 60)
            for m in await hs.mindfulSessions(around: hug.date, hours: 1) where m.minutes >= 1 && m.end > from && m.start < to {
                guard !seen.contains(where: { abs($0.timeIntervalSince(m.start)) < 120 }) else { continue }
                seen.append(m.start)
                let st = await hs.breathStats(from: m.start, to: m.end)
                out.append(TreeBreath(id: UUID(), start: m.start, minutes: m.minutes, avgHR: st.avgHR, minHR: st.minHR,
                                      hrDrop: st.hrDrop, hrv: st.hrv, source: m.source, practice: nil, tagged: false))
            }
        }
        return out.sorted { $0.start > $1.start }
    }
}
