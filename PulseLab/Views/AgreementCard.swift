import SwiftUI

/// Top of Today: the face-off in one card. Watch on the left, WHOOP on the right, for resting HR, HRV, sleep and
/// strain, with an Agree / Split mark on each and today's agreement score (see TodayAgreement).
struct AgreementCard: View {
    let agreement: TodayAgreement
    /// Opens a metric's detail (both trackers on one chart).
    var onOpen: (MetricKey) -> Void
    /// The full VS lab (day-by-day agreement over time).
    var onFaceOff: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LabPanel(tint: Lab.accent, accentEdge: true) {
            VStack(alignment: .leading, spacing: Lab.S.sm) {
                header
                VStack(spacing: 0) {
                    ForEach(Array(agreement.rows.enumerated()), id: \.element.id) { i, row in
                        if i > 0 { Divider().overlay(Lab.line) }
                        rowView(row)
                    }
                }
                Button(action: onFaceOff) {
                    HStack(spacing: 4) {
                        Text("Day-by-day face-off").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Lab.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityHint(Text("Opens the VS lab: how often the two trackers agree, day by day"))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Lab.S.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WATCH VS WHOOP · TODAY")
                    .font(.caption.weight(.bold)).tracking(0.8)
                    .foregroundStyle(Lab.accent)
                Text(agreement.headline)
                    .font(Lab.title(22))
                    .foregroundStyle(Lab.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subline)
                    .font(.footnote).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Lab.S.s)
            if !typeSize.isAccessibilitySize { scoreRing }
        }
        .accessibilityElement(children: .combine)
    }

    private var subline: String {
        if agreement.compared == 0 {
            return String(localized: "Each number needs a recent reading from both trackers. Connect WHOOP or log it by hand in Settings.")
        }
        let splits = agreement.splits
        return splits.isEmpty ? String(localized: "Both trackers tell the same story today.")
            : String(localized: "Split on \(splits.formatted(.list(type: .and))).")
    }

    private var scoreRing: some View {
        let score = agreement.score
        let color = score.map(Lab.band) ?? Lab.faint
        return ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat((score ?? 0) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Lab.reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: score)
            VStack(spacing: 0) {
                Text(score.map { "\(Int($0))%" } ?? "–")
                    .font(Lab.number(18))
                    .foregroundStyle(score == nil ? Lab.faint : Lab.text)
                    .contentTransition(.numericText())
                Text("agree").font(.caption2.weight(.semibold)).foregroundStyle(Lab.faint)
            }
        }
        .frame(width: 70, height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { String(localized: "Agreement \(Int($0)) percent") } ?? String(localized: "No agreement score yet"))
    }

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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Lab.S.s) {
                    Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                    Spacer(minLength: Lab.S.s)
                    verdict(row.agree)
                }
                HStack(alignment: .firstTextBaseline, spacing: Lab.S.s) {
                    side(row.watch, missing: row.missing, color: Lab.watch)
                    Text("vs").font(.caption.weight(.semibold)).foregroundStyle(Lab.faint)
                    side(row.whoop, missing: row.missing, color: Lab.whoop)
                    Spacer(minLength: 0)
                }
                Text(row.detail).font(.caption).foregroundStyle(Lab.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Lab.S.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(row)))
        .accessibilityHint(Text("Opens its chart with both trackers"))
    }

    private func side(_ value: String?, missing: String, color: Color) -> some View {
        Text(value ?? missing)
            .font(value == nil ? .footnote.weight(.medium) : Lab.number(17))
            .foregroundStyle(value == nil ? Lab.faint : color)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func verdict(_ agree: Bool?) -> some View {
        let (text, symbol, color): (String, String, Color) = switch agree {
        case true?: (String(localized: "Agree"), "checkmark.circle.fill", Lab.good)
        case false?: (String(localized: "Split"), "arrow.left.arrow.right.circle.fill", Lab.warn)
        case nil: (String(localized: "Not compared"), "circle.dashed", Lab.faint)
        }
        return Label(text, systemImage: symbol)
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
