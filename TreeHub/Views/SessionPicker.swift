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
        HStack(spacing: RB.m) {
            Image(systemName: selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected.contains(s.id) ? Theme.glow : Theme.textDim)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(RB.text(.headline, .bold)).foregroundStyle(.white)
                Text(LinkedSessionCard.timeRange(s) + " · " + Format.minutes((s.minutes * 10).rounded() / 10))
                    .font(RB.text(.subheadline)).foregroundStyle(Theme.textDim)
                    .monospacedDigit()
                if s.practiceName != nil, !s.source.isEmpty {
                    Text(s.source).font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 0)
            if let hr = s.avgHR {
                Label("\(Int(hr.rounded()))", systemImage: "heart.fill")
                    .font(RB.text(.subheadline, .bold)).monospacedDigit().foregroundStyle(Theme.glow)
                    .accessibilityLabel("\(Int(hr.rounded())) beats per minute average")
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, RB.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected.contains(s.id) ? .isSelected : [])
    }
}

/// One linked breath session as a stat block: practice + time, then HR start→end, drop, HRV, avg, low, max,
/// breathing rate, calm-zone time and paced breathing — each only when it's known.
struct LinkedSessionCard: View {
    let session: LinkedSession
    var compact = false

    static func timeRange(_ s: LinkedSession) -> String {
        "\(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))"
    }

    private static func bpm(_ v: Double) -> String { "\(Int(v.rounded()))" }

    private var metrics: [(value: String, label: String, tint: Color)] {
        var m: [(value: String, label: String, tint: Color)] = []
        // First → last reading when both are known; otherwise whichever one there is.
        switch (session.startHR, session.endHR) {
        case let (a?, b?): m.append(("\(Self.bpm(a))→\(Self.bpm(b))", "HR start→end", .white))
        case let (a?, nil): m.append((Self.bpm(a), "Start bpm", .white))
        case let (nil, b?): m.append((Self.bpm(b), "End bpm", .white))
        default: break
        }
        if let v = session.hrDrop { m.append((v >= 0 ? String(format: "−%.0f", v) : String(format: "+%.0f", -v), "HR drop (bpm)", Theme.glow)) }
        if let v = session.hrv { m.append((String(format: "%.0f ms", v), "HRV", Theme.sky)) }
        if let v = session.avgHR { m.append((Self.bpm(v), "Avg bpm", .white)) }
        if let v = session.minHR { m.append((Self.bpm(v), "Low bpm", .white)) }
        if let v = session.maxHR { m.append((Self.bpm(v), "Max bpm", .white)) }
        if let v = session.respRate { m.append((String(format: "%.1f", v), "Breaths/min", Theme.sky)) }
        // Still Pointz (newer builds): time below the starting heart rate and the practice's paced breathing.
        if let v = session.calmSeconds, v > 0 { m.append((Format.duration(v), "Calm zone", Theme.glow)) }
        if let v = session.pacedBPM, v > 0 { m.append((String(format: "%.1f", v), "Paced breaths/min", Theme.sky)) }
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
                Text(metrics.prefix(3).map { "\($0.label) \($0.value)" }.joined(separator: "  ·  "))
                    .font(RB.text(.caption, .semibold)).foregroundStyle(Theme.glow)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
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
