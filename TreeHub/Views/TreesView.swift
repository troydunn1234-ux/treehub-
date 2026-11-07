import SwiftUI
import SwiftData
import MapKit

struct TreesView: View {
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @State private var mode = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedTree: UUID?

    private var trees: [TreeSummary] { TreeSummary.build(from: hugs) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Grove").font(Theme.title(36)).foregroundStyle(.white)
                        Text("\(trees.count) tree friend\(trees.count == 1 ? "" : "s") · \(hugs.count) hugs")
                            .font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Picker("", selection: $mode) {
                        Image(systemName: "square.grid.2x2.fill").tag(0)
                        Image(systemName: "map.fill").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
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
            .navigationDestination(for: UUID.self) { id in
                if let t = trees.first(where: { $0.id == id }) { TreeDetailView(treeID: t.id) }
                else if let h = hugs.first(where: { $0.id == id }) { HugDetailView(hug: h) }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                ForEach(trees) { t in
                    NavigationLink(value: t.id) { TreeCard(tree: t) }.pressable().cardAppear()
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 120)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoView(data: tree.coverPhoto)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("\(tree.hugCount)×")
                        .font(Theme.rounded(12, .heavy))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            Text(tree.name).font(.system(size: 17, weight: .bold, design: .serif)).foregroundStyle(.white).lineLimit(1)
            Text(tree.species.isEmpty ? "Mystery species" : tree.species)
                .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.glow).lineLimit(1)
            HeartsView(filled: tree.bond, size: 10)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.cardStroke))
    }
}

@MainActor
struct TreeDetailView: View {
    let treeID: UUID
    @Environment(\.modelContext) private var context
    @Query(sort: \Hug.date, order: .reverse) private var allHugs: [Hug]
    @State private var renaming = false
    @State private var newName = ""

    private var tree: TreeSummary? { TreeSummary.build(from: allHugs.filter { $0.treeID == treeID }).first }

    var body: some View {
        ScrollView {
            if let tree {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoView(data: tree.coverPhoto)
                        .frame(height: 280)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tree.name).font(Theme.title(32)).foregroundStyle(.white)
                                Text(tree.species.isEmpty ? "Mystery species" : tree.species)
                                    .font(Theme.rounded(15, .bold)).foregroundStyle(Theme.glow)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }

                    HStack {
                        HeartsView(filled: tree.bond, size: 16)
                        Text(bondLabel(tree.bond)).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                        Spacer()
                        Button { newName = tree.name; renaming = true } label: { Image(systemName: "pencil.circle.fill").font(.system(size: 26)) }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(value: "\(tree.hugCount)", label: "Hugs")
                        StatTile(value: Format.minutes(tree.totalMinutes), label: "Together")
                        StatTile(value: Format.day(tree.firstHug), label: "Met")
                    }

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
                .padding(16)
                .padding(.bottom, 110)
            }
        }
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
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

    private func bondLabel(_ b: Int) -> String {
        ["", "New friend", "Getting close", "Good friends", "Best friends", "Soulmates"][max(0, min(5, b))]
    }
}
