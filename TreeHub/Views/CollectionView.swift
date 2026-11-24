import SwiftUI
import SwiftData

struct CollectionView: View {
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @Query private var activities: [Activity]
    @State private var section = 0
    @State private var selectedBadge: BadgeState?
    @State private var selectedLeaf: LeafType?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var badges: [BadgeState] { GameEngine.badges(hugs: hugs, activities: activities) }
    private var leafCounts: [String: Int] {
        hugs.reduce(into: [:]) { $0[$1.leafKey, default: 0] += 1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RB.l) {
                    RBScreenHeader(title: "Collection", subtitle: "Badges you've earned and leaves you've found")
                    summary
                    if hugs.isEmpty { firstHugHint }
                    PillSwitcher(options: [.init(id: 0, label: "Badges", symbol: "rosette"),
                                           .init(id: 1, label: "Leaves", symbol: "leaf.fill")],
                                 selection: $section)

                    if section == 0 { badgeSections } else { leafGrid }
                }
                .padding(.horizontal, RB.screen)
                .padding(.bottom, 130)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: section)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: section)
        }
        .sheet(item: $selectedBadge) { b in
            badgeSheet(b)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLeaf) { l in
            leafSheet(l)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var columns: [GridItem] {
        let n = typeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: RB.m, alignment: .top), count: n)
    }

    // MARK: Summary

    private var summary: some View {
        let earned = badges.filter(\.earned).count
        let leafKinds = LeafType.all.filter { (leafCounts[$0.id] ?? 0) > 0 }.count
        let level = GameEngine.level(for: GameEngine.totalXP(hugs: hugs, activities: activities))
        return RBCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RB.l) { summaryRing(level); summaryText(level, earned: earned, leafKinds: leafKinds) }
                VStack(alignment: .leading, spacing: RB.m) { summaryRing(level); summaryText(level, earned: earned, leafKinds: leafKinds) }
            }
        }
    }

    private func summaryRing(_ level: LevelInfo) -> some View {
        LevelRing(info: level, size: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(level.level)")
    }

    private func summaryText(_ level: LevelInfo, earned: Int, leafKinds: Int) -> some View {
        VStack(alignment: .leading, spacing: RB.s) {
            Text(level.title).font(RB.text(.title3, .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: RB.s) {
                RBMetric(value: "\(earned)/\(badges.count)", label: "Badges", tint: Theme.gold)
                RBMetric(value: "\(leafKinds)/\(LeafType.all.count)", label: "Leaves", tint: Theme.glow)
                RBMetric(value: "\(hugs.count)", label: hugs.count == 1 ? "Hug" : "Hugs")
            }
        }
    }

    private var firstHugHint: some View {
        RBCard {
            RBEmptyState(symbol: "leaf.fill", title: "Start your collection",
                         hint: "Every hug drops a leaf and moves you toward badges. Barefoot and longer hugs find rarer leaves.",
                         actionTitle: "Log a hug") { RootboundPending.queue(.logHug) }
        }
    }

    // MARK: Badges

    @ViewBuilder private var badgeSections: some View {
        let earned = badges.filter(\.earned).sorted { $0.rarity > $1.rarity }
        let next = badges.filter { !$0.earned }.sorted { a, b in
            if a.progress != b.progress { return a.progress > b.progress }
            return a.rarity < b.rarity
        }
        if !earned.isEmpty {
            RBSectionTitle(title: "Earned · \(earned.count)", symbol: "checkmark.seal.fill", tint: Theme.gold)
            LazyVGrid(columns: columns, spacing: RB.l) {
                ForEach(earned) { b in badgeCell(b) }
            }
        }
        if !next.isEmpty {
            RBSectionTitle(title: earned.isEmpty ? "Badges to earn" : "Up next", symbol: "rosette")
                .padding(.top, earned.isEmpty ? 0 : RB.s)
            LazyVGrid(columns: columns, spacing: RB.l) {
                ForEach(next) { b in badgeCell(b) }
            }
        }
    }

    private func badgeCell(_ b: BadgeState) -> some View {
        Button { selectedBadge = b } label: {
            VStack(spacing: RB.s) {
                Medallion(symbol: b.symbol, rarity: b.rarity, earned: b.earned, size: 68)
                Text(b.name)
                    .font(RB.text(.caption, .bold))
                    .foregroundStyle(b.earned ? .white : Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !b.earned {
                    ProgressView(value: b.progress)
                        .tint(b.rarity.color)
                        .frame(maxWidth: 72)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, RB.m)
            .padding(.horizontal, RB.xs)
            .background(b.earned ? b.rarity.color.opacity(0.10) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: RB.inner + 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RB.inner + 4, style: .continuous)
                .strokeBorder(b.earned ? b.rarity.color.opacity(0.35) : RB.stroke))
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(b.name), \(b.rarity.title)\(b.earned ? ", earned" : ", \(b.progressText)")")
        .accessibilityHint("Shows how to earn it")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Leaves

    private var leafGrid: some View {
        LazyVGrid(columns: columns, spacing: RB.m) {
            ForEach(LeafType.all) { leaf in
                leafCell(leaf, count: leafCounts[leaf.id] ?? 0)
            }
        }
    }

    private func leafCell(_ leaf: LeafType, count: Int) -> some View {
        Button { selectedLeaf = leaf } label: {
            VStack(spacing: 6) {
                LeafView(leaf: leaf, size: 56, collected: count > 0)
                    .frame(height: 64)
                Text(count > 0 ? leaf.name : "Not found yet")
                    .font(RB.text(.caption, .bold))
                    .foregroundStyle(count > 0 ? .white : Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(count > 1 ? "×\(count)" : leaf.rarity.title)
                    .font(RB.text(.caption2, .heavy)).monospacedDigit()
                    .foregroundStyle(leaf.rarity.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, RB.m)
            .padding(.horizontal, RB.xs)
            .background(count > 0 ? leaf.rarity.color.opacity(0.12) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: RB.inner + 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RB.inner + 4, style: .continuous)
                .strokeBorder(count > 0 ? leaf.rarity.color.opacity(0.45) : RB.stroke))
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "\(leaf.name), \(leaf.rarity.title), collected \(count) times" : "Leaf not found yet, \(leaf.rarity.title)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Sheets

    private func badgeSheet(_ b: BadgeState) -> some View {
        ScrollView {
            VStack(spacing: RB.m) {
                Medallion(symbol: b.symbol, rarity: b.rarity, earned: b.earned, size: 110)
                    .padding(.top, RB.xxl)
                    .accessibilityHidden(true)
                Text(b.name).font(Theme.title(28)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                RarityLabel(rarity: b.rarity)
                Text(b.detail).font(RB.text(.body)).foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !b.earned {
                    VStack(spacing: RB.s) {
                        ProgressView(value: b.progress).tint(b.rarity.color)
                        Text(b.progressText).font(RB.text(.subheadline, .bold)).monospacedDigit().foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: 240)
                    .padding(.top, RB.xs)
                } else {
                    Label("Unlocked", systemImage: "checkmark.seal.fill")
                        .font(RB.text(.headline, .bold)).foregroundStyle(Theme.glow)
                        .padding(.top, RB.xs)
                }
            }
            .padding(.horizontal, RB.xl)
            .padding(.bottom, RB.xl)
            .frame(maxWidth: .infinity)
        }
        .background(ForestBackground())
    }

    private func leafSheet(_ l: LeafType) -> some View {
        let count = leafCounts[l.id] ?? 0
        return ScrollView {
            VStack(spacing: RB.m) {
                LeafView(leaf: l, size: 120, collected: count > 0)
                    .padding(.top, RB.xxl)
                    .accessibilityHidden(true)
                Text(count > 0 ? l.name : "Not found yet").font(Theme.title(28)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                RarityLabel(rarity: l.rarity)
                Text(count > 0 ? l.blurb : "Keep hugging. Barefoot and longer sessions improve your odds of rare leaves.")
                    .font(RB.text(.body)).foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if count > 0 {
                    Text("Collected ×\(count)").font(RB.text(.subheadline, .bold)).monospacedDigit().foregroundStyle(l.rarity.color)
                }
            }
            .padding(.horizontal, RB.xl)
            .padding(.bottom, RB.xl)
            .frame(maxWidth: .infinity)
        }
        .background(ForestBackground())
    }
}

extension LeafType: Equatable {
    static func == (a: LeafType, b: LeafType) -> Bool { a.id == b.id }
}
