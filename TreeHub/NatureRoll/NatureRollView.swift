import SwiftUI
import Photos
import MapKit
import UIKit

/// The Nature Roll screen: your camera roll's nature, sorted on this iPhone.
/// Free: scanning, category chips, the Best of gallery, "On this day", the photo viewer, "Make this a hug".
/// Pro: the map and Photos albums.
struct NatureRollView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = NatureRollStore.shared
    @ObservedObject private var unlock = Unlock.shared
    @State private var category: NatureCategory?
    @State private var mode = 0
    @State private var viewer: NatureViewerRequest?
    @State private var showPlans = false
    @State private var planContext = "Nature Roll"
    @State private var albumNote = ""
    @State private var savingAlbums = false
    @State private var albumsSaved = 0
    /// Shown inside a sheet (Home / Grove) with a Done button.
    var showsDone = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RB.l) {
                    RBScreenHeader(title: NatureRoll.title, subtitle: subtitle)
                        .padding(.horizontal, RB.screen)
                    if !store.canRead || !store.hasStarted {
                        welcomeCard.padding(.horizontal, RB.screen)
                    } else {
                        scanStatus.padding(.horizontal, RB.screen)
                        if !store.records.isEmpty {
                            onThisDay
                            controls.padding(.horizontal, RB.screen)
                            chips
                            if store.shown.isEmpty {
                                strictEmpty.padding(.horizontal, RB.screen)
                            } else if mode == 0 {
                                gallery
                            } else {
                                mapSection.padding(.horizontal, RB.screen)
                            }
                            albumsCard.padding(.horizontal, RB.screen)
                        } else if store.scanning {
                            skeletonGallery
                        } else {
                            RBCard {
                                RBEmptyState(symbol: "leaf", title: "No nature found yet",
                                             hint: "Shoot a trail, a view or a sunset and it shows up here next time you open Rootbound.",
                                             actionTitle: "Scan again") { Task { await store.scanNow() } }
                            }
                            .padding(.horizontal, RB.screen)
                        }
                    }
                }
                .padding(.bottom, RB.xxl + RB.xl)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .fullScreenCover(item: $viewer) { req in NatureRollViewer(records: req.records, startID: req.startID) }
            .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: planContext)
            .onAppear { store.scanIfAllowed() }
            .sensoryFeedback(.selection, trigger: category)
            .sensoryFeedback(.selection, trigger: mode)
            .sensoryFeedback(.success, trigger: albumsSaved)
        }
    }

    private var subtitle: String {
        store.shown.isEmpty ? "The nature in your camera roll" : "\(store.shown.count.formatted()) nature photos"
    }

    // MARK: Sections

    private var welcomeCard: some View {
        RBCard {
            VStack(alignment: .leading, spacing: RB.m) {
                Image(systemName: NatureRoll.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 64, height: 64)
                    .background(Theme.glow.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)
                Text("Find the trails, peaks, sunsets and wildlife you've already shot.")
                    .font(RB.text(.title3, .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Sorted on this iPhone by its built-in image recognition. Nothing is uploaded.", systemImage: "lock.shield.fill")
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Works with \"Limited\" access too: share only the photos you want.", systemImage: "hand.raised.fill")
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                if store.auth == .denied || store.auth == .restricted {
                    Text("Photo access is off for Rootbound. Turn it on in Settings › Rootbound › Photos.")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: {
                        Label("Open Settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(RBPrimaryButtonStyle())
                } else {
                    Button { Task { await store.scanNow() } } label: {
                        Label("Scan my photos", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(RBPrimaryButtonStyle())
                }
            }
        }
    }

    /// One calm status line: scanning progress (with Cancel) or "Up to date" (with Scan new).
    private var scanStatus: some View {
        VStack(alignment: .leading, spacing: RB.s) {
            if store.scanning {
                HStack(spacing: RB.s) {
                    Label(store.total == 0 ? "Getting ready…" : "Scanning \(store.done.formatted()) of \(store.total.formatted())",
                          systemImage: "sparkle.magnifyingglass")
                        .font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                        .monospacedDigit()
                    Spacer(minLength: RB.s)
                    Button("Cancel") { store.cancel() }
                        .font(RB.text(.subheadline, .bold))
                        .frame(minHeight: 44)
                }
                ProgressView(value: Double(store.done), total: Double(max(store.total, 1)))
                    .tint(Theme.glow)
                    .accessibilityLabel("Scan progress")
                Text("You can leave this screen; it picks up where it stopped.")
                    .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
            } else {
                HStack(spacing: RB.s) {
                    Label(store.lastScan.map { "Up to date · \(Format.dayTime($0))" } ?? "Not scanned yet",
                          systemImage: "checkmark.seal.fill")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.textDim)
                    Spacer(minLength: RB.s)
                    Button { Task { await store.scanNow() } } label: {
                        Label("Scan new", systemImage: "arrow.clockwise")
                    }
                    .font(RB.text(.footnote, .bold))
                    .frame(minHeight: 44)
                }
            }
            if store.auth == .limited {
                Button { pickMorePhotos() } label: {
                    Label("You shared some photos. Choose more…", systemImage: "plus.rectangle.on.rectangle")
                        .font(RB.text(.footnote, .bold))
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal, RB.m)
        .padding(.vertical, RB.xs)
        .rbInner()
    }

    @ViewBuilder private var onThisDay: some View {
        let days = store.onThisDay()
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: RB.m) {
                RBSectionTitle(title: "On this day", symbol: "calendar")
                    .padding(.horizontal, RB.screen)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: RB.m) {
                        ForEach(days, id: \.year) { day in
                            ForEach(day.items.prefix(6)) { r in
                                Button { openViewer(r, in: days.flatMap { Array($0.items.prefix(6)) }) } label: {
                                    memory(r, year: day.year)
                                }
                                .pressable()
                                .contextMenu { NatureFixMenu(id: r.id) }
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, RB.screen, for: .scrollContent)
            }
        }
    }

    private func memory(_ r: NatureRecord, year: Int) -> some View {
        let ago = Calendar.current.component(.year, from: Date()) - year
        return ZStack(alignment: .bottomLeading) {
            NatureThumb(id: r.id, side: 160)
                .frame(width: 150, height: 200)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            Text(ago == 1 ? "1 year ago" : "\(ago) years ago")
                .font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                .padding(RB.m)
        }
        .frame(width: 150, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: RB.radius - 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RB.radius - 4, style: .continuous).strokeBorder(RB.stroke))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nature photo from \(ago == 1 ? "1 year" : "\(ago) years") ago")
    }

    /// Photos / Map switch and how strict the sorting is.
    private var controls: some View {
        VStack(alignment: .leading, spacing: RB.s) {
            PillSwitcher(options: [.init(id: 0, label: "Photos", symbol: "square.grid.3x3.fill"),
                                   .init(id: 1, label: "Map", symbol: "map.fill")],
                         selection: $mode)
            HStack(alignment: .firstTextBaseline, spacing: RB.s) {
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
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text(store.strictness.name)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(RB.text(.subheadline, .bold))
                    .foregroundStyle(Theme.glow)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Strictness: \(store.strictness.name)")
                Text(store.strictness.blurb)
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RB.s) {
                Button { withAnimation(.snappy) { category = nil } } label: {
                    RBChip(label: "Best of", symbol: "star.fill", selected: category == nil, count: store.shown.count, tint: Theme.gold)
                }
                .buttonStyle(.plain)
                ForEach(NatureCategory.allCases) { c in
                    let n = store.count(c)
                    if n > 0 {
                        Button { withAnimation(.snappy) { category = c } } label: {
                            RBChip(label: c.short, symbol: c.symbol, selected: category == c, count: n)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .contentMargins(.horizontal, RB.screen, for: .scrollContent)
    }

    // MARK: Gallery (full-bleed)

    /// Edge-to-edge grid. "Best of" opens with its top three as a big mosaic.
    private var gallery: some View {
        let items = store.records(in: category)
        let featured: [NatureRecord] = category == nil && items.count >= 6 ? Array(items.prefix(3)) : []
        let rest: [NatureRecord] = featured.isEmpty ? items : Array(items.dropFirst(3))
        return VStack(spacing: 2) {
            if featured.count == 3 { mosaic(featured, list: items) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(rest) { r in tile(r, list: items, side: 150) }
            }
        }
        .animation(.snappy, value: category)
    }

    /// The three best photos: one big square and two small ones beside it.
    private func mosaic(_ f: [NatureRecord], list: [NatureRecord]) -> some View {
        HStack(alignment: .top, spacing: 2) {
            tile(f[0], list: list, side: 320)
                .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 2)
                .overlay(alignment: .topLeading) {
                    Label("Best of", systemImage: "star.fill")
                        .font(RB.text(.caption, .bold))
                        .foregroundStyle(Theme.forestDeep)
                        .padding(.horizontal, RB.s).padding(.vertical, 5)
                        .background(Theme.gold, in: Capsule())
                        .padding(RB.s)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            VStack(spacing: 2) {
                tile(f[1], list: list, side: 160)
                tile(f[2], list: list, side: 160)
            }
            .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 2)
        }
    }

    private func tile(_ r: NatureRecord, list: [NatureRecord], side: CGFloat) -> some View {
        Button { openViewer(r, in: list) } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { NatureThumb(id: r.id, side: side) }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { NatureFixMenu(id: r.id) }
        .accessibilityLabel(Self.label(for: r, store: store))
        .accessibilityHint("Opens the photo")
    }

    /// Placeholder tiles while the first scan runs.
    private var skeletonGallery: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(0..<12, id: \.self) { _ in
                RBSkeletonBlock().aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Looking through your photos")
    }

    private var strictEmpty: some View {
        RBCard {
            RBEmptyState(symbol: "slider.horizontal.3", title: "Nothing passes \(store.strictness.name) right now",
                         hint: "Looser sorting shows outdoor scenes and park shots too.",
                         actionTitle: store.strictness == .everything ? nil : "Show more") {
                store.strictness = store.strictness == .strict ? .balanced : .everything
            }
        }
    }

    @ViewBuilder private var mapSection: some View {
        if unlock.isPro {
            let list = store.records(in: category).filter { $0.coordinate != nil }
            NatureRollMap(records: list) { r in openViewer(r, in: list) }
                .frame(height: 440)
                .clipShape(RoundedRectangle(cornerRadius: RB.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(RB.stroke))
        } else {
            RootboundProLock(symbol: "map.fill", title: "Nature map",
                             message: "See every geotagged nature photo on a map: your favorite trails, beaches and peaks.",
                             context: "\(NatureRoll.title) map")
        }
    }

    private var albumsCard: some View {
        RBCard {
            VStack(alignment: .leading, spacing: RB.m) {
                RBSectionTitle(title: "Save to Photos albums", symbol: "rectangle.stack.badge.plus")
                Text(category.map { "Adds these \(store.count($0)) photos to \"\(NatureRoll.albumName($0))\" in the Photos app." }
                     ?? "Makes an album per category in the Photos app, like \"\(NatureRoll.albumName(.mountains))\". Photos already there are skipped.")
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    guard unlock.isPro else { planContext = "\(NatureRoll.title) albums"; showPlans = true; return }
                    Task { await saveAlbums() }
                } label: {
                    HStack(spacing: RB.s) {
                        if savingAlbums { ProgressView().tint(Theme.forestDeep) }
                        Label(savingAlbums ? "Saving…" : (category == nil ? "Save all albums" : "Save this album"),
                              systemImage: unlock.isPro ? "square.and.arrow.down.on.square.fill" : "lock.fill")
                        if !unlock.isPro { Text("Pro").font(RB.text(.caption, .heavy)) }
                    }
                }
                .buttonStyle(RBPrimaryButtonStyle())
                .disabled(savingAlbums)
                if !albumNote.isEmpty {
                    Label(albumNote, systemImage: "checkmark.circle.fill")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.glow)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: Actions

    /// Opens the viewer on `r`, able to swipe through the photos around it in `list`.
    private func openViewer(_ r: NatureRecord, in list: [NatureRecord]) {
        let i = list.firstIndex(where: { $0.id == r.id }) ?? 0
        // A window around the photo keeps the viewer quick on big libraries.
        let lo = max(0, i - 150), hi = min(list.count, i + 150)
        let window = list.isEmpty ? [r] : Array(list[lo..<hi])
        viewer = NatureViewerRequest(records: window.contains(where: { $0.id == r.id }) ? window : [r], startID: r.id)
    }

    @MainActor
    static func label(for r: NatureRecord, store: NatureRollStore) -> String {
        var parts = ["Nature photo"]
        if let c = store.categories(of: r.id).first { parts.append(c.short) }
        if let d = r.date { parts.append(d.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: ", ")
    }

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
            albumsSaved += 1
            withAnimation { albumNote = added == 0 ? "Albums are already up to date." : "Added \(added) photo\(added == 1 ? "" : "s") to your albums." }
        } catch {
            withAnimation { albumNote = "Couldn't save to Photos. Check that Rootbound has full Photos access." }
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

/// What the viewer shows: a run of photos and the one to start on.
struct NatureViewerRequest: Identifiable {
    let id = UUID()
    let records: [NatureRecord]
    let startID: String
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

/// A camera-roll photo cropped to fill; a soft placeholder until it loads.
struct NatureThumb: View {
    let id: String
    var side: CGFloat = 120
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .task(id: id) {
            let img = await NatureRollPhotos.image(id, side: side)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
        .accessibilityHidden(true)
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
                        NatureThumb(id: r.id, side: 44)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Nature photo")
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls { MapCompass() }
        .overlay {
            if shown.isEmpty {
                Label("No geotagged photos here yet", systemImage: "mappin.slash")
                    .font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, RB.l).padding(.vertical, RB.m)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

// MARK: - Viewer

/// Full-screen photo viewer: swipe between photos, tap to hide the controls.
/// Date and place on top; categories, "Make this a hug", albums (Pro) and fixes at the bottom.
struct NatureRollViewer: View {
    let records: [NatureRecord]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var unlock = Unlock.shared
    @ObservedObject private var store = NatureRollStore.shared
    @State private var current: String?
    @State private var place = ""
    @State private var hugFor: NatureHugPrefill?
    @State private var showPlans = false
    @State private var note = ""
    @State private var chrome = true
    @State private var hidden: Set<String> = []
    @State private var added = 0
    private let startID: String

    init(records: [NatureRecord], startID: String) {
        self.records = records
        self.startID = startID
        _current = State(initialValue: startID)
    }

    private var visible: [NatureRecord] { records.filter { !hidden.contains($0.id) } }
    private var record: NatureRecord? { visible.first(where: { $0.id == current }) ?? visible.first }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            pager
            if chrome {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chrome)
        .preferredColorScheme(.dark)
        .sheet(item: $hugFor) { p in HugLogView(editing: nil, prefillAssetID: p.id) }
        .paywall(isPresented: $showPlans, spec: RootboundPro.spec, context: "\(NatureRoll.title) albums")
        .task(id: current) { await loadPlace() }
        .sensoryFeedback(.selection, trigger: current)
        .sensoryFeedback(.success, trigger: added)
    }

    private var pager: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(visible) { r in
                        NatureFullImage(id: r.id)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(r.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .onAppear { proxy.scrollTo(startID) }
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() } }
            .accessibilityAction(named: chrome ? "Hide controls" : "Show controls") { chrome.toggle() }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: RB.m) {
            RBIconButton(symbol: "xmark", label: "Close") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                if let d = record?.date {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                }
                if !place.isEmpty {
                    Text(place).font(RB.text(.caption, .semibold)).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if visible.count > 1, let i = visible.firstIndex(where: { $0.id == record?.id }) {
                Text("\(i + 1) / \(visible.count)")
                    .font(RB.text(.caption, .bold)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, RB.s).padding(.vertical, RB.xs)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Photo \(i + 1) of \(visible.count)")
            }
        }
        .padding(.horizontal, RB.l)
        .padding(.top, RB.s)
        .padding(.bottom, RB.xl)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: RB.m) {
            if let r = record {
                let cats = store.categories(of: r.id)
                if !cats.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(cats) { c in RBInfoChip(text: c.short, symbol: c.symbol, tint: .white) }
                    }
                }
                if !note.isEmpty {
                    Label(note, systemImage: "checkmark.circle.fill")
                        .font(RB.text(.footnote, .semibold)).foregroundStyle(Theme.glow)
                        .transition(.opacity)
                }
                Button { hugFor = NatureHugPrefill(id: r.id) } label: {
                    Label("Make this a hug", systemImage: "heart.fill")
                }
                .buttonStyle(RBPrimaryButtonStyle())
                HStack(spacing: RB.s) {
                    Menu {
                        ForEach(cats) { c in
                            Button(NatureRoll.albumName(c)) { Task { await add(r, to: c) } }
                        }
                    } label: {
                        Label(unlock.isPro ? "Add to album" : "Album · Pro", systemImage: unlock.isPro ? "rectangle.stack.badge.plus" : "lock.fill")
                            .font(RB.text(.subheadline, .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Menu {
                        NatureFixMenu(id: r.id) { hide(r) }
                    } label: {
                        Label("Fix", systemImage: "hand.thumbsdown.fill")
                            .font(RB.text(.subheadline, .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityHint("Mark as not nature or move to another category")
                }
            }
        }
        .padding(.horizontal, RB.l)
        .padding(.top, RB.xxl)
        .padding(.bottom, RB.s)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func loadPlace() async {
        place = ""
        guard let c = record?.coordinate else { return }
        let id = record?.id
        let name = await Geo.placeName(for: c)
        if record?.id == id { place = name }
    }

    /// "Not nature": take it out of this run and move on (close when it was the last one).
    private func hide(_ r: NatureRecord) {
        let i = visible.firstIndex(where: { $0.id == r.id }) ?? 0
        hidden.insert(r.id)
        let left = visible
        guard !left.isEmpty else { dismiss(); return }
        current = left[min(i, left.count - 1)].id
    }

    private func add(_ r: NatureRecord, to c: NatureCategory) async {
        guard unlock.isPro else { showPlans = true; return }
        do {
            let n = try await NatureRollPhotos.addToAlbum([r.id], category: c)
            added += 1
            withAnimation { note = n == 0 ? "Already in \(NatureRoll.albumName(c))." : "Added to \(NatureRoll.albumName(c))." }
        } catch {
            withAnimation { note = "Couldn't save to Photos. Check that Rootbound has full Photos access." }
        }
    }
}

/// "Make this a hug" from one photo (its PHAsset id).
struct NatureHugPrefill: Identifiable {
    let id: String
}

/// One photo, fitted to the screen (loads a sharp copy; a spinner-free dark placeholder until then).
struct NatureFullImage: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().transition(.opacity)
            } else {
                NatureThumb(id: id, side: 120)
                    .aspectRatio(1, contentMode: .fit)
                    .blur(radius: 12)
                    .opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: id) {
            let img = await NatureRollPhotos.image(id, side: 900)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nature photo")
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Entry card (Home / Grove)

struct NatureRollEntryCard: View {
    @ObservedObject private var store = NatureRollStore.shared
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            RBCard {
                VStack(alignment: .leading, spacing: RB.m) {
                    RBNavRow(symbol: NatureRoll.symbol, title: NatureRoll.title, detail: subtitle)
                    if store.shown.count >= 3 {
                        HStack(spacing: 4) {
                            ForEach(store.best.prefix(4)) { r in
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { NatureThumb(id: r.id, side: 90) }
                                    .clipShape(RoundedRectangle(cornerRadius: RB.inner - 4, style: .continuous))
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
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
