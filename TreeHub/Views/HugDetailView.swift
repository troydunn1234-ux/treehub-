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
            VStack(alignment: .leading, spacing: Theme.gap + 4) {
                hero
                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                FlowLayout(spacing: 8) {
                    Chip(label: "+\(hug.xp) XP", symbol: "star.fill", selected: true)
                    if hug.barefoot { Chip(label: "Barefoot", symbol: "shoeprints.fill") }
                    if hug.feetInWater { Chip(label: "Feet in water", symbol: "drop.fill") }
                    if hug.waterSetting == "water" { Chip(label: "Water tree", symbol: "water.waves") }
                    if hug.waterSetting == "edge" { Chip(label: "Water's edge", symbol: "water.waves.and.arrow.down") }
                    if hug.strollID != nil || !hug.linkedWalks.isEmpty { Chip(label: "On a walk", symbol: "figure.walk") }
                    ForEach(hug.tags, id: \.self) { t in Chip(label: HugTag.label(t)) }
                    if !hug.weather.isEmpty { Chip(label: hug.weather, symbol: "cloud.sun") }
                }

                if hug.durationMin > 0 || hug.hasStats {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "The hug", symbol: hug.fromWatch ? "applewatch" : "heart.fill")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                if hug.durationMin > 0 { StatTile(value: Format.minutes(hug.durationMin), label: "Time") }
                                if hug.avgHR != nil { StatTile(value: Format.number(hug.avgHR), label: "Avg HR") }
                                if hug.minHR != nil { StatTile(value: Format.number(hug.minHR), label: "Low HR") }
                                if hug.maxHR != nil { StatTile(value: Format.number(hug.maxHR), label: "Max HR") }
                                if let drop = hug.hrDrop { StatTile(value: String(format: "%+.0f", -drop), label: "HR change", tint: Theme.sky) }
                                if let v = hug.hrv { StatTile(value: String(format: "%.0f ms", v), label: "HRV", tint: Theme.sky) }
                                if hug.respRate != nil { StatTile(value: Format.number(hug.respRate), label: "Breaths/min") }
                            }
                            if hug.fromWatch {
                                Text("Timed on your Apple Watch").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                }

                breathworkSection

                walksSection

                if hug.moodBefore > 0 || hug.moodAfter > 0 {
                    GlassCard {
                        HStack {
                            Text("Mood").font(Theme.rounded(15, .bold))
                            Spacer()
                            Text(mood(hug.moodBefore)).font(.system(size: 30))
                            Image(systemName: "arrow.right").foregroundStyle(Theme.textDim)
                            Text(mood(hug.moodAfter)).font(.system(size: 30))
                        }
                    }
                }

                if !hug.notes.isEmpty {
                    GlassCard {
                        Text(hug.notes).font(.system(size: 16, design: .serif)).foregroundStyle(.white)
                    }
                }

                if let c = hug.coordinate {
                    VStack(alignment: .leading, spacing: 8) {
                        Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 400, longitudinalMeters: 400))) {
                            Annotation(hug.treeName, coordinate: c) { TreePin(photo: hug.treePhoto) }
                        }
                        .mapStyle(.hybrid(elevation: .realistic))
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        HStack {
                            Text(hug.placeName.isEmpty ? Format.coord(c) : hug.placeName)
                                .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                            Spacer()
                            Button("Directions") { MapsLink.open(c, name: hug.treeName) }
                                .font(Theme.rounded(14, .bold))
                        }
                    }
                }

                Button { editing = true } label: { Label("Edit hug", systemImage: "pencil") }
                    .buttonStyle(PrimaryButtonStyle())
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete hug", systemImage: "trash").font(Theme.rounded(15, .bold)).frame(maxWidth: .infinity)
                }
                }
                .padding(.horizontal, Theme.pad)
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
                Button { fullPhoto = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 32)).foregroundStyle(.white, .black.opacity(0.5))
                }
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
                            PhotoView(data: item.1)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { fullPhoto = IdentifiedData(data: item.1) }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                }
            }
            .frame(height: 460)
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
                    Text(Format.dayTime(hug.date).uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2)
                        .foregroundStyle(Theme.glow)
                    Text(hug.treeName)
                        .font(Theme.title(36))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                    if !hug.species.isEmpty {
                        Text(hug.species).font(Theme.rounded(15, .semibold)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                if let leaf = LeafType.find(hug.leafKey) {
                    VStack(spacing: 6) {
                        LeafView(leaf: leaf, size: 54)
                        RarityLabel(rarity: leaf.rarity)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 4)
        }
    }

    /// Every Still Pointz / Health session linked to this hug, one card each, with totals. Refreshed on open.
    @ViewBuilder private var breathworkSection: some View {
        let sessions = hug.linkedSessions
        if !sessions.isEmpty || refreshing {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "Breathwork", symbol: "wind")
                        if refreshing { ProgressView().controlSize(.small) }
                    }
                    if sessions.count > 1 { LinkedSessionTotals(sessions: sessions) }
                    ForEach(sessions) { s in LinkedSessionCard(session: s) }
                    if sessions.isEmpty {
                        Text("Looking for breath sessions around this hug…")
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    }
                }
            }
        }
    }

    /// Walks attached to this hug (Roamr / Apple Health), each as a stat block.
    @ViewBuilder private var walksSection: some View {
        let walks = hug.linkedWalks
        if !walks.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: walks.count == 1 ? "Walk" : "Walks", symbol: walks.first?.symbol ?? "figure.walk")
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
