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
                VStack(alignment: .leading, spacing: Theme.gap + 6) {
                    hero
                    Group {
                        levelCard.offset(y: -54).padding(.bottom, -54)
                        quickActions
                        statsGrid
                        if hugs.isEmpty { firstHugCard } else { recentHugs }
                        nextBadges
                        if !activities.isEmpty { recentMoves }
                    }
                    .padding(.horizontal, Theme.pad)
                }
                .padding(.bottom, 130)
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let h = hugs.first(where: { $0.id == id }) { HugDetailView(hug: h) }
                else if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    /// Full-bleed photo of your latest hug that stretches when you pull down.
    private var hero: some View {
        let photo = hugs.first.flatMap { $0.selfiePhoto ?? $0.treePhoto }
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let pull = max(0, geo.frame(in: .scrollView).minY)
                Group {
                    if let photo, let ui = UIImage(data: photo) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [Theme.moss, Theme.forest, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
                            Image(systemName: "tree.fill")
                                .font(.system(size: 120))
                                .foregroundStyle(Theme.leafGradient)
                                .opacity(0.35)
                                .offset(y: 10)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height + pull)
                .clipped()
                .offset(y: -pull)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: Theme.forestDeep.opacity(0.65), location: 0.72),
                        .init(color: Theme.forestDeep, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .offset(y: -pull)
                }
            }
            .frame(height: 400)

            VStack(alignment: .leading, spacing: 4) {
                Text(greeting.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundStyle(Theme.glow)
                Text("Rootbound").font(Theme.title(44)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                if let latest = hugs.first {
                    Text("Last hug: \(latest.treeName) · \(Format.day(latest.date))")
                        .font(Theme.rounded(14, .semibold)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 74)
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .pressable()
            .padding(.trailing, Theme.pad)
            .padding(.top, 60)
            .accessibilityLabel("Settings")
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { showHugLog = true } label: {
                Label("Hug a tree", systemImage: "heart.fill")
                    .font(Theme.rounded(16, .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.leafGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Theme.glow.opacity(0.35), radius: 12, y: 4)
            }
            .pressable()
            Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { tab = .track } } label: {
                Label("Go for a stroll", systemImage: "figure.walk")
                    .font(Theme.rounded(16, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            }
            .pressable()
        }
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
        GlassCard(padding: 18) {
            HStack(spacing: 18) {
                LevelRing(info: level, size: 86)
                VStack(alignment: .leading, spacing: 8) {
                    Text(level.title).font(Theme.title(24)).foregroundStyle(.white)
                    ProgressView(value: level.progress)
                        .tint(Theme.glow)
                        .scaleEffect(x: 1, y: 1.4, anchor: .center)
                    HStack {
                        Text("\(level.xpForNext - level.xpIntoLevel) XP to level \(level.level + 1)")
                            .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").symbolEffect(.bounce, value: streak)
                            Text(streak > 0 ? "\(streak)" : "0")
                        }
                        .font(Theme.rounded(13, .heavy))
                        .foregroundStyle(streak > 0 ? Theme.forestDeep : Theme.textDim)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(streak > 0 ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                        .accessibilityLabel("\(streak)-day hug streak")
                    }
                }
            }
        }
    }

    private var statsGrid: some View {
        let trees = Set(hugs.map(\.treeID)).count
        let minutes = hugs.reduce(0) { $0 + $1.durationMin }
        let moved = activities.reduce(0) { $0 + $1.distanceM }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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
        .pressable()
    }

    private var recentHugs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent hugs", symbol: "heart.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(hugs.prefix(10).enumerated()), id: \.element.id) { i, h in
                        NavigationLink(value: h.id) { HugCard(hug: h) }
                            .pressable()
                            .rotationEffect(.degrees(i % 2 == 0 ? -1.5 : 1.5))
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                    .opacity(phase.isIdentity ? 1 : 0.7)
                                    .rotation3DEffect(.degrees(phase.value * -12), axis: (x: 0, y: 1, z: 0))
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 12)
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, Theme.pad, for: .scrollContent)
            .padding(.horizontal, -Theme.pad)
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
            GlassCard(padding: 16) {
                VStack(spacing: 16) {
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
                NavigationLink(value: a.id) { ActivityRow(activity: a) }.pressable().cardAppear()
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
                    .frame(width: 188, height: 228)
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
        .padding(9)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
    }
}

