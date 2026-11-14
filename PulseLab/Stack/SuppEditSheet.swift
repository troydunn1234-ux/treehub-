import SwiftUI
import SwiftData

/// What the edit sheet is working on.
enum SuppSheet: Identifiable {
    case edit(Supplement)
    case preset(SuppPreset)
    case new

    var id: String {
        switch self {
        case .edit(let s): return "edit-\(s.id.uuidString)"
        case .preset(let p): return "preset-\(p.name)"
        case .new: return "new"
        }
    }
}

/// Split a dose like "5000 IU", "1 tablet", "2 scoops", "0.5 capsule" into amount + unit.
struct DoseParts {
    var amount: Double
    var unit: String

    static let units = ["mg", "mcg", "g", "IU", "capsule", "tablet", "softgel", "scoop", "ml", "drop", "gummy", "packet"]
    /// Units you count (get an "s" when there's more than one).
    static let countUnits: Set<String> = ["capsule", "tablet", "softgel", "scoop", "drop", "gummy", "packet"]

    init(amount: Double, unit: String) { self.amount = amount; self.unit = unit }

    init(_ dose: String) {
        let t = dose.trimmingCharacters(in: .whitespaces)
        var num = ""
        var rest = Substring(t)
        while let c = rest.first, c.isNumber || c == "." || c == "," {
            if c != "," { num.append(c) }
            rest = rest.dropFirst()
        }
        amount = Double(num) ?? 1
        var u = rest.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { u = "tablet" }
        // Match a known unit, ignoring case and a plural "s" ("2 Scoops" -> scoop).
        let low = u.lowercased()
        let single = low.hasSuffix("ies") ? String(low.dropLast(3)) + "y" : (low.hasSuffix("s") && low != "s" ? String(low.dropLast()) : low)
        unit = Self.units.first { $0.lowercased() == low || $0.lowercased() == single } ?? u
    }

    var amountText: String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%g", amount)
    }

    var text: String {
        var u = unit
        if Self.countUnits.contains(unit) && amount != 1 { u = unit == "gummy" ? "gummies" : unit + "s" }
        return "\(amountText) \(u)"
    }

    /// One tap of − / +.
    var step: Double {
        switch unit {
        case "mg": return amount < 100 ? 5 : 50
        case "mcg": return amount < 100 ? 10 : 50
        case "g": return amount < 5 ? 0.5 : 1
        case "IU": return amount < 1000 ? 100 : 1000
        case "ml": return 5
        case "drop": return 1
        default: return amount < 1 ? 0.5 : (amount < 2 ? 0.5 : 1)
        }
    }

    /// Common amounts for this unit, as one-tap chips.
    var quick: [Double] {
        switch unit {
        case "mg": return [50, 100, 200, 250, 500, 1000]
        case "mcg": return [50, 100, 500, 1000, 2500, 5000]
        case "g": return [1, 2, 3, 5, 10, 20]
        case "IU": return [400, 1000, 2000, 5000, 10000]
        case "ml": return [5, 10, 15, 30]
        case "drop": return [1, 2, 5, 10]
        default: return [0.5, 1, 2, 3, 4]
        }
    }
}

/// Edit any supplement in the stack (or one you're about to add from a preset):
/// name, dose with big steppers, unit, time of day, with-food, emoji.
struct SuppEditSheet: View {
    let target: SuppSheet
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("suppReminders") private var reminders = false

    @State private var name = ""
    @State private var dose = DoseParts(amount: 1, unit: "tablet")
    @State private var emoji = "💊"
    @State private var time: SuppTime = .morning
    @State private var withFood = false
    @State private var typingAmount = false
    @State private var amountField = ""
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private let emojis = ["💊", "☀️", "🐟", "🍊", "⚡️", "💪", "🥤", "🧂", "🥬", "✨", "🔥", "🦠", "🛡️", "🌙", "🌿", "😴", "🧲", "🟡", "🍵", "🧪"]

    private var existing: Supplement? { if case .edit(let s) = target { return s }; return nil }
    private var title: String { existing == nil ? "Add to stack" : "Edit" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameCard
                    doseCard
                    section("UNIT") { unitChips }
                    section("WHEN") { timeChips }
                    withFoodRow
                    section("ICON") { emojiRow }
                    if existing != nil { deleteButton }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
            .background(Ember.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { saveButton }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Ember.dim) }
            }
            .confirmationDialog("Remove \(name) from your stack?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { delete() }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    // MARK: pieces

    private var nameCard: some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 34))
                .frame(width: 60, height: 60)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            TextField("", text: $name, prompt: Text("Name").foregroundStyle(Ember.dim))
                .font(Ember.font(22, .heavy)).foregroundStyle(Ember.cream)
                .submitLabel(.done)
        }
    }

    private var doseCard: some View {
        VStack(spacing: 14) {
            Text("DOSE").font(Ember.font(11, .heavy)).tracking(3).foregroundStyle(Ember.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                stepButton("minus") { setAmount(max(dose.step >= 1 ? dose.step : 0.5, dose.amount - dose.step)) }
                Group {
                    if typingAmount {
                        TextField("", text: $amountField)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .multilineTextAlignment(.center)
                            .onSubmit(commitTyped)
                            .onChange(of: amountFocused) { _, f in if !f { commitTyped() } }
                    } else {
                        Text(dose.amountText)
                            .contentTransition(.numericText())
                            .onTapGesture {
                                amountField = dose.amountText
                                typingAmount = true
                                amountFocused = true
                            }
                    }
                }
                .font(Ember.font(46, .black)).foregroundStyle(Ember.cream)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Amount \(dose.amountText)")
                stepButton("plus") { setAmount(dose.amount + dose.step) }
            }
            Text(dose.text).font(Ember.font(15, .bold)).foregroundStyle(Ember.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dose.quick, id: \.self) { q in
                        let d = DoseParts(amount: q, unit: dose.unit)
                        chip(d.amountText, on: dose.amount == q) { setAmount(q) }
                    }
                }
            }
        }
        .padding(18)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Ember.line))
    }

    private var unitChips: some View {
        let list = DoseParts.units.contains(dose.unit) ? DoseParts.units : [dose.unit] + DoseParts.units
        return SuppFlowChips(items: list) { u in
            chip(u, on: dose.unit == u) {
                withAnimation(.spring(response: 0.3)) { dose.unit = u }
            }
        }
    }

    private var timeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SuppTime.allCases) { t in
                    Button {
                        withAnimation(.spring(response: 0.3)) { time = t }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Label(t.rawValue, systemImage: t.symbol)
                            .font(Ember.font(14, .bold))
                            .foregroundStyle(time == t ? Color.white : Ember.cream)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background {
                                if time == t { Capsule().fill(Ember.fire) } else { Capsule().fill(Ember.card) }
                            }
                            .overlay(Capsule().strokeBorder(time == t ? Color.clear : Ember.line))
                    }
                    .buttonStyle(Squish())
                }
            }
        }
    }

    private var withFoodRow: some View {
        Toggle(isOn: $withFood) {
            Label("Take with food", systemImage: "fork.knife").font(Ember.font(16, .bold)).foregroundStyle(Ember.cream)
        }
        .tint(Ember.orange)
        .padding(16)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emojiRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(emojis, id: \.self) { e in
                    Button { emoji = e; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        Text(e).font(.system(size: 26)).padding(8)
                            .background(emoji == e ? Ember.orange.opacity(0.3) : Ember.card,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("Remove from stack", systemImage: "trash")
                .font(Ember.font(15, .bold)).foregroundStyle(Ember.pink)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Ember.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Squish())
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(existing == nil ? "Add · \(dose.text)" : "Save · \(dose.text)")
                .font(Ember.font(18, .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(Ember.fire, in: Capsule())
                .shadow(color: Ember.orange.opacity(0.5), radius: 14, y: 6)
        }
        .buttonStyle(Squish())
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    // MARK: helpers

    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(Ember.font(11, .heavy)).tracking(3).foregroundStyle(Ember.orange)
            content()
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Ember.fire, in: Circle())
                .shadow(color: Ember.orange.opacity(0.45), radius: 10)
        }
        .buttonStyle(Squish())
        .accessibilityLabel(symbol == "plus" ? "More" : "Less")
    }

    private func chip(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Ember.font(15, .bold))
                .foregroundStyle(on ? Color.white : Ember.cream)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background {
                    if on { Capsule().fill(Ember.fire) } else { Capsule().fill(Ember.card) }
                }
                .overlay(Capsule().strokeBorder(on ? Color.clear : Ember.line))
        }
        .buttonStyle(Squish())
    }

    private func setAmount(_ v: Double) {
        typingAmount = false
        let clean = (v * 100).rounded() / 100
        withAnimation(.spring(response: 0.25)) { dose.amount = max(0.25, clean) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func commitTyped() {
        guard typingAmount else { return }
        if let v = Double(amountField.replacingOccurrences(of: ",", with: ".")), v > 0 { dose.amount = v }
        typingAmount = false
    }

    private func load() {
        switch target {
        case .edit(let s):
            name = s.name; dose = DoseParts(s.dose); emoji = s.emoji; time = s.time; withFood = s.withFood
        case .preset(let p):
            name = p.name; dose = DoseParts(p.dose); emoji = p.emoji; time = p.time; withFood = false
        case .new:
            name = ""; dose = DoseParts(amount: 1, unit: "capsule"); emoji = "💊"; time = .morning; withFood = false
        }
    }

    private func save() {
        commitTyped()
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let s = existing {
            // Edits apply from now on; past check-offs (SuppDose) only reference the id, so history is untouched.
            s.name = n; s.dose = dose.text; s.emoji = emoji; s.timeRaw = time.rawValue; s.withFood = withFood
        } else {
            let all = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
            let s = Supplement(name: n, dose: dose.text, emoji: emoji, time: time, order: (all.map(\.order).max() ?? -1) + 1)
            s.withFood = withFood
            context.insert(s)
        }
        try? context.save()
        afterChange()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func delete() {
        guard let s = existing else { return }
        context.delete(s)
        try? context.save()
        afterChange()
        dismiss()
    }

    private func afterChange() {
        if reminders {
            let all = (try? context.fetch(FetchDescriptor<Supplement>(sortBy: [SortDescriptor(\.order)]))) ?? []
            Reminders.update(on: true, supps: all)
        }
    }
}

/// Simple wrapping row of chips.
struct SuppFlowChips<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        SuppFlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct SuppFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
