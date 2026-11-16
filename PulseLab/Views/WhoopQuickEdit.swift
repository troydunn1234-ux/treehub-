import SwiftUI

/// Which WHOOP number to quick-edit, and for which day.
struct WhoopQuickEdit: Identifiable {
    let id = UUID()
    var field: ManualField = .steps
    var day = Date().dayStart

    static func steps(_ day: Date = Date().dayStart) -> WhoopQuickEdit { WhoopQuickEdit(field: .steps, day: day) }
    static func kcal(_ day: Date = Date().dayStart) -> WhoopQuickEdit { WhoopQuickEdit(field: .kcal, day: day) }
}

/// One big number for WHOOP steps (or calories): pick the day, type it, Save. Saved as a manual WHOOP
/// value ("WHOOP · MANUAL"), which feeds Today, the charts and All data like synced numbers.
@MainActor
struct WhoopQuickEditSheet: View {
    let request: WhoopQuickEdit
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().dayStart
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var isSteps: Bool { request.field == .steps }
    private var title: String { isSteps ? String(localized: "WHOOP steps") : String(localized: "WHOOP calories") }
    private var unit: String { isSteps ? "steps" : "kcal" }
    private var limit: Double { isSteps ? 100_000 : 10_000 }

    private func saved(_ d: Date) -> Double? {
        let e = store.manualEntry(d)
        return isSteps ? e?.steps : e?.kcal
    }

    /// A number WHOOP itself sent for the day (API or Health), which wins over a typed one.
    private var synced: Double? {
        guard !store.isManual(date, request.field) else { return nil }
        let day = store.whoopDays.stat(on: date)
        return isSteps ? day?.steps : day?.totalKcalWhoop
    }

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Lab.S.m) {
                    HStack(alignment: .top) {
                        ScreenTitle(kicker: "Log WHOOP · by hand", title: title)
                        CloseButton { dismiss() }
                    }
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(Lab.whoop)
                        Text("Day").font(Lab.body(15, .semibold)).foregroundStyle(Lab.text)
                        Spacer()
                        DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().tint(Lab.whoop)
                    }
                    .padding(.horizontal, Lab.S.m).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lab.panel.opacity(0.9)))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("0", text: $text)
                                .keyboardType(.numberPad)
                                .font(Lab.number(56, .black)).foregroundStyle(Lab.whoop)
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .focused($focused)
                                .accessibilityLabel(title)
                            Text(unit).font(Lab.label(12)).foregroundStyle(Lab.faint)
                        }
                        if saved(date) != nil { SourceBadge(text: "WHOOP · MANUAL") }
                        if let s = synced {
                            Text("WHOOP already sent \(Int(s.rounded()).formatted()) \(unit) for this day; a synced number is used over a typed one.")
                                .font(Lab.body(12)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Lab.S.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Lab.panel.opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Lab.whoop.opacity(focused ? 0.6 : 0.15)))
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }

                    Button(action: save) {
                        Text("Save").font(Lab.display(18, .heavy)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Capsule().fill(Lab.whoop.opacity(value == nil ? 0.4 : 1)))
                    }
                    .buttonStyle(PressScale())
                    .disabled(value == nil)

                    if saved(date) != nil {
                        Button(role: .destructive, action: delete) {
                            Text("Delete").font(Lab.mono(13, .heavy)).foregroundStyle(Lab.bad)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(isSteps ? "WHOOP doesn't share steps with other apps, so type them from the WHOOP app. They show as WHOOP · MANUAL everywhere."
                                 : "If WHOOP doesn't share calories, type the day's total from the WHOOP app. It shows as WHOOP · MANUAL everywhere.")
                        .font(Lab.body(11)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Lab.S.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            date = request.day.dayStart
            load()
            focused = true
        }
        .onChange(of: date) { _, _ in load() }
    }

    private func load() {
        let v = saved(date.dayStart)
        text = v.map { String(Int($0.rounded())) } ?? ""
    }

    private func save() {
        guard let v = value else { return }
        focused = false
        let d = date.dayStart
        var e = store.manualEntry(d) ?? WhoopManualEntry(day: d)
        let c = min(limit, max(0, v))
        if isSteps { e.steps = c } else { e.kcal = c }
        store.saveManual(e)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.toast = String(localized: "\(title) saved for \(d.isToday ? String(localized: "today") : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
        dismiss()
    }

    private func delete() {
        let d = date.dayStart
        guard var e = store.manualEntry(d) else { return }
        if isSteps { e.steps = nil } else { e.kcal = nil }
        store.saveManual(e)
        store.toast = String(localized: "\(title) deleted")
        dismiss()
    }
}
