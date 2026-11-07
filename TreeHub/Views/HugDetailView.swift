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

    private var photos: [(String, Data)] {
        [("Tree", hug.treePhoto), ("You + Tree", hug.selfiePhoto), ("Garmin", hug.garminPhoto)]
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
                    if hug.strollID != nil { Chip(label: "On a stroll", symbol: "figure.walk") }
                    ForEach(hug.tags, id: \.self) { t in Chip(label: HugTag.label(t), symbol: HugTag.symbol(t)) }
                    if !hug.weather.isEmpty { Chip(label: hug.weather, symbol: "cloud.sun") }
                }

                if hug.durationMin > 0 || hug.hasStats {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: hug.exercise.isEmpty ? "Breathwork" : hug.exercise, symbol: "wind")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                if hug.durationMin > 0 { StatTile(value: Format.minutes(hug.durationMin), label: "Time") }
                                if hug.avgHR != nil { StatTile(value: Format.number(hug.avgHR), label: "Avg HR") }
                                if hug.minHR != nil { StatTile(value: Format.number(hug.minHR), label: "Low HR") }
                                if hug.maxHR != nil { StatTile(value: Format.number(hug.maxHR), label: "Max HR") }
                                if hug.respRate != nil { StatTile(value: Format.number(hug.respRate), label: "Breaths/min") }
                                if let a = hug.stressStart, let b = hug.stressEnd {
                                    StatTile(value: "\(Format.number(a))→\(Format.number(b))", label: "Stress", tint: Theme.sky)
                                } else if hug.stressStart != nil || hug.stressEnd != nil {
                                    StatTile(value: Format.number(hug.stressEnd ?? hug.stressStart), label: "Stress")
                                }
                                if let bb = hug.bodyBattery {
                                    StatTile(value: (bb > 0 ? "+" : "") + Format.number(bb), label: "Body Battery")
                                }
                            }
                        }
                    }
                }

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
        .sheet(isPresented: $editing) { HugLogView(editing: hug) }
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
