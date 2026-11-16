import SwiftUI

/// "Breath sessions" on a tree's page: Still Pointz breaths done with this tree plus every session linked to
/// its hugs, with heart data and totals.
struct TreeBreathSection: View {
    let treeName: String
    let breaths: [TreeBreath]

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
        VStack(alignment: .leading, spacing: 12) {
            RBSectionTitle(title: "Breath sessions", symbol: "wind")
            if breaths.isEmpty {
                Text("Link Still Pointz sessions when you log a hug, or tap \"Breathe with this tree\". They land here with your heart rate.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
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
        HStack(spacing: 12) {
            Image(systemName: breath.tagged ? "wind" : "heart.text.square")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.sky)
                .frame(width: 40, height: 40)
                .background(Theme.sky.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.dayTime(breath.start)).font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                Text(subtitle).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.textDim).lineLimit(1)
                HStack(spacing: 10) {
                    if let hr = breath.avgHR { Label(String(format: "%.0f bpm", hr), systemImage: "heart.fill") }
                    if let d = breath.hrDrop, d > 0 { Label(String(format: "−%.0f", d), systemImage: "arrow.down.heart.fill") }
                    if let v = breath.hrv { Label(String(format: "%.0f ms", v), systemImage: "waveform.path.ecg") }
                    if breath.avgHR == nil && breath.hrv == nil { Text("Heart data appears once your watch syncs") }
                }
                .font(Theme.rounded(12, .bold)).foregroundStyle(Theme.glow)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let name = breath.practice.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
        return [Format.minutes(breath.minutes), name, breath.source].compactMap { $0 }.joined(separator: " · ")
    }
}
