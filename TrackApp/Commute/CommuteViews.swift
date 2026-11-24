import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - Track screen: one-tap pinned chips

/// Big "→ Work" / "→ Her place" chips on the Track screen (with the drive time from here), plus a way in to set
/// pins. The pin you're standing at is left out. Tapping a chip starts the drive with directions.
@MainActor
struct PinnedChipsRow: View {
    let origin: CLLocationCoordinate2D?
    let onGo: (NavPlace) -> Void
    let onManage: () -> Void

    @State private var nav = Navigator.shared
    @State private var etas: [String: TimeInterval] = [:]
    @State private var tapped = 0
    /// The chip tapped last (its icon bounces).
    @State private var tappedID: String?

    private var pins: [CommutePin] { CommuteStore.pins(nav) }

    private var here: CommutePin? { origin.flatMap { CommuteMath.pin(near: $0, in: pins) } }

    private var targets: [CommutePin] { pins.filter { $0.id != here?.id } }

    private var etaKey: String {
        let o = origin.map { String(format: "%.3f,%.3f", $0.latitude, $0.longitude) } ?? "-"
        return o + "|" + targets.map(\.id).joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: here.map { String(localized: "From \($0.label)") } ?? String(localized: "Quick drives"),
                              symbol: "pin.fill")
                Button(action: onManage) {
                    Text(pins.isEmpty ? "" : String(localized: "Edit"))
                        .font(Theme.rounded(14, .bold)).foregroundStyle(Theme.glow)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .opacity(pins.isEmpty ? 0 : 1)
                .accessibilityLabel(Text("Edit pinned places"))
            }
            if pins.isEmpty {
                setupCard
            } else if targets.isEmpty {
                Text("You're at your only pin. Add another place to get one-tap drives.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap one to start the drive with directions.")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(targets) { p in chip(p) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
        .task(id: etaKey) { await loadETAs() }
        .sensoryFeedback(.impact(weight: .medium), trigger: tapped)
    }

    private var setupCard: some View {
        Button(action: onManage) {
            HStack(spacing: 12) {
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.forestDeep)
                    .frame(width: 44, height: 44).background(Theme.leafGradient, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pin Home and Work").font(Theme.rounded(16, .heavy)).foregroundStyle(.white)
                    Text("One tap to head there, and your commutes add up in History.")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.glow.opacity(0.25)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A dashboard-style chip: dark glass, an edge that catches the light at the top, a glowing icon and a thin
    /// dash light along the bottom; the drive time sits in a small lit pill.
    private func chip(_ p: CommutePin) -> some View {
        let eta = etas[p.id]
        let tint = p.role == .custom ? Theme.gold : Theme.glow
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        return Button {
            tapped += 1
            tappedID = p.id
            onGo(p.place)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: p.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 42, height: 42)
                    .background(p.role == .custom ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.leafGradient), in: Circle())
                    .shadow(color: tint.opacity(0.5), radius: 6)
                    .symbolEffect(.bounce, value: tappedID == p.id ? tapped : 0)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("→ \(p.label)")
                        .font(Theme.rounded(18, .heavy)).foregroundStyle(.white)
                        .lineLimit(1)
                    Group {
                        if let eta {
                            Label {
                                Text(NavFormat.duration(eta)).contentTransition(.numericText())
                            } icon: {
                                Image(systemName: "clock.fill").imageScale(.small)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(tint.opacity(0.16), in: Capsule())
                        } else {
                            Text("Drive with directions")
                        }
                    }
                    .font(Theme.rounded(12, .bold)).monospacedDigit()
                    .foregroundStyle(eta == nil ? Theme.textDim : tint)
                    .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 10).padding(.trailing, 18)
            .frame(minHeight: 66)
            .background {
                shape.fill(.ultraThinMaterial).opacity(0.6)
                shape.fill(LinearGradient(colors: [tint.opacity(0.12), Theme.forestDeep.opacity(0.35)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.10)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0), tint, tint.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 1)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel(Text("Drive to \(p.label)"))
        .accessibilityValue(eta.map { Text("about \(NavFormat.duration($0))") } ?? Text(""))
        .animation(.snappy, value: eta)
    }

    /// Drive time to each pin from where the phone last was (iOS's cached fix; doesn't turn GPS on).
    private func loadETAs() async {
        etas = [:]
        guard let origin else { return }
        for p in targets where etas[p.id] == nil {
            if TrackDemo.isOn {
                etas[p.id] = CommuteMath.meters(origin, p.coordinate) * 1.35 / 11
                continue
            }
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            req.destination = p.place.mapItem
            req.transportType = .automobile
            if let r = try? await MKDirections(request: req).calculateETA() {
                etas[p.id] = r.expectedTravelTime
            }
            if Task.isCancelled { return }
        }
    }
}

// MARK: - "Pin this?" prompt

/// Shown on the Track screen when the same unpinned spot keeps coming up as a drive's start or end (3+ times).
@MainActor
struct PinSuggestionCard: View {
    let activities: [Activity]
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        if let spot = CommuteStore.suggestion(activities) {
            PinSuggestionRow(spot: spot, compact: true) { withAnimation(.snappy) { refresh += 1 } }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

// MARK: - History: commutes

/// "Commutes" in History: each pair of pins you drive between, with this week's count, typical and best time,
/// miles and a fuel estimate from your vehicle's MPG and last price per gallon.
@MainActor
struct CommuteSection: View {
    let activities: [Activity]
    @State private var nav = Navigator.shared
    @Query(sort: \GasVehicle.created) private var vehicles: [GasVehicle]
    @Query(sort: \FillUp.date, order: .reverse) private var fills: [FillUp]
    @AppStorage("gas.vehicleID") private var vehicleRaw = ""

    var body: some View {
        let routes = CommuteMath.routes(CommuteStore.driveTrips(activities), pins: CommuteStore.pins(nav))
        if !routes.isEmpty {
            let economy = CommuteEconomy.current(vehicleRaw: vehicleRaw, vehicles: vehicles, fills: fills, drives: activities)
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Commutes"), symbol: "arrow.left.arrow.right")
                ForEach(routes.prefix(3)) { r in
                    NavigationLink(value: "commute:\(r.id)") {
                        CommuteCard(route: r, economy: economy)
                    }
                    .pressable()
                }
            }
        }
    }
}

/// MPG and price per gallon for the vehicle picked in the gas log (nil until there are enough fill-ups).
enum CommuteEconomy {
    @MainActor
    static func current(vehicleRaw: String, vehicles: [GasVehicle], fills: [FillUp], drives: [Activity]) -> (mpg: Double, pricePerGallon: Double)? {
        let id = vehicles.first { $0.id.uuidString == vehicleRaw }?.id ?? vehicles.first?.id
        return GasMath.fuelEconomy(fills: GasMath.fills(for: id, all: fills, vehicles: vehicles), drives: drives)
    }
}

/// One commute route's numbers.
@MainActor
struct CommuteCard: View {
    let route: CommuteMath.Route
    let economy: (mpg: Double, pricePerGallon: Double)?
    var showsChevron = true

    var body: some View {
        let s = route.stats()
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: route.a.symbol).foregroundStyle(Theme.glow).accessibilityHidden(true)
                    Text(route.title)
                        .font(Theme.rounded(18, .heavy)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: route.b.symbol).foregroundStyle(Theme.glow).accessibilityHidden(true)
                    Spacer(minLength: 0)
                    if showsChevron {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                            .accessibilityHidden(true)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                    stat("\(s.thisWeek)", String(localized: "This week"))
                    stat(s.avgSeconds.map(NavFormat.duration) ?? String(localized: "No time"), String(localized: "Typical"))
                    stat(s.bestSeconds.map(NavFormat.duration) ?? String(localized: "No time"), String(localized: "Best"))
                    stat(s.avgMeters.map(Format.distance) ?? "0", String(localized: "Each way"))
                    if let fuel = fuelPerTrip(s) {
                        stat("~" + fuel.formatted(.currency(code: GasFormat.currency)), String(localized: "Gas per trip"))
                    }
                }
                if economy == nil {
                    Label("Log two fill-ups to see what each trip costs in gas.", systemImage: "fuelpump")
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let week = weekFuel(s), week > 0 {
                    Text("About \(week.formatted(.currency(code: GasFormat.currency))) in gas this week · \(s.count) trips in all")
                        .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(s.count) trips in all").font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fuelPerTrip(_ s: CommuteMath.Stats) -> Double? {
        guard let e = economy, let m = s.avgMeters else { return nil }
        return CommuteMath.fuelCost(meters: m, mpg: e.mpg, pricePerGallon: e.pricePerGallon)
    }

    private func weekFuel(_ s: CommuteMath.Stats) -> Double? {
        guard let e = economy else { return nil }
        return CommuteMath.fuelCost(meters: s.weekMeters, mpg: e.mpg, pricePerGallon: e.pricePerGallon)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Theme.rounded(18, .black)).monospacedDigit().foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
        }
    }
}

/// One commute route: both directions' typical and best times, then every trip on it.
@MainActor
struct CommuteDetailView: View {
    let routeID: String
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @Query(sort: \GasVehicle.created) private var vehicles: [GasVehicle]
    @Query(sort: \FillUp.date, order: .reverse) private var fills: [FillUp]
    @AppStorage("gas.vehicleID") private var vehicleRaw = ""
    @State private var nav = Navigator.shared

    var body: some View {
        let routes = CommuteMath.routes(CommuteStore.driveTrips(activities), pins: CommuteStore.pins(nav))
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                if let r = routes.first(where: { $0.id == routeID }) {
                    CommuteCard(route: r, economy: CommuteEconomy.current(vehicleRaw: vehicleRaw, vehicles: vehicles,
                                                                          fills: fills, drives: activities),
                                showsChevron: false)
                    HStack(spacing: 10) {
                        direction(r, from: r.a, to: r.b)
                        direction(r, from: r.b, to: r.a)
                    }
                    SectionHeader(title: String(localized: "Trips"), symbol: "clock.arrow.circlepath")
                    ForEach(r.legs) { leg in
                        if let a = activities.first(where: { $0.id == leg.id }) {
                            NavigationLink(value: a.id) { TripCard(activity: a) }.pressable()
                        }
                    }
                } else {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "pin.slash").font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.glow)
                            Text("No trips on this route").font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                            Text("A pin may have moved. Trips that start and end at your pins show up here.")
                                .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 12)
            .padding(.bottom, 120)
        }
        .forestScreen()
        .navigationTitle(Text(routes.first { $0.id == routeID }?.title ?? String(localized: "Commute")))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func direction(_ r: CommuteMath.Route, from: CommutePin, to: CommutePin) -> some View {
        let s = CommuteMath.Stats(r.legs(from: from))
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(from.label) → \(to.label)").font(Theme.rounded(13, .heavy)).foregroundStyle(Theme.glow)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.avgSeconds.map(NavFormat.duration) ?? "No trips yet")
                .font(Theme.rounded(20, .black)).monospacedDigit().foregroundStyle(.white)
            Text(s.bestSeconds.map { String(localized: "Best \(NavFormat.duration($0)) · \(s.count) trips") } ?? "")
                .font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
