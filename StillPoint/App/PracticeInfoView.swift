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
                    VStack(alignment: .leading, spacing: SP.s4) {
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
                                // Wraps onto more lines at big text sizes instead of scrolling sideways.
                                SPFlow(spacing: SP.s2) {
                                    ForEach(i.bestFor) { intent in
                                        Label(intent.name, systemImage: intent.symbol)
                                            .font(.subheadline).foregroundStyle(SP.ink)
                                            .padding(.horizontal, SP.s3)
                                            .frame(minHeight: 36)
                                            .background(Capsule().fill(tint.opacity(0.16)))
                                            .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
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
                                VStack(spacing: SP.s2) {
                                    ForEach(i.sources) { s in sourceCard(s, tint: tint) }
                                }
                                Text("Descriptions are summaries for orientation, not religious instruction or medical advice.")
                                    .font(.caption).foregroundStyle(SP.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let safety = i.safety, !safety.isEmpty {
                            section("Safety", symbol: "heart.text.square", tint: SP.rose, cardTint: SP.rose) {
                                Text(safety).font(.subheadline).foregroundStyle(SP.ink.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let fact = i.didYouKnow {
                            VStack(alignment: .leading, spacing: SP.s2) {
                                Label("Did you know", systemImage: "lightbulb")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(SP.accent)
                                    .accessibilityAddTraits(.isHeader)
                                Text(fact).font(SP.serif(17, .light)).italic().foregroundStyle(SP.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .spCard(tint: SP.accent)
                        }
                        NavigationLink { GlossaryListView() } label: {
                            HStack(spacing: SP.s3) {
                                Image(systemName: "character.book.closed")
                                    .font(.system(size: 16, weight: .regular)).foregroundStyle(SP.accent)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(SP.accent.opacity(0.12)))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Glossary").font(.body.weight(.semibold)).foregroundStyle(SP.ink)
                                    Text("Dotted words open the glossary.").font(.footnote).foregroundStyle(SP.faint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: SP.s2)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SP.faint)
                                    .accessibilityHidden(true)
                            }
                            .spCard(padding: SP.s3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SoftPress())
                    }
                    .padding(.horizontal, SP.screenPadding)
                    .padding(.top, SP.s4)
                    .padding(.bottom, SP.s8 + SP.s2)
                }
            }
            .background(DuskBackground(glow: tint))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(SP.accent)
    }

    /// Painted scene behind the name; grows with big text instead of clipping it.
    private func header(_ i: PracticeInfo, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            SPFlow(spacing: 6) {
                if let t = i.tradition { SPChip(text: t.name, color: t.tint) }
                SPChip(text: practice.level.capitalized, color: SP.ink.opacity(0.75))
            }
            Text(practice.title).font(SP.serif(30, .light)).foregroundStyle(SP.ink)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let t = i.tradition {
                let where_ = [t.region, i.era].filter { !$0.isEmpty }.joined(separator: " · ")
                if !where_.isEmpty { Text(where_).font(.subheadline).foregroundStyle(SP.dim) }
                if !t.origin.isEmpty {
                    Text(t.origin).font(.footnote).foregroundStyle(SP.faint).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, SP.screenPadding)
        .padding(.top, SP.s8 + SP.s8)
        .padding(.bottom, SP.s4)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .bottomLeading)
        .background {
            ZStack {
                PaintedScene(kind: i.tradition?.scene ?? .water, tint: tint)
                LinearGradient(colors: [.clear, SP.nightBottom.opacity(0.9)], startPoint: .center, endPoint: .bottom)
            }
            .accessibilityHidden(true)
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, symbol: String, tint: Color, cardTint: Color? = nil,
                                  @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Label { Text(title) } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.headline).foregroundStyle(SP.ink)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .spCard(tint: cardTint)
    }

    private func sourceCard(_ s: ResearchSource, tint: Color) -> some View {
        Button {
            if let u = s.url { openURL(u) }
        } label: {
            HStack(alignment: .top, spacing: SP.s3) {
                Image(systemName: s.url == nil ? "book" : "link")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(tint).frame(width: 18)
                    .accessibilityHidden(true)
                Text(s.title).font(.footnote).foregroundStyle(SP.ink.opacity(0.9))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if s.url != nil {
                    Image(systemName: "arrow.up.right").font(.caption2.weight(.semibold)).foregroundStyle(SP.faint)
                        .accessibilityHidden(true)
                }
            }
            .padding(SP.s3)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SP.innerRadius, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: SP.innerRadius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: SP.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(s.url == nil)
        .accessibilityHint(s.url == nil ? Text("") : Text("Opens in Safari"))
    }
}

/// Small ⓘ button that opens PracticeInfoView (44 pt hit area).
struct PracticeInfoButton: View {
    let practice: Practice
    var size: CGFloat = 18
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Image(systemName: "info.circle").font(.system(size: size, weight: .light)).foregroundStyle(SP.ink.opacity(0.85))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(practice.title)")
        .sheet(isPresented: $show) { PracticeInfoView(practice: practice) }
    }
}
