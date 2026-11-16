import SwiftUI

/// Top of Today: the morning briefing. Recovery, last night vs the week, HRV and resting HR vs the
/// 30-day baseline, yesterday's strain and one plain-English line.
struct BriefingCard: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let b = store.briefing
        LabPanel(tint: Lab.good) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTag(String(localized: "Morning briefing"))
                    Spacer()
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(.footnote).foregroundStyle(Lab.faint)
                        .accessibilityHidden(true)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.detail = b.recoveryKind == .readiness ? .readiness : .recovery
                } label: {
                    recoveryRow(b).contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityHint(b.recoveryKind == .readiness ? String(localized: "Shows how readiness was worked out") : String(localized: "Opens the recovery chart"))
                let cols = typeSize.isAccessibilitySize ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Lab.S.s), count: cols), alignment: .leading, spacing: Lab.S.s) {
                    stat(String(localized: "Sleep"), b.sleepMin.map { fmtHM($0) },
                         delta: b.sleepDeltaMin.map { ($0 >= 0 ? "+" : "−") + fmtHM(abs($0)) + " " + String(localized: "vs 7-night avg") },
                         good: b.sleepDeltaMin.map { $0 >= -10 })
                    stat(String(localized: "HRV"), b.hrv.map { "\(Int($0.rounded())) ms" },
                         delta: b.hrvDeltaPct.map { ($0 >= 0 ? "+" : "−") + "\(Int(abs($0).rounded()))% " + String(localized: "vs 30-day") },
                         good: b.hrvDeltaPct.map { $0 >= -5 })
                    stat(String(localized: "Resting HR"), b.rhr.map { "\(Int($0.rounded())) bpm" },
                         delta: b.rhrDelta.map { ($0 >= 0 ? "+" : "−") + "\(abs($0).formatted(.number.precision(.fractionLength(1)))) " + String(localized: "vs 30-day") },
                         good: b.rhrDelta.map { $0 <= 2 })
                    stat(String(localized: "Strain yesterday"), b.strainYesterday.map { $0.formatted(.number.precision(.fractionLength(1))) },
                         delta: nil, good: nil)
                }
                Text(b.takeaway)
                    .font(.subheadline).foregroundStyle(Lab.text)
                    .fixedSize(horizontal: false, vertical: true)
                if b.whoopMissing {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.logWhoop = LogWhoopRequest()
                    } label: {
                        Label(String(localized: "Log today's WHOOP to complete it"), systemImage: "square.and.pencil")
                    }
                    .buttonStyle(LabSecondaryButton(tint: Lab.whoop))
                }
                Text(String(localized: "Describes your numbers against your own history. Not medical advice."))
                    .font(.caption2).foregroundStyle(Lab.faint)
            }
        }
    }

    private func recoveryRow(_ b: Briefing) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat((b.recovery ?? 0) / 100))
                    .stroke(Lab.band(b.recovery ?? 0), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(b.recovery.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(Lab.number(22)).foregroundStyle(Lab.text)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 62, height: 62)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.recoveryLabel).font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim)
                Text(band(b.recovery)).font(.title3.weight(.bold)).foregroundStyle(b.recovery.map(Lab.band) ?? Lab.text)
                if b.recoveryKind == .readiness {
                    Text(String(localized: "Pulse Lab's score from your Watch")).font(.caption2).foregroundStyle(Lab.faint)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lab.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(b.recovery.map { "\(b.recoveryLabel) \(Int($0.rounded())), \(band($0))" } ?? String(localized: "\(b.recoveryLabel): no score yet"))
    }

    private func band(_ r: Double?) -> String {
        guard let r else { return String(localized: "Not in yet") }
        return r >= 67 ? String(localized: "High") : r >= 34 ? String(localized: "Moderate") : String(localized: "Low")
    }

    private func stat(_ title: String, _ value: String?, delta: String?, good: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Lab.dim)
            Text(value ?? "—").font(Lab.number(19)).foregroundStyle(value == nil ? Lab.faint : Lab.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(delta ?? (value == nil ? String(localized: "No reading") : " ")).font(Lab.mono(11, .medium))
                .foregroundStyle(good == false ? Lab.warn : Lab.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Lab.S.sm)
        .background(RoundedRectangle(cornerRadius: Lab.innerRadius, style: .continuous).fill(Lab.inset))
        .accessibilityElement(children: .combine)
    }
}
