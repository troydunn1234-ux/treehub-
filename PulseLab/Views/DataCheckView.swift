import SwiftUI

/// Settings → Data check: exactly what is flowing in from Apple Health and the WHOOP API,
/// metric by metric, so an empty chart can be traced to its cause.
@MainActor
struct DataCheckView: View {
    @Environment(LabStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var whoop: WhoopClient { WhoopClient.shared }

    var body: some View {
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Lab.S.m) {
                    HStack {
                        ScreenTitle(kicker: "Diagnostics", title: "Data check")
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.06)))
                        }
                        .accessibilityLabel("Close")
                    }
                    summary
                    healthRows
                    whoopPanel
                    syncLog
                    Text("Watch = samples written by your Apple Watch (or Apple's own iPhone writers). WHOOP = samples WHOOP saved into Health. Other = third-party apps, not counted.")
                        .font(Lab.body(12)).foregroundStyle(Lab.faint)
                }
                .padding(.horizontal, Lab.S.m)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task { await store.runDataCheck() }
    }

    private var summary: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                row("Apple Health", store.healthAsked ? "asked for access" : "not asked yet", ok: store.healthAsked)
                row("Watch days loaded", "\(store.watchDays.count)", ok: !store.watchDays.isEmpty)
                row("WHOOP days loaded", "\(store.whoopDays.count)", ok: !store.whoopDays.isEmpty)
                row("Sleep nights", "\(store.sleeps.count)", ok: !store.sleeps.isEmpty)
                row("Workouts", "\(store.workouts.count)", ok: !store.workouts.isEmpty)
                row("Last pull", store.lastPull.map { $0.formatted(.relative(presentation: .named)) } ?? "never", ok: store.lastPull != nil)
                if LabStore.isDemo {
                    Text("Demo mode: sample data, Health isn't read.").font(Lab.body(12)).foregroundStyle(Lab.warn)
                }
            }
        }
    }

    private func row(_ k: String, _ v: String, ok: Bool) -> some View {
        HStack {
            Circle().fill(ok ? Lab.good : Lab.warn).frame(width: 6, height: 6)
            Text(k).font(Lab.body(14)).foregroundStyle(Lab.text)
            Spacer()
            Text(v).font(Lab.mono(12)).foregroundStyle(Lab.dim)
        }
    }

    private var healthRows: some View {
        LabPanel(tint: Lab.watch) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                HStack {
                    SectionTag("Apple Health · last 7 days")
                    Spacer()
                    if store.probing { ProgressView().tint(Lab.watch) }
                    else {
                        Button { Task { await store.runDataCheck() } } label: {
                            Text("RE-CHECK").font(Lab.label(9)).foregroundStyle(Lab.watch)
                        }
                    }
                }
                if store.probe.isEmpty && !store.probing {
                    EmptyNote(text: LabStore.isDemo ? "Not available in demo mode." : "Nothing came back. Check Settings → Health → Data Access → Pulse Lab.")
                }
                ForEach(store.probe) { r in probeRow(r) }
            }
        }
    }

    private func probeRow(_ r: HealthPull.ProbeRow) -> some View {
        HStack(alignment: .top, spacing: Lab.S.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(Lab.body(14)).foregroundStyle(r.count7d > 0 ? Lab.text : Lab.dim)
                Text(lastLine(r)).font(Lab.mono(10)).foregroundStyle(Lab.faint).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(valueText(r.lastValue)).font(Lab.mono(13, .heavy)).foregroundStyle(tint(r.lastOrigin))
                    Text(r.unit).font(Lab.label(8)).foregroundStyle(Lab.faint)
                }
                Text(r.count7d == 0 ? "0 in 7d" : "\(r.count7d) in 7d").font(Lab.label(8)).foregroundStyle(r.count7d > 0 ? Lab.dim : Lab.warn)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.fractionLength(v >= 100 ? 0 : 1)))
    }

    private func lastLine(_ r: HealthPull.ProbeRow) -> String {
        guard let d = r.lastDate else { return "no samples ever" }
        let when = d.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "last \(when) · \(r.lastSource)"
    }

    private func tint(_ o: HealthPull.Origin) -> Color {
        switch o { case .watch: Lab.watch; case .whoop: Lab.whoop; case .other: Lab.dim }
    }

    private var whoopPanel: some View {
        LabPanel(tint: Lab.whoop) {
            VStack(alignment: .leading, spacing: Lab.S.s) {
                SectionTag("WHOOP API", color: Lab.whoop)
                row("Connected", whoop.isConnected ? "yes" : "no", ok: whoop.isConnected)
                row("Last sync", whoop.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "never", ok: whoop.lastSync != nil)
                row("Cycles", count(whoop.cycles.count, whoop.cycles.first?.start), ok: !whoop.cycles.isEmpty)
                row("Recoveries (scored)", "\(whoop.recoveries.filter { $0.score != nil }.count) of \(whoop.recoveries.count)", ok: whoop.recoveries.contains { $0.score != nil })
                row("Sleeps (scored)", "\(whoop.sleeps.filter { $0.score != nil }.count) of \(whoop.sleeps.count)", ok: whoop.sleeps.contains { $0.score != nil })
                row("Workouts", count(whoop.workouts.count, whoop.workouts.first?.start), ok: !whoop.workouts.isEmpty)
                if let e = whoop.lastError { Text(e).font(Lab.body(12)).foregroundStyle(Lab.bad) }
                let pending = whoop.recoveries.filter { $0.score == nil }.count
                if pending > 0 {
                    Text("\(pending) recovery record\(pending == 1 ? "" : "s") not scored yet (WHOOP scores after you wake and sync).")
                        .font(Lab.body(12)).foregroundStyle(Lab.faint)
                }
            }
        }
    }

    private func count(_ n: Int, _ newest: Date?) -> String {
        guard let newest else { return "\(n)" }
        return "\(n) · newest " + newest.formatted(.dateTime.month(.abbreviated).day())
    }

    private var syncLog: some View {
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: Lab.S.xs) {
                SectionTag("Sync log · last \(whoop.log.count) requests")
                if whoop.log.isEmpty { EmptyNote(text: "No WHOOP requests this session.") }
                ForEach(whoop.log) { e in
                    HStack(spacing: Lab.S.xs) {
                        Circle().fill(e.ok ? Lab.good : Lab.bad).frame(width: 6, height: 6)
                        Text(e.time.formatted(.dateTime.hour().minute().second())).font(Lab.mono(10)).foregroundStyle(Lab.faint)
                        Text(e.path.replacingOccurrences(of: "/v2/", with: "")).font(Lab.mono(11, .bold)).foregroundStyle(Lab.text).lineLimit(1)
                        Spacer()
                        if let c = e.count { Text("\(c) rec").font(Lab.mono(10)).foregroundStyle(Lab.dim) }
                        Text(e.status == 0 ? "NET" : "\(e.status)").font(Lab.mono(10, .heavy)).foregroundStyle(e.ok ? Lab.good : Lab.bad)
                    }
                    if !e.note.isEmpty { Text(e.note).font(Lab.mono(9)).foregroundStyle(Lab.faint).lineLimit(2) }
                }
            }
        }
    }
}

/// Small grey chip explaining why a number is "—".
struct ReasonChip: View {
    let source: Source
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Lab.color(source)).frame(width: 5, height: 5)
            Text(text.uppercased()).font(Lab.label(8)).tracking(1).foregroundStyle(Lab.dim)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .accessibilityLabel("\(source.name): \(text)")
    }
}
