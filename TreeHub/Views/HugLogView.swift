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
    /// Legacy third photo of an older hug (kept as is; not offered for new hugs).
    var legacyPhoto: Data? = nil
    var tags: Set<String> = []
    var barefoot = false
    var feetInWater = false
    var waterSetting = ""
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
    var hrStart: Double? = nil
    var hrEnd: Double? = nil
    var hrv: Double? = nil
    var fromWatch = false
    /// Breath sessions linked to this hug.
    var linked: [LinkedSession] = []
    /// False for an older hug whose sessions haven't been looked at yet: saving then keeps its "no list" state.
    var hasLinkList = true

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init() {}

    init(_ h: Hug) {
        date = h.date; treeID = h.treeID; treeName = h.treeName; species = h.species
        latitude = h.latitude; longitude = h.longitude; placeName = h.placeName
        locationSource = h.latitude != nil ? "Saved pin" : ""
        treePhoto = h.treePhoto; selfiePhoto = h.selfiePhoto; legacyPhoto = h.garminPhoto
        tags = Set(h.tags); barefoot = h.barefoot; feetInWater = h.feetInWater; waterSetting = h.waterSetting; weather = h.weather
        moodBefore = h.moodBefore; moodAfter = h.moodAfter; notes = h.notes
        exercise = h.exercise; durationMin = h.durationMin > 0 ? h.durationMin : nil
        avgHR = h.avgHR; minHR = h.minHR; maxHR = h.maxHR; respRate = h.respRate
        hrStart = h.hrStart; hrEnd = h.hrEnd; hrv = h.hrv; fromWatch = h.fromWatch
        linked = h.linkedSessions; hasLinkList = h.hasLinkList
    }

    init(watch w: WatchHug) {
        date = w.start
        durationMin = (w.minutes * 10).rounded() / 10
        avgHR = w.avgHR; minHR = w.minHR; maxHR = w.maxHR
        hrStart = w.startHR; hrEnd = w.endHR
        fromWatch = true
        exercise = "Free breathing"
    }

    func apply(to h: Hug) {
        h.date = date
        h.treeName = treeName.trimmingCharacters(in: .whitespacesAndNewlines)
        h.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        h.latitude = latitude; h.longitude = longitude; h.placeName = placeName
        h.treePhoto = treePhoto; h.selfiePhoto = selfiePhoto; h.garminPhoto = legacyPhoto
        h.tags = HugTag.all.map(\.id).filter { tags.contains($0) }
        h.barefoot = barefoot; h.feetInWater = feetInWater; h.waterSetting = waterSetting; h.weather = weather
        h.moodBefore = moodBefore; h.moodAfter = moodAfter
        h.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        h.exercise = exercise; h.durationMin = max(0, durationMin ?? 0)
        h.avgHR = avgHR; h.minHR = minHR; h.maxHR = maxHR; h.respRate = respRate
        h.hrStart = hrStart; h.hrEnd = hrEnd; h.hrv = hrv; h.fromWatch = fromWatch
        if hasLinkList { h.linkedSessions = linked }
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
    /// First hug of a rare / epic / legendary species: the celebration makes a big deal of it.
    var rareFind: Rarity? = nil
    var species: String = ""
    /// The seasonal event running when the hug was logged.
    var event: SeasonalEvent? = nil
    /// The tree's stable id ("Breathe with this tree" syncs the Still Pointz session back under it).
    var treeID: UUID? = nil
    /// Breath sessions linked to the hug just logged (shown with all their data).
    var sessions: [LinkedSession] = []
}

@MainActor
struct HugLogView: View {
    let editing: Hug?
    /// Set when the hug happens during a stroll or hike that's being recorded.
    var strollID: UUID? = nil
    /// Nature Roll "Make this a hug": a camera-roll photo (PHAsset id) to start the hug with (NatureRoll/).
    var prefillAssetID: String? = nil
    /// A hug timed on the Rootbound Watch app (WatchHugs.swift): its time and heart data fill the form.
    var watchHug: WatchHug? = nil
    /// The tree picked in "Hug from Watch — pick tree" (nil = new tree).
    var preselectTree: UUID? = nil

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
    @State private var showHeartDetails = true
    @State private var showTags = true
    @ObservedObject private var unlock = Unlock.shared
    @State private var showPlans = false
    /// The multi-select session sheet (sessions within ±60 min of the photo / hug time).
    @State private var picker: SessionPickRequest?
    /// Bumped by every Health pull; an older pull still in flight (e.g. the one on open) never overwrites a newer one (the photo's).
    @State private var pullToken = 0

    struct SessionPickRequest: Identifiable {
        let id = UUID()
        let around: Date
        let candidates: [LinkedSession]
        let selected: Set<UUID>
    }

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
                    VStack(spacing: 14) {
                        if editing == nil && strollID != nil {
                            banner("This hug gets pinned on your stroll", symbol: "figure.walk")
                        }
                        if d.fromWatch && editing == nil {
                            banner("Timed on your Watch", symbol: "applewatch")
                        }
                        photosCard.cardAppear()
                        treeCard.cardAppear()
                        breathCard.cardAppear()
                        feelCard.cardAppear()
                        locationCard.cardAppear()
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
            .sheet(item: $picker) { req in
                SessionPickerSheet(around: req.around, candidates: req.candidates, selected: req.selected) { chosen in
                    Task { await applyLinked(chosen) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { hideKeyboard() } }
                }
            }
        }
        .onAppear(perform: setup)
        .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: "Tree selfies")
        .fullScreenCover(item: $celebration) { c in
            CelebrationView(data: c) {
                celebration = nil
                dismiss()
            }
        }
    }

    private func banner(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.rounded(14, .bold))
            .foregroundStyle(Theme.forestDeep)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.leafGradient, in: Capsule())
    }

    /// Small grey label above a group of fields.
    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(0.8)
            .foregroundStyle(Theme.textDim)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Sections

    private var photosCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Photos", symbol: "camera.fill")
                HStack(spacing: 12) {
                    PhotoSlot(title: "Tree", symbol: "tree.fill", data: $d.treePhoto, tilt: -2) { data, info in
                        readPhotoMetadata(data, info: info)
                        Task { await guessSpecies(data) }
                    }
                    // Rootbound Pro: the second photo (tree selfie). A selfie that's already on a hug always stays.
                    PhotoSlot(title: "You + Tree", symbol: "person.crop.square.fill", data: $d.selfiePhoto, tilt: 2,
                              locked: !unlock.isPro, onLocked: { showPlans = true }) { data, info in
                        if d.treePhoto == nil { readPhotoMetadata(data, info: info) }
                    }
                }
                Text("The tree photo's time finds your breath sessions; its location pins the tree.")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var treeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "The tree", symbol: "leaf.fill")
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
                field("Name", text: $d.treeName, prompt: d.treeID == nil ? "e.g. Grandpa Oak" : "Tree name")
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
                                .fixedSize(horizontal: false, vertical: true)
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
            withAnimation(.snappy) { selectTree(id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let symbol {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                        Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.glow)
                    } else {
                        PhotoView(data: photo)
                    }
                }
                .frame(width: 92, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(name).font(Theme.rounded(13, .bold)).foregroundStyle(.white).lineLimit(1)
                Text(sub).font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            .frame(width: 92)
            .padding(8)
            .background(selected ? Theme.leaf.opacity(0.22) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.glow : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectTree(_ id: UUID?) {
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
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            errorText = "Couldn't find coordinates in that. Try \"37.77, -122.45\" or a map pin link."
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
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Breathwork", symbol: "wind")

                // 1. Linked Still Pointz / Health sessions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        groupLabel(d.linked.isEmpty ? "Breath sessions" : "\(d.linked.count) linked session\(d.linked.count == 1 ? "" : "s")")
                        Spacer()
                        Button {
                            Task { await openPicker(around: d.date) }
                        } label: {
                            Label(d.linked.isEmpty ? "Find" : "Change", systemImage: "checklist")
                                .font(Theme.rounded(13, .bold))
                        }
                        .disabled(healthBusy)
                    }
                    if d.linked.isEmpty {
                        Text("No Still Pointz or Health sessions linked. Tap Find to look within an hour of the hug.")
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(d.linked) { s in LinkedSessionCard(session: s, compact: true) }
                    }
                }

                // 2. When + how long
                VStack(alignment: .leading, spacing: 8) {
                    groupLabel("The hug")
                    DatePicker("Started", selection: $d.date, in: ...Date().addingTimeInterval(3600))
                        .font(Theme.rounded(15))
                    HStack(spacing: 10) {
                        NumberField(label: "Minutes", value: $d.durationMin)
                        NumberField(label: "Avg heart rate", value: $d.avgHR)
                    }
                    Menu {
                        ForEach(Self.exercises, id: \.self) { e in Button(e) { d.exercise = e } }
                    } label: {
                        HStack {
                            Text("Practice").font(Theme.rounded(14, .medium)).foregroundStyle(Theme.textDim)
                            Spacer()
                            Text(d.exercise.isEmpty ? "Choose" : d.exercise).font(Theme.rounded(15, .bold))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                // 3. Fill from Apple Health (Apple Watch heart data)
                Button {
                    Task { await pullFromHealth() }
                } label: {
                    HStack {
                        Image(systemName: healthBusy ? "hourglass" : "applewatch")
                        Text(healthBusy ? "Reading Apple Health…" : (healthMessage.isEmpty ? "Fill from Apple Watch" : "Refresh from Apple Watch"))
                    }
                    .font(Theme.rounded(15, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.glow.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.glow)
                }
                .buttonStyle(.plain)
                .disabled(healthBusy)
                if !healthMessage.isEmpty {
                    Text(healthMessage).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 4. Rarely edited heart numbers, collapsed
                DisclosureGroup(isExpanded: $showHeartDetails) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        NumberField(label: "Lowest HR", value: $d.minHR)
                        NumberField(label: "Max HR", value: $d.maxHR)
                        NumberField(label: "HR at start", value: $d.hrStart)
                        NumberField(label: "HR at end", value: $d.hrEnd)
                        NumberField(label: "HRV (ms)", value: $d.hrv)
                        NumberField(label: "Breaths / min", value: $d.respRate)
                    }
                    .padding(.top, 8)
                } label: {
                    Text(heartSummary).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                }
                .tint(Theme.glow)
            }
        }
    }

    private var heartSummary: String {
        var parts: [String] = []
        if let a = d.hrStart, let b = d.hrEnd { parts.append(String(format: "HR %+.0f", b - a)) }
        if let v = d.hrv { parts.append(String(format: "HRV %.0f ms", v)) }
        if let r = d.respRate { parts.append(String(format: "%.1f br/min", r)) }
        return parts.isEmpty ? "More heart data" : "More heart data · " + parts.joined(separator: " · ")
    }

    private var feelCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "How it felt", symbol: "sparkles")
                VStack(spacing: 6) {
                    moodRow("Before", value: $d.moodBefore)
                    moodRow("After", value: $d.moodAfter)
                }
                groundingToggle("Barefoot", "Shoes off, feet on the earth (+25 XP)", "shoeprints.fill", on: $d.barefoot)
                groundingToggle("Feet in water", "Toes in a creek, lake or the ocean (+25 XP)", "drop.fill", on: $d.feetInWater)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where the tree stands").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 8) {
                        waterChip("land", "On land", "tree.fill")
                        waterChip("edge", "Water's edge", "water.waves.and.arrow.down")
                        waterChip("water", "Water tree", "water.waves")
                    }
                }

                TextField("", text: $d.notes, prompt: Text("How did it feel? Anything the tree told you?").foregroundStyle(Theme.textDim), axis: .vertical)
                    .lineLimit(3...8)
                    .font(Theme.rounded(15, .regular))
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                DisclosureGroup(isExpanded: $showTags) {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowLayout(spacing: 8) {
                            ForEach(HugTag.all) { t in
                                Button {
                                    withAnimation(.snappy) {
                                        if d.tags.contains(t.id) { d.tags.remove(t.id) } else { d.tags.insert(t.id) }
                                    }
                                } label: {
                                    Chip(label: t.label, selected: d.tags.contains(t.id))
                                }
                                .buttonStyle(.plain)
                                .haptic()
                            }
                        }
                        groupLabel("Weather")
                        FlowLayout(spacing: 8) {
                            ForEach(Self.weathers, id: \.1) { w in
                                Button { d.weather = d.weather == w.1 ? "" : w.1 } label: {
                                    Chip(label: w.1, symbol: w.0, selected: d.weather == w.1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(tagSummary).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                }
                .tint(Theme.glow)
            }
        }
    }

    private var tagSummary: String {
        let n = d.tags.count + (d.weather.isEmpty ? 0 : 1)
        return n == 0 ? "Tags & weather" : "Tags & weather · \(n) chosen"
    }

    private func moodRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim).frame(minWidth: 56, alignment: .leading)
            ForEach(1...5, id: \.self) { i in
                Button { value.wrappedValue = value.wrappedValue == i ? 0 : i } label: {
                    Text(Self.moods[i - 1])
                        .font(.system(size: value.wrappedValue == i ? 30 : 24))
                        .opacity(value.wrappedValue == 0 || value.wrappedValue == i ? 1 : 0.4)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(i) of 5")
                .accessibilityAddTraits(value.wrappedValue == i ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.3), value: value.wrappedValue)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupLabel(label)
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
            // Older hug (no list yet): show the sessions that overlap its time so they can be kept or changed;
            // refresh the data of the ones already linked.
            Task {
                let list = d.hasLinkList ? d.linked : await HugSessions.overlapping(editing)
                let rich = await HugSessions.enrich(list)
                if !d.hasLinkList { d.hasLinkList = true }
                d.linked = rich
            }
        } else if let watchHug {
            d = HugDraft(watch: watchHug)
            if let preselectTree { selectTree(preselectTree) }
            Task { await useCurrentLocation(autoPickTree: preselectTree == nil) }
            // HRV, breathing rate and any Still Pointz sessions done during the Watch hug.
            Task { await pullFromHealth(quiet: true, prompt: false) }
        } else {
            Task { await useCurrentLocation(autoPickTree: true) }
            // Your watch's breathwork syncs to Apple Health; grab it straight away (no session sheet yet:
            // a camera-roll photo usually follows and asks around its own time).
            Task { await pullFromHealth(quiet: true, prompt: false) }
            if let prefillAssetID {
                Task {
                    guard let p = await NatureRollPhotos.original(prefillAssetID) else { return }
                    readPhotoMetadata(p.data, info: p.info)
                    d.treePhoto = ImageTools.compressed(p.data)
                    await guessSpecies(p.data)
                }
            }
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

    private func readPhotoMetadata(_ data: Data, info: PhotoAssetInfo? = nil) {
        let props = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        // EXIF first; the Photos library's own date / place when the file carries none.
        if editing == nil, !d.fromWatch, let shot = Self.photoDate(props) ?? info?.date {
            d.date = shot
            Task { await pullFromHealth(quiet: true, pickAround: shot) }
        }
        var coord: CLLocationCoordinate2D? = nil
        if let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           var lat = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
           var lng = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue {
            if (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S" { lat = -abs(lat) }
            if (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W" { lng = -abs(lng) }
            if !(lat == 0 && lng == 0) { coord = CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        }
        if let c = coord ?? info?.coordinate {
            photoCoord = c
            // A photo's own location beats "where I'm sitting now", but never a pin the user pasted.
            if d.locationSource != "Pasted pin" { setCoordinate(c, source: "From photo") }
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

    /// When the photo was taken, from its EXIF data (with its time-zone offset when present).
    private func groundingToggle(_ title: String, _ detail: String, _ symbol: String, on: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { on.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.rounded(15, .bold))
                    Text(detail).font(Theme.rounded(12, .medium)).opacity(0.75)
                }
                Spacer()
                Image(systemName: on.wrappedValue ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
            }
            .foregroundStyle(on.wrappedValue ? Theme.glow : .white)
            .padding(12)
            .background(on.wrappedValue ? Theme.leaf.opacity(0.22) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .haptic()
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    private func waterChip(_ value: String, _ label: String, _ symbol: String) -> some View {
        let on = d.waterSetting == value
        return Button {
            withAnimation(.snappy) { d.waterSetting = on ? "" : value }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(label).font(Theme.rounded(12, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(on ? Theme.glow : .white)
            .background(on ? Theme.leaf.opacity(0.22) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .haptic()
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    static func photoDate(_ props: [String: Any]) -> Date? {
        guard let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let raw = (exif[kCGImagePropertyExifDateTimeOriginal as String] ?? exif[kCGImagePropertyExifDateTimeDigitized as String]) as? String
        else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if let off = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String {
            f.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let d = f.date(from: raw + off) { return d }
        }
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = .current
        return f.date(from: raw)
    }

    /// The multi-select sheet for sessions within an hour of `date`. Already-linked ones stay checked; when
    /// nothing is linked yet, every session found is preselected.
    private func openPicker(around date: Date) async {
        healthBusy = true
        var found = await HugSessions.candidates(near: date)
        healthBusy = false
        for s in d.linked where !found.contains(where: { $0.sameSession(as: s) }) { found.append(s) }
        guard !found.isEmpty else {
            healthMessage = "No Still Pointz or Health breath sessions within an hour of \(date.formatted(date: .omitted, time: .shortened))."
            return
        }
        // Keep the linked copies (with their data) in the list so their ids stay checked.
        let list = found.map { f in d.linked.first(where: { $0.sameSession(as: f) }) ?? f }
        let selected = d.linked.isEmpty ? Set(list.map(\.id)) : Set(list.filter { s in d.linked.contains { $0.id == s.id } }.map(\.id))
        picker = SessionPickRequest(around: date, candidates: list, selected: selected)
    }

    /// Link the chosen sessions; the hug then takes their time span (unless it was timed on the Watch) and heart data.
    private func applyLinked(_ chosen: [LinkedSession]) async {
        d.hasLinkList = true
        d.linked = chosen.sorted { $0.start < $1.start }
        if let first = d.linked.first, !d.fromWatch {
            d.date = first.start
            d.durationMin = (d.linked.totalMinutes * 10).rounded() / 10
        }
        let label = chosen.isEmpty ? nil : "\(chosen.count) session\(chosen.count == 1 ? "" : "s") (\(Format.minutes((d.linked.totalMinutes * 10).rounded() / 10)))"
        await pullFromHealth(quiet: true, skipSession: true, label: label)
        let rich = await HugSessions.enrich(d.linked)
        if rich.map(\.id) == d.linked.map(\.id) { d.linked = rich }
    }

    private func pullFromHealth(quiet: Bool = false, pickAround: Date? = nil, skipSession: Bool = false, label: String? = nil,
                                prompt: Bool = true) async {
        pullToken += 1
        let token = pullToken
        healthBusy = true
        defer { if token == pullToken { healthBusy = false } }
        let hs = HealthService.shared
        guard hs.isAvailable, await hs.requestAccess() else {
            if !quiet { healthMessage = "Apple Health isn't available. You can type the numbers in." }
            return
        }
        guard token == pullToken else { return }
        var found: [String] = []
        if let label { found.append(label) }
        if !skipSession {
            let around = pickAround ?? d.date
            let near = await HugSessions.candidates(near: around)
            guard token == pullToken else { return }
            if !near.isEmpty {
                // Every session within the hour is preselected; with several, the sheet opens so any that don't
                // belong can be unchecked. Present only once the photo picker has finished going away.
                d.hasLinkList = true
                d.linked = near.sorted { $0.start < $1.start }
                if !d.fromWatch, let first = d.linked.first {
                    d.date = first.start
                    d.durationMin = (d.linked.totalMinutes * 10).rounded() / 10
                }
                found.append("\(near.count) breath session\(near.count == 1 ? "" : "s")")
                if near.count > 1 && prompt {
                    let list = d.linked
                    Task {
                        try? await Task.sleep(for: .milliseconds(650))
                        guard token == pullToken else { return }
                        picker = SessionPickRequest(around: around, candidates: list, selected: Set(list.map(\.id)))
                    }
                } else if near.count > 1 {
                    found.append("tap Change to review them")
                }
            }
        }
        let start = d.date
        let end = d.date.addingTimeInterval(max(1, d.durationMin ?? 12) * 60)
        var hrFound: HealthService.HeartStats? = nil
        if !(d.fromWatch && d.avgHR != nil) { hrFound = await hs.heartRate(from: start, to: end) }
        let st = await hs.breathStats(from: start, to: end)
        let rrFound = await hs.respiratoryRate(from: start, to: end)
        guard token == pullToken else { return }
        if let hr = hrFound {
            d.avgHR = hr.avg.rounded()
            d.minHR = hr.min.rounded()
            d.maxHR = hr.max.rounded()
            found.append("heart rate (\(hr.samples) readings)")
        }
        if d.hrStart == nil, let a = st.startHR { d.hrStart = a.rounded() }
        if d.hrEnd == nil, let b = st.endHR { d.hrEnd = b.rounded() }
        if let v = st.hrv {
            d.hrv = v.rounded()
            found.append("HRV")
        }
        if let rr = rrFound {
            d.respRate = (rr * 10).rounded() / 10
            found.append("breathing rate")
        }
        if !d.linked.isEmpty {
            let rich = await HugSessions.enrich(d.linked)
            if token == pullToken, rich.map(\.id) == d.linked.map(\.id) { d.linked = rich }
        }
        if found.isEmpty {
            healthMessage = quiet ? "" : "Nothing in Apple Health for that time yet. Your Apple Watch can take a few minutes to sync after a session, so try Refresh in a bit."
        } else {
            healthMessage = "Filled from Apple Health: " + found.joined(separator: ", ") + "."
        }
    }

    private func save() {
        hideKeyboard()
        let all = hugs
        BreathBark.sync(hugs: all)   // count earlier Breath & Bark days first, so only this hug's shows as new
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
        if let watchHug { WatchHugInbox.shared.remove(watchHug.id) }

        let after = isNew ? all + [hug] : all
        // Hug + a Still Pointz session today = Breath & Bark (bonus XP lives in BreathBark, not in hug.xp).
        let breathBarkNew = BreathBark.sync(hugs: after).contains(WellnessBridge.dayKey(hug.date))
        RootboundWellness.publish(hugs: after)
        let levelAfter = GameEngine.level(for: GameEngine.totalXP(hugs: after, activities: activities))
        let newBadges = GameEngine.badges(hugs: after, activities: activities).filter { $0.earned && !badgesBefore.contains($0.id) }

        if isNew, let strollID {
            let onStroll = after.filter { $0.strollID == strollID }.count
            LiveActivityController.shared.setHugs(onStroll)
        }
        if isNew {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let sp = hug.species.lowercased().trimmingCharacters(in: .whitespaces)
            let firstOfSpecies = !sp.isEmpty && !all.contains { $0.id != hug.id && $0.species.lowercased().trimmingCharacters(in: .whitespaces) == sp }
            let r = SpeciesRarity.rarity(for: hug.species)
            var shown = breakdown
            if breathBarkNew { shown.add("Breath & Bark (Still Pointz today)", BreathBark.bonusXP) }
            celebration = CelebrationData(breakdown: shown, leaf: LeafType.find(hug.leafKey), newBadges: newBadges,
                                          levelBefore: levelBefore, levelAfter: levelAfter, treeName: hug.treeName,
                                          rareFind: firstOfSpecies && r > .common ? r : nil, species: hug.species,
                                          event: SeasonalEvent.active(on: hug.date), treeID: hug.treeID,
                                          sessions: hug.linkedSessions)
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

/// When / where the Photos library says a picked photo was taken. Only looked up when the file itself has no
/// EXIF capture time (saved from another app, some edits): then Rootbound asks for library access once.
struct PhotoAssetInfo {
    var date: Date?
    var coordinate: CLLocationCoordinate2D?

    @MainActor
    static func lookup(_ identifier: String?, raw: Data) async -> PhotoAssetInfo? {
        let props = CGImageSourceCreateWithData(raw as CFData, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        guard HugLogView.photoDate(props) == nil, let identifier else { return nil }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return nil }
        return PhotoAssetInfo(date: asset.creationDate, coordinate: asset.location?.coordinate)
    }
}

/// Polaroid-style photo slot: camera or library.
struct PhotoSlot: View {
    let title: String
    let symbol: String
    @Binding var data: Data?
    var tilt: Double = 0
    /// Pro-only slot: when empty, a tap opens the paywall instead of the picker.
    var locked: Bool = false
    var onLocked: () -> Void = {}
    var onPicked: (Data, PhotoAssetInfo?) -> Void

    @State private var item: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var loading = false

    var body: some View {
        if locked && data == nil {
            Button(action: onLocked) { polaroid }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), Rootbound Pro")
        } else {
            picker
        }
    }

    private var picker: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { after { showCamera = true } } label: { Label("Take photo", systemImage: "camera") }
            }
            Button { after { showLibrary = true } } label: { Label("Choose from camera roll", systemImage: "photo.on.rectangle") }
            if data != nil {
                Button(role: .destructive) { data = nil } label: { Label("Remove", systemImage: "trash") }
            }
        } label: {
            polaroid
        }
        .background {
            // Present the picker from a plain view, not from the menu that is still closing (that's what froze it).
            Color.clear
                .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images,
                              preferredItemEncoding: .current, photoLibrary: .shared())
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                // .current encoding: the original file (HEIC/JPEG) with its EXIF time and GPS.
                if let raw = try? await newItem.loadTransferable(type: Data.self) {
                    let info = await PhotoAssetInfo.lookup(newItem.itemIdentifier, raw: raw)
                    onPicked(raw, info)
                    data = ImageTools.compressed(raw)
                }
                loading = false
                item = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: { raw in
                onPicked(raw, nil)
                data = ImageTools.compressed(raw)
            }, onClose: { showCamera = false })
            .ignoresSafeArea()
        }
    }

    /// Let the menu finish closing before presenting a picker.
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    private var polaroid: some View {
            VStack(spacing: 6) {
                ZStack {
                    if let data, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.06)
                        VStack(spacing: 6) {
                            Image(systemName: loading ? "hourglass" : symbol).font(.system(size: 24, weight: .semibold))
                            if locked {
                                Label("Pro", systemImage: "lock.fill").font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.gold)
                            } else {
                                Image(systemName: "plus.circle.fill").font(.system(size: 14))
                            }
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
