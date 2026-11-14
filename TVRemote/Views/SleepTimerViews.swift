import SwiftUI
import UIKit

/// The Sleep key on the remote: a moon, or the countdown while a timer runs. Tap to pick a length or cancel.
struct SleepTimerKey: View {
    var width: CGFloat = 58
    @State private var showPicker = false
    private var timer: SleepTimer { SleepTimer.shared }

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            showPicker = true
        } label: {
            Group {
                if let end = timer.endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(SleepTimerKey.clock(end.timeIntervalSince(ctx.date)))
                            .font(Look.font(12, .black)).monospacedDigit()
                            .foregroundStyle(Look.accentH)
                    }
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: width, height: 36)
            .glassCapsule(glow: timer.isRunning ? Look.violet : nil)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(scale: 0.9))
        .accessibilityLabel(accessibilityText)
        .sleepTimerPicker(isPresented: $showPicker)
    }

    private var accessibilityText: String {
        guard let end = timer.endsAt else { return "Sleep timer" }
        let m = max(1, Int((end.timeIntervalSinceNow / 60).rounded(.up)))
        return "Sleep timer. TV turns off in \(m) minute\(m == 1 ? "" : "s")"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }
}

extension View {
    /// 15 / 30 / 60 / 90 minutes, a custom length, or cancel the running timer.
    func sleepTimerPicker(isPresented: Binding<Bool>) -> some View {
        modifier(SleepTimerPicker(isPresented: isPresented))
    }
}

private struct SleepTimerPicker: ViewModifier {
    @Binding var isPresented: Bool
    @State private var showCustom = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Sleep timer", isPresented: $isPresented, titleVisibility: .visible) {
                ForEach([15, 30, 60, 90], id: \.self) { m in
                    Button(SleepTimer.label(minutes: m)) { SleepTimer.shared.start(minutes: m) }
                }
                Button("Custom…") { showCustom = true }
                if SleepTimer.shared.isRunning {
                    Button("Turn Off Sleep Timer", role: .destructive) { SleepTimer.shared.cancel() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SleepTimerPicker.honestNote)
            }
            .sheet(isPresented: $showCustom) {
                CustomSleepSheet().presentationDetents([.medium])
            }
    }

    static let honestNote = "Turns the TV off when time's up. Your phone needs to be on the same Wi-Fi as the TV. If iOS pauses Couch Remote in the background, you'll get a notification instead: tap Turn Off TV on it."
}

private struct CustomSleepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = SleepTimer.shared.lastMinutes

    var body: some View {
        VStack(spacing: Look.S.l) {
            Text("Sleep timer").font(Look.font(20, .heavy)).foregroundStyle(.white)
            Picker("Minutes", selection: $minutes) {
                ForEach(Array(stride(from: 5, through: 240, by: 5)), id: \.self) { m in
                    Text(SleepTimer.label(minutes: m)).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 160)
            Button {
                SleepTimer.shared.start(minutes: minutes)
                dismiss()
            } label: {
                Text("Turn TV off in \(SleepTimer.label(minutes: minutes))")
                    .font(Look.font(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Look.accent, in: Capsule())
            }
            .buttonStyle(SquishStyle(scale: 0.96))
            Text("Your phone needs to be on the same Wi-Fi as the TV. If iOS pauses Couch Remote, a notification comes up at the end: tap Turn Off TV.")
                .font(Look.font(12, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
        }
        .padding(Look.S.l)
        .onAppear { minutes = max(5, min(240, (minutes / 5) * 5)) }
    }
}
