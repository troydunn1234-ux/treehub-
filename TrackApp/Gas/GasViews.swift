import SwiftUI
import SwiftData
import Charts
import CoreLocation
import MapKit

// MARK: - Gas & MPG screen

struct GasLogView: View {
    var startAdding = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \GasVehicle.created) private var vehicles: [GasVehicle]
    @Query(sort: \FillUp.date, order: .reverse) private var allFills: [FillUp]
    @Query(sort: \Activity.start) private var activities: [Activity]
    @AppStorage("gas.vehicleID") private var vehicleRaw = ""

    @State private var adding = false
    @State private var pasting = false
    @State private var naming = false
    @State private var newName = ""
    @State private var didAutoOpen = false

    private var vehicle: GasVehicle? {
        vehicles.first { $0.id.uuidString == vehicleRaw } ?? vehicles.first
    }

    /// This vehicle's fill-ups; ones without a (known) vehicle show under the first (GasMath.fills), never hidden.
    private var fills: [FillUp] { GasMath.fills(for: vehicle?.id, all: allFills, vehicles: vehicles) }

    private var mpgPoints: [GasMath.MPGPoint] { GasMath.mpg(fills: fills, drives: activities) }
    private var months: [GasMath.MonthSpend] { Array(GasMath.monthly(fills).suffix(12)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    vehicleBar
                    summary
                    if !mpgPoints.isEmpty { mpgChart }
                    if !months.isEmpty { spendChart }
                    fillList
                }
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 12)
            }
            .forestScreen()
            .navigationTitle(Text("Gas & MPG"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { startAdd() } label: { Label("Log a fill-up", systemImage: "plus.circle") }
                        Button { pasting = true } label: { Label("Paste fill-ups from notes", systemImage: "doc.on.clipboard") }
                    } label: {
                        Label("Add fill-ups", systemImage: "plus.circle.fill")
                    } primaryAction: {
                        startAdd()
                    }
                }
            }
            .sheet(isPresented: $adding) {
                AddFillUpView(vehicleID: vehicle?.id)
            }
            .sheet(isPresented: $pasting) {
                FillUpImportView(vehicleID: vehicle?.id)
            }
            .alert(Text("Name your vehicle"), isPresented: $naming) {
                TextField(String(localized: "My truck"), text: $newName)
                Button("Save") { addVehicle() }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .onAppear {
                guard startAdding, !didAutoOpen else { return }
                didAutoOpen = true
                startAdd()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func startAdd() {
        if vehicles.isEmpty { naming = true } else { adding = true }
    }

    private func addVehicle() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let v = GasVehicle(name: name.isEmpty ? String(localized: "My car") : name)
        context.insert(v)
        try? context.save()
        vehicleRaw = v.id.uuidString
        newName = ""
        adding = true
    }

    private var vehicleBar: some View {
        HStack {
            Menu {
                ForEach(vehicles) { v in
                    Button { vehicleRaw = v.id.uuidString } label: {
                        if v.id == vehicle?.id { Label(v.name, systemImage: "checkmark") } else { Text(v.name) }
                    }
                }
                Divider()
                Button { naming = true } label: { Label("Add a vehicle", systemImage: "plus") }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill").accessibilityHidden(true)
                    Text(vehicle?.name ?? String(localized: "Add a vehicle"))
                        .font(Theme.rounded(17, .heavy))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.white.opacity(0.1), in: Capsule())
            }
            .accessibilityLabel(Text("Vehicle: \(vehicle?.name ?? String(localized: "none"))"))
            Spacer()
        }
    }

    private var summary: some View {
        let avg: Double? = {
            let m = mpgPoints.reduce(0) { $0 + $1.miles }, g = mpgPoints.reduce(0) { $0 + $1.gallons }
            return g > 0 ? m / g : nil
        }()
        let thisMonth = months.last.flatMap { Calendar.current.isDate($0.month, equalTo: Date(), toGranularity: .month) ? $0.dollars : nil } ?? 0
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    stat(avg.map { String(format: "%.1f", $0) }, String(localized: "Avg MPG"))
                    Spacer()
                    stat(mpgPoints.last.map { String(format: "%.1f", $0.mpg) }, String(localized: "Last MPG"))
                    Spacer()
                    stat(thisMonth.formatted(.currency(code: GasFormat.currency)), String(localized: "This month"))
                }
                if mpgPoints.isEmpty {
                    // Say why MPG is blank instead of showing a bare dash.
                    Label("MPG shows up after your second full fill-up.", systemImage: "info.circle")
                        .font(Theme.rounded(12, .medium))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One summary number. nil (not enough fill-ups yet) shows a calm dash and reads "Not yet" to VoiceOver.
    private func stat(_ value: String?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(Theme.rounded(24, .black)).foregroundStyle(value == nil ? Theme.textDim : Color.white)
                .monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(value.map { Text($0) } ?? Text("Not yet"))
    }

    private var mpgChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MPG").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
            GlassCard {
                Chart(mpgPoints) { p in
                    LineMark(x: .value("Date", p.date), y: .value("MPG", p.mpg))
                        .foregroundStyle(Theme.glow)
                    PointMark(x: .value("Date", p.date), y: .value("MPG", p.mpg))
                        .foregroundStyle(p.fromOdometer ? Theme.glow : Theme.sky)
                        .accessibilityLabel(Text(p.date, format: .dateTime.month().day()))
                        .accessibilityValue(Text(String(format: "%.1f MPG", p.mpg)))
                }
                .frame(height: 170)
            }
            Text("Gold dots use your odometer or the miles you noted for the tank. Blue dots use the drives Roamr recorded between fill-ups.")
                .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.textDim)
        }
    }

    private var spendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fuel spend by month").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
            GlassCard {
                Chart(months) { m in
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Spend", m.dollars))
                        .foregroundStyle(Theme.goldGradient)
                        .accessibilityLabel(Text(m.month, format: .dateTime.month(.wide).year()))
                        .accessibilityValue(Text(m.dollars.formatted(.currency(code: GasFormat.currency))))
                }
                .frame(height: 170)
            }
        }
    }

    private var fillList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fill-ups").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.textDim)
            if fills.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No fill-ups yet").font(Theme.rounded(16, .heavy)).foregroundStyle(.white)
                        Text("Log gallons and price each time you fill up. With two full fill-ups Roamr can work out your MPG, from the odometer or from the drives it recorded.")
                            .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { logButton; pasteButton }
                            VStack(alignment: .leading, spacing: 10) { logButton; pasteButton }
                        }
                    }
                }
            } else {
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(fills) { f in
                            fillRow(f)
                                .contextMenu {
                                    Button(role: .destructive) { context.delete(f); try? context.save() } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .accessibilityAction(named: Text("Delete")) { context.delete(f); try? context.save() }
                            if f.id != fills.last?.id {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private var logButton: some View {
        Button { startAdd() } label: {
            Text("Log a fill-up").font(Theme.rounded(14, .heavy)).foregroundStyle(Theme.forestDeep)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Theme.goldGradient, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Bring in a list of tanks kept in a phone note.
    private var pasteButton: some View {
        Button { pasting = true } label: {
            Label("Paste from notes", systemImage: "doc.on.clipboard").font(Theme.rounded(14, .heavy)).foregroundStyle(Theme.gold)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Theme.gold.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fillRow(_ f: FillUp) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(f.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                Text(detail(f)).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(f.cost.formatted(.currency(code: GasFormat.currency)))
                    .font(Theme.rounded(15, .heavy)).foregroundStyle(Theme.glow).monospacedDigit()
                if let p = mpgPoints.first(where: { $0.id == f.id }) {
                    Text(String(format: "%.1f MPG", p.mpg)).font(Theme.rounded(12, .bold)).foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ f: FillUp) -> String {
        var parts = [String(format: "%.2f gal", f.gallons)]
        if f.unitPrice > 0 { parts.append(f.unitPrice.formatted(.currency(code: GasFormat.currency)) + "/gal") }
        if let t = f.tripMiles, t > 0 { parts.append(String(localized: "\(Int(t.rounded())) mi on tank")) }
        if let o = f.odometer { parts.append(String(localized: "odo \(Int(o))")) }
        if !f.full { parts.append(String(localized: "partial")) }
        if !f.station.isEmpty { parts.append(f.station) }
        return parts.joined(separator: " · ")
    }
}

enum GasFormat {
    static var currency: String { Locale.current.currency?.identifier ?? "USD" }
}

// MARK: - Add a fill-up

struct AddFillUpView: View {
    let vehicleID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var gallons = ""
    @State private var priceMode = 0   // 0 = per gallon, 1 = total
    @State private var price = ""
    @State private var odometer = ""
    @State private var station = ""
    @State private var full = true
    @State private var finding = false
    @State private var findNote: String?

    private func number(_ s: String) -> Double? {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.number(from: s.trimmingCharacters(in: .whitespaces))?.doubleValue
            ?? Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool { (number(gallons) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date)
                    TextField("Gallons", text: $gallons).keyboardType(.decimalPad)
                    Picker("Price", selection: $priceMode) {
                        Text("Per gallon").tag(0)
                        Text("Total").tag(1)
                    }
                    .pickerStyle(.segmented)
                    TextField(priceMode == 0 ? String(localized: "Price per gallon") : String(localized: "Total paid"), text: $price)
                        .keyboardType(.decimalPad)
                    Toggle("Filled the tank", isOn: $full)
                }
                Section {
                    TextField("Odometer (miles, optional)", text: $odometer).keyboardType(.numberPad)
                } footer: {
                    Text("Without the odometer, Roamr uses the drives it recorded since your last full fill-up.")
                }
                Section {
                    TextField("Station (optional)", text: $station)
                    Button { findStation() } label: {
                        HStack {
                            Label("Use where I am", systemImage: "location.fill")
                            if finding { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(finding)
                } footer: {
                    Text(findNote ?? String(localized: "Looks up the nearest gas station once. Roamr doesn't keep tracking your location for this."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.forestDeep.ignoresSafeArea())
            .navigationTitle(Text("Log a fill-up"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let g = number(gallons) ?? 0
        let p = number(price) ?? 0
        let f = FillUp(vehicleID: vehicleID, date: date, gallons: g,
                       pricePerGallon: priceMode == 0 ? p : 0, total: priceMode == 1 ? p : 0,
                       odometer: number(odometer), station: station.trimmingCharacters(in: .whitespaces), full: full)
        context.insert(f)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func findStation() {
        finding = true
        findNote = nil
        Task {
            let name = await GasStationFinder.nearest()
            finding = false
            if let name { station = name } else { findNote = String(localized: "Couldn't find a station here. Type it in instead.") }
        }
    }
}

// MARK: - Nearest station (one location fix, only when you tap)

@MainActor
enum GasStationFinder {
    static func nearest() async -> String? {
        let coord: CLLocationCoordinate2D?
        if let c = RoamrContext.tracker?.lastCoordinate, RoamrContext.tracker?.isActive == true {
            coord = c   // already recording: reuse the fix we have
        } else {
            coord = await OneShotLocation().get()
        }
        guard let coord else { return nil }
        let req = MKLocalPointsOfInterestRequest(center: coord, radius: 250)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let resp = try? await MKLocalSearch(request: req).start() {
            let best = resp.mapItems.min {
                ($0.placemark.location?.distance(from: here) ?? .infinity) < ($1.placemark.location?.distance(from: here) ?? .infinity)
            }
            if let name = best?.name { return name }
        }
        let place = await Geo.placeName(for: coord)
        return place.isEmpty ? nil : place
    }
}

/// Asks for a single location fix, then stops. Never starts continuous updates.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cont: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var keepAlive: OneShotLocation?

    func get() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { c in
            cont = c
            keepAlive = self
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            case .notDetermined: manager.requestWhenInUseAuthorization()
            default: done(nil)
            }
        }
    }

    private func done(_ c: CLLocationCoordinate2D?) {
        cont?.resume(returning: c)
        cont = nil
        manager.delegate = nil
        keepAlive = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            guard self.cont != nil else { return }
            switch s {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
            case .notDetermined: break
            default: self.done(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        Task { @MainActor in self.done(c) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.done(nil) }
    }
}
