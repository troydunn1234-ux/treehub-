import SwiftUI
import UIKit
import SwiftData
import MapKit

@MainActor
struct HugDetailView: View {
    let hug: Hug
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var fullPhoto: IdentifiedData?
    @State private var refreshing = false

    private var photos: [(String, Data)] {
        [("Tree", hug.treePhoto), ("You + Tree", hug.selfiePhoto), ("Screenshot", hug.garminPhoto)]
            .compactMap { label, d in d.map { (label, $0) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RB.l) {
                hero
                VStack(alignment: .leading, spacing: RB.l) {
                    chips
                    if hug.durationMin > 0 || hug.hasStats { hugStatsCard }
                    breathworkSection
                    walksSection
                    if hug.moodBefore > 0 || hug.moodAfter > 0 { moodCard }
                    if !hug.notes.isEmpty { notesCard }
                    if let c = hug.coordinate { mapCard(c) }

                    Button { editing = true } label: { Label("Edit hug", systemImage: "pencil") }
                        .buttonStyle(RBPrimaryButtonStyle())
                        .padding(.top, RB.s)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete hug", systemImage: "trash")
                    }
                    .buttonStyle(RBDestructiveButtonStyle())
                }
                .padding(.horizontal, RB.screen)
            }
            .padding(.bottom, 130)
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .forestScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing, onDismiss: { Task { await refresh() } }) { HugLogView(editing: hug) }
        // Re-read Still Pointz and Apple Health for the linked sessions (late Watch heart data fills in).
        .task { await refresh() }
        .fullScreenCover(item: $fullPhoto) { item in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let ui = UIImage(data: item.data) {
                    Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                RBIconButton(symbol: "xmark", label: "Close photo") { fullPhoto = nil }
                    .padding()
            }
        }
        .alert("Delete this hug?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let target = hug
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    context.delete(target)
                    try? context.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its XP and leaf go with it.")
        }
    }

    // MARK: Sections

    /// What came with the hug: XP, Watch, grounding, walk, weather and tags.
    private var chips: some View {
        FlowLayout(spacing: RB.s) {
            RBInfoChip(text: "+\(hug.xp) XP", symbol: "star.fill", tint: Theme.gold)
            if hug.fromWatch { RBInfoChip(text: "Apple Watch", symbol: "applewatch") }
            if hug.barefoot { RBInfoChip(text: "Barefoot", symbol: "shoeprints.fill") }
            if hug.feetInWater { RBInfoChip(text: "Feet in water", symbol: "drop.fill", tint: Theme.sky) }
            if hug.waterSetting == "water" { RBInfoChip(text: "Water tree", symbol: "water.waves", tint: Theme.sky) }
            if hug.waterSetting == "edge" { RBInfoChip(text: "Water's edge", symbol: "water.waves.and.arrow.down", tint: Theme.sky) }
            if hug.strollID != nil || !hug.linkedWalks.isEmpty { RBInfoChip(text: "On a walk", symbol: "figure.walk") }
            if !hug.weather.isEmpty { RBInfoChip(text: hug.weather, symbol: "cloud.sun.fill", tint: .white) }
            ForEach(hug.tags, id: \.self) { t in RBInfoChip(text: HugTag.label(t), tint: .white) }
        }
    }

    /// The hug's own numbers (timer and heart data from the Watch / Apple Health), one stat block each.
    private var hugStatsCard: some View {
        RBCard {
            VStack(alignment: .leading, spacing: RB.m) {
                RBSectionTitle(title: "The hug", symbol: hug.fromWatch ? "applewatch" : "heart.fill")
                RBGrid(minimum: 100) {
                    if hug.durationMin > 0 { RBStatTile(value: Format.minutes(hug.durationMin), label: "Time", symbol: "timer") }
                    if let a = hug.hrStart, let b = hug.hrEnd {
                        RBStatTile(value: "\(Int(a.rounded()))→\(Int(b.rounded()))", label: "HR start→end", symbol: "heart.fill")
                    }
                    if let drop = hug.hrDrop {
                        RBStatTile(value: String(format: "%+.0f bpm", -drop), label: "HR change", symbol: "arrow.down.heart.fill", tint: Theme.sky)
                    }
                    if let v = hug.hrv { RBStatTile(value: String(format: "%.0f ms", v), label: "HRV", symbol: "waveform.path.ecg", tint: Theme.sky) }
                    // Every tile carries a symbol so the rows stay the same height.
                    if hug.avgHR != nil { RBStatTile(value: Format.number(hug.avgHR), label: "Avg bpm", symbol: "heart") }
                    if hug.minHR != nil { RBStatTile(value: Format.number(hug.minHR), label: "Low bpm", symbol: "arrow.down") }
                    if hug.maxHR != nil { RBStatTile(value: Format.number(hug.maxHR), label: "Max bpm", symbol: "arrow.up") }
                    if hug.respRate != nil { RBStatTile(value: Format.number(hug.respRate), label: "Breaths/min", symbol: "lungs.fill", tint: Theme.sky) }
                }
                if hug.fromWatch {
                    Label("Timed on your Apple Watch", systemImage: "applewatch")
                        .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    /// Before → after, each face only when it was picked.
    private var moodCard: some View {
        RBCard {
            HStack(spacing: RB.m) {
                RBSectionTitle(title: "Mood", symbol: "face.smiling")
                if hug.moodBefore > 0 {
                    Text(mood(hug.moodBefore)).font(.largeTitle)
                }
                if hug.moodBefore > 0 && hug.moodAfter > 0 {
                    Image(systemName: "arrow.right").font(.headline).foregroundStyle(Theme.textDim)
                }
                if hug.moodAfter > 0 {
                    Text(mood(hug.moodAfter)).font(.largeTitle)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(moodLabel)
        }
    }

    private var moodLabel: String {
        switch (hug.moodBefore > 0, hug.moodAfter > 0) {
        case (true, true): return "Mood \(hug.moodBefore) before, \(hug.moodAfter) after, out of 5"
        case (true, false): return "Mood before: \(hug.moodBefore) out of 5"
        default: return "Mood after: \(hug.moodAfter) out of 5"
        }
    }

    private var notesCard: some View {
        RBCard {
            VStack(alignment: .leading, spacing: RB.s) {
                RBSectionTitle(title: "Notes", symbol: "text.quote")
                Text(hug.notes).font(.system(.body, design: .serif)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func mapCard(_ c: CLLocationCoordinate2D) -> some View {
        RBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 400, longitudinalMeters: 400))) {
                    Annotation(hug.treeName, coordinate: c) { TreePin(photo: hug.treePhoto) }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .frame(height: 180)
                .accessibilityLabel("Map of \(hug.treeName)")
                HStack(spacing: RB.m) {
                    Label(hug.placeName.isEmpty ? Format.coord(c) : hug.placeName, systemImage: "mappin.and.ellipse")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: RB.s)
                    Button("Directions") { MapsLink.open(c, name: hug.treeName) }
                        .font(RB.text(.subheadline, .bold))
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, RB.l)
                .padding(.vertical, RB.xs)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
    }

    private func refresh() async {
        refreshing = true
        await HugSessions.refresh(hug, context: context)
        refreshing = false
    }

    /// Swipeable full-bleed photos with the tree's name over them.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if photos.isEmpty {
                    ZStack {
                        LinearGradient(colors: [Theme.moss, Theme.forestDeep], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "tree.fill").font(.system(size: 110)).foregroundStyle(Theme.leafGradient).opacity(0.3)
                    }
                } else {
                    TabView {
                        ForEach(photos, id: \.0) { item in
                            RBPhotoView(data: item.1, points: 500)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { fullPhoto = IdentifiedData(data: item.1) }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                }
            }
            .frame(height: 440)
            .overlay {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: Theme.forestDeep.opacity(0.55), location: 0.68),
                    .init(color: Theme.forestDeep, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.dayTime(hug.date))
                        .font(RB.text(.subheadline, .semibold))
                        .foregroundStyle(Theme.glow)
                    Text(hug.treeName)
                        .font(Theme.title(34))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    if !hug.species.isEmpty || !hug.placeName.isEmpty {
                        Text([hug.species, hug.placeName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(RB.text(.subheadline, .medium)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                if let leaf = LeafType.find(hug.leafKey) {
                    VStack(spacing: 6) {
                        LeafView(leaf: leaf, size: 54)
                        RarityLabel(rarity: leaf.rarity)
                    }
                    .padding(RB.m)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Leaf found: \(leaf.name), \(leaf.rarity.title)")
                }
            }
            .padding(.horizontal, RB.screen)
            .padding(.bottom, RB.xs)
        }
    }

    /// Every Still Pointz / Health session linked to this hug, one card each, with totals. Refreshed on open.
    @ViewBuilder private var breathworkSection: some View {
        let sessions = hug.linkedSessions
        // Skeleton only while an older hug (no list yet) has its sessions looked up for the first time.
        if !sessions.isEmpty || (refreshing && !hug.hasLinkList) {
            RBCard {
                VStack(alignment: .leading, spacing: RB.m) {
                    RBSectionTitle(title: sessions.count > 1 ? "Breathwork · \(sessions.count) sessions" : "Breathwork", symbol: "wind", tint: Theme.sky)
                    if sessions.count > 1 { LinkedSessionTotals(sessions: sessions) }
                    ForEach(sessions) { s in LinkedSessionCard(session: s) }
                    if sessions.isEmpty {
                        RBSkeletonRow()
                        RBSkeletonRow()
                    }
                }
            }
        }
    }

    /// Walks attached to this hug (Roamr / Apple Health), each as a stat block.
    @ViewBuilder private var walksSection: some View {
        let walks = hug.linkedWalks
        if !walks.isEmpty {
            RBCard {
                VStack(alignment: .leading, spacing: 12) {
                    RBSectionTitle(title: walks.count == 1 ? "Walk" : "Walks", symbol: walks.first?.symbol ?? "figure.walk")
                    ForEach(walks) { w in LinkedWalkCard(walk: w) }
                }
            }
        }
    }

    private func mood(_ v: Int) -> String {
        let moods = ["😣", "😕", "😐", "🙂", "😌"]
        return (1...5).contains(v) ? moods[v - 1] : "–"
    }
}

struct IdentifiedData: Identifiable {
    let id = UUID()
    let data: Data
}

enum MapsLink {
    static func open(_ c: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
