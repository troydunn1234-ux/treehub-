import SwiftUI
import MapKit
import CoreLocation

// MARK: - Button

/// Round "Directions" button for the Track map.
struct DirectionsButton: View {
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(active ? Theme.forestDeep : .white)
                .frame(width: 44, height: 44)
                .background(active ? AnyShapeStyle(Theme.glow) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                .shadow(color: active ? Theme.glow.opacity(0.6) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Directions")
    }
}

// MARK: - Search

@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespaces).isEmpty { results = []; completer.cancel() }
            else { completer.queryFragment = query }
        }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func focus(near c: CLLocationCoordinate2D?) {
        guard let c else { return }
        completer.region = MKCoordinateRegion(center: c, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(12))
        Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ c: MKLocalSearchCompletion) async -> NavPlace? {
        let res = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start()
        guard let item = res?.mapItems.first else { return nil }
        var p = NavPlace(item)
        if !c.title.isEmpty { p.name = c.title }
        if p.subtitle.isEmpty { p.subtitle = c.subtitle }
        return p
    }
}

// MARK: - Sheet: search → preview → Go

@MainActor
struct DirectionsSheet: View {
    @Bindable var nav: Navigator
    let origin: CLLocationCoordinate2D?
    let onGo: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 14) {
            header
            if nav.phase == .preview || nav.phase == .planning, let dest = nav.destination {
                preview(dest)
            } else {
                searchPane
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .background(Theme.forestDeep.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            search.focus(near: origin)
            if Navigator.demo { Task { await nav.plan(to: Navigator.demoPlace, from: origin) } }
            else if nav.phase != .preview { typing = true }
        }
    }

    private var header: some View {
        HStack {
            Text(nav.phase == .preview ? "Pick a route" : "Where to?")
                .font(Theme.title(30)).foregroundStyle(.white)
            Spacer()
            Button {
                if nav.phase == .preview || nav.phase == .planning { nav.cancel() } else { dismiss() }
            } label: {
                Image(systemName: nav.phase == .preview ? "chevron.backward" : "xmark")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(nav.phase == .preview ? "Back to search" : "Close")
        }
    }

    // Search

    private var searchPane: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.glow)
                TextField("", text: $search.query, prompt: Text("Search a place or address").foregroundStyle(Theme.textDim))
                    .font(Theme.rounded(17, .semibold)).foregroundStyle(.white)
                    .focused($typing).submitLabel(.search)
                    .autocorrectionDisabled()
                if !search.query.isEmpty {
                    Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textDim) }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(typing ? Theme.glow.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1.5))

            modePicker

            HStack(spacing: 10) {
                pinChip("Home", "house.fill", nav.home)
                pinChip("Work", "briefcase.fill", nav.work)
            }

            if let e = nav.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.gold)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if search.query.isEmpty {
                        if !nav.recents.isEmpty { sectionLabel("RECENT") }
                        ForEach(nav.recents) { p in
                            placeRow(title: p.name, subtitle: p.subtitle, icon: "clock.arrow.circlepath") { go(p) }
                                .contextMenu {
                                    pinMenu(p)
                                    Button("Remove", role: .destructive) { nav.removeRecent(p) }
                                }
                        }
                        if nav.recents.isEmpty {
                            Text("Type a place. Long-press a result to save it as Home or Work.")
                                .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                        }
                    } else {
                        ForEach(search.results, id: \.self) { c in
                            placeRow(title: c.title, subtitle: c.subtitle, icon: "mappin.circle.fill") {
                                Task { if let p = await search.resolve(c) { go(p) } }
                            }
                            .contextMenu {
                                Button { Task { if let p = await search.resolve(c) { nav.setHome(p) } } } label: { Label("Set as Home", systemImage: "house") }
                                Button { Task { if let p = await search.resolve(c) { nav.setWork(p) } } } label: { Label("Set as Work", systemImage: "briefcase") }
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(NavMode.allCases) { m in
                Button { withAnimation(.snappy) { nav.mode = m } } label: {
                    Label(m.title, systemImage: m.symbol)
                        .font(Theme.rounded(14, .bold))
                        .foregroundStyle(nav.mode == m ? Theme.forestDeep : .white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(nav.mode == m ? AnyShapeStyle(Theme.glow) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .sensoryFeedback(.selection, trigger: nav.mode)
    }

    private func pinChip(_ title: String, _ icon: String, _ place: NavPlace?) -> some View {
        Button { if let place { go(place) } } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Theme.glow)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.rounded(14, .bold)).foregroundStyle(.white)
                    Text(place?.name ?? "Long-press a result").font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 52).frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(place == nil ? 0.6 : 1)
    }

    @ViewBuilder private func pinMenu(_ p: NavPlace) -> some View {
        Button { nav.setHome(p) } label: { Label("Set as Home", systemImage: "house") }
        Button { nav.setWork(p) } label: { Label("Set as Work", systemImage: "briefcase") }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(Theme.rounded(11, .heavy)).tracking(2).foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }

    private func placeRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.glow).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.rounded(16, .bold)).foregroundStyle(.white).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim).lineLimit(1) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func go(_ p: NavPlace) {
        typing = false
        Task { await nav.plan(to: p, from: origin) }
    }

    // Preview

    private func preview(_ dest: NavPlace) -> some View {
        VStack(spacing: 14) {
            Map {
                ForEach(Array(nav.routes.enumerated()), id: \.element.id) { i, r in
                    if i != nav.selected {
                        MapPolyline(coordinates: r.coords)
                            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                if nav.routes.indices.contains(nav.selected) {
                    let r = nav.routes[nav.selected]
                    MapPolyline(coordinates: r.coords)
                        .stroke(Theme.glow.opacity(0.35), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: r.coords)
                        .stroke(Theme.glow, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                Marker(dest.name, systemImage: "flag.checkered", coordinate: dest.coordinate).tint(Theme.leaf)
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .id(nav.routes.first?.id)
            .frame(maxWidth: .infinity).frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .overlay {
                if nav.phase == .planning {
                    ProgressView("Finding the best way…").tint(Theme.glow).font(Theme.rounded(14, .semibold))
                        .padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(dest.name).font(Theme.rounded(20, .heavy)).foregroundStyle(.white).lineLimit(1)
                if !dest.subtitle.isEmpty { Text(dest.subtitle).font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(nav.routes.enumerated()), id: \.element.id) { i, r in
                        Button { withAnimation(.snappy) { nav.selected = i } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NavFormat.duration(r.expectedTime)).font(Theme.title(24)).foregroundStyle(i == nav.selected ? Theme.forestDeep : .white)
                                Text(Navigator.shortDistance(r.distance) + (r.name.isEmpty ? "" : " · via \(r.name)"))
                                    .font(Theme.rounded(12, .bold)).lineLimit(1)
                                    .foregroundStyle(i == nav.selected ? Theme.forestDeep.opacity(0.75) : Theme.textDim)
                                if i == 0 { Text("FASTEST").font(Theme.rounded(10, .heavy)).tracking(1.5)
                                    .foregroundStyle(i == nav.selected ? Theme.forestDeep : Theme.glow) }
                            }
                            .padding(14).frame(width: 170, alignment: .leading)
                            .background(i == nav.selected ? AnyShapeStyle(Theme.leafGradient) : AnyShapeStyle(Color.white.opacity(0.07)),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: nav.selected)

            Spacer(minLength: 0)

            Button {
                onGo()
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.north.line.fill")
                    Text("Go")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(nav.phase != .preview)
            .padding(.bottom, 8)
        }
    }
}

enum NavFormat {
    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(max(1, m)) min" }
        return "\(m / 60) h \(m % 60) min"
    }
}

// MARK: - Map layer

/// The route on the live map: driven part dimmed, the rest glowing.
struct NavRouteContent: MapContent {
    let route: NavRoute
    let traveledIndex: Int
    let destination: NavPlace?

    private var parts: (done: [CLLocationCoordinate2D], ahead: [CLLocationCoordinate2D]) {
        guard route.coords.count > 1 else { return ([], []) }
        let split = max(0, min(traveledIndex + 1, route.coords.count - 1))
        return (Array(route.coords[0...split]), Array(route.coords[split...]))
    }

    @MapContentBuilder var body: some MapContent {
        let done = parts.done
        let ahead = parts.ahead
        if done.count > 1 {
            MapPolyline(coordinates: done)
                .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        if ahead.count > 1 {
            MapPolyline(coordinates: ahead)
                .stroke(Theme.sky.opacity(0.3), style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: ahead)
                .stroke(Theme.sky, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        }
        if let d = destination {
            Marker(d.name, systemImage: "flag.checkered", coordinate: d.coordinate).tint(Theme.leaf)
        }
    }
}

// MARK: - Live banner

/// Big maneuver card shown full-width at the top while navigating.
@MainActor
struct NavBanner: View {
    @Bindable var nav: Navigator

    var body: some View {
        VStack(spacing: 8) {
            if let step = nav.currentStep {
                HStack(spacing: 14) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.forestDeep)
                        .frame(width: 64, height: 64)
                        .background(Theme.leafGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nav.rerouting ? "Rerouting…" : Navigator.shortDistance(nav.toManeuver))
                            .font(Theme.title(32)).foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text(step.road)
                            .font(Theme.rounded(17, .bold)).foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Button { nav.muted.toggle() } label: {
                        Image(systemName: nav.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Color.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel(nav.muted ? "Unmute directions" : "Mute directions")
                }
                .padding(14)
                .background(Theme.forestDeep.opacity(0.93), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.glow.opacity(0.45), lineWidth: 1.5))
                .shadow(color: Theme.glow.opacity(0.25), radius: 16, y: 6)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 8) {
                if let next = nav.nextStep {
                    HStack(spacing: 6) {
                        Text("Then").font(Theme.rounded(12, .heavy)).foregroundStyle(Theme.textDim)
                        Image(systemName: next.symbol).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.glow)
                    }
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Theme.forestDeep.opacity(0.88), in: Capsule())
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(nav.eta, format: .dateTime.hour().minute()).font(Theme.rounded(14, .heavy)).foregroundStyle(Theme.glow)
                    Text("· \(NavFormat.duration(nav.remainingTime)) · \(Navigator.shortDistance(nav.remaining))")
                        .font(Theme.rounded(13, .bold)).foregroundStyle(.white).lineLimit(1)
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(Theme.forestDeep.opacity(0.88), in: Capsule())
                Button { withAnimation(.snappy) { nav.cancel() } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.red.opacity(0.85), in: Circle())
                }
                .accessibilityLabel("End directions")
            }
        }
        .padding(.horizontal, 14)
        .sensoryFeedback(.impact(weight: .medium), trigger: nav.stepIndex)
        .animation(.snappy, value: nav.stepIndex)
    }
}

// MARK: - Arrival

@MainActor
struct NavArrivalCard: View {
    @Bindable var nav: Navigator
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion { NavConfetti().allowsHitTesting(false).ignoresSafeArea() }
            VStack(spacing: 12) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 34, weight: .heavy)).foregroundStyle(Theme.forestDeep)
                    .frame(width: 72, height: 72).background(Theme.leafGradient, in: Circle())
                    .shadow(color: Theme.glow.opacity(0.6), radius: 18)
                Text("You made it").font(Theme.title(32)).foregroundStyle(.white)
                if let d = nav.destination {
                    Text(d.name).font(Theme.rounded(16, .bold)).foregroundStyle(Theme.glow).lineLimit(1)
                }
                if let start = nav.startedAt, let r = nav.active {
                    Text("\(NavFormat.duration(Date().timeIntervalSince(start))) · \(Navigator.shortDistance(r.distance))")
                        .font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.textDim)
                }
                HStack(spacing: 10) {
                    Button { nav.cancel() } label: { Text("Keep recording") }
                        .font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    Button { nav.cancel(); onFinish() } label: { Label("Finish", systemImage: "flag.checkered") }
                        .font(Theme.rounded(15, .heavy)).foregroundStyle(Theme.forestDeep)
                        .padding(.horizontal, 18).frame(height: 48)
                        .background(Theme.leafGradient, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Theme.forestDeep.opacity(0.95), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.glow.opacity(0.4)))
            .padding(.horizontal, 30)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}

/// Lightweight falling confetti.
struct NavConfetti: View {
    @State private var start = Date()
    private let pieces: [(x: Double, speed: Double, spin: Double, hue: Double, size: Double)] = (0..<70).map { _ in
        (Double.random(in: 0...1), Double.random(in: 120...260), Double.random(in: -4...4), Double.random(in: 0...1), Double.random(in: 6...11))
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t < 4 else { return }
                for (i, p) in pieces.enumerated() {
                    let y = -20 + (t - Double(i % 10) * 0.05) * p.speed
                    let x = p.x * size.width + sin(t * 3 + Double(i)) * 14
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(t * p.spin))
                    c.opacity = max(0, 1 - t / 4)
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                           with: .color(Color(hue: p.hue, saturation: 0.8, brightness: 1)))
                }
            }
        }
    }
}
