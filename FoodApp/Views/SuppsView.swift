import SwiftUI
import SwiftData
import UserNotifications

/// Daily supplement checklist: tap to check off, resets every day.
struct SuppsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Supplement.order) private var supps: [Supplement]
    @Query private var doses: [SuppDose]
    @AppStorage("suppReminders") private var reminders = false
    @State private var editing = false
    @State private var celebrate = 0
    @State private var day = Day.key(Date())
    @State private var sheet: SuppSheet?

    private func taken(_ s: Supplement, on d: String) -> SuppDose? { doses.first { $0.suppID == s.id && $0.day == d } }
    private var takenCount: Int { supps.filter { taken($0, on: day) != nil }.count }
    private var allDone: Bool { !supps.isEmpty && takenCount == supps.count }

    /// Days in a row where everything was checked off.
    private var streak: Int {
        guard !supps.isEmpty else { return 0 }
        func complete(_ d: String) -> Bool { supps.allSatisfy { s in doses.contains { $0.suppID == s.id && $0.day == d } } }
        var k = Day.key(Date())
        if !complete(k) { k = Day.shift(k, by: -1) }
        var n = 0
        while complete(k) && n < 3650 { n += 1; k = Day.shift(k, by: -1) }
        return n
    }

    var body: some View {
        ZStack {
            EmberBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    dayPicker
                    if supps.isEmpty { emptyState } else {
                        progressCard
                        weekDots
                        ForEach(SuppTime.allCases) { time in group(time) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            Confetti(trigger: celebrate)
        }
        .sheet(isPresented: $editing) { StackEditor().presentationDetents([.large]) }
        .sheet(item: $sheet) { SuppEditSheet(target: $0).presentationDetents([.large]) }
        .onAppear { day = Day.key(Date()) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY STACK").font(Ember.font(11, .heavy)).tracking(3).foregroundStyle(Ember.fire)
                Text("Supplements").font(Ember.font(28, .heavy)).foregroundStyle(Ember.cream)
            }
            Spacer()
            Button { editing = true } label: {
                Label(supps.isEmpty ? "Add" : "Edit", systemImage: supps.isEmpty ? "plus" : "slider.horizontal.3")
                    .font(Ember.font(14, .bold)).foregroundStyle(Ember.cream)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Ember.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Ember.line))
            }
            .buttonStyle(Squish())
        }
        .padding(.top, 6)
    }

    private var isToday: Bool { day == Day.key(Date()) }

    /// Flip between days so a missed dose can be checked off (or unchecked) after the fact.
    private var dayPicker: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.snappy) { day = Day.shift(day, by: -1) } } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34).background(Ember.card, in: Circle())
            }
            .buttonStyle(Squish()).accessibilityLabel("Previous day")
            Text(dayTitle).font(Ember.font(15, .heavy)).foregroundStyle(isToday ? Ember.cream : Ember.orange)
                .frame(maxWidth: .infinity).contentTransition(.numericText())
            Button { withAnimation(.snappy) { day = Day.shift(day, by: 1) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34).background(Ember.card, in: Circle())
            }
            .buttonStyle(Squish()).disabled(isToday).opacity(isToday ? 0.35 : 1).accessibilityLabel("Next day")
            if !isToday {
                Button { withAnimation(.snappy) { day = Day.key(Date()) } } label: {
                    Text("Today").font(Ember.font(13, .bold)).foregroundStyle(Ember.cream)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(Ember.card, in: Capsule())
                }
                .buttonStyle(Squish())
            }
        }
        .foregroundStyle(Ember.cream)
        .padding(.top, 10)
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        if day == Day.shift(Day.key(Date()), by: -1) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: Day.date(day))
    }

    private var progressCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Ember.card, lineWidth: 10)
                Circle().trim(from: 0, to: supps.isEmpty ? 0 : Double(takenCount) / Double(supps.count))
                    .stroke(Ember.fire, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: takenCount)
                Text(allDone ? "✓" : "\(takenCount)/\(supps.count)")
                    .font(Ember.font(allDone ? 28 : 18, .black)).foregroundStyle(Ember.cream)
                    .contentTransition(.numericText())
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text(allDone ? "Stack complete" : "\(supps.count - takenCount) left \(isToday ? "today" : dayTitle.lowercased())")
                    .font(Ember.font(20, .heavy)).foregroundStyle(Ember.cream)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(Ember.fire)
                    Text(streak == 1 ? "1 day streak" : "\(streak) day streak").font(Ember.font(14, .bold)).foregroundStyle(Ember.dim)
                }
                Toggle(isOn: $reminders) {
                    Text("Reminders").font(Ember.font(13, .bold)).foregroundStyle(Ember.dim)
                }
                .tint(Ember.orange)
                .onChange(of: reminders) { _, on in Reminders.update(on: on, supps: supps) }
            }
        }
        .padding(16)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Ember.line))
    }

    /// Last 7 days: full dot = everything taken, ring = partial.
    private var weekDots: some View {
        HStack(spacing: 0) {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let d = Day.shift(Day.key(Date()), by: -back)
                let n = supps.filter { taken($0, on: d) != nil }.count
                VStack(spacing: 6) {
                    Text(Day.date(d).formatted(.dateTime.weekday(.narrow))).font(Ember.font(11, .heavy)).foregroundStyle(Ember.dim)
                    ZStack {
                        Circle().stroke(Ember.line, lineWidth: 2)
                        if n == supps.count && n > 0 { Circle().fill(Ember.fire) }
                        else if n > 0 { Circle().trim(from: 0, to: Double(n) / Double(supps.count)).stroke(Ember.orange, lineWidth: 3).rotationEffect(.degrees(-90)) }
                    }
                    .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func group(_ time: SuppTime) -> some View {
        let items = supps.filter { $0.time == time }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(time.rawValue, systemImage: time.symbol).font(Ember.font(16, .heavy)).foregroundStyle(Ember.cream)
                ForEach(items) { s in row(s) }
            }
        }
    }

    private func row(_ s: Supplement) -> some View {
        let done = taken(s, on: day) != nil
        return Button { toggle(s) } label: {
            HStack(spacing: 14) {
                Text(s.emoji).font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(Ember.font(17, .bold)).foregroundStyle(Ember.cream)
                        .strikethrough(done, color: Ember.dim)
                    let sub = [s.dose, s.withFood ? "with food" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(Ember.font(13, .medium)).foregroundStyle(Ember.dim) }
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(done ? Color.clear : Ember.line, lineWidth: 2)
                    if done {
                        Circle().fill(Ember.fire)
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 32, height: 32)
                .shadow(color: done ? Ember.orange.opacity(0.6) : .clear, radius: 8)
            }
            .padding(12)
            .background(done ? Ember.orange.opacity(0.10) : Ember.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(done ? Ember.orange.opacity(0.35) : Ember.line))
            .opacity(done ? 0.8 : 1)
        }
        .buttonStyle(Squish())
        .contextMenu {
            Button { sheet = .edit(s) } label: { Label("Edit dose & time", systemImage: "slider.horizontal.3") }
        }
        .accessibilityLabel("\(s.name), \(s.dose)")
        .accessibilityAction(named: "Edit") { sheet = .edit(s) }
        .accessibilityValue(done ? "Taken" : "Not taken")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("💊").font(.system(size: 54))
            Text("Build your daily stack").font(Ember.font(20, .heavy)).foregroundStyle(Ember.cream)
            Text("Add your vitamins, supplements and powders once. Every day, tap each one off as you take it.")
                .font(Ember.font(15, .medium)).foregroundStyle(Ember.dim).multilineTextAlignment(.center)
            Button { editing = true } label: {
                Text("Add supplements").font(Ember.font(17, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 15)
                    .background(Ember.fire, in: Capsule())
            }
            .buttonStyle(Squish())
        }
        .padding(.top, 60)
    }

    private func toggle(_ s: Supplement) {
        let finishing = taken(s, on: day) == nil && takenCount + 1 == supps.count
        if let d = taken(s, on: day) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { context.delete(d) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { context.insert(SuppDose(suppID: s.id, day: day)) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        try? context.save()
        if finishing {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            celebrate += 1
        }
    }
}

/// Add, remove, reorder and edit your stack.
struct StackEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supplement.order) private var supps: [Supplement]
    @State private var sheet: SuppSheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if supps.isEmpty { Text("Nothing yet. Add from below.").foregroundStyle(Ember.dim) }
                    ForEach(supps) { s in
                        Button { sheet = .edit(s) } label: {
                            HStack(spacing: 12) {
                                Text(s.emoji).font(.system(size: 24))
                                VStack(alignment: .leading) {
                                    Text(s.name).font(Ember.font(16, .bold)).foregroundStyle(Ember.cream)
                                    Text([s.dose, s.time.rawValue, s.withFood ? "with food" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(Ember.font(12, .medium)).foregroundStyle(Ember.dim)
                                }
                                Spacer()
                                Image(systemName: "slider.horizontal.3").foregroundStyle(Ember.orange)
                            }
                        }
                        .accessibilityHint("Edit dose, unit and time")
                    }
                    .onDelete { idx in
                        for i in idx { context.delete(supps[i]) }
                        try? context.save()
                        FoodWatchBridge.shared.pushNow()
                    }
                    .onMove { from, to in
                        var list = supps
                        list.move(fromOffsets: from, toOffset: to)
                        for (i, s) in list.enumerated() { s.order = i }
                        try? context.save()
                        FoodWatchBridge.shared.pushNow()
                    }
                } header: {
                    Text("Your stack")
                } footer: {
                    Text("Tap one to change its dose or time. Tap Edit to drag them into order.")
                }
                .listRowBackground(Color.white.opacity(0.05))

                Section {
                    Button { sheet = .new } label: {
                        Label("Create your own", systemImage: "plus.circle.fill")
                            .font(Ember.font(16, .bold)).foregroundStyle(Ember.orange)
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))

                Section("Quick add") {
                    ForEach(SuppPreset.all.filter { p in !supps.contains { $0.name == p.name } }, id: \.self) { p in
                        Button { sheet = .preset(p) } label: {
                            HStack {
                                Text(p.emoji)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).foregroundStyle(Ember.cream)
                                    Text(p.dose).font(Ember.font(12, .medium)).foregroundStyle(Ember.dim)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Ember.orange)
                            }
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .scrollContentBackground(.hidden)
            .background(Ember.bg)
            .navigationTitle("Edit stack")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton().foregroundStyle(Ember.orange) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(Ember.orange) }
            }
            .sheet(item: $sheet) { SuppEditSheet(target: $0).presentationDetents([.large]) }
        }
        .preferredColorScheme(.dark)
    }
}

/// One local reminder per part of the day you have supplements in.
enum Reminders {
    static func update(on: Bool, supps: [Supplement]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: SuppTime.allCases.map { "supps.\($0.rawValue)" })
        guard on else { return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            for time in SuppTime.allCases where time != .anytime {
                let names = supps.filter { $0.time == time }.map(\.name)
                guard !names.isEmpty else { continue }
                let c = UNMutableNotificationContent()
                c.title = "\(time.rawValue) stack"
                c.body = names.joined(separator: ", ")
                c.sound = .default
                var dc = DateComponents(); dc.hour = time.hour
                center.add(UNNotificationRequest(identifier: "supps.\(time.rawValue)", content: c,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
            }
        }
    }
}

/// Burst of confetti when the whole stack is done.
struct Confetti: View {
    let trigger: Int
    @State private var pieces: [(x: Double, delay: Double, color: Color, spin: Double)] = []
    @State private var fall = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces.indices, id: \.self) { i in
                    let p = pieces[i]
                    RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 8, height: 13)
                        .rotationEffect(.degrees(fall ? p.spin : 0))
                        .position(x: geo.size.width * p.x, y: fall ? geo.size.height + 40 : -20)
                        .animation(.easeIn(duration: 1.8).delay(p.delay), value: fall)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: trigger) { _, _ in
            guard !reduce else { return }
            fall = false
            pieces = (0..<60).map { _ in (Double.random(in: 0...1), Double.random(in: 0...0.4),
                                          [Ember.orange, Ember.pink, Ember.gold, Ember.cream].randomElement()!, Double.random(in: -720...720)) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fall = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { pieces = []; fall = false }
        }
    }
}
