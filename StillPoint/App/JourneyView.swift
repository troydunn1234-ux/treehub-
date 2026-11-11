import SwiftUI
import Charts

struct JourneyView: View {
    @EnvironmentObject var log: SessionLog
    @State private var healthWeek: Double? = nil
    @State private var external: [ExternalMindfulSession] = []
    @State private var selectedDay: DayPick? = nil

    private var weekStart: Date { Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Journey").font(SP.serif(34, .light)).foregroundStyle(SP.ink).padding(.top, 8)

                    HStack(spacing: 12) {
                        tile(String(format: "%.0f", max(healthWeek ?? 0, log.weekMinutes)), "mindful minutes\nthis week")
                        tile("\(log.streak)", log.streak == 1 ? "day\nin a row" : "days\nin a row")
                        tile("\(log.records.count)", "sessions\nin all")
                    }

                    WeekCard(selectedDay: $selectedDay)

                    if !log.records.isEmpty || !external.isEmpty {
                        Text("SESSIONS").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                        VStack(spacing: 10) {
                            ForEach(mergedRows.prefix(40)) { item in
                                switch item {
                                case .mine(let r):
                                    NavigationLink(value: r.id) { row(r) }.buttonStyle(.plain)
                                case .other(let e):
                                    externalRow(e)
                                }
                            }
                        }
                    } else {
                        Text("Your sessions will gather here, like stones on a path.")
                            .font(SP.serif(17, .light)).foregroundStyle(SP.dim)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .background(DuskBackground())
            .navigationDestination(for: UUID.self) { id in SessionDetailView(recordId: id) }
            .sheet(item: $selectedDay) { pick in
                DaySessionsSheet(day: pick.day)
                    .environmentObject(log)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .onAppear {
                guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
                MindfulHealth.shared.mindfulMinutes(since: weekStart) { healthWeek = $0 }
                MindfulHealth.shared.externalMindfulSessions(since: Date().addingTimeInterval(-30 * 86400)) { external = $0 }
            }
        }
    }

    private enum RowItem: Identifiable {
        case mine(SessionRecord), other(ExternalMindfulSession)
        var id: UUID { switch self { case .mine(let r): return r.id; case .other(let e): return e.id } }
        var start: Date { switch self { case .mine(let r): return r.start; case .other(let e): return e.start } }
    }

    /// Our sessions plus other apps' mindful sessions, newest first. Skips Health entries that overlap one of ours.
    private var mergedRows: [RowItem] {
        var items: [RowItem] = log.records.map { .mine($0) }
        for e in external where !log.records.contains(where: { abs($0.start.timeIntervalSince(e.start)) < 120 }) {
            items.append(.other(e))
        }
        return items.sorted { $0.start > $1.start }
    }

    private func externalRow(_ e: ExternalMindfulSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.circle").font(.system(size: 15, weight: .light)).foregroundStyle(SP.faint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.source).font(SP.serif(16)).foregroundStyle(SP.dim).lineLimit(1)
                Text(e.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · from Apple Watch Mindfulness")
                    .font(SP.rounded(12)).foregroundStyle(SP.faint)
            }
            Spacer()
            Text(String(format: "%.0f min", max(1, e.minutes.rounded()))).font(SP.rounded(14)).foregroundStyle(SP.dim)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.card.opacity(0.5)))
        .opacity(0.75)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(SP.numbers(32)).foregroundStyle(SP.ink)
            Text(label).font(SP.rounded(12)).foregroundStyle(SP.faint).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SP.stroke, lineWidth: 1))
    }

    private func row(_ r: SessionRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.device == "Watch" ? "applewatch" : "iphone")
                .font(.system(size: 15, weight: .light)).foregroundStyle(SP.teal).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(SP.serif(16)).foregroundStyle(SP.ink).lineLimit(1)
                Text(r.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(SP.rounded(12)).foregroundStyle(SP.faint)
            }
            Spacer()
            if let s = r.hrSamples, s.count >= 2 {
                HRMiniChart(samples: s, tint: SP.teal.opacity(0.8)).frame(width: 54, height: 22)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f min", max(1, r.minutes.rounded()))).font(SP.rounded(14)).foregroundStyle(SP.ink)
                if let drop = r.hrDrop, drop > 0 {
                    Text("♥ −\(Int(drop)) bpm").font(SP.rounded(11)).foregroundStyle(SP.rose)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(SP.faint)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.card))
    }
}

struct SettingsView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var link: PhoneLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Feel") {
                    Picker("Haptics", selection: $prefs.settings.haptics) {
                        ForEach(HapticStyle.allCases) { h in Text(h.label).tag(h) }
                    }
                    Toggle("Vibration only on Watch (no sound)", isOn: $prefs.settings.silentHaptics)
                    Toggle("Count the out-breath", isOn: $prefs.settings.exhaleTicks)
                    Toggle("Start & end bells", isOn: $prefs.settings.bells)
                    Picker("Interval bell", selection: $prefs.settings.intervalMinutes) {
                        Text("Off").tag(0)
                        ForEach([1, 2, 5, 10], id: \.self) { m in Text("Every \(m) min").tag(m) }
                    }
                }
                Section("Sessions") {
                    Picker("Usual length", selection: $prefs.settings.defaultMinutes) {
                        ForEach([2, 3, 5, 10, 15, 20, 30], id: \.self) { m in Text("\(m) min").tag(m) }
                    }
                    Picker("Length by", selection: $prefs.settings.mode) {
                        ForEach(SessionMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    if prefs.settings.mode == .cycles {
                        Stepper("\(prefs.settings.cycles) breaths", value: $prefs.settings.cycles, in: 3...60)
                    }
                    Toggle("Dim after a few seconds", isOn: $prefs.settings.dimScreen)
                    Toggle("Show numbers", isOn: $prefs.settings.showNumbers)
                }
                Section {
                    Toggle("Heart rate on Apple Watch", isOn: $prefs.settings.trackHeartRate)
                    Toggle("Also save as a workout", isOn: $prefs.settings.saveAsWorkout)
                        .disabled(!prefs.settings.trackHeartRate)
                    Toggle("Warm-ups count as mindful minutes", isOn: $prefs.settings.logMovementAsMindful)
                    Button("Connect Apple Health") { MindfulHealth.shared.requestAuthorization() }
                } header: { Text("Apple Health") } footer: {
                    Text("Sessions are saved on your phone and as Mindful Minutes in Apple Health. Heart rate is read from Apple Health; nothing leaves your devices.")
                }
                Section("Apple Watch") {
                    LabeledContent("Watch", value: link.watchPaired ? "Paired" : "Not paired")
                    LabeledContent("Still Point on Watch", value: link.watchAppInstalled ? "Installed" : "Not installed")
                    Text("These settings are shared with your Watch automatically.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DuskBackground())
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationBackground(.ultraThinMaterial)
    }
}

struct DayPick: Identifiable { var day: Date; var id: TimeInterval { day.timeIntervalSince1970 } }

/// This week vs last, minutes per day (tap a bar for that day), best practices by heart-rate drop, streak.
struct WeekCard: View {
    @EnvironmentObject var log: SessionLog
    @Binding var selectedDay: DayPick?

    private var delta: Double { log.weekMinutes - log.previousWeekMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("THIS WEEK").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Spacer()
                if log.previousWeekMinutes > 0 || log.weekMinutes > 0 {
                    Text(deltaText).font(SP.rounded(12)).foregroundStyle(delta >= 0 ? SP.teal : SP.rose)
                }
            }
            Chart(log.lastWeek()) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.minutes))
                    .foregroundStyle(LinearGradient(colors: [SP.amber, SP.plum], startPoint: .top, endPoint: .bottom))
                    .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(SP.faint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(SP.faint)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            let origin = geo[proxy.plotAreaFrame].origin
                            let x = loc.x - origin.x
                            if let day: Date = proxy.value(atX: x) {
                                let d = Calendar.current.startOfDay(for: day)
                                if !log.sessions(on: d).isEmpty { selectedDay = DayPick(day: d) }
                            }
                        }
                }
            }
            .frame(height: 150)
            .accessibilityLabel("Minutes of practice for each of the last seven days")

            let best = log.bestPractices()
            if !best.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT SETTLES YOU MOST").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                    ForEach(best) { b in
                        HStack {
                            Text(b.title).font(SP.serif(15)).foregroundStyle(SP.ink).lineLimit(1)
                            Spacer()
                            Text("♥ −\(Int(b.avgDrop.rounded())) bpm").font(SP.rounded(12)).foregroundStyle(SP.rose)
                            Text("· \(b.count)×").font(SP.rounded(12)).foregroundStyle(SP.faint)
                        }
                    }
                }
            }
            if log.streak > 1 {
                Label("\(log.streak) days in a row", systemImage: "flame").font(SP.rounded(13)).foregroundStyle(SP.amber)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }

    private var deltaText: String {
        let m = Int(abs(delta).rounded())
        if m == 0 { return "same as last week" }
        return delta > 0 ? "+\(m) min vs last week" : "−\(m) min vs last week"
    }
}

/// Sessions from one day, each tappable.
struct DaySessionsSheet: View {
    let day: Date
    @EnvironmentObject var log: SessionLog

    var body: some View {
        NavigationStack {
            List(log.sessions(on: day)) { r in
                NavigationLink { SessionDetailView(recordId: r.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(SP.serif(16)).foregroundStyle(SP.ink)
                            Text(r.start.formatted(.dateTime.hour().minute())).font(SP.rounded(12)).foregroundStyle(SP.faint)
                        }
                        Spacer()
                        Text("\(Int(max(1, r.minutes.rounded()))) min").font(SP.rounded(14)).foregroundStyle(SP.dim)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(DuskBackground())
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
