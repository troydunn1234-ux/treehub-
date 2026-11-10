import SwiftUI

/// "About this practice": purpose, what happens in the body, how it feels, lineage, research, safety.
struct PracticeInfoView: View {
    let practice: Practice
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var info: PracticeInfo { PracticeInfo(practice: practice) }

    var body: some View {
        let i = info
        let tint = i.tradition?.tint ?? SP.teal
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(i, tint: tint)
                    VStack(alignment: .leading, spacing: 18) {
                        section("Purpose", symbol: "sparkle", tint: tint) {
                            GlossaryText(text: i.purpose, font: SP.serif(21, .light), accent: tint)
                        }
                        section("What happens", symbol: "waveform.path.ecg", tint: tint) {
                            GlossaryText(text: i.mechanism, accent: tint)
                        }
                        section("How it feels", symbol: "hand.raised", tint: tint) {
                            GlossaryText(text: i.feel, accent: tint)
                        }
                        if !i.bestFor.isEmpty {
                            section("Best for", symbol: "leaf", tint: tint) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(i.bestFor) { intent in
                                            Label(intent.name, systemImage: intent.symbol)
                                                .font(SP.rounded(13)).foregroundStyle(SP.ink)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(Capsule().fill(tint.opacity(0.18)))
                                        }
                                    }
                                }
                            }
                        }
                        if !i.history.isEmpty {
                            section("History", symbol: "book.closed", tint: tint) {
                                GlossaryText(text: i.history, accent: tint)
                                if !practice.why.isEmpty && practice.why != i.mechanism {
                                    GlossaryText(text: practice.why, font: SP.rounded(14), color: SP.dim, accent: tint)
                                }
                            }
                        }
                        if !i.sources.isEmpty {
                            section("Research & texts", symbol: "text.book.closed", tint: tint) {
                                VStack(spacing: 8) {
                                    ForEach(i.sources) { s in sourceCard(s, tint: tint) }
                                }
                                Text("Descriptions are summaries for orientation, not religious instruction or medical advice.")
                                    .font(SP.rounded(11)).foregroundStyle(SP.faint)
                            }
                        }
                        if let safety = i.safety, !safety.isEmpty {
                            section("Safety", symbol: "heart.text.square", tint: SP.rose) {
                                Text(safety).font(SP.rounded(15)).foregroundStyle(SP.ink.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let fact = i.didYouKnow {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Did you know", systemImage: "lightbulb").font(SP.rounded(12, .semibold)).foregroundStyle(SP.gold)
                                Text(fact).font(SP.serif(17, .light)).italic().foregroundStyle(SP.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.gold.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(SP.gold.opacity(0.3), lineWidth: 1))
                        }
                        NavigationLink { GlossaryListView() } label: {
                            HStack {
                                Label("Glossary", systemImage: "character.book.closed")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            }
                            .font(SP.rounded(15)).foregroundStyle(SP.dim)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.card))
                        }
                        Text("Dotted words open the glossary.").font(SP.rounded(11)).foregroundStyle(SP.faint)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(DuskBackground(glow: tint))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func header(_ i: PracticeInfo, tint: Color) -> some View {
        ZStack(alignment: .bottomLeading) {
            PaintedScene(kind: i.tradition?.scene ?? .water, tint: tint)
            LinearGradient(colors: [.clear, SP.nightBottom.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let t = i.tradition { SPChip(text: t.name, color: t.tint) }
                    SPChip(text: practice.level.capitalized, color: SP.ink.opacity(0.75))
                }
                Text(practice.title).font(SP.serif(30, .light)).foregroundStyle(SP.ink).lineLimit(2)
                if let t = i.tradition {
                    let where_ = [t.region, i.era].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !where_.isEmpty { Text(where_).font(SP.rounded(13)).foregroundStyle(SP.dim) }
                    if !t.origin.isEmpty {
                        Text(t.origin).font(SP.rounded(12)).foregroundStyle(SP.faint).lineLimit(2)
                    }
                }
            }
            .padding(22)
        }
        .frame(height: 260)
    }

    private func section<C: View>(_ title: String, symbol: String, tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
                Text(title.uppercased()).font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Rectangle().fill(SP.gold.opacity(0.35)).frame(height: 1)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }

    private func sourceCard(_ s: ResearchSource, tint: Color) -> some View {
        Button {
            if let u = s.url { openURL(u) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: s.url == nil ? "book" : "link")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(tint).frame(width: 18)
                Text(s.title).font(SP.rounded(13)).foregroundStyle(SP.ink.opacity(0.9))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if s.url != nil {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(SP.faint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(s.url == nil)
    }
}

/// Small ⓘ button that opens PracticeInfoView.
struct PracticeInfoButton: View {
    let practice: Practice
    var size: CGFloat = 18
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Image(systemName: "info.circle").font(.system(size: size, weight: .light)).foregroundStyle(SP.ink.opacity(0.85))
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(practice.title)")
        .sheet(isPresented: $show) { PracticeInfoView(practice: practice) }
    }
}
