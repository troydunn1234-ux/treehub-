import SwiftUI
import Charts

struct JourneyView: View {
    @EnvironmentObject var log: SessionLog
    @State private var healthWeek: Double? = nil

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

                    VStack(alignment: .leading, spacing: 12) {
                        Text("THIS WEEK").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
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
                        .frame(height: 170)
                        .accessibilityLabel("Minutes of practice for each of the last seven days")
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))

                    if !log.records.isEmpty {
                        Text("SESSIONS").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                        VStack(spacing: 10) {
                            ForEach(log.records.prefix(30)) { r in row(r) }
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
            .onAppear {
                guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
                MindfulHealth.shared.mindfulMinutes(since: weekStart) { healthWeek = $0 }
            }
        }
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
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f min", max(1, r.minutes.rounded()))).font(SP.rounded(14)).foregroundStyle(SP.ink)
                if let drop = r.hrDrop, drop > 0 {
                    Text("♥ −\(Int(drop)) bpm").font(SP.rounded(11)).foregroundStyle(SP.rose)
                }
            }
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
                    Text("Still Point saves Mindful Minutes and reads heart rate and HRV. Nothing leaves your devices.")
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
