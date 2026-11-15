import SwiftUI
import HealthKit
import UserNotifications

/// iPhone wiring for the "Right now" card: Pulse Lab's summary, sending the pick to the Watch, the optional nudge.
enum StillPointRightNow {
    @MainActor
    static func setup() {
        let model = RightNow.shared
        model.pulseLab = {
            guard let p = WellnessBridge.pulseLab(), p.isToday else { return nil }
            var src: [String] = []
            if p.fromWhoopAPI { src.append("WHOOP API") }
            if p.fromWhoopManual { src.append("WHOOP (typed in)") }
            if p.fromWhoopHealth { src.append("WHOOP via Health") }
            if p.fromWatch { src.append("Watch") }
            return (p.whoopRecovery, p.whoopStrain, p.sleepPerformance, p.readiness, src)
        }
        var lastSent: Suggestion?
        model.onUpdate = { m in
            let s = m.suggestion
            if lastSent?.practiceId != s.practiceId || lastSent?.because != s.because
                || (lastSent.map { s.computedAt.timeIntervalSince($0.computedAt) > 15 * 60 } ?? true) {
                lastSent = s
                PhoneLink.shared.rightNowData = try? JSONEncoder().encode(s)
                PhoneLink.shared.pushSettings()
            }
            DailyMoments.shared.reschedule(m)
        }
        model.startObserving()
        DailyMoments.shared.enableBackgroundIfNeeded()
    }
}

// MARK: - Card

struct RightNowCard: View {
    @ObservedObject private var model = RightNow.shared
    @EnvironmentObject var router: Router
    @EnvironmentObject var link: PhoneLink
    @State private var showWhy = false
    @State private var taps = 0

    var body: some View {
        let s = model.current
        let p = PracticeLibrary.shared.practice(s.practiceId)
        let tint = PracticeLibrary.shared.category(s.goal).map { Color(spHex: $0.color) } ?? SP.teal
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("RIGHT NOW").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.ink.opacity(0.7))
                Spacer(minLength: 0)
                if let lvl = s.stressLevel.flatMap(StressEstimate.Level.init(rawValue:)) {
                    Label {
                        Text("Stress estimate: \(lvl.label)")
                    } icon: {
                        Circle().fill(lvl.tint).frame(width: 7, height: 7)
                    }
                    .font(SP.rounded(11, .medium)).foregroundStyle(lvl.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(lvl.tint.opacity(0.12)))
                }
            }
            Text(s.title).font(SP.serif(24, .light)).foregroundStyle(SP.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.because).font(SP.rounded(15)).foregroundStyle(SP.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if s.worksBest {
                Label("Works best for you", systemImage: "arrow.down.heart.fill")
                    .font(SP.rounded(12, .semibold)).foregroundStyle(SP.rose)
            }
            if !s.sources.isEmpty {
                HStack(spacing: 6) {
                    ForEach(s.sources.prefix(4), id: \.self) { SourceBadge(name: $0) }
                }
            }
            HStack(spacing: 10) {
                Button {
                    taps += 1
                    if let p { start(p, minutes: s.minutes) }
                } label: {
                    Label("Begin · \(s.minutes) min", systemImage: "circle.circle")
                        .font(SP.rounded(15, .medium))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(SP.goldGlow))
                }
                .buttonStyle(SoftPress())
                .sensoryFeedback(.impact(weight: .light), trigger: taps)
                .disabled(p == nil)
                Button { showWhy = true } label: {
                    Text("Why this?").font(SP.rounded(14, .medium)).foregroundStyle(SP.teal)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                if link.canUseWatch, let p {
                    Button {
                        link.startOnWatch(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: s.minutes)) { _ in }
                    } label: {
                        Image(systemName: "applewatch").font(.system(size: 16, weight: .light)).foregroundStyle(SP.ink)
                            .frame(width: 40, height: 40).background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel("Start on Watch")
                }
            }
            if model.needsHealthAccess {
                Button {
                    Task { await model.requestAccess() }
                } label: {
                    Label("Use my heart rate, HRV and sleep from Health for a better pick", systemImage: "heart.text.square")
                        .font(SP.rounded(13)).foregroundStyle(SP.amber)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            } else if s.timeOnly {
                Text("No recent heart data, so this is picked by time of day.")
                    .font(SP.rounded(12)).foregroundStyle(SP.faint)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.20), SP.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        .sheet(isPresented: $showWhy) { WhyThisSheet(suggestion: s, stress: model.stress) }
        .task { await model.refresh() }
        .accessibilityElement(children: .contain)
    }

    private func start(_ p: Practice, minutes: Int) {
        // First start from this card: the one-time ask for the two daily "Right now" reminders.
        DailyMoments.shared.askOnce()
        if PracticeLibrary.shared.isLocked(p) { router.show(p); return }
        router.run(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: minutes))
    }
}

struct SourceBadge: View {
    let name: String
    var body: some View {
        let tint: Color = name.hasPrefix("WHOOP") ? SP.rose : name == "Watch" ? SP.teal : name == "Pulse Lab" ? SP.gold : SP.dim
        Text(name.uppercased())
            .font(SP.rounded(10, .semibold)).tracking(0.8).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Why this?

struct WhyThisSheet: View {
    let suggestion: Suggestion
    let stress: StressEstimate?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(suggestion.line).font(SP.rounded(15))
                } header: { Text("Suggestion") }
                Section {
                    ForEach(suggestion.why) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(w.label).font(SP.rounded(14, .medium))
                                Spacer()
                                if let s = w.source { SourceBadge(name: s) }
                            }
                            Text(w.value).font(SP.rounded(13)).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Numbers used") }
                Section {
                    if let st = stress {
                        ForEach(st.parts, id: \.self) { Text($0).font(SP.rounded(13)) }
                        Text("Score \(st.score.formatted(.number.precision(.fractionLength(1)))) of 3 → \(st.level.label)")
                            .font(SP.rounded(13, .medium))
                    } else if let n = suggestion.stressNote {
                        Text(n).font(SP.rounded(13))
                    }
                } header: { Text("How the stress estimate works") } footer: {
                    Text("Each signal adds points: heart rate above your resting rate (8+ bpm: 1, 15+: 2, 25+: 3), HRV under your own 14-day average (10% under: 1, 25% under: 2) and breathing faster than usual (1.5+/min: 1, 3+: 2). The points are scaled to 0–3: under 0.75 Calm, under 1.5 Balanced, under 2.25 Elevated, then High. It pauses after workouts, sauna and steam, and while you're walking. WHOOP's own Stress Monitor isn't shared with Health, so this is Still Pointz' own estimate from the numbers WHOOP and your Watch save there.")
                }
                Section {
                    Text("This is a rough estimate from your own numbers to help pick a practice. It isn't a medical measurement or advice. HRV from WHOOP and from the Watch are measured differently, so each is only compared with its own history.")
                        .font(SP.rounded(12)).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DuskBackground())
            .navigationTitle("Why this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Two daily reminders

/// Two gentle daily reminders, each carrying that moment's "Right now" pick: ~6:00 AM (last night's sleep,
/// recovery, HRV) and before bed (default 9:30 PM; wind-down, adjusted by the day's strain and stress).
/// On by default once notifications are allowed (asked once, the first time a Right now practice is started).
/// No sound by default, never time-sensitive. The next 7 days are scheduled and refreshed whenever the app
/// opens or new Health data arrives. Tapping one starts the practice.
@MainActor
final class DailyMoments: ObservableObject {
    static let shared = DailyMoments()

    private let d = UserDefaults.standard
    @Published var morningOn: Bool { didSet { d.set(morningOn, forKey: "sp.moment.morningOn"); changed() } }
    @Published var bedtimeOn: Bool { didSet { d.set(bedtimeOn, forKey: "sp.moment.bedOn"); changed() } }
    /// Only hour and minute matter.
    @Published var morningTime: Date { didSet { save(morningTime, "sp.moment.morning"); changed() } }
    @Published var bedtimeTime: Date { didSet { save(bedtimeTime, "sp.moment.bed"); changed() } }
    @Published var sound: Bool { didSet { d.set(sound, forKey: "sp.moment.sound"); changed() } }
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    static let prefix = "sp.moment."
    static let days = 7

    private init() {
        morningOn = d.object(forKey: "sp.moment.morningOn") as? Bool ?? true
        bedtimeOn = d.object(forKey: "sp.moment.bedOn") as? Bool ?? true
        sound = d.bool(forKey: "sp.moment.sound")
        morningTime = Self.load(d, "sp.moment.morning", 6, 0)
        bedtimeTime = Self.load(d, "sp.moment.bed", 21, 30)
        refreshStatus()
    }

    private static func load(_ d: UserDefaults, _ key: String, _ h: Int, _ m: Int) -> Date {
        let hour = d.object(forKey: key + ".h") as? Int ?? h
        let minute = d.object(forKey: key + ".m") as? Int ?? m
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func save(_ t: Date, _ key: String) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        d.set(c.hour ?? 0, forKey: key + ".h")
        d.set(c.minute ?? 0, forKey: key + ".m")
    }

    private func changed() { reschedule(RightNow.shared) }

    var allowed: Bool { status == .authorized || status == .provisional }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let st = s.authorizationStatus
            Task { @MainActor in
                let was = self.status
                self.status = st
                if st != was { self.reschedule(RightNow.shared) }
            }
        }
    }

    /// The one contextual ask (no-op once asked).
    func askOnce() {
        guard !d.bool(forKey: "sp.moment.asked") else { return }
        d.set(true, forKey: "sp.moment.asked")
        request()
    }

    /// Ask now (Settings toggles when permission was never asked).
    func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refreshStatus() }
        }
    }

    /// Lets new sleep / HRV / workout data wake the app so the next reminder carries a fresh pick.
    func enableBackgroundIfNeeded() {
        guard RightNowHealth.available else { return }
        let store = RightNowHealth.store
        for t in [RightNowHealth.sleep, RightNowHealth.hrv, HKObjectType.workoutType()] as [HKObjectType] {
            store.enableBackgroundDelivery(for: t, frequency: .hourly) { _, _ in }
        }
    }

    enum Moment { case morning, bedtime }

    /// The pick for a reminder at `date`, from the best numbers known now.
    func suggestion(_ m: Moment, at date: Date, model: RightNow) -> Suggestion {
        let cal = Calendar.current
        let snap = model.snapshot
        var s = BodySnapshot()
        // Numbers only carry over to a reminder later today (tomorrow's sleep isn't known yet).
        if let snap, cal.isDate(date, inSameDayAs: Date()) {
            s = snap
            s.heartRate = nil
            s.recentSteps = nil
            s.lastHeatEnd = nil
            s.lastWorkoutEnd = nil
        }
        let lastDone = Prefs.shared.recents.first
        let best = SessionLog.shared.worksBest()
        let locked: (Practice) -> Bool = { PracticeLibrary.shared.isLocked($0) }
        var out = SuggestionEngine.suggest(s, stress: nil, stressNote: nil, now: date, lastDone: lastDone, worksBest: best, isLocked: locked)
        if m == .bedtime, cal.isDate(date, inSameDayAs: Date()) {
            // Adjust the wind-down by the day: heavy strain → restorative, a stressful day → slow-exhale breathing.
            let strain = snap?.whoopStrain
            let trained = (snap?.workoutMinutesToday ?? 0) >= 45
            let stressed = (model.stress?.level ?? .calm) >= .elevated
            var rule: SuggestionEngine.Rule?
            if (strain ?? 0) >= 14 || trained {
                let why = strain.map { String(localized: "Strain \(Int($0.rounded())) today") } ?? String(localized: "A big training day")
                rule = SuggestionEngine.Rule(id: "night", goal: "sleep", picks: [("legs-up-rest", 10), ("wind-down-nidra", 10), ("sleep-pmr", 10)],
                             because: why + String(localized: " — rest the legs and wind down"))
            } else if stressed {
                rule = SuggestionEngine.Rule(id: "night", goal: "sleep", picks: [("wind-down-478", 3), ("long-exhale", 5), ("wind-down-nidra", 10)],
                             because: String(localized: "A stressful stretch today — slow the breath before sleep"))
            }
            if let rule, let pick = SuggestionEngine.choose(rule, lastDone: lastDone, worksBest: best, isLocked: locked) {
                out.practiceId = pick.0.id
                out.title = pick.0.title
                out.minutes = pick.1
                out.worksBest = pick.2
                out.because = rule.because
                out.goal = rule.goal
            }
        }
        return out
    }

    /// Replace the scheduled reminders for the next 7 days.
    func reschedule(_ model: RightNow) {
        let center = UNUserNotificationCenter.current()
        let morningOn = morningOn, bedtimeOn = bedtimeOn, allowed = allowed
        var requests: [UNNotificationRequest] = []
        if allowed {
            let cal = Calendar.current
            let now = Date()
            for offset in 0..<Self.days {
                guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
                let slots: [(Moment, Bool, Date)] = [(.morning, morningOn, morningTime), (.bedtime, bedtimeOn, bedtimeTime)]
                for (m, on, t) in slots where on {
                    let hm = cal.dateComponents([.hour, .minute], from: t)
                    guard let fire = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day), fire > now else { continue }
                    let sug = suggestion(m, at: fire, model: model)
                    let c = UNMutableNotificationContent()
                    c.title = m == .morning ? String(localized: "Good morning") : String(localized: "Before bed")
                    c.body = String(localized: "\(sug.because). \(sug.title) · \(sug.minutes) min")
                    c.sound = sound ? .default : nil
                    c.interruptionLevel = .active
                    c.categoryIdentifier = Reminders.category
                    c.userInfo = ["practiceId": sug.practiceId, "minutes": sug.minutes]
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let id = Self.prefix + (m == .morning ? "am." : "pm.") + WellnessBridge.dayKey(fire)
                    requests.append(UNNotificationRequest(identifier: id, content: c,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            }
        }
        let toAdd = requests, prefix = Self.prefix
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for r in toAdd { center.add(r) }
        }
    }
}

struct DailyMomentsSettings: View {
    @ObservedObject private var moments = DailyMoments.shared

    var body: some View {
        Section {
            Toggle("Morning pick", isOn: $moments.morningOn)
            if moments.morningOn {
                DatePicker("Time", selection: $moments.morningTime, displayedComponents: .hourAndMinute)
            }
            Toggle("Bedtime pick", isOn: $moments.bedtimeOn)
            if moments.bedtimeOn {
                DatePicker("Time", selection: $moments.bedtimeTime, displayedComponents: .hourAndMinute)
            }
            Toggle("Sound", isOn: $moments.sound)
            if moments.status == .notDetermined {
                Button("Allow notifications") { moments.request() }
            }
        } header: { Text("Right now reminders") } footer: {
            if moments.status == .denied {
                Text("Notifications are off for Still Point. Turn them on in the Settings app to get these.")
            } else {
                Text("Two quiet notifications a day with that moment's suggested practice: the morning one from last night's sleep, recovery and HRV, the bedtime one a wind-down shaped by the day's strain and stress estimate. Tap to start it.")
            }
        }
        .onAppear { moments.refreshStatus() }
    }
}
