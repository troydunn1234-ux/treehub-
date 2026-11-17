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
    static let heart = Color(red: 1, green: 0.45, blue: 0.55)
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

    // MARK: Idle

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button {
                    Task { await workout.start() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "tree.fill")
                            .font(.system(size: 30, weight: .bold))
                            .accessibilityHidden(true)
                        Text("Start hug").font(.system(.headline, design: .rounded))
                    }
                    .foregroundStyle(Palette.forest)
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(LinearGradient(colors: [Palette.glow, Palette.leaf], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Measures your heart rate while you hug a tree")

                if !workout.errorText.isEmpty {
                    Label(workout.errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let h = workout.lastHug {
                    lastHugCard(h)
                } else {
                    Text("Your heart rate is measured during the hug. Pick the tree on your iPhone after.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Rootbound")
    }

    private func lastHugCard(_ h: WatchHugRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last hug").font(.caption2.weight(.bold)).foregroundStyle(Palette.glow)
            Text("\(Self.clock(h.minutes * 60)) · \(h.start.formatted(date: .omitted, time: .shortened))")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let avg = h.avgHR {
                Label("\(Int(avg)) bpm avg", systemImage: "heart.fill")
                    .font(.footnote).foregroundStyle(Palette.heart)
                    .monospacedDigit()
            }
            if let a = h.startHR, let b = h.endHR, a - b >= 1 {
                Label("−\(Int(a - b)) bpm calmer", systemImage: "arrow.down.heart.fill")
                    .font(.footnote).foregroundStyle(Palette.glow)
                    .monospacedDigit()
            }
            Label("Pick the tree on your iPhone", systemImage: "iphone")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Running

    private var runningView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 6) {
                Label("Hugging", systemImage: "tree.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(Palette.glow)
                Text(Self.clock(ctx.date.timeIntervalSince(workout.startDate ?? ctx.date)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Hug time")
                    .accessibilityValue(Self.clock(ctx.date.timeIntervalSince(workout.startDate ?? ctx.date)))
                heartRow
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
                    .frame(minHeight: 32)
            }
        }
        .confirmationDialog("Discard this hug?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { workout.discard() }
        }
    }

    /// Live heart rate; "Reading…" until the first sample arrives (never a bare "--").
    private var heartRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Palette.heart)
                .symbolEffect(.pulse, isActive: workout.heartRate != nil)
                .accessibilityHidden(true)
            if let hr = workout.heartRate {
                Text("\(Int(hr))")
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("bpm").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Reading…").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(workout.heartRate.map { "Heart rate \(Int($0)) beats per minute" } ?? "Reading heart rate")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
