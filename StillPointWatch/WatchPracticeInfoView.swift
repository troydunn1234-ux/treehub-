import SwiftUI

/// Compact "About this practice" for the wrist: purpose, how it feels, safety, a fact.
struct WatchPracticeInfoView: View {
    let practice: Practice
    private var info: PracticeInfo { PracticeInfo(practice: practice) }

    var body: some View {
        let i = info
        let tint = i.tradition?.tint ?? SP.teal
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let t = i.tradition {
                    HStack(spacing: 6) {
                        Circle().fill(t.tint).frame(width: 6, height: 6)
                        Text(t.name).font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(1)
                    }
                    if !i.era.isEmpty { Text(i.era).font(SP.rounded(10)).foregroundStyle(SP.faint).lineLimit(2) }
                }
                block("PURPOSE", tint: tint) { GlossaryText(text: i.purpose, font: SP.serif(15, .light), accent: tint) }
                block("WHAT HAPPENS", tint: tint) { GlossaryText(text: i.mechanism, font: SP.rounded(12), color: SP.dim, accent: tint) }
                block("HOW IT FEELS", tint: tint) { GlossaryText(text: i.feel, font: SP.rounded(12), color: SP.dim, accent: tint) }
                if let s = i.safety, !s.isEmpty {
                    block("SAFETY", tint: SP.rose) {
                        Text(s).font(SP.rounded(12)).foregroundStyle(SP.rose.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let f = i.didYouKnow {
                    block("DID YOU KNOW", tint: SP.gold) {
                        Text(f).font(SP.serif(13, .light)).italic().foregroundStyle(SP.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Dotted words open the glossary.").font(SP.rounded(9)).foregroundStyle(SP.faint)
            }
            .padding(.horizontal, 4)
        }
        .background(DuskBackground(glow: tint).opacity(0.9))
        .navigationTitle("About")
    }

    private func block<C: View>(_ title: String, tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(SP.rounded(9, .semibold)).tracking(1.2).foregroundStyle(tint)
                Rectangle().fill(SP.gold.opacity(0.35)).frame(height: 1)
            }
            content()
        }
    }
}
