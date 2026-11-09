import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.createdAt) private var all: [FoodEntry]
    @AppStorage("goal") private var goal: Double = 2200
    @State private var day = Day.key(Date())
    @State private var adding = false
    @State private var editingGoal = false
    @State private var dragX: CGFloat = 0
    @State private var snapping = false
    @State private var celebrate = 0
    @State private var demoSnap: SnapResult?
    @State private var health = FoodHealth.shared
    @AppStorage("eatBackPct") private var eatBack: Int = 0
    @AppStorage("ringNet") private var ringNet = false
    @Environment(\.scenePhase) private var phase

    private var entries: [FoodEntry] { all.filter { $0.day == day } }
    private var eaten: Double { entries.reduce(0) { $0 + $1.cal * $1.servings } }
    private var isToday: Bool { day == Day.key(Date()) }
    /// Burned numbers only make sense for today.
    private var active: Double { isToday && health.showing ? health.active : 0 }
    /// Goal plus the share of active calories you chose to eat back.
    private var dayGoal: Double { goal + active * Double(eatBack) / 100 }
    private func total(_ k: KeyPath<FoodEntry, Double>) -> Double { entries.reduce(0) { $0 + $1[keyPath: k] * $1.servings } }

    /// Days in a row (ending today or yesterday) with something logged.
    private var streak: Int {
        let days = Set(all.map(\.day))
        var k = Day.key(Date())
        if !days.contains(k) { k = Day.shift(k, by: -1) }
        var n = 0
        while days.contains(k) { n += 1; k = Day.shift(k, by: -1) }
        return n
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            EmberBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    CalorieRing(eaten: ringNet && active > 0 ? eaten - active : eaten, goal: dayGoal,
                                subtitle: ringNet && active > 0 ? "\(Int(eaten)) eaten − \(Int(active)) burned" : nil)
                        .onTapGesture { editingGoal = true }
                        .accessibilityHint("Double tap to change your daily goal")
                    if isToday {
                        if health.showing {
                            BurnedStrip(health: health, net: $ringNet, eatBack: eatBack)
                        } else if health.available {
                            Button { Task { await health.connect() } } label: {
                                Label("Sync with Apple Health", systemImage: "heart.fill")
                                    .font(Ember.font(14, .bold)).foregroundStyle(Ember.cream)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(Ember.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Ember.line))
                            }
                            .buttonStyle(Squish())
                            .accessibilityHint("Saves meals to Health and shows calories burned from Whoop and Apple Watch")
                        }
                    }
                    macros
                    ForEach(Meal.allCases) { meal in mealSection(meal) }
                    if entries.isEmpty { emptyState }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 170)
                .offset(x: dragX)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(daySwipe)

            addButtons
            Confetti(trigger: celebrate)
        }
        .sheet(isPresented: $adding) { AddFoodSheet(day: day).presentationDetents([.large]) }
        .fullScreenCover(isPresented: $snapping) { SnapView(day: day) { celebrate += 1 } }
        .sheet(item: $demoSnap) { r in
            SnapResultSheet(result: r, day: day) { celebrate += 1 }.presentationDetents([.large])
        }
        .task { await health.refreshBurned() }
        .onChange(of: phase) { _, p in if p == .active { Task { await health.refreshBurned() } } }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demo") && args.contains("-snap") && demoSnap == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { demoSnap = DemoSnap.result }
            }
        }
        .sheet(isPresented: $editingGoal) { GoalSheet(goal: $goal).presentationDetents([.height(320), .large]) }
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button { change(by: -1) } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)) }
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 2) {
                Text("FOOD BOOK").font(Ember.font(11, .heavy)).tracking(3).foregroundStyle(Ember.fire)
                Text(Day.title(day)).font(Ember.font(26, .heavy)).foregroundStyle(Ember.cream)
                    .contentTransition(.numericText())
            }
            Spacer()
            if Day.key(Date()) != day {
                Button { change(by: 1) } label: { Image(systemName: "chevron.right").font(.system(size: 17, weight: .bold)) }
                    .accessibilityLabel("Next day")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").foregroundStyle(Ember.fire)
                    Text("\(streak)").font(Ember.font(15, .heavy)).foregroundStyle(Ember.cream)
                }
                .accessibilityLabel("\(streak) day streak")
            }
        }
        .foregroundStyle(Ember.cream)
        .padding(.top, 6)
    }

    private var macros: some View {
        HStack(spacing: 10) {
            MacroPill(label: "Protein", grams: total(\.protein), color: Ember.protein)
            MacroPill(label: "Carbs", grams: total(\.carbs), color: Ember.carbs)
            MacroPill(label: "Fat", grams: total(\.fat), color: Ember.fat)
            let caf = total(\.caffeine)
            if caf > 0 { MacroPill(label: "Caffeine", grams: caf, color: Ember.cream, unit: "mg") }
        }
    }

    @ViewBuilder private func mealSection(_ meal: Meal) -> some View {
        let items = entries.filter { $0.meal == meal }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(meal.rawValue, systemImage: meal.symbol).font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
                    Spacer()
                    Text("\(Int(items.reduce(0) { $0 + $1.cal * $1.servings })) cal").font(Ember.font(14, .bold)).foregroundStyle(Ember.dim)
                }
                VStack(spacing: 0) {
                    ForEach(items) { e in
                        FoodRow(entry: e) { delete(e) }
                        if e.id != items.last?.id { Divider().overlay(Ember.line).padding(.leading, 14) }
                    }
                }
                .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Ember.line))
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🍽️").font(.system(size: 44))
            Text(day == Day.key(Date()) ? "Nothing logged yet today" : "Nothing logged this day")
                .font(Ember.font(17, .bold)).foregroundStyle(Ember.cream)
            Text("Tap the camera and snap your plate. Food Book fills in the macros.")
                .font(Ember.font(14, .medium)).foregroundStyle(Ember.dim).multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }

    /// Big camera (the main way in) with a small + above it for picking or searching by hand.
    private var addButtons: some View {
        VStack(spacing: 12) {
            Button { adding = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .black))
                    .foregroundStyle(Ember.cream)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Ember.line))
            }
            .buttonStyle(Squish())
            .accessibilityLabel("Add food by name")
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                snapping = true
            } label: {
                SnapButtonFace()
            }
            .buttonStyle(Squish())
            .accessibilityLabel("Snap food")
            .accessibilityHint("Take a picture and Food Book fills in the calories and macros")
        }
        .padding(.trailing, 20)
        .padding(.bottom, 22)
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { dragX = v.translation.width * 0.35 } }
            .onEnded { v in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragX = 0 }
                guard abs(v.translation.width) > 80, abs(v.translation.width) > abs(v.translation.height) else { return }
                change(by: v.translation.width > 0 ? -1 : 1)
            }
    }

    private func change(by n: Int) {
        let next = Day.shift(day, by: n)
        guard Day.date(next) <= Date() else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { day = next }
    }

    private func delete(_ e: FoodEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { context.delete(e) }
        try? context.save()
    }
}

struct CalorieRing: View {
    let eaten: Double
    let goal: Double
    var subtitle: String? = nil
    @State private var shown: Double = 0

    private var left: Int { Int((goal - eaten).rounded()) }
    private var progress: Double { goal > 0 ? eaten / goal : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Ember.card, lineWidth: 22)
            Circle()
                .trim(from: 0, to: min(1, shown))
                .stroke(Ember.fire, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Ember.orange.opacity(0.6), radius: 14)
            if shown > 1 {
                Circle()
                    .trim(from: 0, to: min(1, shown - 1))
                    .stroke(Ember.pink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-22)
            }
            VStack(spacing: 2) {
                Text("\(abs(left))")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(Ember.cream)
                    .contentTransition(.numericText(value: Double(left)))
                Text(left >= 0 ? "CALORIES LEFT" : "OVER GOAL").font(Ember.font(12, .heavy)).tracking(1.5)
                    .foregroundStyle(left >= 0 ? Ember.dim : Ember.pink)
                Text(subtitle ?? "\(Int(eaten)) of \(Int(goal))").font(Ember.font(subtitle == nil ? 14 : 12, .bold))
                    .foregroundStyle(Ember.dim).padding(.top, 4)
                    .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 180)
            }
        }
        .frame(width: 240, height: 240)
        .padding(.vertical, 8)
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.8)) { shown = progress } }
        .onChange(of: progress) { _, p in withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { shown = p } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left >= 0 ? "\(left) calories left of \(Int(goal))" : "\(-left) calories over your \(Int(goal)) goal")
    }
}

struct MacroPill: View {
    let label: String
    let grams: Double
    let color: Color
    var unit = "g"
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(grams.rounded()))\(unit)").font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
                .contentTransition(.numericText(value: grams))
            Text(label.uppercased()).font(Ember.font(9, .heavy)).tracking(1).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.25)))
        .animation(.snappy, value: grams)
    }
}

struct FoodRow: View {
    let entry: FoodEntry
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash.fill").foregroundStyle(.white).frame(width: 70).frame(maxHeight: .infinity)
            }
            .background(Ember.pink)
            .opacity(offset < -10 ? 1 : 0)
            HStack(spacing: 12) {
                if let data = entry.photo, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Ember.line))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(Ember.font(16, .bold)).foregroundStyle(Ember.cream).lineLimit(1)
                    let macros = [Int(entry.protein * entry.servings) > 0 ? "\(Int(entry.protein * entry.servings))g P" : nil,
                                  Int(entry.carbs * entry.servings) > 0 ? "\(Int(entry.carbs * entry.servings))g C" : nil,
                                  Int(entry.fat * entry.servings) > 0 ? "\(Int(entry.fat * entry.servings))g F" : nil].compactMap { $0 }
                    if !macros.isEmpty || entry.servings != 1 {
                        Text(((entry.servings != 1 ? ["×\(entry.servings.formatted())"] : []) + macros).joined(separator: " · "))
                            .font(Ember.font(12, .medium)).foregroundStyle(Ember.dim)
                    }
                }
                Spacer()
                Text("\(Int(entry.cal * entry.servings))").font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Ember.bg.opacity(0.001))
            .offset(x: offset)
            .gesture(DragGesture(minimumDistance: 20)
                .onChanged { v in if v.translation.width < 0 { offset = max(-80, v.translation.width) } }
                .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = offset < -50 ? -70 : 0 } })
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Delete") { onDelete() }
    }
}

struct GoalSheet: View {
    @Binding var goal: Double
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
        VStack(spacing: 18) {
            Text("Daily goal").font(Ember.font(22, .heavy)).foregroundStyle(Ember.cream)
            Text("\(Int(goal)) cal").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(Ember.fire)
                .contentTransition(.numericText(value: goal))
            Slider(value: $goal, in: 1200...4500, step: 50).tint(Ember.orange)
                .onChange(of: goal) { _, _ in UISelectionFeedbackGenerator().selectionChanged() }
            Button("Done") { dismiss() }.font(Ember.font(17, .bold)).foregroundStyle(Ember.orange)
            HealthSettings().padding(.top, 24)
            SmartPhotoSettings().padding(.top, 8)
        }
        .padding(28)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationBackground(Ember.bg)
        .animation(.snappy, value: goal)
    }
}

/// "Smart photo (AI)": paste an Anthropic API key so meal photos are read by Claude.
struct SmartPhotoSettings: View {
    @State private var hasKey = FoodAI.hasKey
    @State private var message: String?
    @State private var hasUSDA = USDAKey.hasKey
    @State private var usdaMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Smart photo (AI)", systemImage: "sparkles").font(Ember.font(17, .heavy)).foregroundStyle(Ember.cream)
            Text(hasKey
                 ? "On. Claude identifies each item, sizes it against things in the photo (container, plate, hand), then each one is checked against USDA. About 1¢ per photo, billed to your Anthropic account."
                 : "Optional. Paste an Anthropic API key and meal photos get read by Claude: every item on the plate, with portions. About 1¢ per photo, billed to your Anthropic account. Without it, Food Book guesses on your phone for free.")
                .font(Ember.font(13, .medium)).foregroundStyle(Ember.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    let pasted = UIPasteboard.general.string ?? ""
                    if FoodAI.save(key: pasted) {
                        hasKey = true; message = "Key saved on this phone."
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        message = "Copy your key (starts with sk-ant-) first, then tap Paste key."
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                } label: {
                    Label(hasKey ? "Replace key" : "Paste key", systemImage: "doc.on.clipboard")
                        .font(Ember.font(15, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Ember.fire, in: Capsule())
                }
                .buttonStyle(Squish())
                if hasKey {
                    Button(role: .destructive) {
                        FoodAI.removeKey(); hasKey = false; message = "AI turned off."
                    } label: {
                        Text("Turn off").font(Ember.font(15, .heavy)).foregroundStyle(Ember.pink)
                            .padding(.horizontal, 16).frame(height: 44)
                            .background(Ember.card, in: Capsule())
                    }
                    .buttonStyle(Squish())
                }
            }
            if let message { Text(message).font(Ember.font(12, .semibold)).foregroundStyle(Ember.orange) }

            Divider().overlay(Ember.line).padding(.vertical, 4)
            Label("USDA nutrition check", systemImage: "checkmark.seal.fill").font(Ember.font(15, .heavy)).foregroundStyle(Ember.cream)
            Text(hasUSDA
                 ? "Using your own USDA FoodData Central key. Every item is matched against USDA data and scaled to its estimated weight."
                 : "Every item is matched against USDA FoodData Central and scaled to its estimated weight. Works now with the shared demo key; for heavy use, get a free key at fdc.nal.usda.gov and paste it here.")
                .font(Ember.font(13, .medium)).foregroundStyle(Ember.dim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    if USDAKey.save(key: UIPasteboard.general.string ?? "") {
                        hasUSDA = true; usdaMessage = "USDA key saved on this phone."
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        usdaMessage = "Copy your USDA key (letters and numbers) first, then tap Paste."
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                } label: {
                    Label(hasUSDA ? "Replace USDA key" : "Paste USDA key", systemImage: "doc.on.clipboard")
                        .font(Ember.font(14, .heavy)).foregroundStyle(Ember.cream)
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Ember.bg.opacity(0.6), in: Capsule())
                }
                .buttonStyle(Squish())
                if hasUSDA {
                    Button(role: .destructive) {
                        USDAKey.remove(); hasUSDA = false; usdaMessage = "Back to the shared demo key."
                    } label: {
                        Text("Remove").font(Ember.font(14, .heavy)).foregroundStyle(Ember.pink)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Ember.bg.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(Squish())
                }
            }
            if let usdaMessage { Text(usdaMessage).font(Ember.font(12, .semibold)).foregroundStyle(Ember.orange) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The glowing camera button on Today, with a slow breathing halo.
struct SnapButtonFace: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var breathe = false
    var body: some View {
        ZStack {
            Circle().fill(Ember.fire).frame(width: 74, height: 74)
                .blur(radius: 18).opacity(breathe ? 0.75 : 0.35)
                .scaleEffect(breathe ? 1.15 : 0.95)
            Circle().fill(Ember.fire).frame(width: 72, height: 72)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2).frame(width: 64, height: 64)
            Image(systemName: "camera.fill").font(.system(size: 27, weight: .black)).foregroundStyle(.white)
        }
        .shadow(color: Ember.pink.opacity(0.55), radius: 16, y: 6)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
