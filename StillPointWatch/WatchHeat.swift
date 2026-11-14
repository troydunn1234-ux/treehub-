import SwiftUI
import WatchKit
import WatchConnectivity

/// Sauna / steam on the wrist: a timer that survives leaving the app, synced to the iPhone's heat log.
@MainActor
final class WatchHeat: ObservableObject {
    static let shared = WatchHeat()

    struct Active: Codable, Equatable { var kind: HeatKind; var start: Date }
    @Published private(set) var active: Active?

    private let key = "sp.watch.heat"

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode(Active.self, from: d) {
            // Anything older than 3 hours was forgotten; drop it.
            active = Date().timeIntervalSince(a.start) < 3 * 3600 ? a : nil
        }
    }

    private func save() {
        if let a = active, let d = try? JSONEncoder().encode(a) {
            UserDefaults.standard.set(d, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func start(_ kind: HeatKind) {
        let a = Active(kind: kind, start: Date())
        active = a
        save()
        // Keeps the app in front and the heart-rate sensor on; nothing is saved as a workout.
        WatchRuntime.shared.begin(trackHeartRate: true, saveWorkout: false)
        send(["heatKind": kind.rawValue, "heatStart": a.start.timeIntervalSince1970])
        WKInterfaceDevice.current().play(.start)
    }

    func finish() {
        guard let a = active else { return }
        let end = Date()
        active = nil
        save()
        WatchRuntime.shared.end(discard: true)
        if end.timeIntervalSince(a.start) >= 60 {
            send(["heatKind": a.kind.rawValue, "heatStart": a.start.timeIntervalSince1970, "heatEnd": end.timeIntervalSince1970])
        } else {
            send(["heatKind": a.kind.rawValue, "heatStart": a.start.timeIntervalSince1970, "heatCancel": true])
        }
        WKInterfaceDevice.current().play(.success)
    }

    func cancel() {
        guard let a = active else { return }
        active = nil
        save()
        WatchRuntime.shared.end(discard: true)
        send(["heatKind": a.kind.rawValue, "heatStart": a.start.timeIntervalSince1970, "heatCancel": true])
    }

    private func send(_ info: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(info)
    }
}

// MARK: - Home buttons

/// Two buttons on the Watch home screen, or the running session if there is one.
struct WatchHeatButtons: View {
    @ObservedObject var heat = WatchHeat.shared
    let open: () -> Void

    var body: some View {
        if let a = heat.active {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: a.kind.symbol).foregroundStyle(a.kind.tint)
                    TimelineView(.periodic(from: a.start, by: 1)) { ctx in
                        Text(spFormatClock(ctx.date.timeIntervalSince(a.start)))
                            .font(SP.numbers(16)).foregroundStyle(SP.ink).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Text("In \(a.kind.short.lowercased())").font(SP.rounded(12)).foregroundStyle(SP.dim)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Capsule().fill(a.kind.tint.opacity(0.22)))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                ForEach(HeatKind.allCases) { k in
                    Button {
                        heat.start(k)
                        open()
                    } label: {
                        Label(k.short, systemImage: k.symbol)
                            .font(SP.rounded(14)).foregroundStyle(k.tint)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(k.tint.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start \(k.title) timer")
                }
            }
        }
    }
}

// MARK: - Session screen

/// Swipe up/down between the timer, a breathing pacer with wrist taps, and the bench moves.
struct WatchHeatView: View {
    @ObservedObject var heat = WatchHeat.shared
    @ObservedObject var runtime = WatchRuntime.shared
    let close: () -> Void
    @State private var page = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                timerPage.tag(0)
                WatchHeatPacer(tint: kind.tint).tag(1)
                movesPage.tag(2)
            }
            .tabViewStyle(.verticalPage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Back to home; the timer keeps running")
                }
            }
        }
    }

    private var kind: HeatKind { heat.active?.kind ?? .sauna }

    private var timerPage: some View {
        VStack(spacing: 6) {
            Label(kind.title.uppercased(), systemImage: kind.symbol)
                .font(SP.rounded(11, .semibold)).foregroundStyle(kind.tint)
            if let a = heat.active {
                TimelineView(.periodic(from: a.start, by: 1)) { ctx in
                    Text(spFormatClock(ctx.date.timeIntervalSince(a.start)))
                        .font(SP.numbers(40)).foregroundStyle(SP.ink).monospacedDigit()
                }
            }
            if let hr = runtime.heartRate {
                Label("\(Int(hr.rounded()))", systemImage: "heart.fill")
                    .font(SP.numbers(16)).foregroundStyle(SP.rose)
            }
            Button {
                heat.finish()
                close()
            } label: {
                Label("I'm out", systemImage: "checkmark").font(SP.rounded(15, .semibold))
            }
            .tint(kind.tint)
            Text("Swipe up: breathe · moves")
                .font(SP.rounded(10)).foregroundStyle(SP.faint)
            Text("High heat can damage the Watch. For a hot round, start here, then leave it outside; WHOOP keeps your heart rate.")
                .font(SP.rounded(9)).foregroundStyle(SP.faint).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var movesPage: some View {
        List {
            ForEach(HeatMove.all) { m in
                NavigationLink {
                    ScrollView {
                        VStack(spacing: 6) {
                            PoseFigureView(motion: PoseLibrary.motion(for: m.step), tint: kind.tint, glow: kind.tint2,
                                           lineWidth: 2.2, captions: false)
                                .frame(height: 90)
                            Text(m.title).font(SP.serif(17)).foregroundStyle(SP.ink)
                            Text(m.how).font(SP.rounded(12)).foregroundStyle(SP.dim)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } label: {
                    Text(m.title).font(SP.rounded(14))
                }
            }
        }
    }
}

/// Orb that grows on the in-breath, with a tap on the wrist at each change (up = in, down = out).
/// Tap the orb to switch pattern.
struct WatchHeatPacer: View {
    let tint: Color
    @State private var index = 0
    @State private var start = Date()

    private var breath: HeatBreath { HeatBreath.all[index % HeatBreath.all.count] }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let st = state(at: ctx.date)
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.6), tint.opacity(0.05)], center: .center, startRadius: 2, endRadius: 60))
                        .scaleEffect(0.5 + 0.5 * st.size)
                    VStack(spacing: 0) {
                        Text(st.label).font(SP.rounded(13, .semibold)).foregroundStyle(SP.ink)
                        Text("\(st.count)").font(SP.numbers(20)).foregroundStyle(SP.ink.opacity(0.85))
                    }
                }
                .frame(height: 110)
                .contentShape(Rectangle())
                .onTapGesture { index += 1; start = Date() }
                Text("\(breath.title) · \(breath.pattern)")
                    .font(SP.rounded(11)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                Text("Tap the orb to change").font(SP.rounded(9)).foregroundStyle(SP.faint)
            }
            .background(WristTap(key: st.key, grow: st.grow))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(breath.title), \(breath.pattern)")
    }

    private struct PaceState { var label: String; var count: Int; var size: Double; var key: Int; var grow: Bool }

    private func state(at date: Date) -> PaceState {
        let cyc = max(1, breath.cycle)
        let elapsed = date.timeIntervalSince(start)
        var t = elapsed.truncatingRemainder(dividingBy: cyc)
        let round = Int(elapsed / cyc)
        var size = 0.0
        for (i, p) in breath.phases.enumerated() {
            if t < p.seconds {
                let f = t / p.seconds
                let e = f * f * (3 - 2 * f)
                let target = p.grow ? min(1, size + (i == 0 ? 0.85 : 0.15)) : 0
                return PaceState(label: p.label, count: Int((p.seconds - t).rounded(.up)),
                                 size: size + (target - size) * e, key: round * 10 + i, grow: p.grow)
            }
            t -= p.seconds
            size = p.grow ? min(1, size + (i == 0 ? 0.85 : 0.15)) : 0
        }
        return PaceState(label: "", count: 0, size: 0, key: 0, grow: true)
    }
}

/// Plays a wrist tap whenever the breath phase changes.
private struct WristTap: View {
    let key: Int
    let grow: Bool
    var body: some View {
        Color.clear.onChange(of: key) { _, _ in
            WKInterfaceDevice.current().play(grow ? .directionUp : .directionDown)
        }
    }
}
