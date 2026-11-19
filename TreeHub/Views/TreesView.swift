import SwiftUI
import SwiftData
import MapKit

struct TreesView: View {
    /// Home's "Open tree map" sets this; the Grove opens on its map once.
    static var startOnMap = false
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @State private var mode = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedTree: UUID?
    @State private var showFriends = false
    @State private var showNatureRoll = false
    @State private var incomingCode: String?
    @State private var friends = FriendShare.friends
    @State private var showFriendTrees = true
    @State private var path = NavigationPath()
    @Environment(\.dynamicTypeSize) private var typeSize

    private var trees: [TreeSummary] { TreeSummary.build(from: hugs) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: RB.m) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: RB.m) { groveTitle; Spacer(minLength: RB.s); groveControls }
                    VStack(alignment: .leading, spacing: RB.m) { groveTitle; groveControls }
                }
                .padding(.horizontal, RB.screen)
                .padding(.top, RB.m)

                if trees.isEmpty {
                    Spacer()
                    RBEmptyState(symbol: "tree", title: "Your grove is empty",
                                 hint: "Hug a tree and it shows up here, with every visit you share.",
                                 actionTitle: "Hug a tree") { RootboundPending.queue(.logHug) }
                        .padding(.horizontal, RB.screen)
                    Spacer()
                    Spacer()
                } else if mode == 0 {
                    grid
                } else {
                    map
                }
            }
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNatureRoll) { NatureRollView() }
            .sheet(isPresented: $showFriends, onDismiss: { friends = FriendShare.friends }) {
                FriendsView(incoming: incomingCode)
            }
            .onReceive(NotificationCenter.default.publisher(for: FriendShare.changed)) { _ in friends = FriendShare.friends }
            .onReceive(NotificationCenter.default.publisher(for: FriendShare.incoming)) { _ in openIncoming() }
            .onAppear {
                if Self.startOnMap { Self.startOnMap = false; mode = 1 }
                openIncoming(); openPendingTree()
            }
            // rootbound://tree?id=… (back from a Still Pointz breath with this tree)
            .onReceive(NotificationCenter.default.publisher(for: TreeBreaths.openTree)) { _ in openPendingTree() }
            .navigationDestination(for: UUID.self) { id in
                if let t = trees.first(where: { $0.id == id }) { TreeDetailView(treeID: t.id) }
                else if let h = hugs.first(where: { $0.id == id }) { HugDetailView(hug: h) }
            }
        }
    }

    private var groveTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("My Grove").font(Theme.title(36)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("\(trees.count) tree friend\(trees.count == 1 ? "" : "s") · \(hugs.count) hug\(hugs.count == 1 ? "" : "s")")
                .font(RB.text(.subheadline, .semibold)).foregroundStyle(Theme.textDim)
                .monospacedDigit()
        }
    }

    private var groveControls: some View {
        HStack(spacing: RB.s) {
            RBIconButton(symbol: "person.2.fill", label: "Friends map: share and import trees", tint: Theme.sky) {
                incomingCode = nil; showFriends = true
            }
            RBIconButton(symbol: NatureRoll.symbol, label: NatureRoll.title, tint: Theme.glow) { showNatureRoll = true }
            PillSwitcher(options: [.init(id: 0, label: "Grid", symbol: "square.grid.2x2.fill"),
                                   .init(id: 1, label: "Map", symbol: "map.fill")],
                         selection: $mode)
                .frame(width: 180)
        }
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func openPendingTree() {
        guard let id = TreeBreaths.pendingTreeID else { return }
        TreeBreaths.pendingTreeID = nil
        guard trees.contains(where: { $0.id == id }) else { return }
        var p = NavigationPath()
        p.append(id)
        path = p
    }

    /// A rootbound://friends?c=… link was opened (TreeHubApp): show it in the Friends sheet.
    private func openIncoming() {
        guard let c = FriendShare.pendingCode else { return }
        FriendShare.pendingCode = nil
        incomingCode = c
        mode = 1
        showFriends = true
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: rbColumns(2, typeSize, spacing: RB.m), spacing: RB.m) {
                ForEach(trees) { t in
                    NavigationLink(value: t.id) { TreeCard(tree: t) }.pressable().cardAppear()
                }
            }
            .padding(.horizontal, RB.screen)
            .padding(.top, RB.xs)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    private var map: some View {
        let mapped = trees.filter { $0.coordinate != nil }
        return ZStack(alignment: .bottom) {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(mapped) { t in
                    Annotation(t.name, coordinate: t.coordinate!) {
                        Button { withAnimation { selectedTree = t.id } } label: {
                            TreePin(photo: t.coverPhoto, size: selectedTree == t.id ? 58 : 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if showFriendTrees {
                    ForEach(friends) { f in
                        ForEach(Array(f.trees.enumerated()), id: \.offset) { _, ft in
                            Annotation("\(f.name): \(ft.n)", coordinate: ft.coordinate) { FriendTreePin() }
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 12)

            if let id = selectedTree, let t = mapped.first(where: { $0.id == id }) {
                NavigationLink(value: t.id) {
                    HStack(spacing: RB.m) {
                        RBPhotoView(data: t.coverPhoto, points: 56).frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: RB.inner, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.name).font(RB.text(.headline, .bold)).foregroundStyle(.white)
                            HeartsView(filled: t.bond, size: 11)
                            Text("\(t.hugCount) hug\(t.hugCount == 1 ? "" : "s") · last \(Format.day(t.lastHug))")
                                .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                        }
                        Spacer(minLength: RB.s)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.glow)
                    }
                    .padding(RB.m)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(RB.stroke))
                    .padding(.horizontal, RB.xl)
                    .padding(.bottom, RB.m)
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 100)
        .sensoryFeedback(.selection, trigger: selectedTree)
        .overlay(alignment: .topTrailing) {
            if !friends.isEmpty {
                Button { withAnimation { showFriendTrees.toggle() } } label: {
                    Label(showFriendTrees ? "Friends on" : "Friends off", systemImage: "person.2.fill")
                        .font(RB.text(.caption, .bold))
                        .foregroundStyle(showFriendTrees ? Theme.sky : Theme.textDim)
                        .padding(.horizontal, RB.m).padding(.vertical, RB.s)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, RB.xs).padding(.trailing, 70)
                .accessibilityLabel(showFriendTrees ? "Hide friends' trees" : "Show friends' trees")
            }
        }
        .overlay(alignment: .top) {
            if mapped.count < trees.count {
                Label("\(trees.count - mapped.count) tree\(trees.count - mapped.count == 1 ? "" : "s") without a pin", systemImage: "mappin.slash")
                    .font(RB.text(.caption, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, RB.m).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, RB.m)
            }
        }
    }
}

struct TreeCard: View {
    let tree: TreeSummary
    private var rarity: Rarity { SpeciesRarity.rarity(for: tree.species) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RBPhotoView(data: tree.coverPhoto, points: 420)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(stops: [
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(tree.name)
                    .font(RB.text(.headline, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(tree.species.isEmpty ? "Mystery species" : tree.species)
                    .font(RB.text(.caption, .semibold))
                    .foregroundStyle(Theme.glow)
                    .lineLimit(1)
                HeartsView(filled: tree.bond, size: 10)
            }
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(tree.hugCount)×")
                .font(RB.text(.caption, .heavy)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(RB.stroke))
        .overlay { if rarity > .common { RarityFrame(rarity: rarity, cornerRadius: RB.radius) } }
        .overlay(alignment: .topLeading) {
            if rarity > .common { RarityLabel(rarity: rarity).padding(10) }
        }
        .shadow(color: rarity > .common ? rarity.color.opacity(rarity >= .epic ? 0.4 : 0.2) : .clear, radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tree.name), \(tree.species.isEmpty ? "mystery species" : tree.species), \(tree.hugCount) hug\(tree.hugCount == 1 ? "" : "s")")
    }
}

@MainActor
struct TreeDetailView: View {
    let treeID: UUID
    @Environment(\.modelContext) private var context
    @Query(sort: \Hug.date, order: .reverse) private var allHugs: [Hug]
    @State private var renaming = false
    @State private var newName = ""
    @State private var renamed = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Breath sessions with this tree (Still Pointz + overlapping Health mindful sessions).
    @State private var breaths: [TreeBreath] = []
    /// True until the first look-up of this tree's breath sessions finishes (skeleton rows meanwhile).
    @State private var loadingBreaths = true
    @Environment(\.scenePhase) private var scenePhase

    private var tree: TreeSummary? { TreeSummary.build(from: allHugs.filter { $0.treeID == treeID }).first }
    private var taggedMinutes: Double { breaths.filter(\.tagged).reduce(0) { $0 + $1.minutes } }

    var body: some View {
        ScrollView {
            if let tree {
                VStack(alignment: .leading, spacing: RB.xl) {
                    profileHeader(tree)
                        .padding(.horizontal, -RB.screen)

                    totals(tree)

                    RBCard {
                        VStack(alignment: .leading, spacing: RB.m) {
                            TreeBreathSection(treeName: tree.name, breaths: breaths, loading: loadingBreaths)
                            BreatheWithTreeButton(treeName: tree.name, treeID: tree.id)
                        }
                    }

                    TreeInsightsCard(tree: tree, breaths: breaths)

                    // Walks synced from Roamr / Apple Health onto this tree's hugs, then the Roamr walks that
                    // passed it (ConnectionViews.swift).
                    TreeWalksCard(hugs: tree.hugs)
                    TreePassingWalksCard(tree: tree)

                    TreeFactCard(species: tree.species)

                    if let c = tree.coordinate { whereCard(tree, c) }

                    timeline(tree)
                }
                .padding(.horizontal, RB.screen)
                .padding(.bottom, 130)
            } else {
                RBEmptyState(symbol: "tree", title: "Tree not found",
                             hint: "Its hugs may have been moved to another tree.")
                    .padding(.top, 120)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
        // Recomputed whenever this tree's hugs or their linked sessions change (no stale totals).
        .task(id: signature) { await reloadBreaths() }
        .onReceive(NotificationCenter.default.publisher(for: TreeBreaths.openTree)) { _ in Task { await reloadBreaths() } }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await reloadBreaths() } } }
        .sensoryFeedback(.success, trigger: renamed)
        .alert("Rename tree", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                for h in allHugs where h.treeID == treeID { h.treeName = name }
                try? context.save()
                renamed += 1
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Profile

    /// Profile header: cover photo, round portrait overlapping it, name, species, place and bond.
    private func profileHeader(_ tree: TreeSummary) -> some View {
        let rarity = SpeciesRarity.rarity(for: tree.species)
        let portrait = tree.hugs.first(where: { $0.treePhoto != nil })?.treePhoto ?? tree.coverPhoto
        return VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let pull = max(0, geo.frame(in: .scrollView).minY)
                RBPhotoFill(data: tree.coverPhoto)
                    .frame(width: geo.size.width, height: geo.size.height + pull)
                    .clipped()
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.4), location: 0),
                            .init(color: .clear, location: 0.3),
                            .init(color: Theme.forestDeep.opacity(0.6), location: 0.8),
                            .init(color: Theme.forestDeep, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .offset(y: -pull)
            }
            .frame(height: 300)

            VStack(alignment: .leading, spacing: RB.m) {
                HStack(alignment: .bottom, spacing: RB.m) {
                    RBPhotoFill(data: portrait)
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(rarity > .common ? rarity.color : Theme.forestDeep, lineWidth: 4))
                        .background(Circle().fill(Theme.forestDeep).padding(-4))
                    Spacer(minLength: 0)
                    Button { newName = tree.name; renaming = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .buttonStyle(RBSecondaryButtonStyle(compact: true))
                    .fixedSize()
                }
                .padding(.top, -60)

                VStack(alignment: .leading, spacing: RB.xs) {
                    Text(tree.name)
                        .font(Theme.title(34))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: RB.s) {
                        Text(tree.species.isEmpty ? "Mystery species" : tree.species)
                            .font(RB.text(.subheadline, .semibold)).foregroundStyle(Theme.glow)
                        if rarity > .common { RarityLabel(rarity: rarity) }
                    }
                    if !tree.placeName.isEmpty {
                        Label(tree.placeName, systemImage: "mappin.and.ellipse")
                            .font(RB.text(.footnote, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: RB.s) {
                    HeartsView(filled: tree.bond, size: 15)
                    Text(bondLabel(tree.bond)).font(RB.text(.subheadline, .bold)).foregroundStyle(Theme.textDim)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bond: \(bondLabel(tree.bond)), \(tree.bond) of 5 hearts")
            }
            .padding(.horizontal, RB.screen)
        }
    }

    private func totals(_ tree: TreeSummary) -> some View {
        LazyVGrid(columns: rbColumns(2, typeSize, spacing: RB.s), spacing: RB.s) {
            RBStatTile(value: "\(tree.hugCount)", label: tree.hugCount == 1 ? "Hug" : "Hugs", symbol: "heart.fill")
            RBStatTile(value: Format.minutes(tree.totalMinutes + taggedMinutes), label: "Together", symbol: "timer")
            RBStatTile(value: Format.minutes((tree.breathMinutes * 10).rounded() / 10), label: "Breathwork", symbol: "wind", tint: Theme.sky)
            RBStatTile(value: Format.day(tree.firstHug), label: "Met", symbol: "calendar")
        }
    }

    private func whereCard(_ tree: TreeSummary, _ c: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: RB.m) {
            RBSectionTitle(title: "Where it grows", symbol: "map.fill")
            Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 500, longitudinalMeters: 500))) {
                Annotation(tree.name, coordinate: c) { TreePin(photo: tree.coverPhoto) }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
            .accessibilityLabel("Map of \(tree.name)")
            Button { MapsLink.open(c, name: tree.name) } label: {
                Label("Directions to \(tree.name)", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(RBSecondaryButtonStyle())
        }
    }

    /// Every hug with this tree, newest first, on a vertical timeline.
    private func timeline(_ tree: TreeSummary) -> some View {
        VStack(alignment: .leading, spacing: RB.m) {
            RBSectionTitle(title: "Hug timeline", symbol: "clock.arrow.circlepath")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tree.hugs.enumerated()), id: \.element.id) { i, h in
                    HStack(alignment: .top, spacing: RB.m) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(i == 0 ? Theme.glow : Theme.moss)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(Theme.glow.opacity(0.6), lineWidth: 1))
                                .padding(.top, RB.l + 2)
                            if i < tree.hugs.count - 1 {
                                Rectangle().fill(Theme.glow.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 12)
                        .accessibilityHidden(true)
                        NavigationLink(value: h.id) { TreeTimelineRow(hug: h) }
                            .buttonStyle(.plain)
                            .padding(.bottom, RB.s)
                    }
                }
            }
        }
    }

    /// Changes when any hug of this tree is added, edited or gets new session data.
    private var signature: Int {
        var h = Hasher()
        for x in allHugs where x.treeID == treeID {
            h.combine(x.id); h.combine(x.date); h.combine(x.durationMin); h.combine(x.linkedSessionsData)
        }
        return h.finalize()
    }

    /// Breathe-with-this-tree sessions (tagged in Still Pointz) plus every session linked to this tree's hugs.
    /// Each hug's sessions are refreshed from Still Pointz + Apple Health first, so late Watch data fills in;
    /// older hugs get theirs by matching the hug's time window.
    private func reloadBreaths() async {
        guard var tree else { loadingBreaths = false; return }
        let hugs = tree.hugs
        breaths = Self.combine(tagged: breaths.filter(\.tagged), hugs: hugs)   // show what's known straight away
        if !breaths.isEmpty { loadingBreaths = false }
        await HugSessions.refresh(Array(hugs.prefix(30)), context: context)
        tree.hugs = []   // tagged sessions only; the hugs' own sessions come from their links below
        let tagged = await TreeBreaths.load(for: tree)
        breaths = Self.combine(tagged: tagged, hugs: hugs)
        loadingBreaths = false
    }

    private static func combine(tagged: [TreeBreath], hugs: [Hug]) -> [TreeBreath] {
        var out = tagged
        for h in hugs {
            for s in h.linkedSessions where !out.contains(where: { $0.id == s.feedID || abs($0.start.timeIntervalSince(s.start)) < 90 }) {
                out.append(TreeBreath(id: s.feedID ?? s.id, start: s.start, minutes: s.minutes, avgHR: s.avgHR, minHR: s.minHR,
                                      hrDrop: s.hrDrop, hrv: s.hrv, source: s.source, practice: s.practice, tagged: false))
            }
        }
        return out.sorted { $0.start > $1.start }
    }

    private func bondLabel(_ b: Int) -> String {
        ["", "New friend", "Getting close", "Good friends", "Best friends", "Soulmates"][max(0, min(5, b))]
    }
}

/// One hug on a tree's timeline: photo, when, and what came with it.
struct TreeTimelineRow: View {
    let hug: Hug

    var body: some View {
        let walked = hug.linkedWalks.reduce(0) { $0 + $1.distanceM }
        HStack(spacing: RB.m) {
            RBPhotoFill(data: hug.selfiePhoto ?? hug.treePhoto)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: RB.inner, style: .continuous))
            VStack(alignment: .leading, spacing: RB.xs) {
                Text(Format.dayTime(hug.date)).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { chips(walked) }
                    VStack(alignment: .leading, spacing: 4) { chips(walked) }
                }
            }
            Spacer(minLength: 0)
            if let leaf = LeafType.find(hug.leafKey) { LeafView(leaf: leaf, size: 26) }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textDim)
        }
        .padding(RB.m)
        .background(RB.cardFill, in: RoundedRectangle(cornerRadius: RB.radius - 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RB.radius - 4, style: .continuous).strokeBorder(RB.stroke))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func chips(_ walked: Double) -> some View {
        if hug.durationMin > 0 { RBInfoChip(text: Format.minutes(hug.durationMin), symbol: "timer", tint: Theme.glow) }
        if !hug.linkedSessions.isEmpty {
            RBInfoChip(text: Format.minutes((hug.breathMinutes * 10).rounded() / 10), symbol: "wind", tint: Theme.sky)
        }
        if let hr = hug.avgHR { RBInfoChip(text: "\(Int(hr)) bpm", symbol: "heart.fill", tint: .pink) }
        if walked > 0 { RBInfoChip(text: LinkedWalk.distance(walked), symbol: "figure.walk") }
        if hug.barefoot { RBInfoChip(text: "Barefoot", symbol: "shoeprints.fill", tint: Theme.gold) }
        ForEach(hug.tags.prefix(2), id: \.self) { RBInfoChip(text: HugTag.label($0), tint: Theme.textDim) }
    }
}

/// Rootbound Pro: what time with this tree does for you, from the hugs you've logged.
struct TreeInsightsCard: View {
    let tree: TreeSummary
    /// Breath sessions with this tree (Still Pointz / Health), for the calm-effect tiles.
    var breaths: [TreeBreath] = []
    @ObservedObject private var unlock = Unlock.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    private static func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    private var moodLift: Double? {
        Self.avg(tree.hugs.filter { $0.moodBefore > 0 && $0.moodAfter > 0 }.map { Double($0.moodAfter - $0.moodBefore) })
    }
    /// Apple Watch: average start -> end heart-rate drop during hugs with this tree.
    private var hrDrop: Double? { Self.avg(tree.hugs.compactMap(\.hrDrop)) }
    private var avgHRV: Double? { Self.avg(tree.hugs.compactMap(\.hrv) + breaths.compactMap(\.hrv)) }
    private var avgHR: Double? { Self.avg(tree.hugs.compactMap(\.avgHR)) }
    private var avgMinutes: Double? { Self.avg(tree.hugs.map(\.durationMin).filter { $0 > 0 }) }
    private var barefootShare: Double? {
        tree.hugs.isEmpty ? nil : Double(tree.hugs.filter(\.barefoot).count) / Double(tree.hugs.count)
    }
    private var favoriteTime: String? {
        let counts = tree.hugs.reduce(into: [String: Int]()) { $0[Format.partOfDay($1.date), default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    var body: some View {
        if unlock.isPro {
            RBCard {
                VStack(alignment: .leading, spacing: RB.m) {
                    RBSectionTitle(title: "Tree insights", symbol: "chart.line.uptrend.xyaxis")
                    LazyVGrid(columns: rbColumns(2, typeSize), spacing: RB.s) {
                        RBStatTile(value: moodLift.map { String(format: "%+.1f", $0) } ?? "--", label: "Mood lift", symbol: "face.smiling")
                        RBStatTile(value: hrDrop.map { String(format: "−%.0f bpm", $0) } ?? "--", label: "Heart settles", symbol: "arrow.down.heart.fill")
                        RBStatTile(value: avgHR.map { String(format: "%.0f bpm", $0) } ?? "--", label: "Avg heart rate", symbol: "heart.fill")
                        RBStatTile(value: avgMinutes.map { Format.minutes($0) } ?? "--", label: "Avg hug", symbol: "timer")
                        RBStatTile(value: barefootShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "--", label: "Barefoot", symbol: "shoeprints.fill")
                        RBStatTile(value: favoriteTime ?? "--", label: "Favorite time", symbol: "sun.horizon.fill")
                        if let v = avgHRV {
                            RBStatTile(value: String(format: "%.0f ms", v), label: "Avg HRV", symbol: "waveform.path.ecg")
                        }
                        if !breaths.isEmpty {
                            RBStatTile(value: Format.minutes(breaths.reduce(0) { $0 + $1.minutes }), label: "Breathing here", symbol: "wind", tint: Theme.sky)
                            RBStatTile(value: Self.avg(breaths.compactMap(\.hrDrop)).map { String(format: "−%.0f bpm", $0) } ?? "--",
                                     label: "Calm effect", symbol: "arrow.down.heart.fill", tint: Theme.sky)
                        }
                    }
                }
            }
        } else {
            RootboundProLock(symbol: "chart.line.uptrend.xyaxis", title: "Tree insights",
                             message: "See your mood lift, how your heart settles and your favorite time with \(tree.name).",
                             context: "Tree insights")
        }
    }
}

/// Special card frame for rare, epic and legendary species: a rarity-colored rim; epic and legendary shimmer.
struct RarityFrame: View {
    let rarity: Rarity
    var cornerRadius: CGFloat = 22
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if rarity >= .epic {
                shape.strokeBorder(AngularGradient(colors: [rarity.color, .white, rarity.color, rarity.color.opacity(0.4), rarity.color],
                                                   center: .center, angle: .degrees(spin ? 360 : 0)),
                                   lineWidth: rarity == .legendary ? 4 : 3)
            } else {
                shape.strokeBorder(rarity.color, lineWidth: 2.5)
            }
            if rarity == .legendary {
                shape.inset(by: 6).strokeBorder(rarity.color.opacity(0.45), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard rarity >= .epic, !reduceMotion else { return }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}
