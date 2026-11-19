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
    // Same fixed data colours as the iPhone app (Lab): Watch = cyan, WHOOP = amber; red is the accent and is
    // kept for controls. Row icons use the iPhone's All-data category colours (sleep violet, recovery green).
    static let watch = Color(red: 0.25, green: 0.80, blue: 1.00)
    static let whoop = Color(red: 1.00, green: 0.64, blue: 0.20)
    static let accent = Color(red: 1.00, green: 0.25, blue: 0.36)
    static let violet = Color(red: 0.58, green: 0.45, blue: 1.00)
    static let good = Color(red: 0.22, green: 0.84, blue: 0.46)
    static let warn = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let bad = Color(red: 1.00, green: 0.36, blue: 0.32)
    static func band(_ v: Double) -> Color { v >= 67 ? good : v >= 34 ? warn : bad }
}

func watchHM(_ minutes: Double?) -> String {
    guard let m = minutes, m > 0 else { return "—" }
    let h = Int(m) / 60, mm = Int(m) % 60
    return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
}

/// "7 hours, 12 minutes" for VoiceOver.
func watchHMSpoken(_ minutes: Double) -> String {
    Duration.seconds(Int(minutes.rounded()) * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
}

/// `-demo` launch flag (simulator QA and screenshots only): sample numbers so the screen is never empty.
enum WatchDemo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static let snap = WatchStore.Snapshot([
        "recovery": 72.0, "recoveryKind": "whoop", "sleepMin": 446.0, "sleepAvgMin": 421.0,
        "hrv": 61.0, "hrvBase": 56.0, "rhr": 52.0, "rhrBase": 53.4, "strain": 11.4, "strainIsToday": false,
        "takeaway": "Slept longer than your week and HRV is above your usual: a good day to train.",
        "agreeScore": 75.0, "agreeOn": 3, "agreeOf": 4, "agreeSplit": "HRV",
        "updatedAt": Date().timeIntervalSince1970,
    ])
}

struct WatchHome: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let s = WatchDemo.isOn ? WatchDemo.snap : store.snap
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    gauge(s)
                    if s.isEmpty {
                        VStack(spacing: 4) {
                            Image(systemName: "iphone.radiowaves.left.and.right").font(.title3).foregroundStyle(WPalette.watch)
                                .accessibilityHidden(true)
                            Text("No numbers yet").font(.headline)
                            Text("Open Pulse Lab on your iPhone to send today's numbers.")
                                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    } else {
                        if s.agreeOf > 0 { agreementRow(s) }
                        row("moon.zzz.fill", WPalette.violet, String(localized: "Sleep"),
                            s.sleepMin.map { watchHM($0) },
                            s.sleepMin.flatMap { m in s.sleepAvgMin.map { a in delta(m - a, minutes: true) } },
                            spoken: s.sleepMin.map { watchHMSpoken($0) })
                        row("waveform.path.ecg", WPalette.good, String(localized: "HRV"),
                            s.hrv.map { "\(Int($0.rounded())) ms" },
                            s.hrv.flatMap { h in s.hrvBase.flatMap { b in b > 0 ? pct((h - b) / b * 100) : nil } })
                        row("heart.fill", WPalette.good, String(localized: "Resting HR"),
                            s.rhr.map { "\(Int($0.rounded())) bpm" },
                            s.rhr.flatMap { r in s.rhrBase.map { b in bpmDelta(r - b) } })
                        row("bolt.fill", WPalette.whoop, s.strainIsToday ? String(localized: "Strain") : String(localized: "Strain yesterday"),
                            s.strain.map { $0.formatted(.number.precision(.fractionLength(1))) }, nil)
                        if let t = s.takeaway {
                            Text(t).font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
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
                    .tint(WPalette.accent)
                    .sensoryFeedback(.selection, trigger: store.refreshing)
                    .accessibilityHint(String(localized: "Asks your iPhone for fresh numbers"))
                    .padding(.top, 4)
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
            .containerBackground(WPalette.accent.gradient.opacity(0.25), for: .navigation)
        }
    }

    private func gauge(_ s: WatchStore.Snapshot) -> some View {
        let v = s.recovery ?? 0
        return VStack(spacing: 2) {
            Gauge(value: v, in: 0...100) {
                Image(systemName: s.isWhoop ? "bolt.heart.fill" : "applewatch")
            } currentValueLabel: {
                Text(s.recovery.map { "\(Int($0.rounded()))" } ?? "—").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [WPalette.bad, WPalette.warn, WPalette.good]))
            .scaleEffect(1.4)
            .frame(height: 76)
            Text(s.recovery == nil ? String(localized: "No score yet")
                 : s.isWhoop ? String(localized: "WHOOP recovery") : String(localized: "Watch readiness"))
                .font(.caption2).foregroundStyle(s.recovery == nil ? Color.secondary : (s.isWhoop ? WPalette.whoop : WPalette.watch))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.recovery.map { String(localized: "\(s.isWhoop ? String(localized: "WHOOP recovery") : String(localized: "Watch readiness")) \(Int($0.rounded()))") }
                            ?? String(localized: "No recovery score yet"))
    }

    /// Pulse Lab's signature: how closely Watch and WHOOP agree today (resting HR, HRV, sleep, strain).
    private func agreementRow(_ s: WatchStore.Snapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.fill").font(.footnote.weight(.semibold))
                .foregroundStyle(LinearGradient(colors: [WPalette.watch, WPalette.whoop], startPoint: .leading, endPoint: .trailing))
                .frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Watch vs WHOOP").font(.caption2).foregroundStyle(.secondary)
                Text(String(localized: "\(s.agreeOn) of \(s.agreeOf) agree"))
                    .font(.system(.headline, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                if !s.agreeSplit.isEmpty {
                    Text(String(localized: "Split: \(s.agreeSplit)")).font(.caption2).foregroundStyle(WPalette.warn).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let a = s.agreeScore {
                Text("\(Int(a))%").font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(WPalette.band(a))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Watch versus WHOOP: \(s.agreeOn) of \(s.agreeOf) agree\(s.agreeSplit.isEmpty ? "" : ", split on " + s.agreeSplit)"))
    }

    /// One number: tinted icon, title, value (or "Not in yet"), and its change vs your usual with that context.
    private func row(_ icon: String, _ tint: Color, _ title: String, _ value: String?, _ sub: String?, spoken: String? = nil) -> some View {
        HStack {
            Image(systemName: icon).font(.footnote.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                if let value {
                    Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text("Not in yet").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if value != nil, let sub, !sub.isEmpty {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(sub).font(.caption2.monospacedDigit().weight(.semibold))
                    Text("vs usual").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(title, value, sub, spoken: spoken))
    }

    private func rowLabel(_ title: String, _ value: String?, _ sub: String?, spoken: String?) -> String {
        guard let value else { return String(localized: "\(title): not in yet") }
        guard let sub, !sub.isEmpty else { return "\(title): \(spoken ?? value)" }
        return String(localized: "\(title): \(spoken ?? value), \(sub) versus your usual")
    }

    private func delta(_ d: Double, minutes: Bool) -> String {
        let sign = d >= 0 ? "+" : "−"
        if minutes && abs(d) < 1 { return "±0m" }
        return minutes ? sign + watchHM(abs(d)) : sign + abs(d).formatted(.number.precision(.fractionLength(1)))
    }
    private func bpmDelta(_ d: Double) -> String {
        let r = Int(d.rounded())
        return r == 0 ? "±0 bpm" : (r > 0 ? "+" : "−") + "\(abs(r)) bpm"
    }
    private func pct(_ p: Double) -> String { (p >= 0 ? "+" : "−") + "\(Int(abs(p).rounded()))%" }
}
