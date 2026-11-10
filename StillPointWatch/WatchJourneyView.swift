import SwiftUI

/// Last few sessions on the wrist; tap one for its heart-rate curve and stats.
struct WatchJourneyView: View {
    @EnvironmentObject var log: SessionLog

    var body: some View {
        List {
            if log.records.isEmpty {
                Text("Your sessions will gather here.").font(SP.serif(15, .light)).foregroundStyle(SP.dim)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        stat("\(Int(log.weekMinutes.rounded()))", "MIN · 7D")
                        Spacer()
                        stat("\(log.streak)", log.streak == 1 ? "DAY" : "DAYS")
                        Spacer()
                        stat("\(log.records.count)", "ALL")
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Recent") {
                    ForEach(log.records.prefix(7)) { r in
                        NavigationLink { WatchSessionDetailView(record: r) } label: { row(r) }
                            .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
        .navigationTitle("Journey")
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(SP.numbers(18)).foregroundStyle(SP.ink)
            Text(l).font(SP.rounded(8, .semibold)).tracking(1).foregroundStyle(SP.faint)
        }
    }

    private func row(_ r: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.title).font(SP.serif(14)).foregroundStyle(SP.ink).lineLimit(1)
            HStack(spacing: 6) {
                Text(r.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                Text("·")
                Text("\(Int(max(1, r.minutes.rounded()))) min")
                if let d = r.hrDrop, d > 0 { Text("♥ −\(Int(d))").foregroundStyle(SP.rose) }
            }
            .font(SP.rounded(11)).foregroundStyle(SP.faint)
        }
        .padding(.vertical, 2)
    }
}

/// One session: a small heart-rate curve and the numbers.
struct WatchSessionDetailView: View {
    let record: SessionRecord
    private var tint: Color {
        let lib = PracticeLibrary.shared
        guard let p = lib.practice(record.practiceId), let t = lib.tradition(p.traditionId) else { return SP.teal }
        return t.tint
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(record.title).font(SP.serif(16)).foregroundStyle(SP.ink)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Text(record.start.formatted(.dateTime.weekday(.wide).hour().minute()))
                    .font(SP.rounded(11)).foregroundStyle(SP.faint)

                if let samples = record.hrSamples, samples.count >= 2 {
                    HRMiniChart(samples: samples, tint: tint)
                        .frame(height: 64)
                        .padding(.horizontal, 2)
                    HStack {
                        Text("\(Int(record.hrStart ?? samples.first?.bpm ?? 0))").foregroundStyle(SP.dim)
                        Spacer()
                        if let m = record.hrMin { Text("low \(Int(m))").foregroundStyle(SP.teal) }
                        Spacer()
                        Text("\(Int(record.hrEnd ?? samples.last?.bpm ?? 0))").foregroundStyle(SP.dim)
                    }
                    .font(SP.rounded(10))
                } else if record.hasHeartRate {
                    Text("\(Int(record.hrStart ?? 0)) → \(Int(record.hrMin ?? record.hrEnd ?? 0)) bpm")
                        .font(SP.numbers(18)).foregroundStyle(SP.ink)
                } else {
                    Text("No heart rate. Turn it on in Fine-tune.").font(SP.rounded(11)).foregroundStyle(SP.faint)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    tile("\(Int(max(1, record.minutes.rounded())))", "MIN")
                    if record.cycles > 0 { tile("\(record.cycles)", record.isMovement ? "STEPS" : "BREATHS") }
                    if let a = record.hrAvg { tile("\(Int(a.rounded()))", "AVG BPM") }
                    if let d = record.hrDrop { tile((d >= 0 ? "−" : "+") + "\(Int(abs(d).rounded()))", "HR DROP") }
                    if let h = record.hrv { tile("\(Int(h.rounded()))", "HRV MS") }
                    if let b = record.breathsPerMinute, !record.isMovement { tile(String(format: "%.1f", b), "BR/MIN") }
                    if let rr = record.respiratoryRate { tile(String(format: "%.0f", rr), "RESP") }
                    if let c = record.calmScore { tile("\(c)", "CALM*") }
                }
                if record.calmScore != nil {
                    Text("*Calm is a simple estimate from how far your heart rate settled.")
                        .font(SP.rounded(9)).foregroundStyle(SP.faint).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(DuskBackground(glow: tint).opacity(0.9))
        .navigationTitle("Session")
    }

    private func tile(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(SP.numbers(17)).foregroundStyle(SP.ink)
            Text(l).font(SP.rounded(8, .semibold)).tracking(1).foregroundStyle(SP.faint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}
