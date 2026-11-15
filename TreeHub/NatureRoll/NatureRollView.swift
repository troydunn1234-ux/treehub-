import SwiftUI
import Photos
import MapKit
import UIKit

/// The Nature Roll screen: your camera roll's nature, sorted on this iPhone.
/// Free: scanning, category chips, grids, "On this day", "Make this a hug". Pro: the map and Photos albums.
struct NatureRollView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = NatureRollStore.shared
    @ObservedObject private var unlock = Unlock.shared
    @State private var category: NatureCategory?
    @State private var mode = 0
    @State private var open: NatureRecord?
    @State private var showPlans = false
    @State private var planContext = "Nature Roll"
    @State private var albumNote = ""
    @State private var savingAlbums = false
    /// Shown inside a sheet (Home / Grove) with a Done button.
    var showsDone = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap + 2) {
                    header
                    if !store.canRead || !store.hasStarted {
                        welcomeCard
                    } else {
                        scanCard
                        if !store.records.isEmpty {
                            onThisDay
                            PillSwitcher(options: [.init(id: 0, label: "Photos", symbol: "square.grid.3x3.fill"),
                                                   .init(id: 1, label: "Map", symbol: "map.fill")],
                                         selection: $mode)
                            strictnessRow
                            chips
                            if store.shown.isEmpty {
                                Text("Nothing passes \(store.strictness.name) right now. Try Balanced or Everything above.")
                                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                            } else if mode == 0 { grid } else { mapSection }
                            albumsCard
                        } else if !store.scanning {
                            emptyCard
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .sheet(item: $open) { r in NatureRollPhotoView(record: r) }
            .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: planContext)
            .onAppear { store.scanIfAllowed() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NatureRoll.title).font(Theme.title(34)).foregroundStyle(.white)
            Text(store.shown.isEmpty ? "The nature in your camera roll" : "\(store.shown.count) nature photos")
                .font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.textDim)
        }
        .padding(.top, 8)
    }

    private var welcomeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: NatureRoll.symbol).font(.system(size: 34)).foregroundStyle(Theme.leafGradient)
                Text("Find the trails, peaks, sunsets and wildlife you've already shot.")
                    .font(Theme.rounded(17, .bold)).foregroundStyle(.white)
                Label("Sorted on this iPhone by its built-in image recognition. Nothing is uploaded.", systemImage: "lock.shield.fill")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                Label("Works with \"Limited\" access too: share only the photos you want.", systemImage: "hand.raised.fill")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                if store.auth == .denied || store.auth == .restricted {
                    Text("Photo access is off for Rootbound. Turn it on in Settings › Rootbound › Photos.")
                        .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.gold)
                    Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                        Label("Open Settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { Task { await store.scanNow() } } label: {
                        Label("Scan my photos", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var scanCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if store.scanning {
                    HStack {
                        Label(store.total == 0 ? "Getting ready…" : "Scanning \(store.done.formatted()) of \(store.total.formatted())",
                              systemImage: "sparkle.magnifyingglass")
                            .font(Theme.rounded(14, .bold)).foregroundStyle(.white)
                        Spacer()
                        Button("Cancel") { store.cancel() }.font(Theme.rounded(14, .bold))
                    }
                    ProgressView(value: Double(store.done), total: Double(max(store.total, 1))).tint(Theme.glow)
                    Text("You can leave this screen; it picks up where it stopped.")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                } else {
                    HStack {
                        Label(store.lastScan.map { "Up to date · \(Format.dayTime($0))" } ?? "Not scanned yet",
                              systemImage: "checkmark.seal.fill")
                            .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.textDim)
                        Spacer()
                        Button { Task { await store.scanNow() } } label: {
                            Label("Scan new", systemImage: "arrow.clockwise")
                        }
                        .font(Theme.rounded(13, .bold))
                    }
                }
                if store.auth == .limited {
                    Button { pickMorePhotos() } label: {
                        Label("You shared some photos. Choose more…", systemImage: "plus.rectangle.on.rectangle")
                            .font(Theme.rounded(13, .bold))
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "leaf").font(.system(size: 36)).foregroundStyle(Theme.glow.opacity(0.7))
                Text("No nature found yet").font(Theme.rounded(17, .bold)).foregroundStyle(.white)
                Text("Shoot a trail, a view or a sunset and it shows up here next time you open Rootbound.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var onThisDay: some View {
        let days = store.onThisDay()
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "On this day", symbol: "calendar")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(days, id: \.year) { day in
                            ForEach(day.items.prefix(6)) { r in
                                Button { open = r } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        NatureThumb(id: r.id, side: 150)
                                            .frame(width: 150, height: 190)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        let ago = Calendar.current.component(.year, from: Date()) - day.year
                                        Text(ago == 1 ? "1 year ago" : "\(ago) years ago")
                                            .font(Theme.rounded(13, .bold)).foregroundStyle(.white)
                                            .padding(10)
                                    }
                                }
                                .pressable()
                            }
                        }
                    }
                }
            }
        }
    }

    private var strictnessRow: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Strictness", selection: $store.strictness) {
                    ForEach(NatureStrictness.allCases) { s in
                        Text(s.name).tag(s)
                    }
                }
                if !store.corrections.notNature.isEmpty || !store.corrections.moved.isEmpty {
                    Divider()
                    Button(role: .destructive) { store.clearCorrections() } label: {
                        Label("Undo my \(store.corrections.notNature.count + store.corrections.moved.count) fixes", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                Label(store.strictness.name, systemImage: "slider.horizontal.3")
                    .font(Theme.rounded(13, .bold))
            }
            Text(store.strictness.blurb)
                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { withAnimation(.snappy) { category = nil } } label: {
                    Chip(label: "Best of · \(store.shown.count)", symbol: "star.fill", selected: category == nil)
                }
                .buttonStyle(.plain)
                ForEach(NatureCategory.allCases) { c in
                    let n = store.count(c)
                    if n > 0 {
                        Button { withAnimation(.snappy) { category = c } } label: {
                            Chip(label: "\(c.short) · \(n)", symbol: c.symbol, selected: category == c)
                        }
                        .buttonStyle(.plain)
                        .haptic()
                    }
                }
            }
        }
    }

    private var grid: some View {
        let items = store.records(in: category)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(items) { r in
                Button { open = r } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { NatureThumb(id: r.id, side: 130) }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu { NatureFixMenu(id: r.id) }
            }
        }
    }

    @ViewBuilder private var mapSection: some View {
        if unlock.isPro {
            NatureRollMap(records: store.records(in: category).filter { $0.coordinate != nil }) { open = $0 }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            RootboundProLock(symbol: "map.fill", title: "Nature map",
                             message: "See every geotagged nature photo on a map: your favorite trails, beaches and peaks.",
                             context: "\(NatureRoll.title) map")
        }
    }

    private var albumsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Save to Photos albums", symbol: "rectangle.stack.badge.plus")
                Text(category.map { "Adds these \(store.count($0)) photos to \"\(NatureRoll.albumName($0))\" in the Photos app." }
                     ?? "Makes an album per category in the Photos app, like \"\(NatureRoll.albumName(.mountains))\". Photos already there are skipped.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                Button {
                    guard unlock.isPro else { planContext = "\(NatureRoll.title) albums"; showPlans = true; return }
                    Task { await saveAlbums() }
                } label: {
                    HStack {
                        Label(savingAlbums ? "Saving…" : (category == nil ? "Save all albums" : "Save this album"),
                              systemImage: unlock.isPro ? "square.and.arrow.down.on.square.fill" : "lock.fill")
                        if !unlock.isPro { Text("Pro").font(.system(size: 12, weight: .heavy, design: .rounded)) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(savingAlbums)
                if !albumNote.isEmpty {
                    Text(albumNote).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.glow)
                }
            }
        }
    }

    // MARK: Actions

    private func saveAlbums() async {
        savingAlbums = true
        defer { savingAlbums = false }
        var added = 0
        do {
            for c in (category.map { [$0] } ?? NatureCategory.allCases) {
                let ids = store.records(in: c).map(\.id)
                guard !ids.isEmpty else { continue }
                added += try await NatureRollPhotos.addToAlbum(ids, category: c)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            albumNote = added == 0 ? "Albums are already up to date." : "Added \(added) photo\(added == 1 ? "" : "s") to your albums."
        } catch {
            albumNote = "Couldn't save to Photos. Check that Rootbound has full Photos access."
        }
    }

    private func pickMorePhotos() {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
        else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in await NatureRollStore.shared.scanNow() }
        }
    }
}

// MARK: - Fixing a wrong call (long-press)

/// "Not nature", "Move to…", "Also in…": remembered by photo, never undone by a rescan.
struct NatureFixMenu: View {
    let id: String
    var onHidden: () -> Void = {}
    @ObservedObject private var store = NatureRollStore.shared

    var body: some View {
        Button(role: .destructive) { store.markNotNature(id); onHidden() } label: {
            Label("Not nature", systemImage: "eye.slash")
        }
        Menu {
            ForEach(NatureCategory.allCases) { c in
                Button { store.move(id, to: c) } label: { Label(c.name, systemImage: c.symbol) }
            }
        } label: { Label("Move to…", systemImage: "folder") }
        Menu {
            ForEach(NatureCategory.allCases.filter { !store.categories(of: id).contains($0) }) { c in
                Button { store.add(id, to: c) } label: { Label(c.name, systemImage: c.symbol) }
            }
        } label: { Label("Also in…", systemImage: "plus.square.on.square") }
        if store.isCorrected(id) {
            Button { store.undoCorrection(id) } label: { Label("Undo my change", systemImage: "arrow.uturn.backward") }
        }
    }
}

// MARK: - Thumbnail

struct NatureThumb: View {
    let id: String
    var side: CGFloat = 120
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss, Theme.forest], startPoint: .top, endPoint: .bottom)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .task(id: id) {
            let img = await NatureRollPhotos.image(id, side: side)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

// MARK: - Map (Pro)

struct NatureRollMap: View {
    let records: [NatureRecord]
    var onOpen: (NatureRecord) -> Void
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        // The 300 newest keep the map quick on big libraries.
        let shown = Array(records.prefix(300))
        Map(position: $camera) {
            ForEach(shown) { r in
                Annotation("", coordinate: r.coordinate!) {
                    Button { onOpen(r) } label: {
                        NatureThumb(id: r.id, side: 40)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls { MapCompass() }
        .overlay {
            if shown.isEmpty {
                Text("No geotagged photos here yet").font(Theme.rounded(14, .bold)).foregroundStyle(.white)
                    .padding(12).background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

// MARK: - One photo

struct NatureRollPhotoView: View {
    let record: NatureRecord
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var unlock = Unlock.shared
    @ObservedObject private var store = NatureRollStore.shared
    @State private var image: UIImage?
    @State private var place = ""
    @State private var makeHug = false
    @State private var showPlans = false
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        Color.black.opacity(0.3)
                        if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(Theme.glow) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        if let d = record.date {
                            Label(Format.dayTime(d), systemImage: "calendar").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        }
                        if !place.isEmpty {
                            Label(place, systemImage: "mappin.and.ellipse").font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.textDim)
                        }
                    }
                    FlowLayout {
                        ForEach(store.categories(of: record.id)) { c in Chip(label: c.short, symbol: c.symbol) }
                    }

                    Button { makeHug = true } label: { Label("Make this a hug", systemImage: "heart.fill") }
                        .buttonStyle(PrimaryButtonStyle())

                    Menu {
                        ForEach(store.categories(of: record.id)) { c in
                            Button(NatureRoll.albumName(c)) { Task { await add(to: c) } }
                        }
                    } label: {
                        Label(unlock.isPro ? "Add to album" : "Add to album · Pro", systemImage: unlock.isPro ? "rectangle.stack.badge.plus" : "lock.fill")
                            .font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if !note.isEmpty { Text(note).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.glow) }

                    Menu {
                        NatureFixMenu(id: record.id) { dismiss() }
                    } label: {
                        Label("Wrong? Fix it", systemImage: "hand.thumbsdown.fill")
                            .font(Theme.rounded(14, .bold)).foregroundStyle(Theme.textDim)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                .padding(Theme.pad)
            }
            .forestScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $makeHug) {
                HugLogView(editing: nil, prefillAssetID: record.id)
            }
            .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: "\(NatureRoll.title) albums")
            .task {
                image = await NatureRollPhotos.image(record.id, side: 900)
                if let c = record.coordinate { place = await Geo.placeName(for: c) }
            }
        }
    }

    private func add(to c: NatureCategory) async {
        guard unlock.isPro else { showPlans = true; return }
        do {
            let n = try await NatureRollPhotos.addToAlbum([record.id], category: c)
            note = n == 0 ? "Already in \(NatureRoll.albumName(c))." : "Added to \(NatureRoll.albumName(c))."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            note = "Couldn't save to Photos. Check that Rootbound has full Photos access."
        }
    }
}

// MARK: - Entry card (Home / Grove)

struct NatureRollEntryCard: View {
    @ObservedObject private var store = NatureRollStore.shared
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 14) {
                Image(systemName: NatureRoll.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 44, height: 44)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(NatureRoll.title).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                    Text(subtitle).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke))
            .contentShape(Rectangle())
        }
        .pressable()
        .sheet(isPresented: $show) { NatureRollView() }
    }

    private var subtitle: String {
        if store.scanning { return "Scanning your photos… \(store.done.formatted()) of \(store.total.formatted())" }
        if store.shown.isEmpty { return "Sort the nature in your camera roll, on this iPhone" }
        let today = store.onThisDay().reduce(0) { $0 + $1.items.count }
        return today > 0 ? "\(store.shown.count) nature photos · \(today) on this day" : "\(store.shown.count) nature photos"
    }
}
