import SwiftData
import SwiftUI
import UIKit

/// "Here's what I see": the photo, the food with its macros, portion and meal chips, one big Log it.
struct SnapResultSheet: View {
    let result: SnapResult
    let day: String
    var onLogged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var history: [FoodEntry]

    @State private var selected: FoodGuess?
    @State private var servings: Double = 1
    @State private var meal: Meal = .now
    @State private var shown = false
    @State private var showMore = false

    private let portions: [(Double, String)] = [(0.5, "½"), (1, "1"), (1.5, "1½"), (2, "2"), (3, "3")]

    /// Your recent foods first, then popular ones: the tap-to-pick fallback.
    private var picks: [FoodGuess] {
        var seen = Set<String>()
        var out: [FoodGuess] = []
        for e in history where seen.insert(e.name.lowercased()).inserted {
            out.append(FoodGuess(name: e.name, serving: "Recent", cal: e.cal, p: e.protein, c: e.carbs, f: e.fat, caf: e.caffeine, source: .recent))
            if out.count == 8 { break }
        }
        if out.count < 8 {
            let popular = ["Burrito bowl", "Pizza", "Chicken breast", "Cheeseburger", "Side salad", "Tacos", "Sushi roll", "Pasta",
                           "Scrambled eggs", "Greek yogurt", "Protein shake", "Iced latte"]
            for n in popular where out.count < 8 && !seen.contains(n.lowercased()) {
                if let q = QuickFood.all.first(where: { $0.name == n }) { out.append(FoodGuess(q, source: .recent)) }
            }
        }
        return out
    }

    private var alternatives: [FoodGuess] { result.guesses.filter { $0.id != selected?.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photo
                if let s = selected {
                    hero(s)
                        .id(s.id)
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                    if !alternatives.isEmpty || result.mode == .meal { notIt }
                    chips("PORTION", portions.map(\.1), selectedIndex: portions.firstIndex { $0.0 == servings }) { i in
                        servings = portions[i].0
                    }
                    chips("MEAL", Meal.allCases.map(\.rawValue), selectedIndex: Meal.allCases.firstIndex(of: meal)) { i in
                        meal = Meal.allCases[i]
                    }
                } else {
                    Text("Couldn't tell what that is. Tap it:")
                        .font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
                    pickGrid
                }
                if showMore && selected != nil { pickGrid }
            }
            .padding(20)
            .padding(.bottom, 110)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 30)
        }
        .scrollIndicators(.hidden)
        .background(EmberBackground())
        .safeAreaInset(edge: .bottom) { logButton }
        .preferredColorScheme(.dark)
        .onAppear {
            selected = result.guesses.first
            withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.75)) { shown = true }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var photo: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = result.image {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(height: 210).frame(maxWidth: .infinity).clipped()
            } else {
                Ember.fire.opacity(0.35).frame(height: 130)
                Image(systemName: result.mode.symbol).font(.system(size: 54, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            Label(badge, systemImage: result.mode.symbol)
                .font(Ember.font(12, .heavy)).tracking(1).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
        .frame(height: result.image == nil ? 130 : 210)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Ember.line))
        .accessibilityHidden(true)
    }

    private var badge: String {
        switch result.mode {
        case .meal: return result.guesses.isEmpty ? "SNAPPED" : "LOOKS LIKE"
        case .barcode: return "SCANNED BARCODE"
        case .label: return "READ FROM LABEL"
        }
    }

    private func hero(_ s: FoodGuess) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(Ember.font(26, .black)).foregroundStyle(Ember.cream).lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(servings == 1 ? s.serving : "\(s.serving) × \(portionLabel)")
                        .font(Ember.font(14, .semibold)).foregroundStyle(Ember.dim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int((s.cal * servings).rounded()))")
                        .font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(Ember.fire)
                        .contentTransition(.numericText(value: s.cal * servings))
                    Text("CAL").font(Ember.font(11, .heavy)).tracking(1.5).foregroundStyle(Ember.dim)
                }
            }
            HStack(spacing: 10) {
                MacroPill(label: "Protein", grams: s.p * servings, color: Ember.protein)
                MacroPill(label: "Carbs", grams: s.c * servings, color: Ember.carbs)
                MacroPill(label: "Fat", grams: s.f * servings, color: Ember.fat)
            }
        }
        .padding(18)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Ember.orange.opacity(0.35)))
        .shadow(color: Ember.orange.opacity(0.18), radius: 20, y: 8)
        .animation(.snappy, value: servings)
        .accessibilityElement(children: .combine)
    }

    private var portionLabel: String { portions.first { $0.0 == servings }?.1 ?? servings.formatted() }

    private var notIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOT IT? TAP THE RIGHT ONE").font(Ember.font(11, .heavy)).tracking(1.5).foregroundStyle(Ember.dim)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(alternatives.enumerated()), id: \.element.id) { i, alt in
                        Button { choose(alt) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.name).font(Ember.font(14, .bold)).foregroundStyle(Ember.cream).lineLimit(1)
                                Text("\(Int(alt.cal)) cal").font(Ember.font(12, .semibold)).foregroundStyle(Ember.orange)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Ember.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ember.line))
                        }
                        .buttonStyle(Squish())
                        .transition(.scale.combined(with: .opacity))
                        .animation(reduce ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.05), value: shown)
                    }
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMore.toggle() } } label: {
                        Label(showMore ? "Less" : "Something else", systemImage: showMore ? "chevron.up" : "square.grid.2x2")
                            .font(Ember.font(14, .bold)).foregroundStyle(Ember.cream)
                            .padding(.horizontal, 14).padding(.vertical, 16)
                            .background(Ember.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(Squish())
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var pickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(picks) { p in
                Button { choose(p) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name).font(Ember.font(15, .heavy)).foregroundStyle(Ember.cream).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text("\(Int(p.cal)) cal").font(Ember.font(13, .bold)).foregroundStyle(Ember.orange)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                    .padding(12)
                    .background(selected?.id == p.id ? Ember.orange.opacity(0.22) : Ember.card,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(selected?.id == p.id ? Ember.orange : Ember.line))
                }
                .buttonStyle(Squish())
            }
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
                        Text(labels[i]).font(Ember.font(labels[i].count > 3 ? 13 : 18, .heavy))
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
        Button(action: log) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .black))
                Text(selected.map { "Log it · \(Int(($0.cal * servings).rounded())) cal" } ?? "Pick a food")
                    .font(Ember.font(19, .black))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Ember.fire, in: Capsule())
            .shadow(color: Ember.pink.opacity(0.5), radius: 18, y: 6)
            .opacity(selected == nil ? 0.45 : 1)
        }
        .buttonStyle(Squish())
        .disabled(selected == nil)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [Ember.bg.opacity(0), Ember.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    // MARK: Actions

    private func choose(_ g: FoodGuess) {
        UISelectionFeedbackGenerator().selectionChanged()
        // You corrected the camera: next time this kind of photo suggests your pick first.
        if result.mode == .meal, let label = result.topLabel, g.name != result.guesses.first?.name,
           QuickFood.all.contains(where: { $0.name == g.name }) {
            FoodVision.learn(label: label, food: g.name)
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            selected = g
            showMore = false
        }
    }

    private func log() {
        guard let s = selected else { return }
        let thumb = result.image.flatMap { FoodVision.thumbnail($0) }
        let entry = FoodEntry(name: s.name, cal: s.cal, protein: s.p, carbs: s.c, fat: s.f, caffeine: s.caf,
                              servings: servings, meal: meal, day: day, photo: thumb)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { context.insert(entry) }
        try? context.save()
        FoodWatchBridge.shared.pushNow()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged()
        dismiss()
    }
}

/// A drawn sample plate for simulator screenshots (launch with -demo -snap).
enum DemoSnap {
    static var result: SnapResult {
        let names = ["Burrito bowl", "Tacos", "Burrito", "Nachos"]
        let guesses = names.compactMap { n in QuickFood.all.first { $0.name == n }.map { FoodGuess($0) } }
        return SnapResult(image: image(), mode: .meal, guesses: guesses, topLabel: nil)
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
