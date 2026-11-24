import SwiftUI

/// Top of Today, the hero: Watch vs WHOOP in one card. A plain-words headline ("They agree on 3 of 4" / "Sleep is
/// off by 42 min."), today's agreement score as the two-arc versus ring (VersusRing), and one row per metric
/// (resting HR, HRV, sleep, strain) with Watch on the left, WHOOP on the right and the verdict in the middle.
/// Every row opens that metric's chart; the button at the bottom opens VS (see TodayAgreement for the maths).
struct AgreementCard: View {
    let agreement: TodayAgreement
    /// Resting heart rate the ring beats at (nil = a calm 60).
    var restingBPM: Double? = nil
    /// A sync is running and nothing compares yet: the ring scans instead of showing "no score".
    var scanning = false
    /// Opens a metric's detail (both trackers on one chart).
    var onOpen: (MetricKey) -> Void
    /// Opens Log WHOOP (shown when nothing compares and WHOOP is the missing side).
    var onLogWhoop: (() -> Void)? = nil
    /// The VS tab (day-by-day agreement over time).
    var onFaceOff: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var unlock = Unlock.shared
    /// Bumped once a day (per launch) when the two fully agree: sparks, a bounce and a success tap.
    @State private var celebrate = 0
    /// Bumped when the score first shows in a launch or changes: one scanner line across the card.
    @State private var scan = 0

    var body: some View {
        VersusPanel(scan: scan) {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                kicker
                header
                if agreement.compared == 0 && !scanning { emptyHint }
                VStack(spacing: 0) {
                    ForEach(Array(agreement.rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Divider().overlay(Lab.line) }
                        rowView(row)
                    }
                }
                Button(action: onFaceOff) {
                    HStack(spacing: 6) {
                        Image(systemName: unlock.isPro ? "bolt.horizontal.fill" : "lock.fill")
                            .font(.footnote.weight(.bold))
                            .accessibilityHidden(true)
                        Text("Day by day in VS")
                    }
                }
                .buttonStyle(LabSecondaryButton())
                .accessibilityHint(unlock.isPro ? Text("Opens VS: how often the two trackers agree, day by day")
                                                : Text("Opens the Pro unlock for VS"))
            }
        }
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            if agreement.score != nil, AgreementMoments.firstLook() { scan += 1 }
            celebrateIfDue()
        }
        .onChange(of: agreement.score) { old, new in
            if new != nil && old != new { scan += 1 }
            celebrateIfDue()
        }
    }

    // MARK: Header

    /// "Watch vs WHOOP · Today" on one line; at the largest text sizes "Today" goes under it instead of the
    /// wordmark being cut off.
    private var kicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                VersusWordmark(font: .subheadline.weight(.bold))
                Text("· Today").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.faint)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                VersusWordmark(font: .subheadline.weight(.bold)).minimumScaleFactor(0.6)
                Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(Lab.faint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                ring(size: 150).frame(maxWidth: .infinity)
                words
            }
        } else {
            HStack(alignment: .center, spacing: Lab.S.sm) {
                words
                Spacer(minLength: Lab.S.s)
                ring(size: 104)
            }
        }
    }

    private func ring(size: CGFloat) -> some View {
        VersusRing(score: agreement.score, size: size, bpm: restingBPM, scanning: scanning, celebrate: celebrate)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Lab.S.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline)
                    .font(Lab.title(22))
                    .foregroundStyle(Lab.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if agreement.fullAgreement {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(Lab.good)
                        .symbolEffect(.bounce, value: celebrate)
                        .accessibilityHidden(true)
                }
            }
            Text(reason)
                .font(.subheadline).foregroundStyle(Lab.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        scanning ? String(localized: "Reading both trackers…") : agreement.headline
    }

    private var reason: String {
        scanning ? String(localized: "Pulling today's numbers from Health and WHOOP.") : agreement.reason
    }

    /// Nothing compares yet: say which side is missing, with the one thing to do about it.
    @ViewBuilder
    private var emptyHint: some View {
        let whoopMissing = agreement.rows.allSatisfy { $0.whoop == nil }
        let watchMissing = agreement.rows.allSatisfy { $0.watch == nil }
        VStack(alignment: .leading, spacing: Lab.S.s) {
            if whoopMissing || watchMissing {
                HStack(alignment: .top, spacing: Lab.S.s) {
                    Image(systemName: watchMissing && !whoopMissing ? "applewatch" : "bolt.heart.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(watchMissing && !whoopMissing ? Lab.watch : Lab.whoop)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(emptyLine(whoopMissing: whoopMissing, watchMissing: watchMissing))
                        .font(.footnote).foregroundStyle(Lab.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if whoopMissing, let onLogWhoop {
                Button {
                    Lab.tick()
                    onLogWhoop()
                } label: {
                    Label("Log today's WHOOP", systemImage: "square.and.pencil")
                }
                .buttonStyle(LabPrimaryButton(tint: Lab.whoop))
                .accessibilityHint(Text("Type today's WHOOP numbers by hand"))
            }
        }
    }

    private func emptyLine(whoopMissing: Bool, watchMissing: Bool) -> String {
        if whoopMissing && watchMissing {
            return String(localized: "Nothing from either tracker since yesterday. Pull to sync, or type today's WHOOP in.")
        }
        if whoopMissing { return String(localized: "Your Watch is in. Add today's WHOOP to compare.") }
        return String(localized: "WHOOP is in. Wear your Watch a few hours (or to bed) to compare.")
    }

    private func celebrateIfDue() {
        guard agreement.fullAgreement, AgreementMoments.celebrateToday() else { return }
        // Let the arcs finish their sweep and meet at the top first.
        let wait = reduceMotion ? 0.2 : 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { celebrate += 1 }
    }

    // MARK: Rows

    private func metricKey(_ m: TodayAgreement.Row.Metric) -> MetricKey {
        switch m {
        case .rhr: .rhr
        case .hrv: .hrv
        case .sleep: .sleep
        case .strain: .activeKcal
        }
    }

    private func rowView(_ row: TodayAgreement.Row) -> some View {
        Button { onOpen(metricKey(row.metric)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Lab.S.s) {
                    Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                    Spacer(minLength: Lab.S.s)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(Lab.faint)
                        .accessibilityHidden(true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Lab.S.s) {
                        side(row.watch, missing: row.missing, color: Lab.watch)
                        AgreeConnector(agree: row.agree) { verdict(row.agree) }
                        side(row.whoop, missing: row.missing, color: Lab.whoop)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        stackedSide(.watch, row.watch, missing: row.missing)
                        stackedSide(.whoop, row.whoop, missing: row.missing)
                        verdict(row.agree)
                    }
                }
                Text(row.detail).font(.caption).foregroundStyle(Lab.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Lab.S.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(row)))
        .accessibilityHint(Text("Opens its chart with both trackers"))
        .accessibilityAddTraits(.isButton)
    }

    private func side(_ value: String?, missing: String, color: Color) -> some View {
        Text(value ?? missing)
            .font(value == nil ? .footnote.weight(.medium) : Lab.number(17))
            .foregroundStyle(value == nil ? Lab.faint : color)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
    }

    /// Accessibility text sizes: one line per tracker instead of the connector.
    private func stackedSide(_ s: Source, _ value: String?, missing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The dot is centred on its label (an overlay), not stood on the baseline where it read as a full stop.
            Text(verbatim: s.label).font(.footnote.weight(.semibold)).foregroundStyle(Lab.color(s))
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    Circle().fill(Lab.color(s)).frame(width: 7, height: 7).accessibilityHidden(true)
                }
            Text(value ?? missing)
                .font(value == nil ? .footnote.weight(.medium) : Lab.number(17))
                .foregroundStyle(value == nil ? Lab.faint : Lab.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verdict(_ agree: Bool?) -> some View {
        let (text, symbol, color): (String, String, Color) = switch agree {
        case true?: (String(localized: "Agree"), "checkmark.circle.fill", Lab.good)
        case false?: (String(localized: "Split"), "notequal.circle.fill", Lab.warn)
        case nil: (String(localized: "Not compared"), "circle.dashed", Lab.faint)
        }
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .symbolEffect(.bounce, value: agree)
                .accessibilityHidden(true)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .fixedSize()
    }

    private func spoken(_ row: TodayAgreement.Row) -> String {
        let verdict = row.agree.map { $0 ? String(localized: "agree") : String(localized: "split") } ?? String(localized: "not compared")
        return String(localized: "\(row.title): Watch \(row.watch ?? row.missing), WHOOP \(row.whoop ?? row.missing), \(verdict). \(row.detail)")
    }
}
