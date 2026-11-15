import SwiftUI
import SwiftData
import MapKit

struct TreesView: View {
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

    private var trees: [TreeSummary] { TreeSummary.build(from: hugs) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Grove").font(Theme.title(36)).foregroundStyle(.white)
                        Text("\(trees.count) tree friend\(trees.count == 1 ? "" : "s") · \(hugs.count) hugs")
                            .font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Button { incomingCode = nil; showFriends = true } label: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.sky)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Friends map: share and import trees")
                    Button { showNatureRoll = true } label: {
                        Image(systemName: NatureRoll.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.glow)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(NatureRoll.title)
                    PillSwitcher(options: [.init(id: 0, label: "Grid", symbol: "square.grid.2x2.fill"),
                                           .init(id: 1, label: "Map", symbol: "map.fill")],
                                 selection: $mode)
                        .frame(width: 180)
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)

                if trees.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "tree").font(.system(size: 54)).foregroundStyle(Theme.glow.opacity(0.6))
                        Text("Your grove is empty").font(Theme.rounded(18, .bold))
                        Text("Hug a tree and it shows up here, with every visit you share.")
                            .font(Theme.rounded(14, .medium)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
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
            .onAppear { openIncoming(); openPendingTree() }
            // rootbound://tree?id=… (back from a Still Pointz breath with this tree)
            .onReceive(NotificationCenter.default.publisher(for: TreeBreaths.openTree)) { _ in openPendingTree() }
            .navigationDestination(for: UUID.self) { id in
                if let t = trees.first(where: { $0.id == id }) { TreeDetailView(treeID: t.id) }
                else if let h = hugs.first(where: { $0.id == id }) { HugDetailView(hug: h) }
            }
        }
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(trees) { t in
                    NavigationLink(value: t.id) { TreeCard(tree: t) }.pressable().cardAppear()
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 4)
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
                    HStack(spacing: 12) {
                        PhotoView(data: t.coverPhoto).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.name).font(Theme.rounded(17, .bold)).foregroundStyle(.white)
                            HeartsView(filled: t.bond, size: 11)
                            Text("\(t.hugCount) hug\(t.hugCount == 1 ? "" : "s") · last \(Format.day(t.lastHug))")
                                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.glow)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 100)
        .overlay(alignment: .topTrailing) {
            if !friends.isEmpty {
                Button { withAnimation { showFriendTrees.toggle() } } label: {
                    Label(showFriendTrees ? "Friends on" : "Friends off", systemImage: "person.2.fill")
                        .font(Theme.rounded(12, .bold))
                        .foregroundStyle(showFriendTrees ? Theme.sky : Theme.textDim)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.top, 10).padding(.trailing, 70)
            }
        }
        .overlay(alignment: .top) {
            if mapped.count < trees.count {
                Text("\(trees.count - mapped.count) tree\(trees.count - mapped.count == 1 ? "" : "s") without a pin")
                    .font(Theme.rounded(12, .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
            }
        }
    }
}

struct TreeCard: View {
    let tree: TreeSummary
    private var rarity: Rarity { SpeciesRarity.rarity(for: tree.species) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(data: tree.coverPhoto)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(stops: [
                .init(color: .clear, location: 0.35),
                .init(color: .black.opacity(0.75), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(tree.name)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(tree.species.isEmpty ? "Mystery species" : tree.species)
                    .font(Theme.rounded(12, .semibold))
                    .foregroundStyle(Theme.glow)
                    .lineLimit(1)
                HeartsView(filled: tree.bond, size: 10)
            }
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(tree.hugCount)×")
                .font(Theme.rounded(12, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
        .overlay { if rarity > .common { RarityFrame(rarity: rarity, cornerRadius: 22) } }
        .overlay(alignment: .topLeading) {
            if rarity > .common { RarityLabel(rarity: rarity).padding(10) }
        }
        .shadow(color: rarity > .common ? rarity.color.opacity(rarity >= .epic ? 0.55 : 0.3) : .black.opacity(0.35), radius: 14, y: 8)
    }
}

@MainActor
struct TreeDetailView: View {
    let treeID: UUID
    @Environment(\.modelContext) private var context
    @Query(sort: \Hug.date, order: .reverse) private var allHugs: [Hug]
    @State private var renaming = false
    @State private var newName = ""
    /// Breath sessions with this tree (Still Pointz + overlapping Health mindful sessions).
    @State private var breaths: [TreeBreath] = []
    @Environment(\.scenePhase) private var scenePhase

    private var tree: TreeSummary? { TreeSummary.build(from: allHugs.filter { $0.treeID == treeID }).first }
    private var taggedMinutes: Double { breaths.filter(\.tagged).reduce(0) { $0 + $1.minutes } }

    var body: some View {
        ScrollView {
            if let tree {
                VStack(alignment: .leading, spacing: 16) {
                    treeHero(tree)
                        .padding(.horizontal, -Theme.pad)

                    HStack {
                        HeartsView(filled: tree.bond, size: 16)
                        Text(bondLabel(tree.bond)).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                        Spacer()
                        Button { newName = tree.name; renaming = true } label: { Image(systemName: "pencil.circle.fill").font(.system(size: 26)) }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(value: "\(tree.hugCount)", label: "Hugs")
                        StatTile(value: Format.minutes(tree.totalMinutes + taggedMinutes), label: "Together")
                        StatTile(value: Format.day(tree.firstHug), label: "Met")
                    }

                    TreeFactCard(species: tree.species)

                    TreeInsightsCard(tree: tree, breaths: breaths)

                    BreatheWithTreeButton(treeName: tree.name, treeID: tree.id)

                    TreeBreathSection(treeName: tree.name, breaths: breaths)

                    if let c = tree.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 500, longitudinalMeters: 500))) {
                            Annotation(tree.name, coordinate: c) { TreePin(photo: tree.coverPhoto) }
                        }
                        .mapStyle(.hybrid(elevation: .realistic))
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Button { MapsLink.open(c, name: tree.name) } label: {
                            Label("Directions to \(tree.name)", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(Theme.rounded(15, .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    SectionHeader(title: "Our hugs", symbol: "heart.fill")
                    ForEach(tree.hugs) { h in
                        NavigationLink(value: h.id) {
                            HStack(spacing: 12) {
                                PhotoView(data: h.selfiePhoto ?? h.treePhoto).frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Format.dayTime(h.date)).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                                    HStack(spacing: 6) {
                                        if h.durationMin > 0 { Text(Format.minutes(h.durationMin)) }
                                        if h.barefoot { Image(systemName: "shoeprints.fill") }
                                        ForEach(h.tags.prefix(3), id: \.self) { Text(HugTag.label($0)) }
                                    }
                                    .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                                }
                                Spacer()
                                if let leaf = LeafType.find(h.leafKey) { LeafView(leaf: leaf, size: 28) }
                            }
                            .padding(10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 130)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tree?.hugCount ?? 0) { await reloadBreaths() }
        .onReceive(NotificationCenter.default.publisher(for: TreeBreaths.openTree)) { _ in Task { await reloadBreaths() } }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await reloadBreaths() } } }
        .alert("Rename tree", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                for h in allHugs where h.treeID == treeID { h.treeName = name }
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func reloadBreaths() async {
        guard let tree else { return }
        breaths = await TreeBreaths.load(for: tree)
    }

    private func treeHero(_ tree: TreeSummary) -> some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(data: tree.coverPhoto)
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: Theme.forestDeep.opacity(0.55), location: 0.68),
                        .init(color: Theme.forestDeep, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("MET \(Format.day(tree.firstHug).uppercased())")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2)
                    .foregroundStyle(Theme.glow)
                Text(tree.name).font(Theme.title(38)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                HStack(spacing: 8) {
                    Text(tree.species.isEmpty ? "Mystery species" : tree.species)
                        .font(Theme.rounded(15, .semibold)).foregroundStyle(.white.opacity(0.8))
                    let r = SpeciesRarity.rarity(for: tree.species)
                    if r > .common { RarityLabel(rarity: r) }
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 4)
        }
    }

    private func bondLabel(_ b: Int) -> String {
        ["", "New friend", "Getting close", "Good friends", "Best friends", "Soulmates"][max(0, min(5, b))]
    }
}

/// Rootbound Pro: what time with this tree does for you, from the hugs you've logged.
struct TreeInsightsCard: View {
    let tree: TreeSummary
    /// Breath sessions with this tree (Still Pointz / Health), for the calm-effect tiles.
    var breaths: [TreeBreath] = []
    @ObservedObject private var unlock = Unlock.shared

    private static func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }

    private var moodLift: Double? {
        Self.avg(tree.hugs.filter { $0.moodBefore > 0 && $0.moodAfter > 0 }.map { Double($0.moodAfter - $0.moodBefore) })
    }
    private var stressDrop: Double? {
        Self.avg(tree.hugs.compactMap { h in
            guard let a = h.stressStart, let b = h.stressEnd else { return nil }
            return a - b
        })
    }
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
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Tree insights", symbol: "chart.line.uptrend.xyaxis")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(value: moodLift.map { String(format: "%+.1f", $0) } ?? "--", label: "Mood lift", symbol: "face.smiling")
                        StatTile(value: stressDrop.map { String(format: "%.0f", $0) } ?? "--", label: "Stress drop", symbol: "waveform.path.ecg")
                        StatTile(value: avgHR.map { String(format: "%.0f bpm", $0) } ?? "--", label: "Avg heart rate", symbol: "heart.fill")
                        StatTile(value: avgMinutes.map { Format.minutes($0) } ?? "--", label: "Avg hug", symbol: "timer")
                        StatTile(value: barefootShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "--", label: "Barefoot", symbol: "shoeprints.fill")
                        StatTile(value: favoriteTime ?? "--", label: "Favorite time", symbol: "sun.horizon.fill")
                        if !breaths.isEmpty {
                            StatTile(value: Format.minutes(breaths.reduce(0) { $0 + $1.minutes }), label: "Breathing here", symbol: "wind", tint: Theme.sky)
                            StatTile(value: Self.avg(breaths.compactMap(\.hrDrop)).map { String(format: "−%.0f bpm", $0) } ?? "--",
                                     label: "Calm effect", symbol: "arrow.down.heart.fill", tint: Theme.sky)
                        }
                    }
                }
            }
        } else {
            RootboundProLock(symbol: "chart.line.uptrend.xyaxis", title: "Tree insights",
                             message: "See your mood lift, stress drop and heart rate with \(tree.name).",
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
