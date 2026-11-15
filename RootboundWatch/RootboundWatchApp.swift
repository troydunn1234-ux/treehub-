import SwiftUI

@main
struct RootboundWatchApp: App {
    @StateObject private var workout = HugWorkout.shared

    init() {
        PhoneLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HugHomeView()
                .environmentObject(workout)
                // The complication opens rootboundwatch://hug: start a hug straight away.
                .onOpenURL { url in
                    guard url.host == "hug", !workout.running else { return }
                    Task { await workout.start() }
                }
        }
    }
}

private enum Palette {
    static let forest = Color(red: 0.04, green: 0.13, blue: 0.09)
    static let leaf = Color(red: 0.36, green: 0.72, blue: 0.42)
    static let glow = Color(red: 0.74, green: 0.96, blue: 0.55)
}

/// One screen: Start hug -> live timer + heart rate -> End. The iPhone asks which tree it was.
struct HugHomeView: View {
    @EnvironmentObject var workout: HugWorkout
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                if workout.running { runningView } else { idleView }
            }
            .containerBackground(Palette.forest.gradient, for: .navigation)
        }
    }

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    Task { await workout.start() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "tree.fill").font(.system(size: 30, weight: .bold))
                        Text("Start hug").font(.system(.headline, design: .rounded))
                    }
                    .foregroundStyle(Palette.forest)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Palette.glow, Palette.leaf], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Measures your heart rate while you hug a tree")

                if !workout.errorText.isEmpty {
                    Text(workout.errorText).font(.footnote).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if let h = workout.lastHug {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last hug").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("\(Self.clock(h.minutes * 60)) · \(h.start.formatted(date: .omitted, time: .shortened))")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        if let avg = h.avgHR {
                            Label("\(Int(avg)) bpm avg", systemImage: "heart.fill").font(.footnote).foregroundStyle(.pink)
                        }
                        if let a = h.startHR, let b = h.endHR, a - b >= 1 {
                            Label("−\(Int(a - b)) bpm calmer", systemImage: "arrow.down.heart.fill")
                                .font(.footnote).foregroundStyle(Palette.glow)
                        }
                        Text("Pick the tree on your iPhone.").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("Your heart rate is measured during the hug. Pick the tree on your iPhone after.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Rootbound")
    }

    private var runningView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 6) {
                Text("Hugging").font(.caption.weight(.bold)).foregroundStyle(Palette.glow)
                Text(Self.clock(ctx.date.timeIntervalSince(workout.startDate ?? ctx.date)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                    Text(workout.heartRate.map { "\(Int($0))" } ?? "--")
                        .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text("bpm").font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 4)
                Button {
                    Task { await workout.finish() }
                } label: {
                    Label("End hug", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(Palette.leaf)
                Button("Discard", role: .destructive) { confirmDiscard = true }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Discard this hug?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { workout.discard() }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
