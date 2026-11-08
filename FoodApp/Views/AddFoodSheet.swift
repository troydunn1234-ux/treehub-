import SwiftUI
import SwiftData

/// Search or pick a food and it's logged in one tap. Your own foods come back as recents.
struct AddFoodSheet: View {
    let day: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var history: [FoodEntry]

    @State private var query = ""
    @State private var meal: Meal = .now
    @State private var servings: Double = 1
    @State private var added: [String] = []
    @State private var customCal = ""
    @State private var customP = ""
    @State private var customC = ""
    @State private var customF = ""
    @State private var showMacros = false
    @FocusState private var searchFocused: Bool

    private struct Pick: Identifiable, Hashable {
        var id: String { name + detail }
        let name: String, detail: String, cal: Double, p: Double, c: Double, f: Double, caf: Double
    }

    private var recents: [Pick] {
        var seen = Set<String>()
        return history.compactMap { e in
            guard seen.insert(e.name.lowercased()).inserted else { return nil }
            return Pick(name: e.name, detail: "Recent", cal: e.cal, p: e.protein, c: e.carbs, f: e.fat, caf: e.caffeine)
        }
    }

    private var results: [Pick] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let foods = QuickFood.all.map { Pick(name: $0.name, detail: $0.serving, cal: Double($0.cal), p: $0.p, c: $0.c, f: $0.f, caf: Double($0.caf)) }
        if q.isEmpty { return Array(recents.prefix(8)) + (recents.isEmpty ? Array(foods.prefix(20)) : []) }
        let words = q.split(separator: " ").map(String.init)
        func match(_ name: String, _ tags: [String]) -> Bool {
            let hay = ([name.lowercased()] + tags).joined(separator: " ")
            return words.allSatisfy { hay.contains($0) }
        }
        let fromRecents = recents.filter { match($0.name, []) }
        let fromFoods = zip(QuickFood.all, foods).filter { match($0.0.name, $0.0.tags) }.map(\.1)
        return Array((fromRecents + fromFoods).prefix(40))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchBar
                    mealPicker
                    servingsStepper
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty { customCard }
                    VStack(spacing: 8) {
                        if query.isEmpty && !recents.isEmpty {
                            sectionLabel("RECENT")
                        } else if query.isEmpty {
                            sectionLabel("POPULAR")
                        }
                        ForEach(results) { pick in row(pick) }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(EmberBackground())
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(added.isEmpty ? "Close" : "Done") { dismiss() }.font(Ember.font(16, .bold)).foregroundStyle(Ember.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Ember.dim)
            TextField("", text: $query, prompt: Text("What did you eat?").foregroundStyle(Ember.dim))
                .font(Ember.font(18, .semibold)).foregroundStyle(Ember.cream)
                .focused($searchFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ember.dim) }
            }
        }
        .padding(14)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ember.fire.opacity(searchFocused ? 0.8 : 0.25), lineWidth: 1.5))
    }

    private var mealPicker: some View {
        HStack(spacing: 8) {
            ForEach(Meal.allCases) { m in
                Button {
                    withAnimation(.snappy) { meal = m }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label(m.rawValue, systemImage: m.symbol)
                        .labelStyle(.titleOnly)
                        .font(Ember.font(14, .bold))
                        .foregroundStyle(meal == m ? .white : Ember.dim)
                        .padding(.vertical, 9).frame(maxWidth: .infinity)
                        .background { if meal == m { Capsule().fill(Ember.fire) } else { Capsule().fill(Ember.card) } }
                }
                .buttonStyle(Squish())
            }
        }
    }

    private var servingsStepper: some View {
        HStack {
            Text("Servings").font(Ember.font(14, .bold)).foregroundStyle(Ember.dim)
            Spacer()
            ForEach([0.5, 1, 1.5, 2, 3], id: \.self) { s in
                Button { withAnimation(.snappy) { servings = s } } label: {
                    Text(s == 0.5 ? "½" : s == 1.5 ? "1½" : "\(Int(s))")
                        .font(Ember.font(15, .heavy))
                        .foregroundStyle(servings == s ? .white : Ember.dim)
                        .frame(width: 42, height: 34)
                        .background(servings == s ? AnyShapeStyle(Ember.fire) : AnyShapeStyle(Ember.card), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(Squish())
            }
        }
    }

    /// For anything not in the list: type the calories yourself.
    private var customCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add “\(query.trimmingCharacters(in: .whitespaces))”").font(Ember.font(16, .heavy)).foregroundStyle(Ember.cream)
            HStack(spacing: 10) {
                numberField("Calories", $customCal)
                Button {
                    log(Pick(name: query.trimmingCharacters(in: .whitespaces).capitalized, detail: "", cal: Double(customCal) ?? 0,
                             p: Double(customP) ?? 0, c: Double(customC) ?? 0, f: Double(customF) ?? 0, caf: 0))
                    customCal = ""; customP = ""; customC = ""; customF = ""; query = ""
                } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                        .frame(width: 50, height: 46).background(Ember.fire, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(Squish())
                .disabled(Double(customCal) == nil)
                .opacity(Double(customCal) == nil ? 0.4 : 1)
            }
            if showMacros {
                HStack(spacing: 8) { numberField("Protein g", $customP); numberField("Carbs g", $customC); numberField("Fat g", $customF) }
            } else {
                Button("+ protein, carbs, fat") { withAnimation(.snappy) { showMacros = true } }
                    .font(Ember.font(13, .bold)).foregroundStyle(Ember.orange)
            }
        }
        .padding(14)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ember.line))
    }

    private func numberField(_ label: String, _ text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(label).foregroundStyle(Ember.dim))
            .keyboardType(.numberPad)
            .font(Ember.font(16, .bold)).foregroundStyle(Ember.cream)
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(Ember.font(11, .heavy)).tracking(2).foregroundStyle(Ember.dim)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }

    private func row(_ pick: Pick) -> some View {
        let justAdded = added.contains(pick.id)
        return Button { log(pick) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pick.name).font(Ember.font(16, .bold)).foregroundStyle(Ember.cream)
                    Text([pick.detail.isEmpty ? nil : pick.detail,
                          pick.p > 0 ? "\(Int(pick.p))g protein" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(Ember.font(12, .medium)).foregroundStyle(Ember.dim)
                }
                Spacer()
                Text("\(Int(pick.cal * servings))").font(Ember.font(16, .heavy)).foregroundStyle(Ember.cream)
                Image(systemName: justAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(justAdded ? AnyShapeStyle(Ember.gold) : AnyShapeStyle(Ember.fire))
                    .symbolEffect(.bounce, value: justAdded)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Ember.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Squish())
        .accessibilityLabel("Add \(pick.name), \(Int(pick.cal * servings)) calories")
    }

    private func log(_ pick: Pick) {
        let e = FoodEntry(name: pick.name, cal: pick.cal, protein: pick.p, carbs: pick.c, fat: pick.f, caffeine: pick.caf,
                          servings: servings, meal: meal, day: day)
        context.insert(e)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { added.append(pick.id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { added.removeAll { $0 == pick.id } } }
    }
}
