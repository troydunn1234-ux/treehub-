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
    /// "Sync Roamr": walks from Roamr / Apple Health onto the hugs they passed.
    @State private var syncing = false
    @State private var syncNote = ""

    private var level: LevelInfo { GameEngine.level(for: GameEngine.totalXP(hugs: hugs, activities: activities)) }
    private var streak: Int { GameEngine.currentStreak(hugs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap + 6) {
                    hero
                    Group {
                        // 1. You: level + streak, then the two things to do.
                        levelCard.offset(y: -54).padding(.bottom, -54)
                        quickActions
                        if !syncNote.isEmpty { syncResult }
                        if !watchInbox.pending.isEmpty { watchHugCard }
                        // 2. Your numbers, always recomputed from the hugs + linked sessions.
                        statsGrid
                        TodayConnectionsCard(hugs: hugs)
                        CalmMinutesCard(hugs: hugs)
                        // 3. Memories and goals.
                        if hugs.isEmpty { firstHugCard } else { recentHugs }
                        if let ev = SeasonalEvent.active() { SeasonalEventBanner(event: ev, hugs: hugs) }
                        nextBadges
                        NatureRollEntryCard()
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
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(Theme.forestDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.leafGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Theme.glow.opacity(0.25), radius: 10, y: 4)
            }
            .pressable()
            Button { Task { await syncRoamr() } } label: {
                HStack(spacing: 8) {
                    if syncing { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text(syncing ? "Syncing…" : "Sync Roamr")
                }
                    .font(Theme.rounded(16, .bold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            }
            .pressable()
            .disabled(syncing)
            .accessibilityHint("Adds walks from Roamr and Apple Health to the hugs they passed")
        }
    }

    /// What the last "Sync Roamr" did, and where to get Roamr when it isn't there.
    private var syncResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(syncNote, systemImage: "figure.walk")
                .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            if !WellnessLinks.roamrInstalled { GetRoamrCard() }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func syncRoamr() async {
        syncing = true
        let added = await RoamrWalks.sync(hugs, context: context, ask: true)
        syncing = false
        UINotificationFeedbackGenerator().notificationOccurred(added > 0 ? .success : .warning)
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
        let minutes = hugs.reduce(0) { $0 + $1.breathMinutes }
        let walked = GameEngine.uniqueWalks(hugs).reduce(0) { $0 + $1.distanceM }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: "\(hugs.count)", label: "Hugs", symbol: "heart.fill")
            StatTile(value: "\(trees)", label: "Tree friends", symbol: "tree.fill")
            StatTile(value: Format.minutes((minutes * 10).rounded() / 10), label: "Breathwork at trees", symbol: "wind", tint: Theme.sky)
            StatTile(value: LinkedWalk.distance(walked), label: "Walked to trees", symbol: "figure.walk")
        }
    }

    /// A hug timed on the Watch that still needs its tree.
    private var watchHugCard: some View {
        Button(action: openWatchHug) {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.forestDeep)
                        .frame(width: 40, height: 40)
                        .background(Theme.leafGradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        let n = watchInbox.pending.count
                        Text(n == 1 ? "Hug from Watch" : "\(n) hugs from Watch").font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                        Text("Pick the tree to log it").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.glow)
                }
            }
        }
        .pressable()
    }

    private var firstHugCard: some View {
        Button { showHugLog = true } label: {
            GlassCard {
                HStack(spacing: 16) {
                    Image(systemName: "tree.fill").font(.system(size: 40)).foregroundStyle(Theme.leafGradient)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log your first hug").font(Theme.rounded(18, .bold)).foregroundStyle(.white)
                        Text("Snap the tree; your Apple Watch and Still Pointz sessions fill in the rest.")
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
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [event.colors[0].opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(event.colors[0].opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
