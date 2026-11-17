import SwiftUI
import UIKit

/// The reward screen after logging a hug: XP tally, leaf reveal, new badges, level up, and the breath sessions
/// that went with it.
struct CelebrationView: View {
    let data: CelebrationData
    var onDone: () -> Void

    @State private var step = 0
    @State private var xpShown = 0
    @State private var leafFlipped = false
    @State private var burst = false
    @State private var badgePop = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leveledUp: Bool { data.levelAfter.level > data.levelBefore.level }
    private var levelUpShown: Bool { leveledUp && step >= 1 }

    var body: some View {
        ZStack {
            ForestBackground()
            if burst && !reduceMotion { LeafBurst().allowsHitTesting(false) }
            ScrollView {
                VStack(spacing: RB.l) {
                    header
                    if let r = data.rareFind {
                        RareFindCard(rarity: r, species: data.species)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if let ev = data.event { eventRow(ev) }
                    xpCard
                    if let leaf = data.leaf, step >= 1 {
                        leafReveal(leaf)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if !data.newBadges.isEmpty && leafFlipped {
                        badgesCard
                            .onAppear { badgePop += 1 }
                            .transition(.scale.combined(with: .opacity))
                    }
                    if !data.sessions.isEmpty { sessionsCard }
                    if step >= 1 {
                        breatheRow.transition(.opacity)
                    }
                    Button("Back to the forest", action: onDone)
                        .buttonStyle(RBPrimaryButtonStyle())
                        .padding(.top, RB.s)
                        .padding(.bottom, RB.xxl)
                }
                .padding(.horizontal, RB.screen)
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.success, trigger: step)
        .sensoryFeedback(.impact(weight: .heavy), trigger: leafFlipped)
        .sensoryFeedback(.success, trigger: badgePop)
        .sensoryFeedback(.levelChange, trigger: levelUpShown)
        .task { await run() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: RB.s) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.55))
                .frame(width: 84, height: 84)
                .background(Color(red: 1, green: 0.45, blue: 0.55).opacity(0.15), in: Circle())
                .symbolEffect(.bounce, value: step)
                .accessibilityHidden(true)
            Text("Hug logged").font(Theme.title(32)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("\(data.treeName) felt that.").font(RB.text(.body, .medium)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(.top, RB.xxl + RB.s)
    }

    private func eventRow(_ ev: SeasonalEvent) -> some View {
        HStack(spacing: RB.m) {
            Image(systemName: ev.symbol).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(ev.gradient, in: Circle())
                .accessibilityHidden(true)
            Text("\(ev.name) event: bonus XP on every hug").font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(RB.m)
        .rbInner()
    }

    private var xpCard: some View {
        RBCard(tint: Theme.gold) {
            VStack(alignment: .leading, spacing: RB.m) {
                HStack(alignment: .center, spacing: RB.l) {
                    LevelRing(info: step >= 1 ? data.levelAfter : data.levelBefore, size: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("+\(xpShown) XP")
                            .font(.system(.largeTitle, design: .rounded).weight(.black))
                            .monospacedDigit()
                            .foregroundStyle(Theme.goldGradient)
                            .contentTransition(.numericText(value: Double(xpShown)))
                            .accessibilityLabel("\(data.breakdown.total) XP earned")
                        if levelUpShown {
                            Label("Level \(data.levelAfter.level) · \(data.levelAfter.title)", systemImage: "arrow.up.circle.fill")
                                .font(RB.text(.subheadline, .bold)).foregroundStyle(Theme.gold)
                                .symbolEffect(.bounce, value: step)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("\(data.levelAfter.xpForNext - data.levelAfter.xpIntoLevel) XP to level \(data.levelAfter.level + 1)")
                                .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                ProgressView(value: step >= 1 ? data.levelAfter.progress : data.levelBefore.progress)
                    .tint(Theme.gold)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: step)
                    .accessibilityLabel("Level progress")
                Divider().overlay(RB.stroke)
                ForEach(Array(data.breakdown.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.0).font(RB.text(.subheadline)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: RB.s)
                        Text("+\(line.1)").font(RB.number(.subheadline)).monospacedDigit().foregroundStyle(Theme.glow)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// The leaf this hug dropped: a face-down card that flips over on tap.
    private func leafReveal(_ leaf: LeafType) -> some View {
        VStack(spacing: RB.s) {
            Text(leafFlipped ? "You found a leaf!" : "A leaf is falling…")
                .font(RB.text(.headline, .bold)).foregroundStyle(.white)
            Button { flip() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(leafFlipped
                              ? AnyShapeStyle(RadialGradient(colors: [leaf.rarity.color.opacity(0.55), Theme.forestDeep],
                                                             center: .center, startRadius: 5, endRadius: 140))
                              : AnyShapeStyle(Theme.moss))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(leafFlipped ? leaf.rarity.color : Theme.cardStroke, lineWidth: 2))
                    if leafFlipped {
                        VStack(spacing: RB.s) {
                            LeafView(leaf: leaf, size: 96)
                            Text(leaf.name).font(Theme.title(22)).foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            RarityLabel(rarity: leaf.rarity)
                            Text(leaf.blurb).font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    } else {
                        Image(systemName: "questionmark")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.glow.opacity(0.7))
                    }
                }
                .frame(width: 230, height: 270)
                .rotation3DEffect(.degrees(leafFlipped && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leafFlipped ? "\(leaf.name), \(leaf.rarity.title) leaf. \(leaf.blurb)" : "Hidden leaf")
            .accessibilityHint(leafFlipped ? "" : "Reveals the leaf you found")
            if !leafFlipped {
                Text("Tap to reveal").font(RB.text(.footnote, .bold)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var badgesCard: some View {
        RBCard(tint: data.newBadges.map(\.rarity).max()?.color) {
            VStack(alignment: .leading, spacing: RB.m) {
                RBSectionTitle(title: data.newBadges.count == 1 ? "Badge unlocked" : "\(data.newBadges.count) badges unlocked",
                               symbol: "rosette", tint: Theme.gold)
                ForEach(data.newBadges) { b in
                    HStack(spacing: RB.m) {
                        Medallion(symbol: b.symbol, rarity: b.rarity, earned: true, size: 56)
                            .scaleEffect(badgePop > 0 || reduceMotion ? 1 : 0.6)
                            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55), value: badgePop)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: RB.xs) {
                            Text(b.name).font(RB.text(.headline, .bold)).foregroundStyle(.white)
                            Text(b.detail).font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                            RarityLabel(rarity: b.rarity)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var sessionsCard: some View {
        RBCard {
            VStack(alignment: .leading, spacing: RB.m) {
                RBSectionTitle(title: data.sessions.count == 1 ? "Your breath session" : "Your \(data.sessions.count) breath sessions",
                               symbol: "wind", tint: Theme.sky)
                if data.sessions.count > 1 { LinkedSessionTotals(sessions: data.sessions) }
                ForEach(data.sessions) { s in LinkedSessionCard(session: s) }
            }
        }
    }

    private var breatheRow: some View {
        VStack(spacing: RB.s) {
            BreatheWithTreeButton(treeName: data.treeName, treeID: data.treeID)
            if let id = data.treeID {
                let b = TreeBreaths.tagged(for: id)
                if !b.isEmpty {
                    Text("\(b.count) breath session\(b.count == 1 ? "" : "s") with \(data.treeName) · \(Format.minutes(b.reduce(0) { $0 + $1.minutes })) mindful")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: Motion

    private func flip() {
        guard !leafFlipped else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.7)) { leafFlipped = true }
        if let leaf = data.leaf, leaf.rarity >= .rare {
            burst = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func run() async {
        burst = true
        let target = data.breakdown.total
        let steps = reduceMotion ? 1 : 24
        for i in 1...steps {
            try? await Task.sleep(nanoseconds: 35_000_000)
            withAnimation(.snappy) { xpShown = Int(Double(target) * Double(i) / Double(steps)) }
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.75)) { step = 1 }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        burst = false
        if data.leaf == nil || DemoData.isOn { withAnimation { leafFlipped = true } }
    }
}

/// Leaves bursting out from the center.
struct LeafBurst: View {
    @State private var start = Date()
    private let pieces: [(angle: Double, dist: Double, spin: Double, color: Int, size: Double)] = {
        var r = SeededRNG(seed: "burst")
        return (0..<36).map { _ in (r.next() * .pi * 2, 160 + r.next() * 260, (r.next() - 0.5) * 8, Int(r.next() * 4), 12 + r.next() * 16) }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = min(1.6, ctx.date.timeIntervalSince(start))
                let p = 1 - pow(1 - min(1, t / 1.1), 3)
                let colors: [Color] = [Theme.glow, Theme.gold, Color(red: 1, green: 0.5, blue: 0.3), Theme.leaf]
                for piece in pieces {
                    var g = gc
                    let x = size.width / 2 + cos(piece.angle) * piece.dist * p
                    let y = size.height * 0.35 + sin(piece.angle) * piece.dist * p + 120 * t * t
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .radians(piece.spin * t))
                    g.opacity = max(0, 1 - t / 1.6)
                    let s = piece.size
                    g.fill(LeafPath(shape: .oval).path(in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s)), with: .color(colors[piece.color]))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { start = Date() }
    }
}

/// "Rare find!": the first time you hug a species that's rare, epic or legendary.
struct RareFindCard: View {
    let rarity: Rarity
    let species: String
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: RB.s) {
            Image(systemName: rarity == .legendary ? "crown.fill" : rarity == .epic ? "star.circle.fill" : "sparkle.magnifyingglass")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: rarity.color, radius: glow ? 18 : 6)
                .symbolEffect(.bounce, value: glow)
                .accessibilityHidden(true)
            Text(rarity == .legendary ? "LEGENDARY FIND!" : "RARE FIND!")
                .font(RB.text(.footnote, .heavy)).tracking(2)
                .foregroundStyle(rarity.color)
            Text(species).font(Theme.title(26)).foregroundStyle(.white).multilineTextAlignment(.center)
            RarityLabel(rarity: rarity)
            Text("+\(SpeciesRarity.firstFindXP(rarity)) XP for your first \(rarity.title.lowercased()) \(species.lowercased()).")
                .font(RB.text(.footnote)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RB.l + 4)
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: [rarity.color.opacity(0.45), Theme.forestDeep.opacity(0.6)], center: .center, startRadius: 4, endRadius: 220),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RarityFrame(rarity: rarity, cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            guard !reduceMotion else { glow = true; return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
