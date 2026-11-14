import SwiftUI

/// Pulse Lab on the Watch: today's recovery, last night's sleep, HRV and strain, from the iPhone.
@main
struct PulseLabWatchApp: App {
    @StateObject private var store = WatchStore.shared

    init() { WatchStore.shared.activate() }

    var body: some Scene {
        WindowGroup {
            WatchHome().environmentObject(store)
        }
    }
}

enum WPalette {
    static let watch = Color(red: 0.20, green: 0.92, blue: 1.00)
    static let whoop = Color(red: 1.00, green: 0.66, blue: 0.16)
    static let good = Color(red: 0.25, green: 0.95, blue: 0.55)
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.30, blue: 0.40)
    static func band(_ v: Double) -> Color { v >= 67 ? good : v >= 34 ? warn : bad }
}

func watchHM(_ minutes: Double?) -> String {
    guard let m = minutes, m > 0 else { return "—" }
    let h = Int(m) / 60, mm = Int(m) % 60
    return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
}

struct WatchHome: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let s = store.snap
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    gauge(s)
                    if s.isEmpty {
                        Text("Open Pulse Lab on your iPhone to send today's numbers.")
                            .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    } else {
                        row("moon.zzz.fill", String(localized: "Sleep"), watchHM(s.sleepMin),
                            s.sleepMin.flatMap { m in s.sleepAvgMin.map { a in delta(m - a, minutes: true) } })
                        row("waveform.path.ecg", String(localized: "HRV"), s.hrv.map { "\(Int($0.rounded())) ms" } ?? "—",
                            s.hrv.flatMap { h in s.hrvBase.map { b in b > 0 ? pct((h - b) / b * 100) : "" } })
                        row("heart.fill", String(localized: "Resting HR"), s.rhr.map { "\(Int($0.rounded())) bpm" } ?? "—",
                            s.rhr.flatMap { r in s.rhrBase.map { b in delta(r - b, minutes: false) } })
                        row("bolt.fill", s.strainIsToday ? String(localized: "Strain") : String(localized: "Strain yesterday"),
                            s.strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", nil)
                        if let t = s.takeaway {
                            Text(t).font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                    Button {
                        store.refresh()
                    } label: {
                        if store.refreshing {
                            ProgressView()
                        } else {
                            Label(String(localized: "Sync"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .padding(.top, 6)
                    if store.phoneUnreachable {
                        Text("iPhone not reachable. Numbers update after its next sync.")
                            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let u = s.updatedAt {
                        Text(String(localized: "Updated \(u.formatted(.relative(presentation: .named)))"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Pulse Lab")
        }
    }

    private func gauge(_ s: WatchStore.Snapshot) -> some View {
        let v = s.recovery ?? 0
        return VStack(spacing: 2) {
            Gauge(value: v, in: 0...100) {
                Text(s.isWhoop ? "REC" : "RDY")
            } currentValueLabel: {
                Text(s.recovery.map { "\(Int($0.rounded()))" } ?? "—")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [WPalette.bad, WPalette.warn, WPalette.good]))
            .scaleEffect(1.4)
            .frame(height: 76)
            Text(s.isWhoop ? String(localized: "WHOOP recovery") : String(localized: "Watch readiness"))
                .font(.caption2).foregroundStyle(s.isWhoop ? WPalette.whoop : WPalette.watch)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.recovery.map { String(localized: "\(s.isWhoop ? String(localized: "WHOOP recovery") : String(localized: "Watch readiness")) \(Int($0.rounded()))") }
                            ?? String(localized: "No recovery score yet"))
    }

    private func row(_ icon: String, _ title: String, _ value: String, _ sub: String?) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(WPalette.watch).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            Spacer()
            if let sub, !sub.isEmpty {
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func delta(_ d: Double, minutes: Bool) -> String {
        let sign = d >= 0 ? "+" : "−"
        if minutes && abs(d) < 1 { return "±0m" }
        return minutes ? sign + watchHM(abs(d)) : sign + abs(d).formatted(.number.precision(.fractionLength(1)))
    }
    private func pct(_ p: Double) -> String { (p >= 0 ? "+" : "−") + "\(Int(abs(p).rounded()))%" }
}
