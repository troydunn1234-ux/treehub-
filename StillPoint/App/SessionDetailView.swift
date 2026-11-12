import SwiftUI
import Charts

/// One session, in full: heart-rate curve from the Watch, the numbers, a calm estimate, your notes, and a share card.
struct SessionDetailView: View {
    let recordId: UUID
    @EnvironmentObject var log: SessionLog
    @State private var editing = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var showInfo = false
    @State private var shareImage: Image? = nil
    private let lib = PracticeLibrary.shared

    private var record: SessionRecord? { log.record(recordId) }

    var body: some View {
        Group {
            if let r = record {
                content(r)
            } else {
                Text("This session is no longer here.").font(SP.serif(18, .light)).foregroundStyle(SP.dim)
            }
        }
        .background(DuskBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if record != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = true } label: { Label("Edit time & length", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete session", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Session options")
                }
            }
            if let r = record, let img = shareImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: img, preview: SharePreview(r.title, image: img)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            notes = record?.notes ?? ""
            if let r = record { shareImage = SessionShareCard(record: r, tint: tint(r)).rendered() }
        }
        .sheet(isPresented: $editing) {
            if let r = record { SessionEditSheet(record: r).environmentObject(log) }
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = record { log.remove(r.id) }
                dismiss()
            }
        } message: { Text("It's removed from your journey and from Mindful Minutes in Apple Health.") }
        .sheet(isPresented: $showInfo) {
            if let r = record, let p = lib.practice(r.practiceId) {
                PracticeInfoView(practice: p)
            }
        }
    }

    private func practice(_ r: SessionRecord) -> Practice? { lib.practice(r.practiceId) }
    private func tradition(_ r: SessionRecord) -> Tradition? { practice(r).flatMap { lib.tradition($0.traditionId) } }
    private func tint(_ r: SessionRecord) -> Color { tradition(r)?.tint ?? SP.teal }

    private func content(_ r: SessionRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero(r)
                VStack(alignment: .leading, spacing: 22) {
                    if let samples = r.hrSamples, samples.count >= 2 {
                        HRChartCard(samples: samples, record: r, tint: tint(r))
                    } else if r.hasHeartRate {
                        simpleHR(r)
                    } else {
                        noHR(r)
                    }
                    tiles(r)
                    if let c = r.calmScore { CalmGauge(score: c, tint: tint(r)) }
                    notesCard(r)
                    if let w = r.warmUpId, let wp = lib.practice(w) {
                        Label("Warmed up with \(wp.title)", systemImage: "figure.cooldown")
                            .font(SP.rounded(13)).foregroundStyle(SP.faint)
                    }
                    Text("Heart rate and HRV come from your Apple Watch via Apple Health. Nothing leaves your devices.")
                        .font(SP.rounded(12)).foregroundStyle(SP.faint)
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: Hero

    private func hero(_ r: SessionRecord) -> some View {
        ZStack(alignment: .bottomLeading) {
            PaintedScene(kind: tradition(r)?.scene ?? .water, tint: tint(r))
            LinearGradient(colors: [.clear, SP.nightBottom.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let t = tradition(r) { SPChip(text: t.name, color: t.tint) }
                    SPChip(text: r.device == "Watch" ? "Apple Watch" : "iPhone", color: SP.ink.opacity(0.7))
                    if practice(r) != nil {
                        Button { showInfo = true } label: {
                            Image(systemName: "info.circle").font(.system(size: 18, weight: .light)).foregroundStyle(SP.ink)
                        }
                        .accessibilityLabel("About this practice")
                    }
                }
                Text(r.title).font(SP.serif(30, .light)).foregroundStyle(SP.ink).lineLimit(2)
                HStack(spacing: 10) {
                    Text(r.start.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    Text("·")
                    Text("\(Int(max(1, r.minutes.rounded()))) min")
                }
                .font(SP.rounded(14)).foregroundStyle(SP.dim)
            }
            .padding(22)
        }
        .frame(height: 250)
    }

    // MARK: Heart rate states

    private func simpleHR(_ r: SessionRecord) -> some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEART RATE").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                    Text("\(Int(r.hrStart ?? 0)) → \(Int(r.hrMin ?? r.hrEnd ?? 0)) bpm").font(SP.numbers(28)).foregroundStyle(SP.ink)
                }
                Spacer()
                Image(systemName: "heart.fill").font(.system(size: 26)).foregroundStyle(SP.rose)
            }
        }
    }

    private func noHR(_ r: SessionRecord) -> some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: "applewatch").font(.system(size: 26, weight: .light)).foregroundStyle(SP.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No heart rate for this session").font(SP.serif(17)).foregroundStyle(SP.ink)
                    Text(r.device == "Watch"
                         ? "Turn on heart rate in the watch session settings (Fine-tune → Heart rate)."
                         : "Heart rate is recorded when you practice on your Apple Watch with heart rate on.")
                        .font(SP.rounded(13)).foregroundStyle(SP.dim)
                }
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ r: SessionRecord) -> some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            if let a = r.hrAvg { tile("\(Int(a.rounded()))", "avg bpm", SP.rose) }
            if let d = r.hrDrop { tile((d >= 0 ? "−" : "+") + "\(Int(abs(d).rounded()))", "bpm drop", SP.teal) }
            if let h = r.hrv { tile("\(Int(h.rounded()))", "HRV ms", SP.violet) }
            if r.cycles > 0 { tile("\(r.cycles)", r.isMovement ? "steps" : "breaths", SP.amber) }
            if let b = r.breathsPerMinute, !r.isMovement { tile(String(format: "%.1f", b), "breaths / min", SP.gold) }
            if let rr = r.respiratoryRate { tile(String(format: "%.0f", rr), "resp. rate", SP.teal) }
        }
    }

    private func tile(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(SP.numbers(24)).foregroundStyle(SP.ink)
            Text(l).font(SP.rounded(11)).foregroundStyle(SP.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(c.opacity(0.25), lineWidth: 1))
    }

    // MARK: Notes

    private func notesCard(_ r: SessionRecord) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                TextField("How did it feel?", text: $notes, axis: .vertical)
                    .font(SP.serif(16, .light)).foregroundStyle(SP.ink)
                    .lineLimit(2...6)
                    .onChange(of: notes) { _, new in
                        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        log.update(r.id) { $0.notes = trimmed.isEmpty ? nil : trimmed }
                    }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }
}

// MARK: - Heart-rate chart

struct HRChartCard: View {
    let samples: [HRSample]
    let record: SessionRecord
    let tint: Color

    private var lo: Double { (samples.map(\.bpm).min() ?? 50) - 4 }
    private var hi: Double { (samples.map(\.bpm).max() ?? 90) + 4 }
    private var minSample: HRSample? { samples.min { $0.bpm < $1.bpm } }
    /// A soft "resting" band: from the lowest reading up to a few bpm above it.
    private var restingTop: Double { (minSample?.bpm ?? lo) + 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HEART RATE").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Spacer()
                Text("\(Int(record.hrStart ?? samples.first?.bpm ?? 0)) → \(Int(record.hrMin ?? minSample?.bpm ?? 0)) bpm")
                    .font(SP.rounded(12)).foregroundStyle(SP.dim)
            }
            Chart {
                RectangleMark(xStart: .value("s", 0.0), xEnd: .value("e", samples.last?.t ?? 1),
                              yStart: .value("lo", lo), yEnd: .value("rest", restingTop))
                    .foregroundStyle(tint.opacity(0.10))
                ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                    AreaMark(x: .value("Time", s.t), y: .value("BPM", s.bpm))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", s.t), y: .value("BPM", s.bpm))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if let f = samples.first {
                    PointMark(x: .value("Time", f.t), y: .value("BPM", f.bpm)).foregroundStyle(SP.ink).symbolSize(40)
                        .annotation(position: .top, alignment: .leading) { Text("start").font(SP.rounded(10)).foregroundStyle(SP.faint) }
                }
                if let m = minSample {
                    PointMark(x: .value("Time", m.t), y: .value("BPM", m.bpm)).foregroundStyle(SP.amber).symbolSize(50)
                        .annotation(position: .bottom) { Text("low \(Int(m.bpm))").font(SP.rounded(10)).foregroundStyle(SP.amber) }
                }
                if let l = samples.last, samples.count > 1 {
                    PointMark(x: .value("Time", l.t), y: .value("BPM", l.bpm)).foregroundStyle(SP.ink).symbolSize(40)
                        .annotation(position: .top, alignment: .trailing) { Text("end").font(SP.rounded(10)).foregroundStyle(SP.faint) }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisValueLabel {
                        if let secs = v.as(Double.self) { Text(spFormatClock(secs)).foregroundStyle(SP.faint) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(SP.faint)
                }
            }
            .frame(height: 190)
            .accessibilityLabel("Heart rate over the session, from \(Int(record.hrStart ?? 0)) to a low of \(Int(record.hrMin ?? 0)) beats per minute")
            Text("Shaded band: the calmest few beats of the session.").font(SP.rounded(11)).foregroundStyle(SP.faint)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }
}

// MARK: - Calm gauge

struct CalmGauge: View {
    let score: Int
    let tint: Color
    @State private var shown = false

    private var word: String {
        switch score {
        case 80...: return "Deeply settled"
        case 55..<80: return "Settled"
        case 30..<55: return "Softening"
        default: return "Just beginning"
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle().trim(from: 0, to: shown ? CGFloat(score) / 100 : 0)
                    .stroke(AngularGradient(colors: [tint, SP.amber], center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)").font(SP.numbers(22)).foregroundStyle(SP.ink)
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text("CALM").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Text(word).font(SP.serif(20, .light)).foregroundStyle(SP.ink)
                Text("A simple estimate from how far your heart rate settled below where it began. Not a medical measure.")
                    .font(SP.rounded(12)).foregroundStyle(SP.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { shown = true } }
    }
}

// MARK: - Share card

/// A square card for sharing a session (rendered with ImageRenderer).
struct SessionShareCard: View {
    let record: SessionRecord
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [SP.nightTop, tint.opacity(0.6), SP.nightBottom], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text("STILL POINT").font(SP.rounded(12, .semibold)).tracking(2).foregroundStyle(SP.amber)
                Text(record.title).font(SP.serif(34, .light)).foregroundStyle(SP.ink).lineLimit(2)
                Text(record.start.formatted(.dateTime.weekday(.wide).month().day())).font(SP.rounded(15)).foregroundStyle(SP.dim)
                if let s = record.hrSamples, s.count >= 2 {
                    HRMiniChart(samples: s, tint: SP.ink).frame(height: 90).padding(.vertical, 6)
                }
                HStack(spacing: 22) {
                    big("\(Int(max(1, record.minutes.rounded())))", "min")
                    if let d = record.hrDrop, d > 0 { big("−\(Int(d.rounded()))", "bpm") }
                    if let h = record.hrv { big("\(Int(h.rounded()))", "HRV") }
                    if let c = record.calmScore { big("\(c)", "calm") }
                }
            }
            .padding(34)
        }
        .frame(width: 600, height: 600)
    }

    private func big(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(SP.numbers(36)).foregroundStyle(SP.ink)
            Text(l).font(SP.rounded(13)).foregroundStyle(SP.faint)
        }
    }

    @MainActor func rendered() -> Image {
        let r = ImageRenderer(content: self)
        r.scale = 2
        if let ui = r.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "heart")
    }
}

/// Fix a session's start time or length (say you stopped the timer late).
struct SessionEditSheet: View {
    let record: SessionRecord
    @EnvironmentObject var log: SessionLog
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var minutes = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Started", selection: $start, in: ...Date())
                    Stepper(value: $minutes, in: 1...240) {
                        HStack { Text("Length"); Spacer(); Text("\(minutes) min").foregroundStyle(.secondary) }
                    }
                } footer: {
                    Text("Changes your journey and streak. Apple Health keeps the original Mindful Minutes.")
                }
            }
            .navigationTitle(record.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let secs = Double(minutes * 60)
                        let changedLength = abs(secs - record.seconds) >= 30
                        log.update(record.id) { r in
                            r.start = start
                            if changedLength { r.seconds = secs }
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                start = record.start
                minutes = max(1, Int((record.seconds / 60).rounded()))
            }
        }
        .presentationDetents([.medium])
    }
}
