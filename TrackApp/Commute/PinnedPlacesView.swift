import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// What a pin is being set as.
enum PinTarget: Identifiable, Hashable {
    case home
    case work
    /// A named spot; `replacing` is the pin being moved or renamed.
    case custom(name: String, replacing: NavPlace?)

    var id: String {
        switch self {
        case .home: return "home"
        case .work: return "work"
        case .custom(let n, let r): return "custom:\(n):\(r?.id ?? "")"
        }
    }

    var label: String {
        switch self {
        case .home: return String(localized: "Home")
        case .work: return String(localized: "Work")
        case .custom(let n, _): return n
        }
    }

    /// Saves `place` as this pin (Home / Work / a named Favorite in Navigator).
    @MainActor
    func apply(_ place: NavPlace, nav: Navigator = .shared) {
        switch self {
        case .home: nav.setHome(place)
        case .work: nav.setWork(place)
        case .custom(let name, let old):
            var p = place
            // Keep the place's own name (street, business) as the subtitle under yours.
            if !place.name.isEmpty && place.name != name { p.subtitle = place.name }
            p.name = name
            nav.pinFavorite(p, replacing: old)
        }
    }
}

// MARK: - Manage pinned places

/// Home, Work and your own named spots on a night map, with every way to set one:
/// where you are now, a search, or the start/end of a past trip.
@MainActor
struct PinnedPlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @State private var nav = Navigator.shared

    @State private var choosingSource: PinTarget?
    @State private var searching: PinTarget?
    @State private var pickingTrip: PinTarget?
    @State private var naming = false
    @State private var newName = ""
    @State private var renaming: NavPlace?
    @State private var locating = false
    @State private var note: String?
    @State private var saved = 0
    @State private var camera: MapCameraPosition = .automatic

    private var pins: [CommutePin] { CommuteStore.pins(nav) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    if !pins.isEmpty { map }
                    Text("Pin the places you drive between. Trips that start and end at pins get named for you (\u{201C}Home → Work\u{201D}) and show up as commutes in History.")
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.gold)
                    }
                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            row(.home, current: nav.home)
                            divider
                            row(.work, current: nav.work)
                            ForEach(nav.favorites) { f in
                                divider
                                row(.custom(name: f.name, replacing: f), current: f)
                            }
                        }
                    }
                    Button { newName = ""; naming = true } label: {
                        Label("Add a place", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    suggestions
                }
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 12)
            }
            .forestScreen()
            .navigationTitle(Text("Pinned places"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if locating { ToolbarItem(placement: .cancellationAction) { ProgressView().tint(Theme.glow) } }
            }
            .confirmationDialog(Text("Set \(choosingSource?.label ?? "")"), isPresented: Binding(
                get: { choosingSource != nil }, set: { if !$0 { choosingSource = nil } }), titleVisibility: .visible,
                presenting: choosingSource) { target in
                Button("Where I am now") { useCurrentLocation(target) }
                Button("Search an address") { searching = target }
                Button("Start or end of a past trip") { pickingTrip = target }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $searching) { target in
                PinSearchView(target: target) { saved += 1 }
            }
            .sheet(item: $pickingTrip) { target in
                PinFromTripView(target: target, activities: Array(activities.prefix(40))) { saved += 1 }
            }
            .alert(Text("Name this place"), isPresented: $naming) {
                TextField(String(localized: "Her place"), text: $newName)
                Button("Next") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { choosingSource = .custom(name: n, replacing: nil) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Like \u{201C}Her place\u{201D}, \u{201C}Gym\u{201D} or \u{201C}Mom's\u{201D}.")
            }
            .alert(Text("Rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(String(localized: "Name"), text: $newName)
                Button("Save") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if let old = renaming, !n.isEmpty { var p = old; p.name = n; nav.pinFavorite(p, replacing: old); saved += 1 }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: saved)
            .onAppear { fitMap() }
            .onChange(of: saved) { fitMap() }
        }
        .preferredColorScheme(.dark)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 60)
    }

    // Night map with every pin.
    private var map: some View {
        Map(position: $camera) {
            ForEach(pins) { p in
                Annotation(p.label, coordinate: p.coordinate) {
                    Image(systemName: p.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.forestDeep)
                        .frame(width: 32, height: 32)
                        .background(p.role == .custom ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.leafGradient), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .environment(\.colorScheme, .dark)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .accessibilityLabel(Text("Map of your pinned places"))
    }

    private func fitMap() {
        let cs = pins.map(\.coordinate)
        guard !cs.isEmpty else { return }
        let lats = cs.map(\.latitude), lngs = cs.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.6),
                                    longitudeDelta: max(0.02, (lngs.max()! - lngs.min()!) * 1.6))
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func row(_ target: PinTarget, current: NavPlace?) -> some View {
        let symbol: String = {
            switch target { case .home: return "house.fill"; case .work: return "briefcase.fill"; case .custom: return "mappin.circle.fill" }
        }()
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(current == nil ? Theme.textDim : Theme.forestDeep)
                .frame(width: 36, height: 36)
                .background(current == nil ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.leafGradient), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.label).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                Text(subtitle(target, current)).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Menu {
                Button { useCurrentLocation(target) } label: { Label("Where I am now", systemImage: "location.fill") }
                Button { searching = target } label: { Label("Search an address", systemImage: "magnifyingglass") }
                Button { pickingTrip = target } label: { Label("From a past trip", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                if case .custom(_, let old?) = target {
                    Divider()
                    Button { newName = old.name; renaming = old } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { nav.removeFavorite(old); saved += 1 } label: { Label("Remove", systemImage: "trash") }
                } else if current != nil {
                    Divider()
                    Button(role: .destructive) {
                        if case .home = target { nav.clearHome() } else { nav.clearWork() }
                        saved += 1
                    } label: { Label("Remove", systemImage: "trash") }
                }
            } label: {
                Text(current == nil ? String(localized: "Set") : String(localized: "Change"))
                    .font(Theme.rounded(14, .heavy))
                    .foregroundStyle(Theme.glow)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.glow.opacity(0.14), in: Capsule())
            }
            .accessibilityLabel(Text(current == nil ? "Set \(target.label)" : "Change \(target.label)"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func subtitle(_ target: PinTarget, _ p: NavPlace?) -> String {
        guard let p else { return String(localized: "Not set") }
        if case .custom = target { return p.subtitle.isEmpty ? String(localized: "Pinned") : p.subtitle }
        return [p.name, p.subtitle].filter { !$0.isEmpty && $0 != target.label }.joined(separator: " · ")
    }

    @ViewBuilder private var suggestions: some View {
        let spots = CommuteMath.frequentSpots(CommuteStore.driveTrips(Array(activities.prefix(200))), pins: pins, minCount: 2)
        if !spots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: String(localized: "From your drives"), symbol: "sparkles")
                ForEach(spots.prefix(4)) { s in
                    PinSuggestionRow(spot: s) { saved += 1 }
                }
            }
            .padding(.top, 8)
        }
    }

    private func useCurrentLocation(_ target: PinTarget) {
        locating = true
        note = nil
        Task {
            defer { locating = false }
            guard let c = await OneShotLocation().get() else {
                note = String(localized: "Couldn't get your location. Try a search instead.")
                return
            }
            let name = await Geo.placeName(for: c)
            target.apply(NavPlace(name: name.isEmpty ? target.label : name, subtitle: "", coordinate: c), nav: nav)
            saved += 1
        }
    }
}

// MARK: - Suggestion row ("You stop here a lot")

/// One unpinned spot you keep driving to or from, with one-tap Home / Work / name it.
@MainActor
struct PinSuggestionRow: View {
    let spot: CommuteMath.Spot
    var compact = false
    let onPinned: () -> Void
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.forestDeep)
                        .frame(width: 34, height: 34).background(Theme.goldGradient, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compact ? String(localized: "Pin a place you keep driving to?") : (spot.name.isEmpty ? String(localized: "A spot you stop at") : spot.name))
                            .font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(compact && !spot.name.isEmpty ? String(localized: "\(spot.name) · \(spot.count) trips") : String(localized: "\(spot.count) trips start or end here"))
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if compact {
                        Button { CommuteStore.dismiss(spot); onPinned() } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.textDim)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("Not now"))
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
            }
        }
        .alert(Text("Name this place"), isPresented: $naming) {
            TextField(String(localized: "Her place"), text: $name)
            Button("Pin") {
                let n = name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                PinTarget.custom(name: n, replacing: nil).apply(place)
                onPinned()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var place: NavPlace { NavPlace(name: spot.name, subtitle: "", coordinate: spot.coordinate) }

    @ViewBuilder private var buttons: some View {
        pill(String(localized: "Home"), "house.fill") { PinTarget.home.apply(place); onPinned() }
        pill(String(localized: "Work"), "briefcase.fill") { PinTarget.work.apply(place); onPinned() }
        pill(String(localized: "Name it…"), "pencil") { name = ""; naming = true }
    }

    private func pill(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.rounded(13, .bold)).foregroundStyle(Theme.glow)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(Theme.glow.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pin by search

@MainActor
struct PinSearchView: View {
    let target: PinTarget
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.glow).accessibilityHidden(true)
                    TextField("", text: $search.query, prompt: Text("Search a place or address").foregroundStyle(Theme.textDim))
                        .font(Theme.rounded(17, .semibold)).foregroundStyle(.white)
                        .focused($typing).autocorrectionDisabled().submitLabel(.search)
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(search.results, id: \.self) { c in
                            Button {
                                Task {
                                    if let p = await search.resolve(c) { target.apply(p); onSaved(); dismiss() }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.glow)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).font(Theme.rounded(16, .bold)).foregroundStyle(.white).lineLimit(2)
                                        if !c.subtitle.isEmpty { Text(c.subtitle).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim).lineLimit(2) }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, Theme.pad).padding(.top, 12)
            .background(Theme.forestDeep.ignoresSafeArea())
            .navigationTitle(Text("Set \(target.label)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                search.focus(near: RoamrContext.tracker?.lastKnownCoordinate)
                typing = true
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pin from a past trip

@MainActor
struct PinFromTripView: View {
    private struct TripEnds: Identifiable {
        let activity: Activity
        let trip: CommuteMath.Trip
        var id: UUID { trip.id }
    }

    let target: PinTarget
    let activities: [Activity]
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let trips = activities.compactMap { a in CommuteStore.trip(a).map { TripEnds(activity: a, trip: $0) } }
                    if trips.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "map").font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.glow)
                                Text("No trips yet").font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                                Text("Record a drive and you can pin where it started or ended.")
                                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                    ForEach(trips) { e in
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("\(e.activity.displayTitle) · \(Format.dayTime(e.activity.start))", systemImage: e.activity.kind.symbol)
                                    .font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
                                endButton(String(localized: "Started"), e.trip.fromName, e.trip.from)
                                endButton(String(localized: "Ended"), e.trip.toName, e.trip.to)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pad).padding(.vertical, 12)
            }
            .forestScreen()
            .navigationTitle(Text("Set \(target.label)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func endButton(_ which: String, _ name: String, _ c: CLLocationCoordinate2D) -> some View {
        Button {
            target.apply(NavPlace(name: name.isEmpty ? target.label : name, subtitle: "", coordinate: c))
            onSaved()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(which).font(Theme.rounded(11, .heavy)).foregroundStyle(Theme.textDim)
                    Text(name.isEmpty ? String(localized: "Unnamed spot") : name).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.glow)
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Pin where it \(which.lowercased()): \(name)"))
    }
}
