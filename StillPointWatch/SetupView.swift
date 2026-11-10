import SwiftUI

/// Begin is the first thing on screen; everything else is optional fine-tuning below it.
struct SetupView: View {
    let practice: Practice
    let onStart: (SessionPlan) -> Void
    @EnvironmentObject var prefs: Prefs
    @State private var minutes: Double = 5
    @State private var warmUpId: String = ""
    @State private var custom = false
    @State private var inhale: Double = 4
    @State private var holdIn: Double = 0
    @State private var exhale: Double = 4
    @State private var holdOut: Double = 0
    private let lib = PracticeLibrary.shared

    private var minuteOptions: [Int] {
        let base = Set(practice.minutes + [1, 2, 3, 5, 10, 15, 20, 30])
        return base.filter { $0 >= 1 && $0 <= 60 }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(practice.title).font(SP.serif(18)).foregroundStyle(SP.ink)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)

                Button(action: begin) {
                    Text("Begin")
                        .font(SP.serif(18))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Capsule().fill(SP.goldGlow))
                }
                .buttonStyle(.plain)

                // Duration: turn the Digital Crown.
                VStack(spacing: 2) {
                    Text("\(Int(minutes))").font(SP.numbers(34)).foregroundStyle(SP.ink)
                    Text(practice.isMovement ? "MINUTES OF MOVEMENT" : "MINUTES")
                        .font(SP.rounded(9, .semibold)).tracking(1.2).foregroundStyle(SP.faint)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                .focusable()
                .digitalCrownRotation($minutes, from: 1, through: 60, by: 1, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("\(Int(minutes)) minutes. Turn the Digital Crown to change.")

                if let p = practice.pattern, !practice.isMovement {
                    PatternStrip(pattern: custom ? currentPattern : p, compact: true)
                }

                if !practice.isMovement && !lib.warmUps.isEmpty {
                    Picker("Warm up first", selection: $warmUpId) {
                        Text("No warm-up").tag("")
                        ForEach(lib.warmUps) { w in Text(w.title).tag(w.id) }
                    }
                }

                Toggle(isOn: Binding(get: { prefs.isFavorite(practice.id) }, set: { _ in prefs.toggleFavorite(practice.id) })) {
                    Label("Favorite", systemImage: "heart")
                }

                WatchDisclosureGroup("Fine-tune") {
                    VStack(spacing: 8) {
                        if practice.pattern != nil && !practice.isMovement {
                            Toggle("Custom rhythm", isOn: $custom)
                            if custom {
                                Stepper("In \(BreathPattern.fmt(inhale))s", value: $inhale, in: 1...12, step: 0.5)
                                Stepper("Hold \(BreathPattern.fmt(holdIn))s", value: $holdIn, in: 0...20, step: 0.5)
                                Stepper("Out \(BreathPattern.fmt(exhale))s", value: $exhale, in: 1...16, step: 0.5)
                                Stepper("Rest \(BreathPattern.fmt(holdOut))s", value: $holdOut, in: 0...20, step: 0.5)
                            }
                            Picker("Length", selection: $prefs.settings.mode) {
                                ForEach(SessionMode.allCases) { m in Text(m.label).tag(m) }
                            }
                            if prefs.settings.mode == .cycles {
                                Stepper("\(prefs.settings.cycles) breaths", value: $prefs.settings.cycles, in: 3...60)
                            }
                        }
                        Picker("Haptics", selection: $prefs.settings.haptics) {
                            ForEach(HapticStyle.allCases) { h in Text(h.label).tag(h) }
                        }
                        Toggle("Count the out-breath", isOn: $prefs.settings.exhaleTicks)
                        Toggle("Start & end bells", isOn: $prefs.settings.bells)
                        Picker("Interval bell", selection: $prefs.settings.intervalMinutes) {
                            Text("Off").tag(0)
                            ForEach([1, 2, 5, 10], id: \.self) { m in Text("Every \(m) min").tag(m) }
                        }
                        Toggle("Dim after start", isOn: $prefs.settings.dimScreen)
                        Toggle("Show numbers", isOn: $prefs.settings.showNumbers)
                        Toggle("Heart rate", isOn: $prefs.settings.trackHeartRate)
                        if prefs.settings.trackHeartRate {
                            Toggle("Save as workout", isOn: $prefs.settings.saveAsWorkout)
                        }
                        Toggle("Movement counts as mindful", isOn: $prefs.settings.logMovementAsMindful)
                    }
                    .font(SP.rounded(13))
                }
                .font(SP.rounded(14))
                .tint(SP.amber)

                NavigationLink { WatchPracticeInfoView(practice: practice) } label: {
                    Label("About this practice", systemImage: "info.circle")
                        .font(SP.rounded(13)).foregroundStyle(SP.teal)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                if let s = practice.safety, !s.isEmpty {
                    Label(s, systemImage: "heart.text.square").font(SP.rounded(11)).foregroundStyle(SP.rose.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(DuskBackground(glow: lib.tradition(practice.traditionId)?.tint ?? SP.amber).opacity(0.9))
        .onAppear {
            let d = prefs.settings.defaultMinutes
            minutes = Double(practice.minutes.contains(d) ? d : practice.defaultMinutes)
            if let p = practice.pattern {
                inhale = p.inhale; holdIn = p.holdIn; exhale = p.exhale; holdOut = p.holdOut
            }
        }
    }

    private var currentPattern: BreathPattern {
        var p = practice.pattern ?? BreathPattern(inhale: 4, exhale: 4)
        p.inhale = inhale; p.holdIn = holdIn; p.exhale = exhale; p.holdOut = holdOut
        return p
    }

    private func begin() {
        let w = warmUpId.isEmpty ? nil : lib.practice(warmUpId)
        onStart(SessionPlan(warmUp: w, warmUpMinutes: w?.minutes.first ?? 2, practice: practice,
                            minutes: max(1, Int(minutes)), patternOverride: custom ? currentPattern : nil))
    }
}

private struct WatchDisclosureGroup<Content: View>: View {
    let title: String
    let content: Content
    @State private var expanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                content
            }
        }
    }
}
