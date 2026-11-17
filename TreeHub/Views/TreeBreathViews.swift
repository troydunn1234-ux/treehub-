import SwiftUI

/// "Breath sessions" on a tree's page: Still Pointz breaths done with this tree plus every session linked to
/// its hugs, with heart data and totals.
struct TreeBreathSection: View {
    let treeName: String
    let breaths: [TreeBreath]
    /// First look-up still running: skeleton rows instead of the empty hint.
    var loading = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var totalMinutes: Double { breaths.reduce(0) { $0 + $1.minutes } }
    private var avgDrop: Double? {
        let d = breaths.compactMap(\.hrDrop)
        return d.isEmpty ? nil : d.reduce(0, +) / Double(d.count)
    }
    private var avgHR: Double? {
        let v = breaths.compactMap(\.avgHR)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    private var avgHRV: Double? {
        let v = breaths.compactMap(\.hrv)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RB.m) {
            RBSectionTitle(title: "Breath sessions", symbol: "wind", tint: Theme.sky)
            if breaths.isEmpty && loading {
                RBSkeletonRow()
                RBSkeletonRow()
            } else if breaths.isEmpty {
                Text("Link Still Pointz sessions when you log a hug, or tap \"Breathe with this tree\". They land here with your heart rate.")
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: rbColumns(2, typeSize), spacing: RB.s) {
                    RBStatTile(value: Format.minutes((totalMinutes * 10).rounded() / 10), label: "\(breaths.count) session\(breaths.count == 1 ? "" : "s")", tint: Theme.sky)
                    RBStatTile(value: avgHR.map { String(format: "%.0f bpm", $0) } ?? "--", label: "Avg heart rate", tint: Theme.sky)
                    RBStatTile(value: avgDrop.map { String(format: "−%.0f bpm", $0) } ?? "--", label: "HR drop", tint: Theme.sky)
                    RBStatTile(value: avgHRV.map { String(format: "%.0f ms", $0) } ?? "--", label: "Avg HRV", tint: Theme.sky)
                }
                ForEach(breaths.prefix(20)) { b in TreeBreathRow(breath: b) }
            }
        }
    }
}

struct TreeBreathRow: View {
    let breath: TreeBreath

    var body: some View {
        HStack(alignment: .top, spacing: RB.m) {
            Image(systemName: breath.tagged ? "wind" : "heart.text.square")
                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.sky)
                .frame(width: 40, height: 40)
                .background(Theme.sky.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.dayTime(breath.start)).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                Text(subtitle).font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                if breath.avgHR == nil && breath.hrv == nil {
                    Text("Heart data appears once your watch syncs")
                        .font(RB.text(.caption, .semibold)).foregroundStyle(Theme.textDim)
                } else {
                    FlowLayout(spacing: 6) {
                        if let hr = breath.avgHR { RBInfoChip(text: String(format: "%.0f bpm", hr), symbol: "heart.fill", tint: .white) }
                        if let d = breath.hrDrop, d > 0 { RBInfoChip(text: String(format: "−%.0f bpm", d), symbol: "arrow.down.heart.fill") }
                        if let v = breath.hrv { RBInfoChip(text: String(format: "%.0f ms HRV", v), symbol: "waveform.path.ecg", tint: Theme.sky) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(RB.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbInner()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let name = breath.practice.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
        return [Format.minutes(breath.minutes), name, breath.source].compactMap { $0 }.joined(separator: " · ")
    }
}
