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
                            .listRowBackground(RB.cardFill)
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

/// One linked breath session as a stat block: practice + time, then HR start→end, drop, HRV, avg, low, breathing.
struct LinkedSessionCard: View {
    let session: LinkedSession
    var compact = false

    static func timeRange(_ s: LinkedSession) -> String {
        "\(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))"
    }

    private static func bpm(_ v: Double) -> String { "\(Int(v.rounded()))" }

    private var startEnd: String? {
        var end = session.endHR
        if end == nil, let a = session.startHR, let d = session.hrDrop { end = a - d }
        switch (session.startHR, end) {
        case let (a?, b?): return "\(Self.bpm(a))→\(Self.bpm(b))"
        case let (a?, nil): return Self.bpm(a)
        default: return nil
        }
    }

    private var metrics: [(value: String, label: String, tint: Color)] {
        var m: [(String, String, Color)] = []
        if let v = startEnd { m.append((v, "HR start→end", .white)) }
        if let v = session.hrDrop { m.append((v >= 0 ? String(format: "−%.0f", v) : String(format: "+%.0f", -v), "HR drop (bpm)", Theme.glow)) }
        if let v = session.hrv { m.append((String(format: "%.0f ms", v), "HRV", Theme.sky)) }
        if let v = session.avgHR { m.append((Self.bpm(v), "Avg bpm", .white)) }
        if let v = session.minHR { m.append((Self.bpm(v), "Low bpm", .white)) }
        if let v = session.respRate { m.append((String(format: "%.1f", v), "Breaths/min", .white)) }
        return m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RB.m) {
            HStack(alignment: .center, spacing: RB.m) {
                Image(systemName: "wind")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.sky)
                    .frame(width: 36, height: 36)
                    .background(Theme.sky.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                    Text([Self.timeRange(session), session.practiceName != nil ? session.source : nil]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: RB.s)
                Text(Format.minutes((session.minutes * 10).rounded() / 10))
                    .font(RB.number(.subheadline)).monospacedDigit().foregroundStyle(Theme.sky)
            }
            if metrics.isEmpty {
                Label("Heart data appears once your watch syncs to Health.", systemImage: "applewatch")
                    .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
            } else if !compact {
                RBGrid(minimum: 92) {
                    ForEach(metrics, id: \.label) { m in RBMetric(value: m.value, label: m.label, tint: m.tint) }
                }
            } else {
                Text(metrics.prefix(3).map { "\($0.value) \($0.label.lowercased())" }.joined(separator: " · "))
                    .font(RB.text(.caption, .semibold)).foregroundStyle(Theme.glow)
            }
        }
        .padding(RB.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbInner()
        .accessibilityElement(children: .combine)
    }
}

/// Totals across a hug's linked sessions: breathwork minutes, avg HR, HR drop, HRV.
struct LinkedSessionTotals: View {
    let sessions: [LinkedSession]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(columns: rbColumns(2, typeSize), spacing: RB.s) {
            RBStatTile(value: Format.minutes((sessions.totalMinutes * 10).rounded() / 10), label: "Breathwork", tint: Theme.sky)
            RBStatTile(value: sessions.avgHR.map { "\(Int($0.rounded()))" } ?? "--", label: "Avg bpm", tint: Theme.sky)
            RBStatTile(value: sessions.avgDrop.map { String(format: "−%.0f", $0) } ?? "--", label: "HR drop", tint: Theme.sky)
            RBStatTile(value: sessions.avgHRV.map { String(format: "%.0f ms", $0) } ?? "--", label: "HRV", tint: Theme.sky)
        }
    }
}
