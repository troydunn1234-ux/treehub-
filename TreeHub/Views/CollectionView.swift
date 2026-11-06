import SwiftUI
import SwiftData

struct CollectionView: View {
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @Query private var activities: [Activity]
    @State private var section = 0
    @State private var selectedBadge: BadgeState?
    @State private var selectedLeaf: LeafType?

    private var badges: [BadgeState] { GameEngine.badges(hugs: hugs, activities: activities) }
    private var leafCounts: [String: Int] {
        hugs.reduce(into: [:]) { $0[$1.leafKey, default: 0] += 1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Collection").font(Theme.title(36)).foregroundStyle(.white).padding(.top, 8)
                    summary
                    Picker("", selection: $section) {
                        Text("Badges").tag(0)
                        Text("Leaves").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if section == 0 { badgeGrid } else { leafGrid }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedBadge) { b in badgeSheet(b).presentationDetents([.medium]) }
        .sheet(item: $selectedLeaf) { l in leafSheet(l).presentationDetents([.medium]) }
    }

    private var summary: some View {
        let earned = badges.filter(\.earned).count
        let leafKinds = LeafType.all.filter { (leafCounts[$0.id] ?? 0) > 0 }.count
        let level = GameEngine.level(for: GameEngine.totalXP(hugs: hugs, activities: activities))
        return GlassCard {
            HStack(spacing: 16) {
                LevelRing(info: level, size: 70)
                VStack(alignment: .leading, spacing: 6) {
                    Text(level.title).font(Theme.title(20))
                    HStack(spacing: 14) {
                        Label("\(earned)/\(badges.count)", systemImage: "rosette")
                        Label("\(leafKinds)/\(LeafType.all.count)", systemImage: "leaf.fill")
                    }
                    .font(Theme.rounded(14, .bold))
                    .foregroundStyle(Theme.glow)
                }
                Spacer()
            }
        }
    }

    private var badgeGrid: some View {
        let sorted = badges.sorted { a, b in
            if a.earned != b.earned { return a.earned }
            if a.rarity != b.rarity { return a.rarity > b.rarity }
            return a.progress > b.progress
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 18) {
            ForEach(sorted) { b in
                Button { selectedBadge = b } label: {
                    VStack(spacing: 8) {
                        Medallion(symbol: b.symbol, rarity: b.rarity, earned: b.earned, size: 70)
                        Text(b.name).font(Theme.rounded(12, .bold))
                            .foregroundStyle(b.earned ? .white : Theme.textDim)
                            .multilineTextAlignment(.center).lineLimit(2)
                            .frame(height: 32, alignment: .top)
                        if !b.earned {
                            ProgressView(value: b.progress).tint(b.rarity.color).frame(width: 60)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var leafGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
            ForEach(LeafType.all) { leaf in
                let count = leafCounts[leaf.id] ?? 0
                Button { selectedLeaf = leaf } label: {
                    VStack(spacing: 6) {
                        LeafView(leaf: leaf, size: 58, collected: count > 0)
                            .frame(height: 70)
                        Text(count > 0 ? leaf.name : "???").font(Theme.rounded(12, .bold))
                            .foregroundStyle(count > 0 ? .white : Theme.textDim).lineLimit(1)
                        Text(count > 1 ? "×\(count)" : leaf.rarity.title)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(leaf.rarity.color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(count > 0 ? leaf.rarity.color.opacity(0.12) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(count > 0 ? leaf.rarity.color.opacity(0.5) : Theme.cardStroke))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func badgeSheet(_ b: BadgeState) -> some View {
        VStack(spacing: 14) {
            Medallion(symbol: b.symbol, rarity: b.rarity, earned: b.earned, size: 110)
                .padding(.top, 30)
            Text(b.name).font(Theme.title(26))
            RarityLabel(rarity: b.rarity)
            Text(b.detail).font(Theme.rounded(16, .medium)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            if !b.earned {
                ProgressView(value: b.progress).tint(b.rarity.color).frame(width: 200)
                Text(b.progressText).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
            } else {
                Label("Unlocked", systemImage: "checkmark.seal.fill").font(Theme.rounded(16, .bold)).foregroundStyle(Theme.glow)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ForestBackground())
    }

    private func leafSheet(_ l: LeafType) -> some View {
        let count = leafCounts[l.id] ?? 0
        return VStack(spacing: 14) {
            LeafView(leaf: l, size: 120, collected: count > 0).padding(.top, 30)
            Text(count > 0 ? l.name : "Not found yet").font(Theme.title(26))
            RarityLabel(rarity: l.rarity)
            Text(count > 0 ? l.blurb : "Keep hugging. Barefoot and longer sessions improve your odds of rare leaves.")
                .font(Theme.rounded(16, .medium)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            if count > 0 { Text("Collected ×\(count)").font(Theme.rounded(14, .bold)).foregroundStyle(l.rarity.color) }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(ForestBackground())
    }
}

extension LeafType: Equatable {
    static func == (a: LeafType, b: LeafType) -> Bool { a.id == b.id }
}
