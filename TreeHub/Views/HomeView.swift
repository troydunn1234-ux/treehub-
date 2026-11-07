import SwiftUI
import UIKit
import SwiftData
import MapKit

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var showHugLog: Bool
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @State private var showSettings = false

    private var level: LevelInfo { GameEngine.level(for: GameEngine.totalXP(hugs: hugs, activities: activities)) }
    private var streak: Int { GameEngine.currentStreak(hugs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    levelCard
                    statsGrid
                    if hugs.isEmpty { firstHugCard } else { recentHugs }
                    nextBadges
                    if !activities.isEmpty { recentMoves }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let h = hugs.first(where: { $0.id == id }) { HugDetailView(hug: h) }
                else if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting.uppercased()).font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.5)
                    .foregroundStyle(Theme.glow)
                Text("TreeHub").font(Theme.title(36)).foregroundStyle(.white)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Moonlight hours"
        }
    }

    private var levelCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                LevelRing(info: level, size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text(level.title).font(Theme.title(24)).foregroundStyle(.white)
                    Text("\(level.xpIntoLevel) / \(level.xpForNext) XP to level \(level.level + 1)")
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(streak > 0 ? Theme.gold : Color.white.opacity(0.3))
                            .symbolEffect(.bounce, value: streak)
                        Text(streak > 0 ? "\(streak)-day hug streak" : "Start a streak today")
                            .font(Theme.rounded(14, .bold))
                            .foregroundStyle(streak > 0 ? Theme.gold : Theme.textDim)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var statsGrid: some View {
        let trees = Set(hugs.map(\.treeID)).count
        let minutes = hugs.reduce(0) { $0 + $1.durationMin }
        let moved = activities.reduce(0) { $0 + $1.distanceM }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(value: "\(hugs.count)", label: "Hugs", symbol: "heart.fill", tint: Color(red: 1, green: 0.5, blue: 0.6))
            StatTile(value: "\(trees)", label: "Tree friends", symbol: "tree.fill")
            StatTile(value: Format.minutes(minutes), label: "Breathwork", symbol: "wind", tint: Theme.sky)
            StatTile(value: Format.distance(moved), label: "Strolled", symbol: "figure.walk", tint: Theme.gold)
        }
    }

    private var firstHugCard: some View {
        Button { showHugLog = true } label: {
            GlassCard {
                HStack(spacing: 16) {
                    Image(systemName: "tree.fill").font(.system(size: 40)).foregroundStyle(Theme.leafGradient)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log your first hug").font(Theme.rounded(18, .bold)).foregroundStyle(.white)
                        Text("Snap the tree, a selfie, and your breathwork stats.")
                            .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.glow)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recentHugs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent hugs", symbol: "heart.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(hugs.prefix(10)) { h in
                        NavigationLink(value: h.id) { HugCard(hug: h) }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var nextBadges: some View {
        let all = GameEngine.badges(hugs: hugs, activities: activities)
        let next = all.filter { !$0.earned }.sorted { $0.progress > $1.progress }.prefix(3)
        let earned = all.filter(\.earned).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Almost there", symbol: "rosette")
                Button { tab = .collection } label: {
                    Text("\(earned)/\(all.count) badges").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.glow)
                }
            }
            GlassCard(padding: 12) {
                VStack(spacing: 12) {
                    ForEach(Array(next)) { b in
                        HStack(spacing: 12) {
                            Medallion(symbol: b.symbol, rarity: b.rarity, earned: false, size: 42)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(b.name).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                                    Spacer()
                                    Text(b.progressText).font(Theme.rounded(12, .bold)).foregroundStyle(Theme.textDim)
                                }
                                ProgressView(value: b.progress).tint(b.rarity.color)
                                Text(b.detail).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentMoves: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Recent strolls", symbol: "figure.walk")
                Button { tab = .track } label: { Text("All").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.glow) }
            }
            ForEach(activities.prefix(3)) { a in
                NavigationLink(value: a.id) { ActivityRow(activity: a) }.buttonStyle(.plain)
            }
        }
    }
}

struct HugCard: View {
    let hug: Hug

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                PhotoView(data: hug.selfiePhoto ?? hug.treePhoto)
                    .frame(width: 170, height: 200)
                    .clipped()
                if let leaf = LeafType.find(hug.leafKey) {
                    LeafView(leaf: leaf, size: 30)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(hug.treeName).font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(Theme.forestDeep).lineLimit(1)
                HStack(spacing: 6) {
                    Text(Format.day(hug.date))
                    if hug.durationMin > 0 { Text("· \(Format.minutes(hug.durationMin))") }
                    if hug.barefoot { Image(systemName: "shoeprints.fill") }
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.bark)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(8)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

