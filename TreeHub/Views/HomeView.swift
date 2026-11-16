import SwiftUI
import UIKit
import SwiftData
import MapKit

struct HomeView: View {
    @Binding var tab: AppTab
    @Binding var showHugLog: Bool
    /// Opens "Hug from Watch — pick tree" (RootView owns it).
    var openWatchHug: () -> Void = {}
    @ObservedObject private var watchInbox = WatchHugInbox.shared
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @State private var showSettings = false
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    /// "Sync Roamr": walks from Roamr / Apple Health onto the hugs they passed.
    @State private var syncing = false
    @State private var syncNote = ""
    @State private var syncDone = 0

    private var level: LevelInfo { GameEngine.level(for: GameEngine.totalXP(hugs: hugs, activities: activities)) }
    private var streak: Int { GameEngine.currentStreak(hugs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RB.xl) {
                    hero
                    Group {
                        // 1. You: level + streak, then the two things to do.
                        VStack(spacing: RB.m) {
                            levelCard
                            quickActions
                            if !syncNote.isEmpty { syncResult }
                            if !watchInbox.pending.isEmpty { watchHugCard }
                        }
                        .padding(.top, -RB.xxl - RB.s)
                        // 2. Your numbers, always recomputed from the hugs + linked sessions.
                        VStack(alignment: .leading, spacing: RB.m) {
                            RBSectionTitle(title: "Your numbers", symbol: "chart.bar.fill")
                            statsGrid
                            CalmMinutesCard(hugs: hugs)
                        }
                        // 3. Memories and goals.
                        if hugs.isEmpty { firstHugCard } else { recentHugs }
                        if let ev = SeasonalEvent.active() { SeasonalEventBanner(event: ev, hugs: hugs) }
                        nextBadges
                        NatureRollEntryCard()
                    }
                    .padding(.horizontal, RB.screen)
                }
                .padding(.bottom, 130)
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let h = hugs.first(where: { $0.id == id }) { HugDetailView(hug: h) }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sensoryFeedback(.success, trigger: syncDone)
        }
    }

    /// Clean hero: your latest hug's photo, softly faded, with the greeting and app name.
    private var hero: some View {
        let photo = hugs.first.flatMap { $0.selfiePhoto ?? $0.treePhoto }
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let pull = max(0, geo.frame(in: .scrollView).minY)
                RBPhotoFill(data: photo)
                    .frame(width: geo.size.width, height: geo.size.height + pull)
                    .clipped()
                    .offset(y: -pull)
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.3),
                            .init(color: Theme.forestDeep.opacity(0.7), location: 0.75),
                            .init(color: Theme.forestDeep, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        .offset(y: -pull)
                    }
            }
            .frame(height: 340)

            VStack(alignment: .leading, spacing: RB.xs) {
                Text(greeting)
                    .font(RB.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.glow)
                Text("Rootbound")
                    .font(Theme.title(40))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                if let latest = hugs.first {
                    Text("Last hug · \(latest.treeName) · \(Format.day(latest.date))")
                        .font(RB.text(.footnote, .medium)).foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, RB.screen)
            .padding(.bottom, RB.xxl + RB.xl)
        }
        .overlay(alignment: .topTrailing) {
            RBIconButton(symbol: "gearshape.fill", label: "Settings") { showSettings = true }
                .padding(.trailing, RB.screen)
                .padding(.top, 60)
        }
    }

    private var quickActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RB.m) { hugButton; syncButton }
            VStack(spacing: RB.m) { hugButton; syncButton }
        }
    }

    private var hugButton: some View {
        Button { showHugLog = true } label: { Label("Hug a tree", systemImage: "heart.fill") }
            .buttonStyle(RBPrimaryButtonStyle())
    }

    private var syncButton: some View {
        Button { Task { await syncRoamr() } } label: {
            HStack(spacing: RB.s) {
                if syncing { ProgressView().controlSize(.small).tint(Theme.glow) }
                else { Image(systemName: "arrow.triangle.2.circlepath") }
                Text(syncing ? "Syncing…" : "Sync Roamr")
            }
        }
        .buttonStyle(RBSecondaryButtonStyle())
        .disabled(syncing)
        .accessibilityHint("Adds walks from Roamr and Apple Health to the hugs they passed")
    }

    /// What the last "Sync Roamr" did, and where to get Roamr when it isn't there.
    private var syncResult: some View {
        VStack(alignment: .leading, spacing: RB.s) {
            Label(syncNote, systemImage: "figure.walk")
                .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            if !WellnessLinks.roamrInstalled { GetRoamrCard() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func syncRoamr() async {
        syncing = true
        let added = await RoamrWalks.sync(hugs, context: context, ask: true)
        syncing = false
        if added > 0 { syncDone += 1 } else { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        withAnimation(.snappy) {
            if added > 0 {
                syncNote = "Added \(added) walk\(added == 1 ? "" : "s") to your hugs."
            } else if hugs.isEmpty {
                syncNote = "Log a hug first. Walks within 2 hours of it show up under it."
            } else {
                syncNote = "Up to date. Walks within 2 hours of a hug show up under it; pick others in Edit hug."
            }
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
        RBCard {
            HStack(spacing: RB.l) {
                LevelRing(info: level, size: 76)
                VStack(alignment: .leading, spacing: RB.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(level.title).font(RB.text(.title3, .bold)).foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer(minLength: RB.s)
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").symbolEffect(.bounce, value: streak)
                            Text("\(streak)").monospacedDigit().contentTransition(.numericText())
                        }
                        .font(RB.text(.subheadline, .heavy))
                        .foregroundStyle(streak > 0 ? Theme.forestDeep : Theme.textDim)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(streak > 0 ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(streak)-day hug streak")
                    }
                    ProgressView(value: level.progress)
                        .tint(Theme.glow)
                        .accessibilityLabel("Level progress")
                    Text("\(level.xpForNext - level.xpIntoLevel) XP to level \(level.level + 1)")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                        .monospacedDigit()
                }
            }
        }
        .background(Theme.forestDeep.opacity(0.6), in: RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
    }

    private var statsGrid: some View {
        let trees = Set(hugs.map(\.treeID)).count
        let minutes = hugs.reduce(0) { $0 + $1.breathMinutes }
        let walked = GameEngine.uniqueWalks(hugs).reduce(0) { $0 + $1.distanceM }
        return LazyVGrid(columns: rbColumns(2, typeSize, spacing: RB.s), spacing: RB.s) {
            RBStatTile(value: "\(hugs.count)", label: "Hugs", symbol: "heart.fill")
            RBStatTile(value: "\(trees)", label: "Tree friends", symbol: "tree.fill")
            RBStatTile(value: Format.minutes((minutes * 10).rounded() / 10), label: "Breathwork at trees", symbol: "wind", tint: Theme.sky)
            RBStatTile(value: LinkedWalk.distance(walked), label: "Walked to trees", symbol: "figure.walk")
        }
    }

    /// A hug timed on the Watch that still needs its tree.
    private var watchHugCard: some View {
        Button(action: openWatchHug) {
            RBCard(padding: RB.m, tint: Theme.glow) {
                HStack(spacing: RB.m) {
                    Image(systemName: "applewatch")
                        .font(.headline).foregroundStyle(Theme.forestDeep)
                        .frame(width: 44, height: 44)
                        .background(Theme.glow, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        let n = watchInbox.pending.count
                        Text(n == 1 ? "Hug from Watch" : "\(n) hugs from Watch").font(RB.text(.headline, .bold)).foregroundStyle(.white)
                        Text("Pick the tree to log it").font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.glow)
                }
            }
        }
        .pressable()
    }

    private var firstHugCard: some View {
        RBCard {
            RBEmptyState(symbol: "tree.fill", title: "Log your first hug",
                         hint: "Snap the tree; your Apple Watch and Still Pointz sessions fill in the rest.",
                         actionTitle: "Hug a tree") { showHugLog = true }
        }
    }

    private var recentHugs: some View {
        VStack(alignment: .leading, spacing: RB.m) {
            RBSectionTitle(title: "Recent hugs", symbol: "heart.fill") {
                Button("Grove") { tab = .trees }
                    .font(RB.text(.subheadline, .semibold)).foregroundStyle(Theme.glow)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: RB.m) {
                    ForEach(hugs.prefix(10)) { h in
                        NavigationLink(value: h.id) { HugCard(hug: h) }
                            .pressable()
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content.scaleEffect(phase.isIdentity ? 1 : 0.95).opacity(phase.isIdentity ? 1 : 0.8)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, RB.screen, for: .scrollContent)
            .padding(.horizontal, -RB.screen)
        }
    }

    private var nextBadges: some View {
        let all = GameEngine.badges(hugs: hugs, activities: activities)
        let next = all.filter { !$0.earned }.sorted { $0.progress > $1.progress }.prefix(3)
        let earned = all.filter(\.earned).count
        return VStack(alignment: .leading, spacing: RB.m) {
            RBSectionTitle(title: "Almost there", symbol: "rosette") {
                Button("\(earned)/\(all.count) badges") { tab = .collection }
                    .font(RB.text(.subheadline, .semibold)).foregroundStyle(Theme.glow)
                    .monospacedDigit()
            }
            RBCard {
                VStack(spacing: RB.l) {
                    ForEach(Array(next)) { b in
                        HStack(spacing: RB.m) {
                            Medallion(symbol: b.symbol, rarity: b.rarity, earned: false, size: 44)
                            VStack(alignment: .leading, spacing: RB.xs) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(b.name).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                                    Spacer(minLength: RB.s)
                                    Text(b.progressText).font(RB.text(.caption, .bold)).foregroundStyle(Theme.textDim).monospacedDigit()
                                }
                                ProgressView(value: b.progress).tint(b.rarity.color)
                                Text(b.detail).font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Recent hug as a hero tree card: full-bleed photo, tree name, date, and chips for its breathwork and walks.
struct HugCard: View {
    let hug: Hug
    @Environment(\.dynamicTypeSize) private var typeSize

    private var breathChip: String? {
        let n = hug.linkedSessions.count
        let min = hug.breathMinutes
        guard n > 0 || min > 0 else { return nil }
        let m = Format.minutes((min * 10).rounded() / 10)
        return n > 1 ? "\(n) breaths · \(m)" : m
    }
    private var walkChip: String? {
        let d = hug.linkedWalks.reduce(0) { $0 + $1.distanceM }
        return d > 0 ? LinkedWalk.distance(d) : (hug.linkedWalks.isEmpty ? nil : hug.linkedWalks[0].timeText)
    }

    var body: some View {
        let width: CGFloat = typeSize.isAccessibilitySize ? 300 : 240
        ZStack(alignment: .bottomLeading) {
            RBPhotoFill(data: hug.selfiePhoto ?? hug.treePhoto)
                .frame(width: width, height: 300)
                .clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: RB.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hug.treeName)
                        .font(RB.text(.title3, .bold)).foregroundStyle(.white)
                        .lineLimit(2)
                    Text(Format.day(hug.date))
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 6) {
                    if let b = breathChip { RBInfoChip(text: b, symbol: "wind", tint: Theme.sky) }
                    if let w = walkChip { RBInfoChip(text: w, symbol: hug.linkedWalks.first?.symbol ?? "figure.walk") }
                    if hug.barefoot { RBInfoChip(text: "Barefoot", symbol: "shoeprints.fill", tint: Theme.gold) }
                }
            }
            .padding(RB.l)
        }
        .frame(width: width, height: 300)
        .overlay(alignment: .topTrailing) {
            if let leaf = LeafType.find(hug.leafKey) {
                LeafView(leaf: leaf, size: 26)
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(RB.m)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(RB.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hug.treeName), \(Format.day(hug.date))\(breathChip.map { ", breathwork \($0)" } ?? "")\(walkChip.map { ", walk \($0)" } ?? "")")
    }
}


/// The running seasonal event (Seasons.swift): what it is, how long it lasts, and whether you've got its badge.
struct SeasonalEventBanner: View {
    let event: SeasonalEvent
    let hugs: [Hug]

    private var duringEvent: [Hug] {
        let start = Calendar.current.date(byAdding: .day, value: -100, to: Date()) ?? Date()
        return hugs.filter { $0.date >= start && event.isActive(on: $0.date) }
    }
    private var badgeEarned: Bool { hugs.contains { event.isActive(on: $0.date) && event.features(species: $0.species) } }

    var body: some View {
        let days = event.daysLeft()
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: event.symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(event.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: event.colors[0].opacity(0.6), radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("EVENT").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(event.colors[0], in: Capsule()).foregroundStyle(Theme.forestDeep)
                    Text(days == 0 ? "Last day" : "\(days) day\(days == 1 ? "" : "s") left")
                        .font(Theme.rounded(12, .bold)).foregroundStyle(Theme.textDim)
                }
                Text(event.name).font(Theme.rounded(19, .heavy)).foregroundStyle(.white)
                Text(event.tagline).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                Text("+\(event.bonusXP) XP every hug · +\(event.featuredBonusXP) more for \(event.featuredLabel)")
                    .font(Theme.rounded(12, .bold)).foregroundStyle(event.colors[0])
                HStack(spacing: 6) {
                    Image(systemName: badgeEarned ? "checkmark.seal.fill" : "seal")
                    Text(badgeEarned ? "\(event.badgeName) badge earned" : "Hug one of the \(event.featuredLabel) for the \(event.badgeName) badge")
                }
                .font(Theme.rounded(12, .semibold))
                .foregroundStyle(badgeEarned ? Theme.gold : Theme.textDim)
                if !duringEvent.isEmpty {
                    Text("\(duringEvent.count) hug\(duringEvent.count == 1 ? "" : "s") so far this event")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: RB.radius, style: .continuous).fill(Theme.card)
            RoundedRectangle(cornerRadius: RB.radius, style: .continuous)
                .fill(LinearGradient(colors: [event.colors[0].opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(event.colors[0].opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
