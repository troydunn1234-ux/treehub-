import SwiftUI

/// Watch home "Right now": the iPhone's pick (it sees WHOOP and Pulse Lab) while fresh, else one made here
/// from the Watch's own Health data. One tap starts it; "Why?" lists the numbers used.
struct WatchRightNowCard: View {
    @ObservedObject private var model = RightNow.shared
    let onStart: (Practice, Int) -> Void

    var body: some View {
        let s = model.current
        if let p = PracticeLibrary.shared.practice(s.practiceId) {
            VStack(alignment: .leading, spacing: 4) {
                Button { onStart(p, s.minutes) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("RIGHT NOW").font(SP.rounded(10, .semibold)).foregroundStyle(SP.amber)
                            Spacer(minLength: 0)
                            if let lvl = s.stressLevel.flatMap(StressEstimate.Level.init(rawValue:)) {
                                Circle().fill(lvl.tint).frame(width: 6, height: 6)
                                Text(lvl.label).font(SP.rounded(10)).foregroundStyle(lvl.tint)
                            }
                        }
                        Text(s.title).font(SP.serif(16)).foregroundStyle(SP.ink).lineLimit(2)
                        Text(s.because).font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(3)
                        Text("Begin · \(s.minutes) min").font(SP.rounded(12, .medium)).foregroundStyle(SP.gold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Right now: \(s.title), \(s.minutes) minutes. \(s.because)")
                NavigationLink(value: "why") {
                    Text("Why this?").font(SP.rounded(12)).foregroundStyle(SP.teal)
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
