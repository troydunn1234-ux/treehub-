import SwiftUI

/// "Does my stack show up in my numbers?" For each supplement, compares the next morning's
/// WHOOP recovery and Watch readiness after days you took it vs days you didn't (last 60 days).
struct StackInsightsCard: View {
    let supps: [Supplement]
    let doses: [SuppDose]
    @Environment(LabStore.self) private var store

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        let whoop: (on: Double, off: Double)?
        let watch: (on: Double, off: Double)?
        var biggest: Double { max(abs((whoop?.on ?? 0) - (whoop?.off ?? 0)), abs((watch?.on ?? 0) - (watch?.off ?? 0))) }
    }

    private var rows: [Row] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Next-morning score keyed by the day the supplement was taken.
        func nextDay(_ days: [DayStat]) -> [String: Double] {
            var out: [String: Double] = [:]
            for d in days {
                guard let r = d.recovery, let prev = cal.date(byAdding: .day, value: -1, to: d.day) else { continue }
                out[Day.key(prev)] = r
            }
            return out
        }
        let whoopNext = nextDay(store.whoopDays)
        let watchNext = nextDay(store.watchDays)
        let window = (1...60).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.map { Day.key($0) }
        func split(_ next: [String: Double], taken: Set<String>) -> (on: Double, off: Double)? {
            var on: [Double] = [], off: [Double] = []
            for k in window { if let v = next[k] { if taken.contains(k) { on.append(v) } else { off.append(v) } } }
            guard on.count >= 4, off.count >= 4 else { return nil }
            return (on.reduce(0, +) / Double(on.count), off.reduce(0, +) / Double(off.count))
        }
        return supps.compactMap { s in
            let taken = Set(doses.filter { $0.suppID == s.id }.map(\.day))
            let w = split(whoopNext, taken: taken), a = split(watchNext, taken: taken)
            guard w != nil || a != nil else { return nil }
            return Row(id: s.id, name: s.name, emoji: s.emoji, whoop: w, watch: a)
        }
        .sorted { $0.biggest > $1.biggest }
        .prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STACK VS RECOVERY").font(Ember.font(11, .heavy)).tracking(2.5).foregroundStyle(Lab.duel)
                Spacer()
                Text("next morning · 60 days").font(Ember.font(11, .medium)).foregroundStyle(Lab.faint)
            }
            if rows.isEmpty {
                Text("Keep checking off your stack. After a couple of weeks with some days on and some off, this shows how each supplement lines up with your WHOOP recovery and Watch readiness the next morning.")
                    .font(Ember.font(13, .regular)).foregroundStyle(Lab.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(r.emoji) \(r.name)").font(Ember.font(15, .bold)).foregroundStyle(Lab.text)
                        if let w = r.whoop { line("WHOOP recovery", w, tint: Lab.whoop, suffix: "%") }
                        if let a = r.watch { line("Watch readiness", a, tint: Lab.watch, suffix: "") }
                    }
                    .padding(.vertical, 4)
                }
                Text("Patterns, not proof: sleep, training and stress move these numbers too.")
                    .font(Ember.font(11, .regular)).foregroundStyle(Lab.faint)
            }
        }
        .padding(16)
        .background(Ember.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Ember.line))
    }

    private func line(_ label: String, _ v: (on: Double, off: Double), tint: Color, suffix: String) -> some View {
        let diff = v.on - v.off
        return HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(Ember.font(12, .medium)).foregroundStyle(Lab.dim)
            Spacer()
            Text("\(Int(v.on.rounded()))\(suffix) taken").font(Ember.font(12, .semibold)).foregroundStyle(Lab.text)
            Text("vs \(Int(v.off.rounded()))\(suffix)").font(Ember.font(12, .regular)).foregroundStyle(Lab.faint)
            Text(String(format: "%@%.0f", diff >= 0 ? "▲" : "▼", abs(diff)))
                .font(Ember.font(12, .heavy))
                .foregroundStyle(abs(diff) < 2 ? Lab.dim : (diff > 0 ? Lab.good : Lab.bad))
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
