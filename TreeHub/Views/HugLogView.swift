import SwiftUI
import SwiftData
import PhotosUI
import Photos
import UIKit
import MapKit
import ImageIO

/// Everything typed into the form, applied to a Hug only on Save (so Cancel never changes anything).
struct HugDraft {
    var date = Date()
    var treeID: UUID? = nil          // nil = new tree
    var treeName = ""
    var species = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var locationSource = ""
    var placeName = ""
    var treePhoto: Data? = nil
    var selfiePhoto: Data? = nil
    var garminPhoto: Data? = nil
    var tags: Set<String> = []
    var barefoot = false
    var weather = ""
    var moodBefore = 0
    var moodAfter = 0
    var notes = ""
    var exercise = "Tranquility"
    var durationMin: Double? = 12
    var avgHR: Double? = nil
    var minHR: Double? = nil
    var maxHR: Double? = nil
    var respRate: Double? = nil
    var stressStart: Double? = nil
    var stressEnd: Double? = nil
    var bodyBattery: Double? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init() {}

    init(_ h: Hug) {
        date = h.date; treeID = h.treeID; treeName = h.treeName; species = h.species
        latitude = h.latitude; longitude = h.longitude; placeName = h.placeName
        locationSource = h.latitude != nil ? "Saved pin" : ""
        treePhoto = h.treePhoto; selfiePhoto = h.selfiePhoto; garminPhoto = h.garminPhoto
        tags = Set(h.tags); barefoot = h.barefoot; weather = h.weather
        moodBefore = h.moodBefore; moodAfter = h.moodAfter; notes = h.notes
        exercise = h.exercise; durationMin = h.durationMin > 0 ? h.durationMin : nil
        avgHR = h.avgHR; minHR = h.minHR; maxHR = h.maxHR; respRate = h.respRate
        stressStart = h.stressStart; stressEnd = h.stressEnd; bodyBattery = h.bodyBattery
    }

    func apply(to h: Hug) {
        h.date = date
        h.treeName = treeName.trimmingCharacters(in: .whitespacesAndNewlines)
        h.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        h.latitude = latitude; h.longitude = longitude; h.placeName = placeName
        h.treePhoto = treePhoto; h.selfiePhoto = selfiePhoto; h.garminPhoto = garminPhoto
        h.tags = HugTag.all.map(\.id).filter { tags.contains($0) }
        h.barefoot = barefoot; h.weather = weather
        h.moodBefore = moodBefore; h.moodAfter = moodAfter
        h.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        h.exercise = exercise; h.durationMin = max(0, durationMin ?? 0)
        h.avgHR = avgHR; h.minHR = minHR; h.maxHR = maxHR; h.respRate = respRate
        h.stressStart = stressStart; h.stressEnd = stressEnd; h.bodyBattery = bodyBattery
    }
}

struct CelebrationData: Identifiable {
    let id = UUID()
    let breakdown: XPBreakdown
    let leaf: LeafType?
    let newBadges: [BadgeState]
    let levelBefore: LevelInfo
    let levelAfter: LevelInfo
    let treeName: String
}

@MainActor
struct HugLogView: View {
    let editing: Hug?
    /// Set when the hug happens during a stroll or hike that's being recorded.
    var strollID: UUID? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Hug.date, order: .reverse) private var hugs: [Hug]
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]

    @State private var d = HugDraft()
    @State private var loaded = false
    @State private var pinText = ""
    @State private var photoCoord: CLLocationCoordinate2D?
    @State private var locating = false
    @State private var healthMessage = ""
    @State private var healthBusy = false
    @State private var celebration: CelebrationData?
    @State private var errorText = ""
    @State private var fetcher = LocationFetcher()
    @State private var guesses: [SpeciesGuess] = []
    @State private var guessing = false
    @State private var guessNote = ""
    @State private var showExtras = false

    private static let speciesSuggestions = [
        "Coast Redwood", "Coast Live Oak", "Valley Oak", "California Sycamore", "Eucalyptus", "Monterey Pine",
        "Monterey Cypress", "Giant Sequoia", "Douglas Fir", "California Bay Laurel", "Pepper Tree", "Olive",
        "Magnolia", "Japanese Maple", "Bigleaf Maple", "Ginkgo", "Palm", "Willow", "Birch", "Cedar", "Pine",
        "California Buckeye", "Madrone", "Jacaranda", "Elm", "Ash", "Cherry", "Fig", "Unknown"]

    private static let exercises = ["Tranquility", "Coherence", "Relaxation & Focus", "Box Breathing", "4-7-8 Breathing", "Free breathing", "Meditation"]
    private static let weathers: [(String, String)] = [
        ("sun.max.fill", "Sunny"), ("cloud.sun.fill", "Partly cloudy"), ("cloud.fill", "Cloudy"),
        ("cloud.fog.fill", "Foggy"), ("cloud.rain.fill", "Rainy"), ("wind", "Windy"), ("moon.stars.fill", "Night")]
    private static let moods = ["😣", "😕", "😐", "🙂", "😌"]

    private var trees: [TreeSummary] { TreeSummary.build(from: hugs.filter { $0.id != editing?.id }) }

    private var nearbyTrees: [(TreeSummary, Double?)] {
        let here = d.coordinate
        return trees.map { t -> (TreeSummary, Double?) in
            guard let here, let c = t.coordinate else { return (t, nil) }
            return (t, Geo.distance(here, c))
        }.sorted { ($0.1 ?? .infinity) < ($1.1 ?? .infinity) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        if editing == nil && strollID != nil {
                            Label("This hug gets pinned on your stroll", systemImage: "figure.walk")
                                .font(Theme.rounded(14, .bold))
                                .foregroundStyle(Theme.forestDeep)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Theme.leafGradient, in: Capsule())
                        }
                        photosCard.cardAppear()
                        treeCard.cardAppear()
                        locationCard.cardAppear()
                        breathCard.cardAppear()
                        vibeCard.cardAppear()
                        if !errorText.isEmpty {
                            Text(errorText).font(Theme.rounded(14)).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Button(action: save) {
                        Label(editing == nil ? "Save this hug" : "Save changes", systemImage: "heart.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background {
                        LinearGradient(colors: [Theme.forestDeep.opacity(0), Theme.forestDeep.opacity(0.92)], startPoint: .top, endPoint: .center)
                            .ignoresSafeArea()
                    }
                }
            }
            .forestScreen()
            .navigationTitle(editing == nil ? "Hug a Tree" : "Edit Hug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { hideKeyboard() } }
                }
            }
        }
        .onAppear(perform: setup)
        .fullScreenCover(item: $celebration) { c in
            CelebrationView(data: c) {
                celebration = nil
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var photosCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Photos", symbol: "camera.fill")
                HStack(spacing: 10) {
                    PhotoSlot(title: "Tree", symbol: "tree.fill", data: $d.treePhoto, tilt: -3) { data in
                        readPhotoMetadata(data)
                        Task { await guessSpecies(data) }
                    }
                    PhotoSlot(title: "You + Tree", symbol: "person.crop.square.fill", data: $d.selfiePhoto, tilt: 2) { data in
                        if d.treePhoto == nil { readPhotoMetadata(data) }
                    }
                }
            }
        }
    }

    private var treeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "The Tree", symbol: "leaf.fill")
                if !trees.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            treeChoice(id: nil, name: "New tree", sub: "Make a new friend", photo: nil, symbol: "plus")
                            ForEach(nearbyTrees, id: \.0.id) { pair in
                                treeChoice(id: pair.0.id, name: pair.0.name,
                                           sub: pair.1.map { $0 < 1000 ? "\(Int($0)) m away" : Format.distance($0) + " away" } ?? "\(pair.0.hugCount) hugs",
                                           photo: pair.0.coverPhoto, symbol: nil)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if let id = d.treeID, let t = trees.first(where: { $0.id == id }) {
                    HStack {
                        HeartsView(filled: t.bond)
                        Text("Hug #\(t.hugCount + 1) with \(t.name)").font(Theme.rounded(14)).foregroundStyle(Theme.textDim)
                    }
                }
                field("Name your tree", text: $d.treeName, prompt: d.treeID == nil ? "e.g. Grandpa Oak" : "Tree name")
                field("Species", text: $d.species, prompt: "What kind of tree?")
                if guessing || !guesses.isEmpty || !guessNote.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(guessing ? "Looking at your photo…" : "Suggested from your photo", systemImage: "sparkles")
                            .font(Theme.rounded(12, .bold)).foregroundStyle(Theme.glow)
                        if !guesses.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(guesses) { g in
                                        Button { withAnimation(.snappy) { d.species = g.name } } label: {
                                            Chip(label: "\(g.name) · \(Int((g.confidence * 100).rounded()))%", symbol: "leaf.fill",
                                                 selected: d.species == g.name)
                                        }
                                        .buttonStyle(.plain)
                                        .haptic()
                                    }
                                }
                            }
                        }
                        if !guessNote.isEmpty {
                            Text(guessNote).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.leaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                let q = d.species.lowercased()
                let suggestions = Self.speciesSuggestions.filter { q.isEmpty || ($0.lowercased().contains(q) && $0.lowercased() != q) }
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions.prefix(12), id: \.self) { s in
                                Button { d.species = s } label: { Chip(label: s) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func treeChoice(id: UUID?, name: String, sub: String, photo: Data?, symbol: String?) -> some View {
        let selected = d.treeID == id
        return Button {
            withAnimation(.snappy) {
                d.treeID = id
                if let id, let t = trees.first(where: { $0.id == id }) {
                    d.treeName = t.name
                    d.species = t.species
                    if d.coordinate == nil, let c = t.coordinate {
                        d.latitude = c.latitude; d.longitude = c.longitude
                        d.locationSource = "Same spot as last time"
                        d.placeName = t.placeName
                    }
                } else {
                    d.treeName = ""
                    d.species = ""
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let symbol {
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08))
                        Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.glow)
                    } else {
                        PhotoView(data: photo)
                    }
                }
                .frame(width: 92, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(name).font(Theme.rounded(13, .bold)).foregroundStyle(.white).lineLimit(1)
                Text(sub).font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            .frame(width: 92)
            .padding(8)
            .background(selected ? Theme.leaf.opacity(0.25) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? Theme.glow : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var locationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Where", symbol: "mappin.and.ellipse")
                if let c = d.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 300, longitudinalMeters: 300)),
                        interactionModes: []) {
                        Annotation(d.treeName.isEmpty ? "Tree" : d.treeName, coordinate: c) {
                            TreePin(photo: d.treePhoto)
                        }
                    }
                    .mapStyle(.hybrid(elevation: .realistic))
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .id("\(c.latitude),\(c.longitude)")
                    VStack(alignment: .leading, spacing: 2) {
                        if !d.placeName.isEmpty { Text(d.placeName).font(Theme.rounded(15, .bold)) }
                        Text("\(Format.coord(c)) · \(d.locationSource)").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    }
                } else {
                    Text(locating ? "Finding your spot…" : "No pin yet").font(Theme.rounded(15)).foregroundStyle(Theme.textDim)
                }
                HStack(spacing: 8) {
                    Button { Task { await useCurrentLocation() } } label: {
                        Chip(label: locating ? "Locating…" : "I'm here now", symbol: "location.fill")
                    }
                    .buttonStyle(.plain).disabled(locating)
                    if let pc = photoCoord {
                        Button { setCoordinate(pc, source: "From photo") } label: { Chip(label: "Photo's spot", symbol: "photo") }
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("", text: $pinText, prompt: Text("Paste coordinates or a map link").foregroundStyle(Theme.textDim))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(Theme.rounded(14, .regular))
                    Button("Pin") {
                        if let c = Geo.parseCoordinates(pinText) {
                            setCoordinate(c, source: "Pasted pin")
                            pinText = ""
                        } else {
                            errorText = "Couldn't find coordinates in that. Try \"37.28, -121.95\" or an Apple Maps pin link."
                        }
                    }
                    .font(Theme.rounded(14, .bold))
                    .disabled(pinText.isEmpty)
                }
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var breathCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Breathwork", symbol: "wind")
                Menu {
                    ForEach(Self.exercises, id: \.self) { e in Button(e) { d.exercise = e } }
                } label: {
                    HStack {
                        Text(d.exercise.isEmpty ? "Exercise" : d.exercise).font(Theme.rounded(16, .bold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                DatePicker("Started", selection: $d.date, in: ...Date().addingTimeInterval(3600))
                    .font(Theme.rounded(15))
                Button {
                    Task { await pullFromHealth() }
                } label: {
                    HStack {
                        Image(systemName: healthBusy ? "hourglass" : "heart.text.square.fill")
                        Text(healthBusy ? "Reading Apple Health…" : (healthMessage.isEmpty ? "Fill from Apple Health" : "Refresh from Apple Health"))
                    }
                    .font(Theme.rounded(15, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(red: 1, green: 0.3, blue: 0.4).opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color(red: 1, green: 0.6, blue: 0.65))
                }
                .buttonStyle(.plain)
                .disabled(healthBusy)
                if !healthMessage.isEmpty {
                    Text(healthMessage).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    NumberField(label: "Minutes", value: $d.durationMin)
                    NumberField(label: "Breaths / min", value: $d.respRate)
                    NumberField(label: "Avg heart rate", value: $d.avgHR)
                    NumberField(label: "Lowest HR", value: $d.minHR)
                    NumberField(label: "Max HR", value: $d.maxHR)
                }
                DisclosureGroup(isExpanded: $showExtras) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        NumberField(label: "Stress before", value: $d.stressStart)
                        NumberField(label: "Stress after", value: $d.stressEnd)
                        NumberField(label: "Body Battery ±", value: $d.bodyBattery, allowNegative: true)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Stress & Body Battery (optional)").font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                }
                .tint(Theme.glow)
            }
        }
    }

    private var vibeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "The Vibe", symbol: "sparkles")
                Button {
                    withAnimation(.snappy) { d.barefoot.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shoeprints.fill").font(.system(size: 22))
                            .foregroundStyle(d.barefoot ? Theme.forestDeep : Theme.glow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Barefoot · grounded").font(Theme.rounded(16, .bold))
                            Text("Shoes and socks off, feet on the earth").font(Theme.rounded(12, .medium)).opacity(0.75)
                        }
                        Spacer()
                        Image(systemName: d.barefoot ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                    }
                    .foregroundStyle(d.barefoot ? Theme.forestDeep : .white)
                    .padding(14)
                    .background(d.barefoot ? AnyShapeStyle(Theme.leafGradient) : AnyShapeStyle(Color.white.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .haptic()

                Text("Tags").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                FlowLayout(spacing: 8) {
                    ForEach(HugTag.all) { t in
                        Button {
                            withAnimation(.snappy) {
                                if d.tags.contains(t.id) { d.tags.remove(t.id) } else { d.tags.insert(t.id) }
                            }
                        } label: {
                            Chip(label: t.label, symbol: t.symbol, selected: d.tags.contains(t.id))
                        }
                        .buttonStyle(.plain)
                        .haptic()
                    }
                }

                Text("Weather").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.weathers, id: \.1) { w in
                            Button { d.weather = d.weather == w.1 ? "" : w.1 } label: {
                                Chip(label: w.1, symbol: w.0, selected: d.weather == w.1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                moodRow("Before", value: $d.moodBefore)
                moodRow("After", value: $d.moodAfter)

                TextField("", text: $d.notes, prompt: Text("How did it feel? Anything the tree told you?").foregroundStyle(Theme.textDim), axis: .vertical)
                    .lineLimit(3...8)
                    .font(Theme.rounded(15, .regular))
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func moodRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim).frame(width: 56, alignment: .leading)
            ForEach(1...5, id: \.self) { i in
                Button { value.wrappedValue = value.wrappedValue == i ? 0 : i } label: {
                    Text(Self.moods[i - 1])
                        .font(.system(size: value.wrappedValue == i ? 32 : 24))
                        .opacity(value.wrappedValue == 0 || value.wrappedValue == i ? 1 : 0.4)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3), value: value.wrappedValue)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.rounded(12, .bold)).foregroundStyle(Theme.textDim)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Color.white.opacity(0.35)))
                .font(Theme.rounded(16, .semibold))
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Actions

    private func setup() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            d = HugDraft(editing)
            showExtras = editing.stressStart != nil || editing.stressEnd != nil || editing.bodyBattery != nil
        } else {
            Task { await useCurrentLocation(autoPickTree: true) }
            // Your watch's breathwork syncs to Apple Health; grab it straight away.
            Task { await pullFromHealth(quiet: true) }
        }
    }

    private func setCoordinate(_ c: CLLocationCoordinate2D, source: String) {
        d.latitude = c.latitude
        d.longitude = c.longitude
        d.locationSource = source
        errorText = ""
        Task {
            let name = await Geo.placeName(for: c)
            if d.latitude == c.latitude && d.longitude == c.longitude { d.placeName = name }
        }
    }

    private func useCurrentLocation(autoPickTree: Bool = false) async {
        locating = true
        defer { locating = false }
        guard let loc = await fetcher.current() else {
            if !autoPickTree { errorText = "Couldn't get your location. Check that Rootbound has Location access in Settings." }
            return
        }
        // Don't overwrite a pin the user already chose while we were waiting.
        if autoPickTree && d.coordinate != nil { return }
        setCoordinate(loc.coordinate, source: "GPS ±\(Int(loc.horizontalAccuracy)) m")
        if autoPickTree, d.treeID == nil,
           let first = nearbyTrees.first, let dist = first.1, dist < 40 {
            let t = first.0
            d.treeID = t.id
            d.treeName = t.name
            d.species = t.species
        }
    }

    private func readPhotoMetadata(_ data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else { return }
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           var lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
           var lng = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
            if (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S" { lat = -abs(lat) }
            if (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W" { lng = -abs(lng) }
            if !(lat == 0 && lng == 0) {
                let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                photoCoord = c
                // A photo's own location beats "where I'm sitting now", but never a pin the user pasted.
                if d.locationSource != "Pasted pin" { setCoordinate(c, source: "From photo") }
            }
        }
    }

    private func guessSpecies(_ data: Data) async {
        withAnimation(.snappy) { guessing = true; guesses = []; guessNote = "" }
        let r = await SpeciesGuesser.guess(from: data)
        withAnimation(.snappy) {
            guessing = false
            guesses = r.guesses
            if r.guesses.isEmpty {
                guessNote = r.looksLikeTree
                    ? "Can't tell the exact species from this one. For a sharper ID, open the photo in Photos, swipe up and tap Look Up Plant."
                    : "That doesn't look much like a tree to me. Try a shot of the trunk and leaves."
            } else if d.species.isEmpty, let top = r.guesses.first, top.confidence >= 0.5 {
                d.species = top.name
                guessNote = "Best guess filled in. Tap another if it's wrong."
            }
        }
    }

    private func pullFromHealth(quiet: Bool = false) async {
        healthBusy = true
        defer { healthBusy = false }
        let hs = HealthService.shared
        guard hs.isAvailable, await hs.requestAccess() else {
            if !quiet { healthMessage = "Apple Health isn't available. You can type the numbers in." }
            return
        }
        var found: [String] = []
        if let s = await hs.nearestBreathSession(around: d.date) {
            d.date = s.start
            d.durationMin = (s.minutes * 10).rounded() / 10
            found.append("\(Format.minutes(d.durationMin ?? 0)) session from \(s.source)")
        }
        let start = d.date
        let end = d.date.addingTimeInterval(max(1, d.durationMin ?? 12) * 60)
        if let hr = await hs.heartRate(from: start, to: end) {
            d.avgHR = hr.avg.rounded()
            d.minHR = hr.min.rounded()
            d.maxHR = hr.max.rounded()
            found.append("heart rate (\(hr.samples) readings)")
        }
        if let rr = await hs.respiratoryRate(from: start, to: end) {
            d.respRate = (rr * 10).rounded() / 10
            found.append("breathing rate")
        }
        if found.isEmpty {
            healthMessage = quiet ? "" : "Nothing in Apple Health for that time yet. Garmin Connect can take a few minutes to sync after a session, so try Refresh in a bit."
        } else {
            healthMessage = "Filled from Apple Health: " + found.joined(separator: ", ") + "."
        }
    }

    private func save() {
        hideKeyboard()
        let all = hugs
        let levelBefore = GameEngine.level(for: GameEngine.totalXP(hugs: all, activities: activities))
        let badgesBefore = Set(GameEngine.badges(hugs: all, activities: activities).filter(\.earned).map(\.id))

        let hug = editing ?? Hug()
        let newTree = d.treeID == nil
        hug.treeID = d.treeID ?? (editing?.treeID ?? UUID())
        if newTree, editing != nil, trees.contains(where: { $0.id == hug.treeID }) {
            hug.treeID = UUID()   // moved to a brand-new tree while editing
        }
        d.apply(to: hug)
        if editing == nil { Reviews.noteWin() }
        if hug.treeName.isEmpty {
            hug.treeName = newTree ? "Tree #\(trees.count + 1)" : (trees.first { $0.id == hug.treeID }?.name ?? "Tree")
        }
        let isNew = editing == nil
        if isNew {
            hug.strollID = strollID
            hug.leafKey = GameEngine.rollLeaf(for: hug).id
            context.insert(hug)
        }
        // Renaming a tree renames it everywhere.
        for other in all where other.treeID == hug.treeID && other.id != hug.id {
            if other.treeName != hug.treeName { other.treeName = hug.treeName }
            if !hug.species.isEmpty && other.species != hug.species { other.species = hug.species }
        }
        let breakdown = GameEngine.xp(for: hug, existing: all)
        hug.xp = breakdown.total

        do { try context.save() } catch {
            errorText = "Couldn't save: \(error.localizedDescription)"
            return
        }

        let after = isNew ? all + [hug] : all
        let levelAfter = GameEngine.level(for: GameEngine.totalXP(hugs: after, activities: activities))
        let newBadges = GameEngine.badges(hugs: after, activities: activities).filter { $0.earned && !badgesBefore.contains($0.id) }

        if isNew, let strollID {
            let onStroll = after.filter { $0.strollID == strollID }.count
            LiveActivityController.shared.setHugs(onStroll)
        }
        if isNew {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            celebration = CelebrationData(breakdown: breakdown, leaf: LeafType.find(hug.leafKey), newBadges: newBadges,
                                          levelBefore: levelBefore, levelAfter: levelAfter, treeName: hug.treeName)
        } else {
            dismiss()
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Pieces

struct TreePin: View {
    let photo: Data?
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            PhotoView(data: photo)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.glow, lineWidth: 3))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.glow)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
    }
}

/// Number entry that allows blank (= unknown).
struct NumberField: View {
    let label: String
    @Binding var value: Double?
    var allowNegative = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.rounded(11, .bold)).foregroundStyle(Theme.textDim).lineLimit(1)
            TextField("", text: $text, prompt: Text("–").foregroundStyle(Color.white.opacity(0.3)))
                .keyboardType(allowNegative ? .numbersAndPunctuation : .decimalPad)
                .font(Theme.rounded(18, .bold))
                .focused($focused)
                .onChange(of: text) { _, t in
                    let cleaned = t.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                    if cleaned.isEmpty { value = nil }
                    else if let v = Double(cleaned), allowNegative || v >= 0 { value = v }
                }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { text = Self.render(value) }
        .onChange(of: value) { _, v in
            if !focused { text = Self.render(v) }
        }
    }

    static func render(_ v: Double?) -> String {
        guard let v else { return "" }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// Polaroid-style photo slot: camera or library.
struct PhotoSlot: View {
    let title: String
    let symbol: String
    @Binding var data: Data?
    var tilt: Double = 0
    var onPicked: (Data) -> Void

    @State private var item: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var loading = false

    var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
            }
            Button { showLibrary = true } label: { Label("Choose from library", systemImage: "photo.on.rectangle") }
            if data != nil {
                Button(role: .destructive) { data = nil } label: { Label("Remove", systemImage: "trash") }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let data, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.06)
                        VStack(spacing: 6) {
                            Image(systemName: loading ? "hourglass" : symbol).font(.system(size: 24, weight: .semibold))
                            Image(systemName: "plus.circle.fill").font(.system(size: 14))
                        }
                        .foregroundStyle(Theme.glow)
                    }
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.forestDeep)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(6)
            .padding(.bottom, 2)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 8))
            .rotationEffect(.degrees(tilt))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images, photoLibrary: .shared())
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                if let raw = try? await newItem.loadTransferable(type: Data.self) {
                    onPicked(raw)
                    data = ImageTools.compressed(raw)
                }
                loading = false
                item = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: { raw in
                data = ImageTools.compressed(raw)
            }, onClose: { showCamera = false })
            .ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage, let data = img.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onClose()
        }
    }
}
