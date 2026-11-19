import SwiftUI
import SwiftData

/// "Insights": next-morning recovery / HRV / sleep on days with vs without each thing you do.
struct InsightsScreen: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Supplement.order) private var supps: [Supplement]
    @Query private var doses: [SuppDose]
    @State private var kind: Correlations.OutcomeKind = .recovery
    @State private var extras = HealthExtras()
    @State private var loadingExtras = true
    @State private var alcoholAsked = InsightsHealth.alcoholAsked

    var body: some View {
        let outcome = Correlations.outcome(kind, store: store)
        let results = Correlations.factors(store: store, supps: supps, doses: doses, extras: extras)
            .map { Correlations.compare($0, outcome) }
        let ready = results.filter(\.enough).sorted { abs($0.effect ?? 0) > abs($1.effect ?? 0) }
        let waiting = results.filter { !$0.enough }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "How your next morning looks after days with, and without, each thing you do. Averages of your own days only."))
                        .font(Lab.body(14)).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker(String(localized: "Compare"), selection: $kind) {
                        ForEach(Correlations.OutcomeKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(String(localized: "Measured with: \(outcome.noun) · \(outcome.byMorning.count) mornings"))
                        .font(Lab.label(9)).foregroundStyle(Lab.faint)

                    if loadingExtras {
                        // Placeholder rows (not a spinner) while sauna, food and drink data is read.
                        VStack(spacing: 10) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous)
                                    .fill(Lab.inset)
                                    .frame(height: 64)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "Reading sauna, food and drink data"))
                    }
                    if results.isEmpty && !loadingExtras {
                        emptyState
                    }
                    ForEach(ready) { ResultRow(result: $0) }
                    if !waiting.isEmpty {
                        SectionTag(String(localized: "Not enough data yet"))
                            .padding(.top, 4)
                        ForEach(waiting) { WaitingRow(result: $0) }
                    }
                    if !alcoholAsked {
                        alcoholPrompt
                    }
                    Text(String(localized: "These are patterns in your own numbers, not cause and effect, and not medical advice. Sleep, training, stress and illness move these numbers too. Effect size is Cohen's d: under 0.2 is no clear difference, 0.5 moderate, 0.8 or more large."))
                        .font(Lab.label(9)).foregroundStyle(Lab.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Lab.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Insights"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: kind)
        }
        .task { await loadExtras() }
    }

    private func loadExtras() async {
        loadingExtras = true
        extras = await InsightsHealth.shared.load()
        loadingExtras = false
    }

    private var emptyState: some View {
        LabPanel(tint: Lab.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Nothing to compare yet")).font(Lab.display(17, .heavy)).foregroundStyle(Lab.text)
                Text(String(localized: "Check off your Stack, log workouts or sauna sessions, and keep wearing your trackers. Once there are at least \(Correlations.minDays) days with and \(Correlations.minDays) without, comparisons show up here."))
                    .font(Lab.body(13)).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var alcoholPrompt: some View {
        LabPanel(tint: Lab.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "Include alcohol"), systemImage: "wineglass.fill")
                    .font(Lab.display(15, .heavy)).foregroundStyle(Lab.text)
                Text(String(localized: "If you log drinks in the Health app (or an app that saves them there), Pulse Lab can compare mornings after. It only reads them."))
                    .font(Lab.body(13)).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        await InsightsHealth.shared.requestAlcohol()
                        alcoholAsked = true
                        await loadExtras()
                    }
                } label: {
                    Text(String(localized: "Allow reading drinks"))
                        .font(Lab.display(14, .heavy)).foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Lab.accent))
                }
                .buttonStyle(PressScale())
            }
        }
    }
}

private struct ResultRow: View {
    let result: Correlations.Result

    var body: some View {
        let r = result
        let diff = r.diff ?? 0
        // Recovery, HRV and sleep: higher is the better direction for all three.
        let better = diff >= 0
        LabPanel(tint: r.size == .none ? Lab.accent : (better ? Lab.good : Lab.warn)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(r.factor.title).font(Lab.display(16, .heavy)).foregroundStyle(Lab.text)
                    Spacer()
                    Text(r.size.label.uppercased())
                        .font(Lab.label(8)).tracking(0.4).foregroundStyle(r.size == .none ? Lab.dim : (better ? Lab.good : Lab.warn))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                Text(r.sentence).font(Lab.body(13)).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
                bars
                HStack(spacing: 12) {
                    Text(String(localized: "Difference \(signed(diff))")).font(Lab.mono(10)).foregroundStyle(Lab.text)
                    if let e = r.effect {
                        Text(String(localized: "Effect size \(e.formatted(.number.precision(.fractionLength(2))))")).font(Lab.mono(10)).foregroundStyle(Lab.dim)
                    }
                    Text(String(localized: "n = \(r.on.count) / \(r.off.count)")).font(Lab.mono(10)).foregroundStyle(Lab.faint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.factor.title). \(r.size.label). \(r.sentence)")
    }

    private func signed(_ d: Double) -> String {
        let o = result.outcome
        let text = o.kind == .sleep ? fmtHM(abs(d)) : abs(d).formatted(.number.precision(.fractionLength(o.decimals))) + o.unit
        return (d >= 0 ? "+" : "−") + text
    }

    private var bars: some View {
        let a = result.onMean ?? 0, b = result.offMean ?? 0
        let top = max(a, b, 1)
        return VStack(alignment: .leading, spacing: 5) {
            bar(String(localized: "With"), a, top, Lab.watch)
            bar(String(localized: "Without"), b, top, Color.white.opacity(0.3))
        }
        .accessibilityHidden(true)
    }

    private func bar(_ label: String, _ v: Double, _ top: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Lab.label(8)).foregroundStyle(Lab.faint).frame(width: 52, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(color).frame(width: max(4, g.size.width * CGFloat(v / top)))
            }
            .frame(height: 8)
            Text(result.outcome.format(v)).font(Lab.mono(10)).foregroundStyle(Lab.text).frame(width: 64, alignment: .trailing)
        }
    }
}

private struct WaitingRow: View {
    let result: Correlations.Result
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.factor.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Lab.faint)
                .frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.factor.title).font(Lab.display(14, .bold)).foregroundStyle(Lab.text)
                Text(String(localized: "\(result.on.count) days with, \(result.off.count) without · needs \(Correlations.minDays) of each"))
                    .font(Lab.mono(10)).foregroundStyle(Lab.faint)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Entry point on Today and in the Stack.
struct InsightsButton: View {
    @Environment(LabStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var show = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            show = true
        } label: {
            HStack(spacing: Lab.S.s) {
                Image(systemName: "chart.dots.scatter").font(.system(size: 14, weight: .bold)).foregroundStyle(Lab.good)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Insights")).font(Lab.display(15, .heavy)).foregroundStyle(Lab.text)
                    Text(String(localized: "Supplements, sauna, workouts and more vs your next morning"))
                        .font(Lab.mono(10)).foregroundStyle(Lab.faint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Lab.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Lab.S.m).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Lab.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Lab.good.opacity(0.35)))
        }
        .buttonStyle(PressScale())
        .accessibilityHint(String(localized: "Opens trends and correlations"))
        .sheet(isPresented: $show) {
            InsightsScreen().environment(store).modelContext(modelContext).presentationBackground(Lab.bg)
        }
    }
}
