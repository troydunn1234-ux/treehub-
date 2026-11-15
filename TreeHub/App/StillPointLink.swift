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
                                   tree: $0.treeName, species: $0.species)
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
    @State private var installed = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if installed {
                Button {
                    if !WellnessLinks.open(WellnessLinks.breatheWithTree(treeName)) { installed = false }
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

    private func reload() {
        sessions = RootboundWellness.calmSessions()
        BreathBark.sync(hugs: hugs)
    }
}
