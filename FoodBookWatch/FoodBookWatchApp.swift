import SwiftUI
import Observation
import WatchConnectivity
import WatchKit
import UIKit

@main
struct FoodBookWatchApp: App {
    @State private var link = FoodLink.shared
    var body: some Scene {
        WindowGroup {
            FoodWatchRoot()
                .environment(link)
                .onAppear { link.activate() }
        }
    }
}

enum FW {
    static let bg = Color(red: 0.07, green: 0.05, blue: 0.05)
    static let cream = Color(red: 1.0, green: 0.95, blue: 0.88)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let pink = Color(red: 1.0, green: 0.27, blue: 0.47)
    static let gold = Color(red: 1.0, green: 0.8, blue: 0.3)
    static let protein = Color(red: 0.42, green: 0.78, blue: 1.0)
    static let carbs = Color(red: 1.0, green: 0.8, blue: 0.3)
    static let fat = Color(red: 1.0, green: 0.45, blue: 0.55)
    static let green = Color(red: 0.35, green: 0.9, blue: 0.55)
    static let fire = LinearGradient(colors: [gold, orange, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

struct FoodState: Equatable {
    struct Quick: Identifiable, Equatable { var id: String; var name: String; var cal: Double; var thumb: Data? = nil }
    struct Last: Equatable { var name: String; var cal: Double; var thumb: Data?; var at: Date }
    struct Supp: Identifiable, Equatable { var id: String; var name: String; var dose: String; var emoji: String; var time: String; var taken: Bool }

    var cal: Double = 0, goal: Double = 2200, p: Double = 0, c: Double = 0, f: Double = 0
    var quick: [Quick] = []
    var supps: [Supp] = []
    var last: Last?

    init() {}
    init(_ d: [String: Any]) {
        cal = d["cal"] as? Double ?? 0
        goal = max(1, d["goal"] as? Double ?? 2200)
        p = d["p"] as? Double ?? 0; c = d["c"] as? Double ?? 0; f = d["f"] as? Double ?? 0
        quick = (d["quick"] as? [[String: Any]] ?? []).map {
            Quick(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", cal: $0["cal"] as? Double ?? 0,
                  thumb: $0["thumb"] as? Data)
        }
        if let l = d["last"] as? [String: Any], let name = l["name"] as? String {
            last = Last(name: name, cal: l["cal"] as? Double ?? 0, thumb: l["thumb"] as? Data,
                        at: Date(timeIntervalSince1970: l["at"] as? Double ?? Date().timeIntervalSince1970))
        }
        supps = (d["supps"] as? [[String: Any]] ?? []).map {
            Supp(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", dose: $0["dose"] as? String ?? "",
                 emoji: $0["emoji"] as? String ?? "💊", time: $0["time"] as? String ?? "", taken: $0["taken"] as? Bool ?? false)
        }
    }

    var left: Double { goal - cal }
    var takenCount: Int { supps.filter(\.taken).count }
}

@MainActor
@Observable
final class FoodLink: NSObject {
    static let shared = FoodLink()
    private(set) var state = FoodState()
    private(set) var loaded = false
    var error: String?
    var justLogged: String?

    static let demo = ProcessInfo.processInfo.arguments.contains("-demo")

    func activate() {
        if Self.demo { state = Self.demoState; loaded = true; return }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() { send([:], quiet: true) }

    func log(_ q: FoodState.Quick) {
        // Show it right away; the iPhone's answer confirms.
        state.cal += q.cal
        state.last = FoodState.Last(name: q.name, cal: q.cal, thumb: q.thumb, at: Date())
        justLogged = q.name
        WKInterfaceDevice.current().play(.success)
        send(["cmd": "logQuick", "id": q.id])
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if justLogged == q.name { justLogged = nil } }
    }

    func toggle(_ s: FoodState.Supp) {
        if let i = state.supps.firstIndex(where: { $0.id == s.id }) {
            state.supps[i].taken.toggle()
            let all = state.takenCount == state.supps.count
            WKInterfaceDevice.current().play(all ? .success : .click)
        }
        send(["cmd": "toggleSupp", "id": s.id])
    }

    private func send(_ msg: [String: Any], quiet: Bool = false) {
        if Self.demo { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        guard s.isReachable else {
            // Not reachable: queue it; the iPhone handles it when it wakes.
            if !quiet { s.transferUserInfo(msg) }
            return
        }
        s.sendMessage(msg, replyHandler: { reply in
            Task { @MainActor in self.apply(reply) }
        }, errorHandler: { _ in
            Task { @MainActor in if !quiet { self.error = "Couldn't reach your iPhone." } }
        })
    }

    fileprivate func apply(_ d: [String: Any]) {
        guard d["goal"] != nil else { return }
        state = FoodState(d)
        loaded = true
    }

    static let demoState: FoodState = {
        var s = FoodState()
        s.cal = 1_340; s.goal = 2_200; s.p = 96; s.c = 140; s.f = 44
        s.last = .init(name: "Chicken burrito bowl", cal: 680, thumb: nil, at: Date())
        s.quick = [.init(id: "1", name: "Iced latte", cal: 190), .init(id: "2", name: "Chicken burrito bowl", cal: 680),
                   .init(id: "3", name: "Protein shake", cal: 160), .init(id: "4", name: "Banana", cal: 105)]
        s.supps = [.init(id: "a", name: "Multivitamin", dose: "1 tablet", emoji: "💊", time: "Morning", taken: true),
                   .init(id: "b", name: "Creatine", dose: "1 scoop", emoji: "💪", time: "Anytime", taken: true),
                   .init(id: "c", name: "Omega-3", dose: "1 softgel", emoji: "🐟", time: "Morning", taken: false),
                   .init(id: "d", name: "Magnesium", dose: "1 capsule", emoji: "🌙", time: "Bedtime", taken: false)]
        return s
    }()
}

extension FoodLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in
            if !ctx.isEmpty { self.apply(ctx) }
            self.refresh()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { Task { @MainActor in self.refresh() } }
    }
}

struct FoodWatchRoot: View {
    @Environment(FoodLink.self) private var link
    var body: some View {
        NavigationStack {
            TabView {
                TodayPage().containerBackground(FW.bg.gradient, for: .tabView)
                QuickPage().containerBackground(FW.bg.gradient, for: .tabView)
                StackPage().containerBackground(FW.bg.gradient, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
        }
        .alert("Food Book", isPresented: Binding(get: { link.error != nil }, set: { if !$0 { link.error = nil } })) {
            Button("OK", role: .cancel) { link.error = nil }
        } message: { Text(link.error ?? "") }
    }
}

/// Calorie ring and macros.
struct TodayPage: View {
    @Environment(FoodLink.self) private var link
    var body: some View {
        let s = link.state
        let frac = min(1.2, s.cal / s.goal)
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: min(1, frac))
                    .stroke(FW.fire, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: FW.orange.opacity(0.6), radius: 6)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: frac)
                VStack(spacing: -2) {
                    Text("\(Int(abs(s.left)))")
                        .font(FW.font(32, .black)).monospacedDigit()
                        .contentTransition(.numericText(value: s.left))
                        .foregroundStyle(s.left < 0 ? FW.pink : FW.cream)
                    Text(s.left < 0 ? "OVER" : "LEFT").font(FW.font(10, .heavy)).foregroundStyle(.secondary)
                }
            }
            .frame(width: s.last == nil ? 108 : 94, height: s.last == nil ? 108 : 94)
            HStack(spacing: 6) {
                macro("P", s.p, FW.protein)
                macro("C", s.c, FW.carbs)
                macro("F", s.f, FW.fat)
            }
            if let last = s.last {
                HStack(spacing: 7) {
                    FoodThumb(data: last.thumb, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("JUST LOGGED").font(FW.font(8, .heavy)).foregroundStyle(.secondary)
                        Text("\(last.name) · \(Int(last.cal)) kcal").font(FW.font(12, .bold)).lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(last.name + "\(last.at.timeIntervalSince1970)")
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: s.last)
        .navigationTitle { Text("\(Int(s.cal)) cal").font(FW.font(15, .heavy)).foregroundStyle(FW.orange) }
        .onAppear { link.refresh() }
        .accessibilityElement(children: .combine)
    }

    private func macro(_ l: String, _ v: Double, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(v))g").font(FW.font(14, .heavy)).monospacedDigit().foregroundStyle(c)
            Text(l).font(FW.font(9, .heavy)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One-tap re-log of your recent foods.
struct QuickPage: View {
    @Environment(FoodLink.self) private var link
    var body: some View {
        List {
            if link.state.quick.isEmpty {
                Text("Log a food on your iPhone and it shows up here for one-tap re-logging.")
                    .font(FW.font(13, .medium)).foregroundStyle(.secondary)
            }
            ForEach(link.state.quick) { q in
                Button { link.log(q) } label: {
                    HStack(spacing: 8) {
                        if q.thumb != nil { FoodThumb(data: q.thumb, size: 32) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.name).font(FW.font(14, .bold)).lineLimit(2)
                            Text("\(Int(q.cal)) cal").font(FW.font(11, .semibold)).foregroundStyle(FW.orange)
                        }
                        Spacer()
                        Image(systemName: link.justLogged == q.name ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(link.justLogged == q.name ? FW.green : FW.orange)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                .accessibilityLabel("Log \(q.name), \(Int(q.cal)) calories")
            }
        }
        .navigationTitle("Quick add")
    }
}

/// Today's supplement checklist.
struct StackPage: View {
    @Environment(FoodLink.self) private var link
    var body: some View {
        let s = link.state
        List {
            if s.supps.isEmpty {
                Text("Add your vitamins and powders in Food Book's Stack tab.")
                    .font(FW.font(13, .medium)).foregroundStyle(.secondary)
            }
            ForEach(s.supps) { sp in
                Button { link.toggle(sp) } label: {
                    HStack(spacing: 8) {
                        Text(sp.emoji).font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sp.name).font(FW.font(14, .bold)).lineLimit(1)
                                .strikethrough(sp.taken, color: .secondary)
                            Text(sp.dose.isEmpty ? sp.time : "\(sp.dose) · \(sp.time)")
                                .font(FW.font(10, .semibold)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: sp.taken ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(sp.taken ? FW.green : Color.white.opacity(0.35))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .opacity(sp.taken ? 0.75 : 1)
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(sp.taken ? FW.green.opacity(0.12) : Color.white.opacity(0.07)))
                .accessibilityLabel("\(sp.name), \(sp.taken ? "taken" : "not taken")")
            }
        }
        .navigationTitle {
            Text("Stack \(s.takenCount)/\(s.supps.count)").font(FW.font(15, .heavy))
                .foregroundStyle(s.takenCount == s.supps.count && !s.supps.isEmpty ? FW.green : FW.orange)
        }
    }
}

/// A food's photo in a circle (or a fork-and-knife badge when there's no photo).
struct FoodThumb: View {
    let data: Data?
    let size: CGFloat
    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    FW.fire
                    Image(systemName: "fork.knife").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(FW.orange.opacity(0.6), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}
