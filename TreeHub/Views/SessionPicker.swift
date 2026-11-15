import SwiftUI

/// Multi-select sheet: which Still Pointz / Health breath sessions go with this hug.
/// Every session within an hour of the photo is listed (and preselected by the logger); uncheck any that don't belong.
@MainActor
struct SessionPickerSheet: View {
    let around: Date
    @State var candidates: [LinkedSession]
    @State var selected: Set<UUID>
    var onDone: ([LinkedSession]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { s in
                        Button { toggle(s) } label: { row(s) }
                            .listRowBackground(Theme.card)
                    }
                } header: {
                    Text("Within an hour of \(around.formatted(date: .omitted, time: .shortened))")
                } footer: {
                    Text("Checked sessions are linked to this hug. Their heart rate and HRV fill in as your watch syncs.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ForestBackground())
            .navigationTitle("Breath sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Link none" : "Link \(selected.count)") {
                        onDone(candidates.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                // Fill in heart data for the rows (avg HR "if known").
                let rich = await HugSessions.enrich(candidates)
                if rich.count == candidates.count { candidates = rich }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ s: LinkedSession) {
        if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func row(_ s: LinkedSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected.contains(s.id) ? Theme.glow : Theme.textDim)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                Text(LinkedSessionCard.timeRange(s) + " · " + Format.minutes((s.minutes * 10).rounded() / 10))
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                if s.practiceName != nil, !s.source.isEmpty {
                    Text(s.source).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 0)
            if let hr = s.avgHR {
                Label("\(Int(hr.rounded()))", systemImage: "heart.fill")
                    .font(Theme.rounded(13, .bold)).foregroundStyle(Theme.glow)
                    .accessibilityLabel("\(Int(hr.rounded())) beats per minute average")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected.contains(s.id) ? .isSelected : [])
    }
}

/// One linked breath session with all its data: practice, time, minutes, heart rate, HR drop, HRV, breathing.
struct LinkedSessionCard: View {
    let session: LinkedSession
    var compact = false

    static func timeRange(_ s: LinkedSession) -> String {
        "\(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))"
    }

    private var metrics: [(String, String, String)] {
        var m: [(String, String, String)] = []
        if let v = session.avgHR { m.append(("heart.fill", "\(Int(v.rounded()))", "Avg bpm")) }
        if let v = session.minHR { m.append(("arrow.down", "\(Int(v.rounded()))", "Low bpm")) }
        if let v = session.startHR { m.append(("play.fill", "\(Int(v.rounded()))", "Start bpm")) }
        if let v = session.hrDrop { m.append(("arrow.down.heart.fill", String(format: "%.0f", v), "HR drop")) }
        if let v = session.hrv { m.append(("waveform.path.ecg", String(format: "%.0f ms", v), "HRV")) }
        if let v = session.respRate { m.append(("lungs.fill", String(format: "%.1f", v), "Breaths/min")) }
        return m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                    Text([Self.timeRange(session), session.practiceName != nil ? session.source : nil]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Text(Format.minutes((session.minutes * 10).rounded() / 10))
                    .font(Theme.rounded(15, .bold)).foregroundStyle(Theme.sky)
            }
            if metrics.isEmpty {
                Text("Heart data appears once your watch syncs to Health.")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            } else if !compact {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(metrics, id: \.2) { m in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.1).font(Theme.rounded(17, .bold)).foregroundStyle(.white).monospacedDigit()
                            Text(m.2).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text(metrics.prefix(3).map { "\($0.1) \($0.2.lowercased())" }.joined(separator: " · "))
                    .font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.glow)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Totals across a hug's linked sessions: breathwork minutes, avg HR, HR drop, HRV.
struct LinkedSessionTotals: View {
    let sessions: [LinkedSession]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatTile(value: Format.minutes((sessions.totalMinutes * 10).rounded() / 10), label: "Breathwork", tint: Theme.sky)
            StatTile(value: sessions.avgHR.map { "\(Int($0.rounded()))" } ?? "--", label: "Avg bpm", tint: Theme.sky)
            StatTile(value: sessions.avgDrop.map { String(format: "−%.0f", $0) } ?? "--", label: "HR drop", tint: Theme.sky)
            StatTile(value: sessions.avgHRV.map { String(format: "%.0f ms", $0) } ?? "--", label: "HRV", tint: Theme.sky)
        }
    }
}
