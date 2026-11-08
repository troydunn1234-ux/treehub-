import SwiftUI

/// Pick which apps live on your wall (the main Apps screen), browse by category,
/// and drag the wall chips to reorder.
struct AppPicker: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var category: AppCategory = .all
    @FocusState private var searching: Bool

    private let cols = [GridItem(.flexible(), spacing: Look.S.m), GridItem(.flexible(), spacing: Look.S.m),
                        GridItem(.flexible(), spacing: Look.S.m)]

    private var results: [StreamingApp] {
        store.catalog.filter { app in
            (query.isEmpty || app.name.localizedCaseInsensitiveContains(query)) && category.contains(app.name)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AuroraBackground().ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Look.S.l, pinnedViews: [.sectionHeaders]) {
                    header
                    wall
                    Section {
                        grid
                    } header: {
                        filters
                    }
                }
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)

            doneBar
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: store.favorites)
        .sensoryFeedback(.selection, trigger: category)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Look.S.s) {
            HStack {
                HStack(spacing: 6) {
                    LiveDot(color: Look.cyan, size: 7)
                    CapsLabel("App wall", color: Look.cyan)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).glassCircle()
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel("Close")
            }
            Text("Pick your apps.")
                .font(Look.display(40)).tracking(-1.2)
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                Text("\(store.favorites.count)")
                    .font(Look.font(15, .black)).foregroundStyle(Look.accentH)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.favorites.count)
                Text(store.favorites.count == 1 ? "on your wall" : "on your wall · \(store.catalog.count) to explore")
                    .font(Look.font(15, .semibold)).foregroundStyle(Look.dim)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 20)
        .padding(.top, Look.S.s)
    }

    // MARK: Your wall (reorderable)

    private var wall: some View {
        VStack(alignment: .leading, spacing: Look.S.s) {
            SectionHeader(title: "Your wall") {
                Text("Hold & drag to reorder").font(Look.font(11, .bold)).foregroundStyle(Look.faint)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: Look.S.s) {
                    if store.favoriteApps.isEmpty {
                        Text("Tap apps below to add them")
                            .font(Look.font(14, .bold)).foregroundStyle(Look.dim)
                            .padding(.horizontal, Look.S.l).frame(height: 48)
                            .background(Capsule().strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 6])))
                    }
                    ForEach(store.favoriteApps) { app in
                        WallChip(app: app) { withAnimation(spring) { store.toggleFavorite(app) } }
                            .draggable(app.name) { WallChip(app: app, action: {}).opacity(0.9) }
                            .dropDestination(for: String.self) { items, _ in move(items.first, before: app.name) }
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .animation(spring, value: store.favorites)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func move(_ name: String?, before target: String) -> Bool {
        guard let name, name != target,
              let from = store.favorites.firstIndex(of: name),
              let to = store.favorites.firstIndex(of: target) else { return false }
        withAnimation(spring) {
            store.favorites.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        return true
    }

    // MARK: Search + categories (pinned)

    private var filters: some View {
        VStack(spacing: Look.S.m) {
            HStack(spacing: Look.S.s) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(searching ? Look.cyan : Look.dim)
                TextField("", text: $query, prompt: Text("Search \(store.catalog.count) apps").foregroundStyle(Look.faint))
                    .font(Look.font(16, .bold)).foregroundStyle(.white)
                    .focused($searching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Look.dim)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Look.S.l)
            .frame(height: 50)
            .glassCapsule(tint: searching ? Look.cyan : .white, glow: searching ? Look.cyan : nil, material: true)
            .animation(.easeOut(duration: 0.2), value: searching)
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: Look.S.s) {
                    ForEach(AppCategory.allCases) { c in
                        CategoryChip(category: c, count: store.catalog.filter { c.contains($0.name) }.count,
                                     selected: category == c) {
                            withAnimation(spring) { category = c }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, Look.S.s)
        .background {
            LinearGradient(colors: [Look.bg.opacity(0.96), Look.bg.opacity(0.85), Look.bg.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -18)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Grid

    @ViewBuilder private var grid: some View {
        let apps = results
        if apps.isEmpty {
            VStack(spacing: Look.S.m) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Look.accent)
                Text("Nothing called \u{201C}\(query)\u{201D}").font(Look.font(18, .heavy)).foregroundStyle(.white)
                Text("Try another name or category.").font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            LazyVGrid(columns: cols, spacing: Look.S.m) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                    PickerTile(app: app, selected: store.favorites.contains(app.name), index: i) {
                        withAnimation(spring) { store.toggleFavorite(app) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .id(category)   // re-run the pop-in when switching categories
        }
    }

    // MARK: Done

    private var doneBar: some View {
        Button { dismiss() } label: {
            HStack(spacing: Look.S.s) {
                Image(systemName: "checkmark").font(.system(size: 15, weight: .black))
                Text("Done · \(store.favorites.count) apps")
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, Look.S.xl)
        .padding(.bottom, Look.S.s)
        .background(
            LinearGradient(colors: [Look.bgDeep.opacity(0), Look.bgDeep.opacity(0.9), Look.bgDeep], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
        .accessibilityLabel("Done, \(store.favorites.count) apps on your wall")
    }

    private var spring: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.72) }
}

// MARK: - Pieces

/// A small app chip on "Your wall". Tap to remove, hold to drag.
private struct WallChip: View {
    let app: StreamingApp
    let action: () -> Void

    var body: some View {
        let c0 = app.colors.first ?? Look.violet
        let c1 = app.colors.count > 1 ? app.colors[1] : Look.bg
        Button(action: action) {
            HStack(spacing: 8) {
                Text(String(app.name.prefix(1)).uppercased())
                    .font(Look.display(15)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [c0, c1], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                Text(app.name).font(Look.font(14, .heavy)).foregroundStyle(.white).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 10, weight: .black)).foregroundStyle(Look.dim)
            }
            .padding(.leading, 9).padding(.trailing, 14)
            .frame(height: 48)
            .glassCapsule(tint: c0, glow: c0, strength: 1.6)
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel("\(app.name), on your wall. Tap to remove")
    }
}

private struct CategoryChip: View {
    let category: AppCategory
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon).font(.system(size: 13, weight: .heavy))
                Text(category.title).font(Look.font(14, .heavy))
                Text("\(count)").font(Look.font(11, .black))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(selected ? Color.white.opacity(0.25) : Color.white.opacity(0.08), in: Capsule())
            }
            .foregroundStyle(selected ? .white : Look.dim)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                if selected {
                    Capsule().fill(LinearGradient(colors: [category.tint, category.tint.opacity(0.55)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: category.tint.opacity(0.6), radius: 10, y: 3)
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0.4 : 0.12), lineWidth: 1))
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel("\(category.title), \(count) apps")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A colorful mini poster. Glows and gets a check when it's on your wall.
private struct PickerTile: View {
    let app: StreamingApp
    let selected: Bool
    let index: Int
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let c0 = app.colors.first ?? Look.violet
        let c1 = app.colors.count > 1 ? app.colors[1] : Look.bg
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [c0, c1], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(app.name.prefix(1)).uppercased())
                    .font(.system(size: 104, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .fixedSize()
                    .offset(x: 18, y: -14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 110)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                Text(app.name)
                    .font(Look.font(13, .black)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .padding(10)
                if !selected { Color.black.opacity(0.28) }
            }
            .frame(height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topLeading) { badge.padding(8) }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.white.opacity(0.10)),
                                  lineWidth: selected ? 2.5 : 1)
            }
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(c0).blur(radius: 14).opacity(0.55)
                }
            }
            .scaleEffect(selected ? 1 : 0.95)
            .saturation(selected ? 1 : 0.75)
        }
        .buttonStyle(SquishStyle(scale: 0.9))
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : 0.7)
        .offset(y: shown || reduceMotion ? 0 : 20)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68).delay(Double(min(index, 14)) * 0.025)) { shown = true }
        }
        .accessibilityLabel(selected ? "\(app.name), in your apps" : "Add \(app.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var badge: some View {
        ZStack {
            Circle().fill(selected ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Color.black.opacity(0.35)))
            Circle().strokeBorder(Color.white.opacity(selected ? 0.7 : 0.35), lineWidth: 1.2)
            Image(systemName: selected ? "checkmark" : "plus")
                .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 24, height: 24)
        .scaleEffect(selected ? 1.12 : 1)
        .shadow(color: selected ? Look.magenta.opacity(0.7) : .clear, radius: 6)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.45), value: selected)
    }
}

// MARK: - Categories

enum AppCategory: String, CaseIterable, Identifiable {
    case all, popular, moviesTV, free, sports, kids, music, news
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .popular: "Popular"
        case .moviesTV: "Movies & TV"
        case .free: "Free"
        case .sports: "Sports"
        case .kids: "Kids"
        case .music: "Music"
        case .news: "News"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .popular: "flame.fill"
        case .moviesTV: "film.fill"
        case .free: "gift.fill"
        case .sports: "sportscourt.fill"
        case .kids: "teddybear.fill"
        case .music: "music.note"
        case .news: "newspaper.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all: Look.violet
        case .popular: Color(red: 1, green: 0.45, blue: 0.2)
        case .moviesTV: Look.magenta
        case .free: Look.live
        case .sports: Color(red: 0.2, green: 0.6, blue: 1)
        case .kids: Color(red: 1, green: 0.75, blue: 0.2)
        case .music: Look.cyan
        case .news: Color(red: 0.75, green: 0.75, blue: 0.85)
        }
    }

    func contains(_ name: String) -> Bool {
        switch self {
        case .all: return true
        case .moviesTV:
            if Self.sets[.popular, default: []].contains(name) { return true }
            return ![AppCategory.sports, .kids, .music, .news].contains { Self.sets[$0, default: []].contains(name) }
        default: return Self.sets[self]?.contains(name) ?? false
        }
    }

    private static let sets: [AppCategory: Set<String>] = [
        .popular: ["Netflix", "YouTube", "Prime Video", "Hulu", "Disney+", "HBO Max", "Peacock", "Paramount+", "Apple TV+",
                   "YouTube TV", "Tubi", "Pluto TV", "Sling TV", "fuboTV", "Plex", "discovery+", "STARZ", "AMC+"],
        .free: ["Tubi", "Pluto TV", "Crackle", "Plex", "XUMO", "Distro TV", "WatchFree+", "WatchFree+ On Demand", "Free Movies+",
                "FilmRise", "Fawesome.tv", "Local Now", "Haystack TV", "Sensical", "Kidoodle.tv", "Free Games by PlayWorks",
                "Cinehouse", "Smart Cinema", "YouTube", "Vevo", "RedBox", "Popstar TV", "Newsy", "Run:Time en Español"],
        .sports: ["CBS Sports", "FOX Sports", "DAZN", "fuboTV", "Fite TV", "World Poker Tour", "Adventure Sports Network",
                  "Outside TV", "Motorvision TV", "MyOutdoorTV", "Outdoor America", "Into The Outdoors", "Run The Fut Market"],
        .kids: ["PBS Kids", "CoCoMelon", "Baby Einstein", "Sesame Street", "HappyKids.tv", "Kidoodle.tv", "LEGO TV",
                "Toon Goggles", "Ninja Kidz TV", "Zoomi", "Sensical", "PlayWorks Kids", "Annoying Orange", "Dan TDM",
                "Ssundee", "Best of Roblox", "FamilyTime", "Adventure 2 Learning", "Disney+"],
        .music: ["Pandora", "iHeartRadio", "Sirius XM", "Amazon Music", "Vevo", "Party Tyme Karaoke", "Popstar TV",
                 "Wu Tang Collection", "TikTok"],
        .news: ["CBS News", "Newsy", "Court TV", "The Daily Wire", "Local Now", "Haystack TV", "Fox Nation", "US Weekly TV"],
    ]
}
