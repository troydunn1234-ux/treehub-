import SwiftData
import SwiftUI
import UIKit

/// One thing on the plate, with its own portion.
struct PlateItem: Identifiable, Equatable {
    let id = UUID()
    var food: FoodGuess
    var servings: Double = 1
    var cal: Double { food.cal * servings }
}

/// "Here's what I see": the photo, a plate of items (each with its own portion), totals, meal chips, one big Log it.
struct SnapResultSheet: View {
    let result: SnapResult
    let day: String
    var onLogged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var history: [FoodEntry]

    @State private var plate: [PlateItem] = []
    @State private var meal: Meal = .now
    @State private var shown = false
    @State private var picking = false
    /// When set, the picker swaps this item instead of adding a new one.
    @State private var swapping: UUID?

    private let portions: [(Double, String)] = [(0.5, "½"), (1, "1"), (1.5, "1½"), (2, "2")]

    private var totals: (cal: Double, p: Double, c: Double, f: Double) {
        var t: (cal: Double, p: Double, c: Double, f: Double) = (0, 0, 0, 0)
        for i in plate {
            t.cal += i.food.cal * i.servings; t.p += i.food.p * i.servings
            t.c += i.food.c * i.servings; t.f += i.food.f * i.servings
        }
        return t
    }

    /// "Not it?" row: what the photo also looked like, plus close relatives. Never random snacks.
    private var alternatives: [FoodGuess] {
        let on = Set(plate.map { $0.food.name })
        return result.guesses.filter { !on.contains($0.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photo
                if let note = result.note {
                    Label(note, systemImage: result.ai ? "text.bubble" : "wifi.exclamationmark")
                        .font(Ember.font(12, .semibold)).foregroundStyle(Ember.dim)
                }
                if plate.isEmpty {
                    Text("Couldn't tell what that is. Add what's on your plate:")
                        .font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
                } else {
                    totalsCard
                    ForEach($plate) { $item in
                        itemCard($item)
                            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                addButton
                if result.mode == .meal && !alternatives.isEmpty { notIt }
                chips("MEAL", Meal.allCases.map(\.rawValue), selectedIndex: Meal.allCases.firstIndex(of: meal)) { i in
                    meal = Meal.allCases[i]
                }
            }
            .padding(20)
            .padding(.bottom, 110)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 30)
            .animation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.8), value: plate)
        }
        .scrollIndicators(.hidden)
        .background(EmberBackground())
        .safeAreaInset(edge: .bottom) { logButton }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $picking) {
            FoodPicker(recent: recentFoods) { food in pick(food) }
                .presentationDetents([.large])
        }
        .onAppear {
            plate = (result.plate.isEmpty ? Array(result.guesses.prefix(result.mode == .meal ? 0 : 1)) : result.plate)
                .map { PlateItem(food: $0) }
            if plate.isEmpty && result.mode != .meal, let g = result.guesses.first { plate = [PlateItem(food: g)] }
            withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.75)) { shown = true }
        }
    }

    private var recentFoods: [FoodGuess] {
        var seen = Set<String>(), out: [FoodGuess] = []
        for e in history where seen.insert(e.name.lowercased()).inserted {
            out.append(FoodGuess(name: e.name, serving: "Recent", cal: e.cal, p: e.protein, c: e.carbs, f: e.fat, caf: e.caffeine, source: .recent))
            if out.count == 12 { break }
        }
        return out
    }

    // MARK: Pieces

    @ViewBuilder private var photo: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = result.image {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(height: 200).frame(maxWidth: .infinity).clipped()
            } else {
                Ember.fire.opacity(0.35).frame(height: 130)
                Image(systemName: result.mode.symbol).font(.system(size: 54, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 8) {
                Label(badge, systemImage: result.mode.symbol)
                    .font(Ember.font(12, .heavy)).tracking(1).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                if result.ai {
                    Label("AI", systemImage: "sparkles")
                        .font(Ember.font(12, .black)).tracking(1).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Ember.fire, in: Capsule())
                }
            }
            .padding(12)
        }
        .frame(height: result.image == nil ? 130 : 200)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Ember.line))
        .accessibilityHidden(true)
    }

    private var badge: String {
        switch result.mode {
        case .meal: return plate.count > 1 ? "ON YOUR PLATE" : (plate.isEmpty ? "SNAPPED" : "LOOKS LIKE")
        case .barcode: return "SCANNED BARCODE"
        case .label: return "READ FROM LABEL"
        }
    }

    private var totalsCard: some View {
        let t = totals
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(plate.count == 1 ? "1 item" : "\(plate.count) items")
                    .font(Ember.font(15, .heavy)).foregroundStyle(Ember.dim)
                Spacer()
                Text("\(Int(t.cal.rounded()))")
                    .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Ember.fire)
                    .contentTransition(.numericText(value: t.cal))
                Text("CAL").font(Ember.font(11, .heavy)).tracking(1.5).foregroundStyle(Ember.dim)
            }
            HStack(spacing: 10) {
                MacroPill(label: "Protein", grams: t.p, color: Ember.protein)
                MacroPill(label: "Carbs", grams: t.c, color: Ember.carbs)
                MacroPill(label: "Fat", grams: t.f, color: Ember.fat)
            }
        }
        .padding(18)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Ember.orange.opacity(0.35)))
        .shadow(color: Ember.orange.opacity(0.18), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func itemCard(_ item: Binding<PlateItem>) -> some View {
        let it = item.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(FoodGroup.of(name: it.food.name, tags: QuickFood.all.first { $0.name == it.food.name }?.tags ?? []).emoji)
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
                    .background(Ember.card, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Button { swapping = it.id; picking = true } label: {
                        HStack(spacing: 4) {
                            Text(it.food.name).font(Ember.font(18, .heavy)).foregroundStyle(Ember.cream)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy)).foregroundStyle(Ember.dim)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Swap for a different food")
                    Text("\(amount(it)) · P \(Int((it.food.p * it.servings).rounded())) C \(Int((it.food.c * it.servings).rounded())) F \(Int((it.food.f * it.servings).rounded()))")
                        .font(Ember.font(12, .semibold)).foregroundStyle(Ember.dim).lineLimit(2)
                    if let src = it.food.sourceNote {
                        Label(src, systemImage: src.hasPrefix("USDA") ? "checkmark.seal.fill" : "sparkles")
                            .font(Ember.font(11, .bold)).foregroundStyle(src.hasPrefix("USDA") ? Ember.protein : Ember.gold)
                            .lineLimit(2)
                    }
                    if let ref = it.food.sizedFrom {
                        Label(ref.prefix(1).uppercased() + ref.dropFirst(), systemImage: "ruler")
                            .font(Ember.font(11, .semibold)).foregroundStyle(Ember.dim).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        plate.removeAll { $0.id == it.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .black)).foregroundStyle(Ember.dim)
                            .frame(width: 30, height: 30).background(Ember.card, in: Circle())
                    }
                    .accessibilityLabel("Remove \(it.food.name)")
                    Text("\(Int(it.cal.rounded())) cal").font(Ember.font(15, .black)).foregroundStyle(Ember.orange)
                        .contentTransition(.numericText(value: it.cal))
                }
            }
            HStack(spacing: 8) {
                ForEach(portions.indices, id: \.self) { k in
                    let p = portions[k]
                    let on = p.0 == it.servings
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        item.wrappedValue.servings = p.0
                    } label: {
                        Text(p.1).font(Ember.font(16, .heavy)).foregroundStyle(on ? .white : Ember.cream)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Ember.fire) : AnyShapeStyle(Ember.card))
                            }
                    }
                    .buttonStyle(Squish())
                    .accessibilityLabel("\(p.1) serving")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let base = it.food.grams, base > 0 { gramsControl(item, base: base) }
        }
        .padding(14)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
    }

    private func label(_ s: Double) -> String { portions.first { $0.0 == s }?.1 ?? s.formatted(.number.precision(.fractionLength(0...2))) }

    /// "170 g" when the weight is known, else "6 oz × 1½".
    private func amount(_ it: PlateItem) -> String {
        if let g = it.food.grams, g > 0 { return "\(Int((g * it.servings).rounded())) g" }
        return "\(it.food.serving)\(it.servings == 1 ? "" : " × \(label(it.servings))")"
    }

    /// Fine-tune the weight: −25 g, a slider across the estimate's likely range, +25 g. Macros follow live.
    private func gramsControl(_ item: Binding<PlateItem>, base: Double) -> some View {
        let it = item.wrappedValue
        let now = base * it.servings
        let lo = min(it.food.gramsLow ?? base * 0.7, now)
        let hi = max(it.food.gramsHigh ?? base * 1.35, now, lo + 10)
        let grams = Binding<Double>(
            get: { base * item.wrappedValue.servings },
            set: { v in item.wrappedValue.servings = max(5, (v / 5).rounded() * 5) / base })
        return HStack(spacing: 10) {
            stepButton("minus", label: "25 grams less") {
                item.wrappedValue.servings = max(5, base * item.wrappedValue.servings - 25) / base
            }
            VStack(spacing: 2) {
                Slider(value: grams, in: lo...hi, step: 5)
                    .tint(Ember.orange)
                    .accessibilityLabel("Weight")
                    .accessibilityValue("\(Int(now.rounded())) grams")
                HStack {
                    Text("\(Int(lo)) g").font(Ember.font(10, .bold)).foregroundStyle(Ember.dim)
                    Spacer()
                    Text("\(Int(now.rounded())) g").font(Ember.font(13, .black)).foregroundStyle(Ember.cream)
                        .contentTransition(.numericText(value: now))
                    Spacer()
                    Text("\(Int(hi)) g").font(Ember.font(10, .bold)).foregroundStyle(Ember.dim)
                }
            }
            stepButton("plus", label: "25 grams more") {
                item.wrappedValue.servings = (base * item.wrappedValue.servings + 25) / base
            }
        }
        .padding(.top, 2)
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .black)).foregroundStyle(Ember.cream)
                .frame(width: 38, height: 38).background(Ember.bg.opacity(0.6), in: Circle())
        }
        .buttonStyle(Squish())
        .accessibilityLabel(label)
    }

    private var addButton: some View {
        Button { swapping = nil; picking = true } label: {
            Label(plate.isEmpty ? "Add what's on your plate" : "Add item", systemImage: "plus.circle.fill")
                .font(Ember.font(16, .heavy)).foregroundStyle(Ember.orange)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Ember.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        .buttonStyle(Squish())
    }

    private var notIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALSO LOOKS LIKE · TAP TO ADD").font(Ember.font(11, .heavy)).tracking(1.5).foregroundStyle(Ember.dim)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(alternatives) { alt in
                        Button { pick(alt) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.name).font(Ember.font(14, .bold)).foregroundStyle(Ember.cream).lineLimit(1)
                                Text("\(Int(alt.cal)) cal").font(Ember.font(12, .semibold)).foregroundStyle(Ember.orange)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Ember.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ember.line))
                        }
                        .buttonStyle(Squish())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chips(_ title: String, _ labels: [String], selectedIndex: Int?, onPick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Ember.font(11, .heavy)).tracking(1.5).foregroundStyle(Ember.dim)
            HStack(spacing: 8) {
                ForEach(labels.indices, id: \.self) { i in
                    let on = i == selectedIndex
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { onPick(i) }
                    } label: {
                        Text(labels[i]).font(Ember.font(13, .heavy))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(on ? .white : Ember.cream)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Ember.fire) : AnyShapeStyle(Ember.card))
                            }
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? .clear : Ember.line))
                    }
                    .buttonStyle(Squish())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var logButton: some View {
        let t = totals
        return Button(action: log) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .black))
                Text(plate.isEmpty ? "Add a food" : "Log \(plate.count == 1 ? "it" : "\(plate.count) items") · \(Int(t.cal.rounded())) cal")
                    .font(Ember.font(19, .black))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Ember.fire, in: Capsule())
            .shadow(color: Ember.pink.opacity(0.5), radius: 18, y: 6)
            .opacity(plate.isEmpty ? 0.45 : 1)
        }
        .buttonStyle(Squish())
        .disabled(plate.isEmpty)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [Ember.bg.opacity(0), Ember.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    // MARK: Actions

    private func pick(_ g: FoodGuess) {
        UISelectionFeedbackGenerator().selectionChanged()
        if let sid = swapping, let i = plate.firstIndex(where: { $0.id == sid }) {
            // You corrected the camera: next time this kind of photo suggests your pick first.
            if result.mode == .meal, !result.ai, i == 0, let label = result.topLabel,
               QuickFood.all.contains(where: { $0.name == g.name }) {
                FoodVision.learn(label: label, food: g.name)
            }
            plate[i].food = g
        } else if let i = plate.firstIndex(where: { $0.food.name == g.name }) {
            plate[i].servings += 1
        } else {
            plate.append(PlateItem(food: g))
        }
        swapping = nil
    }

    private func log() {
        guard !plate.isEmpty else { return }
        let thumb = result.image.flatMap { FoodVision.thumbnail($0) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            for (i, it) in plate.enumerated() {
                let entry = FoodEntry(name: it.food.name, cal: it.food.cal, protein: it.food.p, carbs: it.food.c, fat: it.food.f,
                                      caffeine: it.food.caf, servings: it.servings, meal: meal, day: day,
                                      photo: i == 0 ? thumb : nil)
                context.insert(entry)
            }
        }
        try? context.save()
        FoodWatchBridge.shared.pushNow()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged()
        dismiss()
    }
}

/// Fast "what else is on the plate" picker: search, group tabs, emoji grid.
struct FoodPicker: View {
    let recent: [FoodGuess]
    var onPick: (FoodGuess) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var group: FoodGroup? = .protein

    private var foods: [FoodGuess] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            return QuickFood.all.filter { $0.name.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) } }
                .prefix(40).map { FoodGuess($0) }
        }
        guard let g = group else { return recent }
        return QuickFood.all.filter { FoodGroup.of($0) == g }.map { FoodGuess($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add to plate").font(Ember.font(24, .black)).foregroundStyle(Ember.cream)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Ember.dim)
                        .frame(width: 36, height: 36).background(Ember.card, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Ember.dim)
                TextField("", text: $query, prompt: Text("Search foods").foregroundStyle(Ember.dim))
                    .font(Ember.font(16, .semibold)).foregroundStyle(Ember.cream)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Ember.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if !recent.isEmpty { tab(nil, "🕘 Recent") }
                    ForEach(FoodGroup.allCases) { g in tab(g, "\(g.emoji) \(g.rawValue)") }
                }
            }
            .scrollIndicators(.hidden)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(foods) { f in
                        Button { onPick(f); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(FoodGroup.of(name: f.name, tags: QuickFood.all.first { $0.name == f.name }?.tags ?? []).emoji)
                                    .font(.system(size: 22))
                                Text(f.name).font(Ember.font(15, .heavy)).foregroundStyle(Ember.cream).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text("\(Int(f.cal)) cal · \(f.serving)").font(Ember.font(11, .bold)).foregroundStyle(Ember.orange)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                            .padding(12)
                            .background(Ember.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ember.line))
                        }
                        .buttonStyle(Squish())
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .background(EmberBackground())
        .preferredColorScheme(.dark)
    }

    private func tab(_ g: FoodGroup?, _ title: String) -> some View {
        let on = query.isEmpty && g == group
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            query = ""
            withAnimation(.snappy) { group = g }
        } label: {
            Text(title).font(Ember.font(14, .heavy)).foregroundStyle(on ? .white : Ember.cream)
                .padding(.horizontal, 14).frame(height: 38)
                .background { Capsule().fill(on ? AnyShapeStyle(Ember.fire) : AnyShapeStyle(Ember.card)) }
        }
        .buttonStyle(Squish())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A drawn sample plate for simulator screenshots (launch with -demo -snap).
enum DemoSnap {
    static var result: SnapResult {
        func g(_ n: String) -> FoodGuess? { QuickFood.all.first { $0.name == n }.map { FoodGuess($0) } }
        let ref = "sized from your meal-prep container"
        let plate = [
            FoodGuess(name: "Grilled sirloin steak", serving: "170 g", cal: 330, p: 51.7, c: 0, f: 12.4, source: .photo,
                      grams: 170, gramsLow: 140, gramsHigh: 210,
                      sourceNote: "USDA: Beef, top sirloin, steak, lean, cooked, grilled", sizedFrom: ref),
            FoodGuess(name: "Roasted potatoes", serving: "180 g", cal: 238, p: 3.8, c: 34.6, f: 9.9, source: .photo,
                      grams: 180, gramsLow: 130, gramsHigh: 230,
                      sourceNote: "USDA: Potato, roasted + ~1 tsp oil", sizedFrom: ref),
            FoodGuess(name: "Roasted asparagus", serving: "110 g", cal: 64, p: 2.6, c: 4.6, f: 4.7, source: .photo,
                      grams: 110, gramsLow: 80, gramsHigh: 150,
                      sourceNote: "USDA: Asparagus, cooked + ~1 tsp oil", sizedFrom: ref),
        ]
        let alts = ["Ribeye steak", "Sirloin steak", "Baked potato", "Green beans"].compactMap(g)
        return SnapResult(image: image(), mode: .meal, guesses: alts, topLabel: nil, plate: plate, ai: true,
                          note: "Steak, potatoes and asparagus in a glass meal-prep container.")
    }

    static func image() -> UIImage {
        let size = CGSize(width: 900, height: 700)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 0.28, green: 0.18, blue: 0.12, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            // wood grain
            for i in 0..<14 {
                UIColor(white: 0, alpha: 0.08).setFill()
                c.fill(CGRect(x: 0, y: CGFloat(i) * 52, width: size.width, height: 10))
            }
            // bowl
            UIColor(white: 0.95, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 170, y: 90, width: 560, height: 520))
            UIColor(red: 0.98, green: 0.93, blue: 0.85, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 205, y: 125, width: 490, height: 450))
            // rice, beans, chicken, salsa, guac, cheese, lettuce
            let blobs: [(UIColor, CGRect)] = [
                (UIColor(white: 0.97, alpha: 1), CGRect(x: 240, y: 170, width: 230, height: 190)),
                (UIColor(red: 0.25, green: 0.12, blue: 0.1, alpha: 1), CGRect(x: 450, y: 170, width: 200, height: 170)),
                (UIColor(red: 0.82, green: 0.55, blue: 0.3, alpha: 1), CGRect(x: 300, y: 330, width: 230, height: 190)),
                (UIColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1), CGRect(x: 510, y: 340, width: 150, height: 130)),
                (UIColor(red: 0.45, green: 0.7, blue: 0.25, alpha: 1), CGRect(x: 470, y: 450, width: 150, height: 100)),
                (UIColor(red: 1.0, green: 0.82, blue: 0.3, alpha: 1), CGRect(x: 390, y: 260, width: 120, height: 90)),
            ]
            for (color, rect) in blobs {
                color.setFill()
                c.fillEllipse(in: rect)
            }
            // lime wedge
            UIColor(red: 0.55, green: 0.85, blue: 0.3, alpha: 1).setFill()
            c.move(to: CGPoint(x: 600, y: 160))
            c.addLine(to: CGPoint(x: 690, y: 230))
            c.addLine(to: CGPoint(x: 620, y: 270))
            c.closePath()
            c.fillPath()
        }
    }
}
