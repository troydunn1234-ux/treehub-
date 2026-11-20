import SwiftUI
import SwiftData

/// "Paste fill-ups": paste the lines from a phone note (one tank per line), check the rows, pick the vehicle, import.
/// Price per gallon is worked out as total ÷ gallons; the miles become the tank's trip miles, so MPG is right away.
@MainActor
struct FillUpImportView: View {
    var vehicleID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \GasVehicle.created) private var vehicles: [GasVehicle]
    @Query(sort: \FillUp.date, order: .reverse) private var allFills: [FillUp]

    @State private var text = ""
    @State private var rows: [Row] = []
    @State private var chosenVehicle: UUID?
    @State private var imported = 0
    @State private var showingPreview = false
    @FocusState private var editing: Bool

    struct Row: Identifiable {
        var id: Int
        var raw: String
        var date: Date
        var dateGuessed: Bool
        var total: Double?
        var gallons: Double?
        var miles: Double?
        var include: Bool

        var line: FillUpPaste.Line {
            FillUpPaste.Line(index: id, raw: raw, tank: nil, date: date, dateGuessed: dateGuessed,
                             total: total, gallons: gallons, miles: miles)
        }
    }

    private var existing: [(date: Date, total: Double)] { allFills.map { (date: $0.date, total: $0.cost) } }

    /// Duplicates against the log, and against rows earlier in this paste.
    private func warnings(_ r: Row) -> [FillUpPaste.Warning] {
        let earlier = rows.prefix { $0.id != r.id }.filter(\.include).compactMap { x in x.total.map { (date: x.date, total: $0) } }
        return r.line.warnings(existing: existing + earlier)
    }

    private var toImport: [Row] {
        rows.filter { $0.include && $0.line.importable && !warnings($0).contains(.duplicate) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showingPreview { preview } else { pasteBox }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.forestDeep.ignoresSafeArea())
            .navigationTitle(Text("Paste fill-ups"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if showingPreview {
                        Button { withAnimation(.snappy) { showingPreview = false } } label: { Label("Back", systemImage: "chevron.backward") }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { editing = false } }
                }
            }
            .onAppear { if chosenVehicle == nil { chosenVehicle = vehicleID ?? vehicles.first?.id } }
            .sensoryFeedback(.success, trigger: imported)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Step 1: paste

    private var pasteBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste the tanks from your notes, one per line. Fields can be in any order.")
                .font(Theme.rounded(14, .medium)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(verbatim: "tank 1 $58.40 16.2 gallons 371 miles 9/12\ntank 2 10/01 6pm $61 17.1 gal 402 mi")
                        .font(.system(size: Theme.scaled(14), design: .monospaced))
                        .foregroundStyle(Theme.textDim.opacity(0.6))
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .font(.system(size: Theme.scaled(14), design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($editing)
                    .frame(minHeight: 180)
                    .accessibilityLabel(Text("Fill-up lines"))
            }
            .padding(10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.1)))

            HStack(spacing: 10) {
                // PasteButton reads the clipboard only when tapped, so there's no "allow paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    let s = strings.joined(separator: "\n")
                    Task { @MainActor in text = text.isEmpty ? s : text + "\n" + s }
                }
                .buttonBorderShape(.capsule)
                .tint(Theme.glow)
                .labelStyle(.titleAndIcon)
                if !text.isEmpty {
                    Button("Clear", role: .destructive) { text = "" }
                        .font(Theme.rounded(14, .bold))
                        .frame(minHeight: 44)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                hint("dollarsign.circle", String(localized: "$ = what you paid"))
                hint("fuelpump", String(localized: "gallons or gal"))
                hint("road.lanes", String(localized: "miles or mi = driven on that tank"))
                hint("calendar", String(localized: "9/16 or 9/16/25, time like 7pm is optional"))
            }
            .padding(.top, 4)

            Button {
                editing = false
                let parsed = FillUpPaste.parse(text)
                rows = parsed.map {
                    Row(id: $0.index, raw: $0.raw, date: $0.date, dateGuessed: $0.dateGuessed,
                        total: $0.total, gallons: $0.gallons, miles: $0.miles, include: true)
                }
                // Lines already in the log start unticked.
                for i in rows.indices where warnings(rows[i]).contains(.duplicate) { rows[i].include = false }
                withAnimation(.snappy) { showingPreview = true }
            } label: {
                Label("Read lines", systemImage: "text.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 6)
        }
    }

    private func hint(_ symbol: String, _ s: String) -> some View {
        Label(s, systemImage: symbol)
            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Step 2: check and import

    @ViewBuilder private var preview: some View {
        if rows.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "text.magnifyingglass").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.glow)
                        .accessibilityHidden(true)
                    Text("No fill-ups found").font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                    Text("Each line needs at least two of: a $ total, gallons, miles.")
                        .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { withAnimation(.snappy) { showingPreview = false } } label: { Text("Edit the text") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        } else {
            vehiclePicker
            ForEach($rows) { $r in rowCard($r) }
            importBar
        }
    }

    private var vehiclePicker: some View {
        HStack {
            Text("Vehicle").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
            Spacer()
            if vehicles.isEmpty {
                Text("My car").font(Theme.rounded(15, .semibold)).foregroundStyle(Theme.textDim)
            } else {
                Picker("Vehicle", selection: $chosenVehicle) {
                    ForEach(vehicles) { v in Text(v.name).tag(Optional(v.id)) }
                }
                .tint(Theme.glow)
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
    }

    private func rowCard(_ r: Binding<Row>) -> some View {
        let w = warnings(r.wrappedValue)
        let line = r.wrappedValue.line
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: r.include) {
                        Text(verbatim: r.wrappedValue.raw)
                            .font(.system(size: Theme.scaled(12), design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.glow)
                }
                DatePicker(selection: r.date) { fieldLabel(String(localized: "Date")) }
                    .tint(Theme.glow)
                numberField(String(localized: "Total $"), r.total)
                numberField(String(localized: "Gallons"), r.gallons)
                numberField(String(localized: "Miles on tank"), r.miles)
                HStack(spacing: 14) {
                    computed(line.pricePerGallon.map { $0.formatted(.currency(code: GasFormat.currency)) }, String(localized: "per gal"))
                    computed(line.mpg.map { String(format: "%.1f", $0) }, String(localized: "MPG"))
                    Spacer()
                }
                if !w.isEmpty {
                    FlowWarnings(warnings: w)
                }
            }
            .opacity(r.wrappedValue.include ? 1 : 0.55)
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(Theme.rounded(14, .semibold)).foregroundStyle(.white)
    }

    private func numberField(_ label: String, _ value: Binding<Double?>) -> some View {
        HStack {
            fieldLabel(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Theme.rounded(16, .bold)).monospacedDigit()
                .foregroundStyle(Theme.glow)
                .focused($editing)
                .frame(maxWidth: 140)
        }
        .frame(minHeight: 36)
    }

    private func computed(_ value: String?, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value ?? String(localized: "not yet")).font(Theme.rounded(14, .heavy)).monospacedDigit()
                .foregroundStyle(value == nil ? Theme.textDim : .white)
            Text(label).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim)
        }
        .accessibilityElement(children: .combine)
    }

    private var importBar: some View {
        let n = toImport.count
        let skipped = rows.filter { $0.include && warnings($0).contains(.duplicate) }.count
        return VStack(spacing: 8) {
            Button { importRows() } label: {
                Label(n == 1 ? String(localized: "Import 1 fill-up") : String(localized: "Import \(n) fill-ups"),
                      systemImage: "square.and.arrow.down.fill")
                    .contentTransition(.numericText())
            }
            .buttonStyle(PrimaryButtonStyle(gradient: Theme.goldGradient))
            .disabled(n == 0)
            if skipped > 0 {
                Text(skipped == 1 ? String(localized: "1 line is already in your log and will be skipped.")
                                  : String(localized: "\(skipped) lines are already in your log and will be skipped."))
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.top, 4)
    }

    private func importRows() {
        var vid = chosenVehicle ?? vehicleID ?? vehicles.first?.id
        if vid == nil {
            let v = GasVehicle(name: String(localized: "My car"))
            context.insert(v)
            vid = v.id
        }
        for r in toImport {
            let g = r.gallons ?? 0
            let total = r.total ?? 0
            let f = FillUp(vehicleID: vid, date: r.date, gallons: g,
                           pricePerGallon: (total > 0 && g > 0) ? total / g : 0, total: total,
                           odometer: nil, station: "", full: true)
            f.tripMiles = (r.miles ?? 0) > 0 ? r.miles : nil
            f.notes = r.raw
            context.insert(f)
        }
        try? context.save()
        imported += 1
        dismiss()
    }
}

/// Warning pills under a pasted row (wrap at large text sizes).
private struct FlowWarnings: View {
    let warnings: [FillUpPaste.Warning]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(warnings, id: \.self) { w in
                Label(w.text, systemImage: w == .duplicate ? "doc.on.doc" : "exclamationmark.triangle.fill")
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(w == .duplicate ? Theme.sky : Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((w == .duplicate ? Theme.sky : Theme.gold).opacity(0.14), in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
