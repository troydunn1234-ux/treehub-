import SwiftUI

/// What the root-level Log WHOOP sheet should open on.
struct LogWhoopRequest: Identifiable {
    let id = UUID()
    var day = Date().dayStart
    /// Opened by the morning pop-up (shows "Not now" and "Stop asking").
    var auto = false
}

/// "Today's WHOOP": type the numbers from the WHOOP app by hand. Big fields, number pads, steppers and
/// sliders. Prefilled from WHOOP values already in Apple Health, so usually only the WHOOP-only scores
/// (recovery, strain, sleep performance) need typing. Only filled fields are saved.
@MainActor
struct LogWhoopSheet: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var day: Date = Date().dayStart
    var auto = false

    @State private var date = Date().dayStart
    @State private var text: [ManualField: String] = [:]
    @State private var sleepH = ""
    @State private var sleepM = ""
    /// Values already known for this day from Health / the WHOOP API (not typed). Unchanged ones aren't stored.
    @State private var known: [ManualField: Double] = [:]
    @State private var confirmDelete = false
    @State private var loaded = false
    @FocusState private var focus: ManualField?

    private var existing: WhoopManualEntry? { store.manualEntry(date) }

    var body: some View {
        NavigationStack {
            ZStack {
                LabBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Lab.S.m) {
                        header
                        dateRow
                        slider(.steps, "Steps", "steps", range: 0...40_000, step: 500, decimals: 0, tint: Lab.whoop)
                        openWhoopButton
                        slider(.recovery, "Recovery", "%", range: 0...100, step: 1, decimals: 0, tint: band)
                        slider(.strain, "Day strain", "/ 21", range: 0...21, step: 0.1, decimals: 1, tint: Lab.whoop)
                        slider(.sleepPerformance, "Sleep performance", "%", range: 0...100, step: 1, decimals: 0, tint: Lab.whoop)
                        sleepTile
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Lab.S.s), GridItem(.flexible())], spacing: Lab.S.s) {
                            stepper(.hrv, "HRV", "ms", range: 0...300, step: 1, decimals: 0)
                            stepper(.rhr, "Resting HR", "bpm", range: 20...150, step: 1, decimals: 0)
                            stepper(.resp, "Respiratory", "br/min", range: 5...40, step: 0.1, decimals: 1)
                            stepper(.kcal, "Calories", "kcal · optional", range: 0...10_000, step: 50, decimals: 0)
                        }
                        saveButton
                        footer
                    }
                    .padding(.horizontal, Lab.S.m)
                    .padding(.top, Lab.S.m)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focus = nil
                        // The sleep minutes field has no focus value of its own; end editing everywhere.
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.font(.body.weight(.semibold)).foregroundStyle(Lab.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            date = day.dayStart
            load()
        }
        .onChange(of: date) { _, _ in load() }
        .confirmationDialog("Delete the WHOOP numbers you typed for this day?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                store.deleteManual(date)
                store.toast = "Deleted the logged WHOOP numbers"
                dismiss()
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top) {
            ScreenTitle(kicker: "Log WHOOP · by hand", title: date.isToday ? "Today's WHOOP" : "WHOOP · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
            Spacer()
            CloseButton { dismiss() }
        }
    }

    private var dateRow: some View {
        HStack {
            Image(systemName: "calendar").foregroundStyle(Lab.whoop).accessibilityHidden(true)
            Text("Day").font(.body.weight(.semibold)).foregroundStyle(Lab.text)
            Spacer()
            DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                .labelsHidden().tint(Lab.whoop)
            if existing != nil { SourceBadge(text: "WHOOP · MANUAL") }
        }
        .padding(.horizontal, Lab.S.m).padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.panel))
        .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(Lab.line))
    }

    private var openWhoopButton: some View {
        Button {
            Lab.tick()
            openURL(URL(string: "whoop://")!) { ok in
                if !ok { Task { @MainActor in store.toast = "Couldn't open the WHOOP app" } }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bolt.heart.fill").font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open WHOOP").font(.body.weight(.semibold))
                    Text("Glance at today's numbers, then come back").font(.caption).opacity(0.8)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Lab.whoop)
            .padding(.horizontal, Lab.S.m).padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.whoop.opacity(0.12)))
        }
        .buttonStyle(PressScale())
    }

    /// Where − / + start from on an empty field.
    private static let starts: [ManualField: Double] = [
        .recovery: 50, .strain: 10, .sleepPerformance: 80, .hrv: 50, .rhr: 55, .resp: 15, .steps: 8000, .kcal: 2500,
    ]

    /// Decimals each field is shown with (sleep: whole minutes).
    static func decimals(_ f: ManualField) -> Int { f == .strain || f == .resp ? 1 : 0 }

    /// True when `value` is what the field showed for `known` (a Health / API number, rounded for the field): left as
    /// it was. Health's numbers carry more decimals than the fields (WHOOP's HRV of 61.4 shows as 61), so an exact
    /// match would store every untouched prefilled field as a hand-typed WHOOP number on Save.
    static func isUnchanged(_ value: Double, from known: Double?, decimals: Int) -> Bool {
        guard let known else { return false }
        return abs(known - value) < 0.5 * pow(10, -Double(decimals))
    }

    private var band: Color { value(.recovery).map(Lab.band) ?? Lab.whoop }

    /// Full-width tile: big number field plus a slider (recovery, strain, sleep performance).
    private func slider(_ f: ManualField, _ title: String, _ unit: String, range: ClosedRange<Double>, step: Double, decimals: Int, tint: Color) -> some View {
        let v = value(f)
        return tile(f, title, unit, tint: tint) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                field(f, decimals: decimals, size: 40, tint: tint)
                Text(unit).font(Lab.label(12)).foregroundStyle(Lab.faint)
                Spacer()
                bump(f, -step, range, decimals)
                bump(f, step, range, decimals)
            }
            Slider(value: Binding(get: { v ?? (range.lowerBound + range.upperBound) / 2 },
                                  set: { setValue(f, ($0 / step).rounded() * step, decimals) }),
                   in: range, step: step)
                .tint(tint)
                .opacity(v == nil ? 0.45 : 1)
                .accessibilityLabel(title)
        }
    }

    /// Half-width tile: number field with − / + buttons.
    private func stepper(_ f: ManualField, _ title: String, _ unit: String, range: ClosedRange<Double>, step: Double, decimals: Int) -> some View {
        tile(f, title, unit, tint: Lab.whoop) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                field(f, decimals: decimals, size: 30, tint: Lab.whoop)
                Text(unit).font(Lab.label(9)).foregroundStyle(Lab.faint).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                bump(f, -step, range, decimals)
                bump(f, step, range, decimals)
                Spacer(minLength: 0)
            }
        }
    }

    private var sleepTile: some View {
        tile(.sleep, "Hours of sleep", "h:mm", tint: Lab.whoop) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("–", text: $sleepH)
                    .keyboardType(.numberPad)
                    .font(Lab.number(40)).foregroundStyle(Lab.whoop)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .focused($focus, equals: .sleep)
                    .accessibilityLabel("Hours asleep")
                Text("h").font(Lab.label(12)).foregroundStyle(Lab.faint)
                TextField("00", text: $sleepM)
                    .keyboardType(.numberPad)
                    .font(Lab.number(40)).foregroundStyle(Lab.whoop)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .accessibilityLabel("Minutes asleep")
                Text("m").font(Lab.label(12)).foregroundStyle(Lab.faint)
                Spacer()
                roundButton("minus") { bumpSleep(-15) }
                roundButton("plus") { bumpSleep(15) }
            }
        }
    }

    private func tile<C: View>(_ f: ManualField, _ title: String, _ unit: String, tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Lab.S.s) {
            HStack(spacing: 6) {
                Text(L(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.dim).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let v = value(f), Self.isUnchanged(v, from: known[f], decimals: Self.decimals(f)) {
                    Text("From Health").font(.caption2.weight(.medium)).foregroundStyle(Lab.faint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Lab.inset))
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Lab.S.m)
        .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.panel))
        .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(focus == f ? tint.opacity(0.7) : Lab.line))
        .contentShape(Rectangle())
        .onTapGesture { focus = f }
    }

    private func field(_ f: ManualField, decimals: Int, size: CGFloat, tint: Color) -> some View {
        TextField("–", text: Binding(get: { text[f] ?? "" }, set: { text[f] = $0 }))
            .keyboardType(decimals > 0 ? .decimalPad : .numberPad)
            .font(Lab.number(size)).foregroundStyle(tint)
            .lineLimit(1).minimumScaleFactor(0.5)
            .focused($focus, equals: f)
            .frame(minWidth: 60)
    }

    private func bump(_ f: ManualField, _ by: Double, _ range: ClosedRange<Double>, _ decimals: Int) -> some View {
        roundButton(by < 0 ? "minus" : "plus") {
            let base = value(f) ?? known[f] ?? (Self.starts[f] ?? range.lowerBound) - by
            setValue(f, min(range.upperBound, max(range.lowerBound, base + by)), decimals)
        }
    }

    private func roundButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Lab.tick()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Lab.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(symbol == "minus" ? "Decrease" : "Increase")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(existing == nil ? "Save" : "Save changes")
        }
        .buttonStyle(LabPrimaryButton())
        .padding(.top, Lab.S.s)
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: Lab.S.s) {
            if auto {
                Button { dismiss() } label: {
                    Text("Not now")
                }
                .buttonStyle(LabSecondaryButton(tint: Lab.dim))
                Button {
                    WhoopPrompt.askEnabled = false
                    store.toast = "Won't ask each morning. Turn it back on in Settings."
                    dismiss()
                } label: {
                    Text("Don't ask again").font(.footnote).foregroundStyle(Lab.faint).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            if existing != nil {
                Button { confirmDelete = true } label: {
                    Text("Delete this day's entry").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.bad)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Text("Everything is optional; only what you fill in is saved. Numbers already in Apple Health are filled in for you. If the WHOOP API sends this day later, its numbers win.")
                .font(.caption).foregroundStyle(Lab.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Values

    private func value(_ f: ManualField) -> Double? {
        if f == .sleep {
            let h = Double(sleepH.trimmingCharacters(in: .whitespaces)), m = Double(sleepM.trimmingCharacters(in: .whitespaces))
            guard h != nil || m != nil else { return nil }
            return (h ?? 0) * 60 + (m ?? 0)
        }
        guard let t = text[f]?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }

    private func isFilled(_ f: ManualField) -> Bool { value(f) != nil }

    private func setValue(_ f: ManualField, _ v: Double?, _ decimals: Int) {
        if f == .sleep { setSleep(v); return }
        text[f] = v.map { decimals > 0 ? String(format: "%.\(decimals)f", $0) : String(Int($0.rounded())) } ?? ""
    }

    private func setSleep(_ minutes: Double?) {
        guard let m = minutes else { sleepH = ""; sleepM = ""; return }
        let t = Int(m.rounded())
        sleepH = String(t / 60)
        sleepM = String(format: "%02d", t % 60)
    }

    private func bumpSleep(_ by: Double) {
        let base = value(.sleep) ?? known[.sleep] ?? 7 * 60 - by
        setSleep(min(16 * 60, max(0, base + by)))
    }

    /// Fill the fields: the saved entry first, then whatever Health / the API already has for that day.
    private func load() {
        let d = date.dayStart
        let e = store.manualEntry(d)
        let day = store.whoopDays.stat(on: d)
        let night = store.sleeps.last { $0.source == .whoop && $0.night == d }
        var k: [ManualField: Double] = [:]
        func from(_ f: ManualField, _ v: Double?) { if let v, !store.isManual(d, f) { k[f] = v } }
        from(.recovery, day?.recovery)
        from(.strain, day?.strain)
        from(.hrv, day?.hrv)
        from(.rhr, day?.rhr)
        from(.resp, day?.resp)
        from(.steps, day?.steps)
        from(.kcal, day?.totalKcalWhoop)
        from(.sleepPerformance, night?.performance)
        from(.sleep, night.flatMap { $0.asleepMin > 0 ? $0.asleepMin : nil })
        known = k
        func pick(_ f: ManualField, _ m: Double?) -> Double? { m ?? k[f] }
        setValue(.recovery, pick(.recovery, e?.recovery), 0)
        setValue(.strain, pick(.strain, e?.strain), 1)
        setValue(.sleepPerformance, pick(.sleepPerformance, e?.sleepPerformance), 0)
        setValue(.hrv, pick(.hrv, e?.hrv), 0)
        setValue(.rhr, pick(.rhr, e?.rhr), 0)
        setValue(.resp, pick(.resp, e?.resp), 1)
        setValue(.steps, pick(.steps, e?.steps), 0)
        setValue(.kcal, pick(.kcal, e?.kcal), 0)
        setSleep(pick(.sleep, e?.sleepMin))
    }

    private func save() {
        focus = nil
        let d = date.dayStart
        let old = store.manualEntry(d)
        var e = WhoopManualEntry(day: d)
        /// Store a field when it was typed (differs from what Health / the API had) or was already a manual value.
        func keep(_ f: ManualField, _ was: Double?, _ range: ClosedRange<Double>) -> Double? {
            guard let v = value(f) else { return nil }
            let c = min(range.upperBound, max(range.lowerBound, v))
            if was == nil, Self.isUnchanged(c, from: known[f], decimals: Self.decimals(f)) { return nil }
            return c
        }
        e.recovery = keep(.recovery, old?.recovery, 0...100)
        e.strain = keep(.strain, old?.strain, 0...21)
        e.sleepPerformance = keep(.sleepPerformance, old?.sleepPerformance, 0...100)
        e.hrv = keep(.hrv, old?.hrv, 0...300)
        e.rhr = keep(.rhr, old?.rhr, 20...150)
        e.resp = keep(.resp, old?.resp, 5...40)
        e.steps = keep(.steps, old?.steps, 0...100_000)
        e.kcal = keep(.kcal, old?.kcal, 0...10_000)
        e.sleepMin = keep(.sleep, old?.sleepMin, 0...(16 * 60))

        if e.isEmpty && old == nil {
            store.toast = known.isEmpty ? "Nothing to save yet: fill in a number" : "Already up to date from Health"
            dismiss()
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.saveManual(e)
        store.toast = e.isEmpty ? "Cleared the logged WHOOP numbers" : (d.isToday ? "Today's WHOOP logged" : "WHOOP logged for \(d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
        let loggedToday = store.hasWhoopRecoveryToday
        // First save is when the morning reminder asks for notification permission (once).
        Task { await WhoopPrompt.askPermissionIfNeeded(loggedToday: loggedToday) }
        dismiss()
    }
}

/// "Log WHOOP" entry point for Today and Sources: shows today's status and opens the sheet.
@MainActor
struct LogWhoopCard: View {
    @Environment(LabStore.self) private var store
    @State private var show = false

    var body: some View {
        let today = store.whoopDays.stat(on: Date())
        let manualToday = store.manualEntry(Date()) != nil
        let rec = today?.recovery
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            show = true
        } label: {
            HStack(spacing: Lab.S.s) {
                Image(systemName: rec == nil ? "square.and.pencil" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(rec == nil ? Lab.whoop : Lab.good)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((rec == nil ? Lab.whoop : Lab.good).opacity(0.15)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Log WHOOP").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                        if manualToday { SourceBadge(text: "WHOOP · MANUAL") }
                    }
                    Text(line(today, rec)).font(.caption).foregroundStyle(Lab.dim).lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lab.faint)
            }
            .padding(.horizontal, Lab.S.m).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).fill(Lab.panel))
            .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(Lab.line))
        }
        .buttonStyle(PressScale())
        .accessibilityHint("Type today's WHOOP numbers by hand")
        .sheet(isPresented: $show) {
            LogWhoopSheet().environment(store).presentationBackground(Lab.bg)
        }
    }

    private func line(_ d: DayStat?, _ rec: Double?) -> String {
        guard let rec else { return "No WHOOP recovery yet today · type it in, 20 seconds" }
        var parts = ["Recovery \(Int(rec.rounded()))%"]
        if let s = d?.strain { parts.append("Strain \(s.formatted(.number.precision(.fractionLength(1))))") }
        if let n = store.sleeps.last(where: { $0.source == .whoop && $0.night == Date().dayStart }), let p = n.performance {
            parts.append("Sleep \(Int(p.rounded()))%")
        }
        return parts.joined(separator: " · ") + " · tap to edit"
    }
}
