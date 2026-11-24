import SwiftUI

/// Watch home "Right now": the iPhone's pick (it sees WHOOP and Pulse Lab) while fresh, else one made here
/// from the Watch's own Health data. One tap starts it; "Why?" lists the numbers used.
struct WatchRightNowCard: View {
    @ObservedObject private var model = RightNow.shared
    let onStart: (Practice, Int) -> Void

    var body: some View {
        let s = model.current
        if let p = PracticeLibrary.shared.practice(s.practiceId) {
            let tint = PracticeLibrary.shared.category(s.goal).map { Color(spHex: $0.color) } ?? SP.teal
            VStack(alignment: .leading, spacing: 4) {
                Button { onStart(p, s.minutes) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Label("Right now", systemImage: "sparkles").font(SP.rounded(10, .semibold)).textCase(.uppercase).foregroundStyle(SP.dim)
                            Spacer(minLength: 0)
                            if let lvl = s.stressLevel.flatMap(StressEstimate.Level.init(rawValue:)) {
                                Circle().fill(lvl.tint).frame(width: 6, height: 6)
                                Text(lvl.label).font(SP.rounded(10)).foregroundStyle(lvl.tint)
                            }
                        }
                        // In plain words first ("Your body says: slow down"), then the practice.
                        Text(s.plainHeadline).font(SP.rounded(12, .semibold)).foregroundStyle(SP.accent)
                            .lineLimit(2).minimumScaleFactor(0.85)
                        Text(s.title).font(SP.serif(16)).foregroundStyle(SP.ink).lineLimit(2)
                        if s.becauseAddsSomething {
                            Text(s.because).font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(2)
                        }
                        Label("Start · \(s.minutes) min", systemImage: "play.fill")
                            .font(SP.rounded(12, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(minHeight: 28)
                            .background(Capsule().fill(SP.accentFill))
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                        ZStack {
                            shape.fill(LinearGradient(colors: [Color(spHex: "#2C3580"), Color(spHex: "#1A1F4E")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            // The goal's colour glows in the corner and breathes slowly, as on the iPhone.
                            shape.fill(RadialGradient(colors: [tint.opacity(0.32), .clear], center: .topTrailing, startRadius: 2, endRadius: 120))
                                .slowBreathe(period: 5.5, low: 0.55, grow: 0)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Right now: \(s.plainHeadline). \(s.title), \(s.minutes) minutes. \(s.because)")
                NavigationLink(value: "why") {
                    Label("Why this?", systemImage: "info.circle").font(SP.rounded(12)).foregroundStyle(SP.accent).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .task {
                if await RightNowHealth.shouldAsk() { await model.requestAccess() } else { await model.refresh() }
            }
        }
    }
}

struct WatchWhyView: View {
    @ObservedObject private var model = RightNow.shared

    var body: some View {
        let s = model.current
        List {
            Text(s.line).font(SP.rounded(13))
            ForEach(s.why) { w in
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.label).font(SP.rounded(12, .medium))
                    Text(w.value).font(SP.rounded(11)).foregroundStyle(SP.dim)
                    if let src = w.source { Text(src.uppercased()).font(SP.rounded(9, .semibold)).foregroundStyle(SP.faint) }
                }
            }
            Text("The stress level is an estimate from heart rate, HRV and breathing rate vs your usual. Not a medical reading.")
                .font(SP.rounded(10)).foregroundStyle(SP.faint)
        }
        .navigationTitle("Why this?")
    }
}
