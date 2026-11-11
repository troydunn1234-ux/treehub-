import SwiftUI
import SwiftData

/// Everything you've logged, newest day first: each meal with its photo, items and macros.
/// Day totals sit in the section header. Tap a meal to edit it.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var all: [FoodEntry]
    @Query private var logs: [DayLog]
    @AppStorage("goal") private var goal: Double = 2200
    @State private var editing: FoodEntry?
    @State private var showReport = false

    private struct DayGroup: Identifiable {
        let day: String
        let entries: [FoodEntry]
        var id: String { day }
        var cal: Double { entries.reduce(0) { $0 + $1.cal * $1.servings } }
        func total(_ k: KeyPath<FoodEntry, Double>) -> Double { entries.reduce(0) { $0 + $1[keyPath: k] * $1.servings } }
    }

    private var days: [DayGroup] {
        var order: [String] = []
        var byDay: [String: [FoodEntry]] = [:]
        for e in all {
            if byDay[e.day] == nil { order.append(e.day) }
            byDay[e.day, default: []].append(e)
        }
        return order.sorted(by: >).map { DayGroup(day: $0, entries: byDay[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: .sectionHeaders) {
                    if days.isEmpty {
                        VStack(spacing: 8) {
                            Text("📖").font(.system(size: 44))
                            Text("Nothing logged yet").font(Ember.font(17, .bold)).foregroundStyle(Ember.cream)
                            Text("Meals you snap or add show up here, day by day.")
                                .font(Ember.font(14, .medium)).foregroundStyle(Ember.dim).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(days) { g in
                        Section {
                            ForEach(Meal.allCases) { meal in
                                let items = g.entries.filter { $0.meal == meal }.sorted { $0.createdAt < $1.createdAt }
                                if !items.isEmpty { mealCard(meal, items) }
                            }
                        } header: {
                            dayHeader(g)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(EmberBackground())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showReport = true } label: {
                        Label("Week", systemImage: "chart.bar.fill").font(Ember.font(15, .bold)).foregroundStyle(Ember.orange)
                    }
                    .accessibilityLabel("Weekly report")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Ember.font(16, .bold)).foregroundStyle(Ember.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { e in EntryEditSheet(entry: e).presentationDetents([.large]) }
        .sheet(isPresented: $showReport) { WeekReportView().presentationDetents([.large]) }
    }

    private func dayHeader(_ g: DayGroup) -> some View {
        let log = logs.first { $0.day == g.day }
        let over = g.cal > goal
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Day.title(g.day)).font(Ember.font(20, .heavy)).foregroundStyle(Ember.cream)
                Text("\(Int(g.total(\.protein)))g P · \(Int(g.total(\.carbs)))g C · \(Int(g.total(\.fat)))g F"
                     + ((log?.water ?? 0) > 0 ? " · \(log?.water ?? 0) 💧" : ""))
                    .font(Ember.font(12, .semibold)).foregroundStyle(Ember.dim)
            }
            Spacer()
            Text("\(Int(g.cal)) cal").font(Ember.font(16, .heavy)).foregroundStyle(over ? Ember.pink : Ember.cream)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Ember.bg.opacity(0.92))
        .accessibilityElement(children: .combine)
    }

    private func mealCard(_ meal: Meal, _ items: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(meal.rawValue, systemImage: meal.symbol).font(Ember.font(15, .heavy)).foregroundStyle(Ember.cream)
                Spacer()
                Text("\(Int(items.reduce(0) { $0 + $1.cal * $1.servings })) cal").font(Ember.font(13, .bold)).foregroundStyle(Ember.dim)
            }
            VStack(spacing: 0) {
                ForEach(items) { e in
                    Button { editing = e } label: { HistoryRow(entry: e) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit this item")
                    if e.id != items.last?.id { Divider().overlay(Ember.line).padding(.leading, 14) }
                }
            }
            .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
        }
    }
}

/// One logged item in History: photo thumbnail, name, macros, calories and the time.
struct HistoryRow: View {
    let entry: FoodEntry
    private var s: Double { entry.servings }
    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ember.line))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: entry.meal.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(Ember.dim)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(Ember.font(16, .bold)).foregroundStyle(Ember.cream).lineLimit(1)
                Text(((s != 1 ? ["×\(s.formatted())"] : []) +
                      ["\(Int(entry.protein * s))g P", "\(Int(entry.carbs * s))g C", "\(Int(entry.fat * s))g F",
                       entry.createdAt.formatted(date: .omitted, time: .shortened)]).joined(separator: " · "))
                    .font(Ember.font(12, .medium)).foregroundStyle(Ember.dim).lineLimit(1)
            }
            Spacer()
            Text("\(Int(entry.cal * s))").font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Edit one logged item: name, meal, servings and the per-serving numbers. Changes save on Done.
struct EntryEditSheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var meal: Meal = .snacks
    @State private var servings: Double = 1
    @State private var cal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var caffeine = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let data = entry.photo, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(height: 160).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
                            .accessibilityHidden(true)
                    }
                    field("Name", text: $name, keyboard: .default)
                    VStack(alignment: .leading, spacing: 8) {
                        label("MEAL")
                        HStack(spacing: 6) {
                            ForEach(Meal.allCases) { m in
                                Button { meal = m; UISelectionFeedbackGenerator().selectionChanged() } label: {
                                    Label(m.rawValue, systemImage: m.symbol).font(Ember.font(12, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                        .foregroundStyle(meal == m ? .white : Ember.dim)
                                        .padding(.horizontal, 10).padding(.vertical, 9)
                                        .frame(maxWidth: .infinity)
                                        .background { if meal == m { Capsule().fill(Ember.fire) } else { Capsule().fill(Ember.card) } }
                                }
                                .buttonStyle(Squish())
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        label("SERVINGS")
                        HStack {
                            Text(servings.formatted()).font(Ember.font(22, .heavy)).foregroundStyle(Ember.cream)
                                .contentTransition(.numericText(value: servings))
                            Spacer()
                            Stepper("", value: $servings, in: 0.25...20, step: 0.25).labelsHidden().tint(Ember.orange)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Ember.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    label("PER SERVING")
                    HStack(spacing: 8) {
                        numberField("Cal", $cal, Ember.orange)
                        numberField("Protein", $protein, Ember.protein)
                        numberField("Carbs", $carbs, Ember.carbs)
                        numberField("Fat", $fat, Ember.fat)
                    }
                    numberField("Caffeine (mg)", $caffeine, Ember.cream)
                    Text("Total: \(Int((Double(cal) ?? 0) * servings)) cal").font(Ember.font(14, .bold)).foregroundStyle(Ember.dim)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete item", systemImage: "trash").font(Ember.font(15, .heavy)).foregroundStyle(Ember.pink)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Ember.card, in: Capsule())
                    }
                    .buttonStyle(Squish())
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(EmberBackground())
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Ember.dim) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.font(Ember.font(16, .bold)).foregroundStyle(Ember.orange)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(entry.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            name = entry.name; meal = entry.meal; servings = entry.servings
            cal = Self.fmt(entry.cal); protein = Self.fmt(entry.protein); carbs = Self.fmt(entry.carbs)
            fat = Self.fmt(entry.fat); caffeine = Self.fmt(entry.caffeine)
        }
    }

    private static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    private func save() {
        entry.name = name.trimmingCharacters(in: .whitespaces)
        entry.mealRaw = meal.rawValue
        entry.servings = max(0.25, servings)
        entry.cal = max(0, Double(cal) ?? entry.cal)
        entry.protein = max(0, Double(protein) ?? entry.protein)
        entry.carbs = max(0, Double(carbs) ?? entry.carbs)
        entry.fat = max(0, Double(fat) ?? entry.fat)
        entry.caffeine = max(0, Double(caffeine) ?? entry.caffeine)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Ember.font(10, .heavy)).tracking(1.2).foregroundStyle(Ember.dim)
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title.uppercased())
            TextField(title, text: text).keyboardType(keyboard)
                .font(Ember.font(17, .bold)).foregroundStyle(Ember.cream)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Ember.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func numberField(_ title: String, _ text: Binding<String>, _ color: Color) -> some View {
        VStack(spacing: 6) {
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.center)
                .font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
            Text(title.uppercased()).font(Ember.font(9, .heavy)).tracking(1).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.25)))
    }
}
