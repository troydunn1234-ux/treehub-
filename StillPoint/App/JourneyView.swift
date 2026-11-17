import SwiftUI
import Charts

struct JourneyView: View {
    @EnvironmentObject var log: SessionLog
    @EnvironmentObject var router: Router
    @State private var healthWeek: Double? = nil
    @State private var external: [ExternalMindfulSession] = []
    @State private var selectedDay: DayPick? = nil
    @State private var path = NavigationPath()

    private var weekStart: Date { Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date() }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: SP.s6) {
                    VStack(alignment: .leading, spacing: SP.s1) {
                        Text("Journey").font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(storyLine).font(.subheadline).foregroundStyle(SP.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, SP.s2)

                    // 1. Where you are: streak and weekly goal.
                    StreakGoalCard()

                    // Today in Rootbound, Roamr and Pulse Lab (ConnectionsViews.swift; hidden without them).
                    TodayAcrossAppsStrip()

                    // 2. What you've reached, and what's next.
                    JourneyMilestoneStrip()

                    // 3. This week, day by day.
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Last 7 days", detail: String(localized: "Tap a day"))
                        WeekCard(selectedDay: $selectedDay)
                    }

                    // 4. Trends.
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Trends")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: SP.s3) { trendTiles }
                            VStack(spacing: SP.s3) { trendTiles }
                        }
                        ProgressEntryCard()
                    }

                    // 5. What works for you.
                    let best = log.worksBest().compactMap { PracticeLibrary.shared.practice($0) }
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Works best for you", detail: best.isEmpty ? nil : String(localized: "Biggest heart-rate drops"))
                        if best.isEmpty {
                            HStack(spacing: SP.s3) {
                                Image(systemName: "arrow.down.heart").font(.system(size: 18, weight: .light)).foregroundStyle(SP.rose)
                                    .frame(width: 40, height: 40).background(Circle().fill(SP.rose.opacity(0.12)))
                                    .accessibilityHidden(true)
                                Text("Practice with your Watch on. After 3 sessions of a practice, the ones that settle you most show here.")
                                    .font(.footnote).foregroundStyle(SP.dim).fixedSize(horizontal: false, vertical: true)
                            }
                            .spCard(padding: SP.s3)
                        } else {
                            PracticeStack(practices: best)
                        }
                    }

                    RootboundLinkCard()

                    // 6. Every session, grouped by day.
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Sessions")
                        if !log.records.isEmpty || !external.isEmpty {
                            ForEach(groupedRows, id: \.day) { group in
                                VStack(alignment: .leading, spacing: SP.s2) {
                                    HStack {
                                        Text(dayTitle(group.day)).font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink.opacity(0.85))
                                        Spacer()
                                        Text(String(format: "%.0f min", max(1, group.minutes.rounded())))
                                            .font(.footnote).monospacedDigit().foregroundStyle(SP.faint)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isHeader)
                                    ForEach(group.items) { item in
                                        switch item {
                                        case .mine(let r):
                                            NavigationLink(value: r.id) { row(r) }.buttonStyle(SoftPress())
                                                .contextMenu {
                                                    Button(role: .destructive) { withAnimation { log.remove(r.id) } } label: {
                                                        Label("Delete session", systemImage: "trash")
                                                    }
                                                }
                                        case .other(let e):
                                            externalRow(e)
                                        }
                                    }
                                }
                                .padding(.bottom, SP.s1)
                            }
                        } else {
                            SPEmptyState(symbol: "leaf", title: String(localized: "No sessions yet"),
                                         hint: String(localized: "Your sessions will gather here, like stones on a path."),
                                         actionTitle: String(localized: "Begin a first practice")) { router.tab = 0 }
                                .spCard()
                        }
                    }
                }
                .padding(.horizontal, SP.screenPadding)
                .padding(.bottom, SP.s8)
            }
            .background(DuskBackground())
            .navigationDestination(for: UUID.self) { id in SessionDetailView(recordId: id) }
            .navigationDestination(for: ProgressRoute.self) { _ in PracticeProgressView() }
            .sheet(item: $selectedDay) { pick in
                DaySessionsSheet(day: pick.day)
                    .environmentObject(log)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .onAppear {
                // -demo -open progress (simulator QA / screenshots): straight to the Progress screen.
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-demo"), let i = args.firstIndex(of: "-open"), i + 1 < args.count,
                   args[i + 1] == "progress", path.isEmpty {
                    path.append(ProgressRoute.main)
                }
                guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
                MindfulHealth.shared.mindfulMinutes(since: weekStart) { healthWeek = $0 }
                MindfulHealth.shared.externalMindfulSessions(since: Date().addingTimeInterval(-30 * 86400)) { external = $0 }
            }
            // stillpoint://journey?session=… (Roamr "Breathwork after"): that session's page.
            .journeySessionLink(path: $path)
        }
    }

    /// One line that tells the story so far.
    private var storyLine: String {
        let total = Int(log.totalMinutes.rounded())
        let n = log.records.count
        if n == 0 { return String(localized: "Every session you finish is kept here, with how your heart settled.") }
        return n == 1 ? String(localized: "1 session and \(total) mindful minutes so far.")
                      : String(localized: "\(n) sessions and \(total) mindful minutes so far.")
    }

    @ViewBuilder private var trendTiles: some View {
        let week = max(healthWeek ?? 0, log.weekMinutes)
        let prev = log.previousWeekMinutes
        let delta = week - prev
        tile(String(format: "%.0f", week), String(localized: "minutes in the last 7 days"),
             note: prev > 0 || week > 0 ? (delta >= 0 ? String(localized: "▲ \(Int(delta.rounded())) vs the week before")
                                                       : String(localized: "▼ \(Int((-delta).rounded())) vs the week before")) : nil)
        tile("\(log.bestStreak)", String(localized: "best streak (days)"))
        tile("\(log.records.count)", String(localized: "sessions in all"))
    }

    private struct DayGroup { let day: Date; let items: [RowItem]; let minutes: Double }

    /// The newest 60 rows, grouped under their day.
    private var groupedRows: [DayGroup] {
        let cal = Calendar.current
        var out: [DayGroup] = []
        for item in mergedRows.prefix(60) {
            let d = cal.startOfDay(for: item.start)
            let m = item.minutes
            if let last = out.last, last.day == d {
                out[out.count - 1] = DayGroup(day: d, items: last.items + [item], minutes: last.minutes + m)
            } else {
                out.append(DayGroup(day: d, items: [item], minutes: m))
            }
        }
        return out
    }

    private func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "Today") }
        if cal.isDateInYesterday(d) { return String(localized: "Yesterday") }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private enum RowItem: Identifiable {
        case mine(SessionRecord), other(ExternalMindfulSession)
        var id: UUID { switch self { case .mine(let r): return r.id; case .other(let e): return e.id } }
        var start: Date { switch self { case .mine(let r): return r.start; case .other(let e): return e.start } }
        var minutes: Double { switch self { case .mine(let r): return r.minutes; case .other(let e): return e.minutes } }
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
                Text(e.start.formatted(.dateTime.hour().minute()) + " · from Apple Watch Mindfulness")
                    .font(SP.rounded(12)).foregroundStyle(SP.faint)
            }
            Spacer()
            Text(String(format: "%.0f min", max(1, e.minutes.rounded()))).font(SP.rounded(14)).foregroundStyle(SP.dim)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).fill(SP.card.opacity(0.5)))
        .opacity(0.8)
    }

    private func tile(_ value: String, _ label: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: SP.s1) {
            Text(value).font(SP.numbers(30)).foregroundStyle(SP.ink).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(SP.dim).fixedSize(horizontal: false, vertical: true)
            if let note { Text(note).font(.caption2.weight(.medium)).foregroundStyle(SP.accent).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .spCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([value, label, note].compactMap { $0 }.joined(separator: " "))
    }

    private func row(_ r: SessionRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.device == "Watch" ? "applewatch" : "iphone")
                .font(.system(size: 15, weight: .light)).foregroundStyle(SP.teal).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink).lineLimit(2)
                Text(r.start.formatted(.dateTime.hour().minute())).font(.caption).foregroundStyle(SP.faint)
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
                .accessibilityHidden(true)
        }
        .spCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(r))
        .accessibilityHint("Opens the session")
    }

    private func rowLabel(_ r: SessionRecord) -> String {
        var parts = [r.title, r.start.formatted(.dateTime.weekday(.wide).hour().minute()),
                     "\(Int(max(1, r.minutes.rounded()))) minutes", "on \(r.device == "Watch" ? "Watch" : "iPhone")"]
        if let drop = r.hrDrop, drop > 0 { parts.append("heart rate down \(Int(drop)) beats per minute") }
        return parts.joined(separator: ", ")
    }
}

/// The Journey's milestone line: what you've earned most recently and what's next, with a link to all of them.
struct JourneyMilestoneStrip: View {
    @EnvironmentObject var log: SessionLog
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let all = log.milestones
        let earned = all.filter(\.earned)
        let next = all.filter { !$0.earned }.sorted { $0.progress > $1.progress }
        let shown = Array(earned.suffix(2) + next.prefix(4 - min(2, earned.count)))
        VStack(alignment: .leading, spacing: SP.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Milestones").font(.headline).foregroundStyle(SP.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                NavigationLink(value: ProgressRoute.main) {
                    Text("\(earned.count) of \(all.count) · See all").font(.footnote.weight(.medium)).foregroundStyle(SP.accent)
                        .frame(minHeight: 32)
                }
            }
            // Four across; two across at accessibility text sizes so titles never squeeze.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SP.s2, alignment: .top), count: typeSize.isAccessibilitySize ? 2 : 4),
                      alignment: .leading, spacing: SP.s3) {
                ForEach(shown) { m in MilestoneBadge(milestone: m) }
            }
        }
        .spCard()
    }
}

struct SettingsView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var link: PhoneLink
    @EnvironmentObject var log: SessionLog
    @StateObject private var reminders = Reminders.shared
    @ObservedObject private var unlock = Unlock.shared
    @State private var showPlans = false
    @Environment(\.dismiss) private var dismiss

    private let goalChoices: [Double] = [15, 30, 45, 60, 90, 120, 150, 210]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showPlans = true } label: {
                        HStack {
                            Label("Still Pointz Pro", systemImage: "sparkles")
                            Spacer()
                            Text(unlock.subscribed ? "Active" : (unlock.isPro ? "Lifetime" : "See plans"))
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(unlock.subscribed ? "Change plan, cancel or restore from here." : "Free trial, monthly, yearly or lifetime.")
                }
                Section {
                    Picker(selection: $log.weeklyGoal) {
                        ForEach(goalOptions, id: \.self) { m in Text(goalLabel(m)).tag(m) }
                    } label: { Label("Weekly goal", systemImage: "target") }
                    Toggle(isOn: $reminders.enabled) { Label("Daily reminder", systemImage: "bell") }
                    if reminders.enabled {
                        DatePicker("Time", selection: $reminders.time, displayedComponents: .hourAndMinute)
                    }
                } header: { Text("Rhythm") } footer: {
                    if reminders.enabled && reminders.denied {
                        Text("Notifications are off for Still Point. Turn them on in the Settings app to get the reminder.")
                    } else {
                        Text("A quiet nudge once a day, at a time you choose. Nothing else, ever.")
                    }
                }
                DailyMomentsSettings()
                Section {
                    Toggle(isOn: $prefs.settings.voiceGuide) { Label("Voice guide", systemImage: "waveform") }
                    Toggle("Tap the count, in & out", isOn: $prefs.settings.countTaps)
                } header: { Text("Voice") } footer: {
                    Text("A calm voice names each move and counts the breath, in sessions and in the sauna & steam guide. It keeps going with the screen locked, and music only gets quieter. The speaker button in a session switches it for that session. On the Watch, the count is tapped on your wrist instead.")
                }
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
                MoreAppsGate { Section { MoreAppsRow() } }
                Section {
                    // The family About block: app icon, name and version, then privacy, terms and help.
                    FamilyAboutHeader(name: "Still Pointz", tint: SP.accent)
                    FamilyAboutLinks(privacy: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/stillpoint/PRIVACY.md"),
                                     terms: FamilyAboutLinks.standardTerms,
                                     support: URL(string: "https://github.com/troydunn1234-ux/treehub-/blob/main/store/stillpoint/SUPPORT.md"),
                                     tint: SP.accent)
                } header: { Text("About") } footer: {
                    Text("No accounts, no ads, no tracking. Your sessions stay on your devices and in Apple Health.")
                }
            }
            .tint(SP.accent)
            .scrollContentBackground(.hidden)
            .background(DuskBackground())
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPlans) { PaywallView(spec: StillPointPro.spec) }
        }
        .presentationBackground(.ultraThinMaterial)
    }

    /// The fixed choices, plus the current goal if it came from elsewhere (e.g. synced) so the picker always shows it.
    private var goalOptions: [Double] {
        goalChoices.contains(log.weeklyGoal) ? goalChoices : (goalChoices + [log.weeklyGoal]).sorted()
    }

    private func goalLabel(_ m: Double) -> String {
        let mins = Int(m)
        if mins % 60 == 0 { return mins == 60 ? "1 hour a week" : "\(mins / 60) hours a week" }
        if mins > 60 { return String(format: "%.1f hours a week", m / 60) }
        return "\(mins) min a week"
    }
}

/// Streak flame beside a weekly-goal ring: the two numbers that keep a practice going.
struct StreakGoalCard: View {
    @EnvironmentObject var log: SessionLog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var progress: Double { appeared ? log.weekProgress : 0 }
    private var alive: Bool { log.streak > 0 && log.practicedToday }

    var body: some View {
        HStack(spacing: 18) {
            // Streak
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: log.streak > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(log.streak > 0 ? SP.goldGlow : LinearGradient(colors: [SP.faint, SP.faint], startPoint: .top, endPoint: .bottom))
                        .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: alive && !reduceMotion)
                        .shadow(color: log.streak > 0 ? SP.amber.opacity(0.45) : .clear, radius: 10)
                        .accessibilityHidden(true)
                    Text("\(log.streak)").font(SP.numbers(40)).foregroundStyle(SP.ink).contentTransition(.numericText())
                    Text(log.streak == 1 ? "day" : "days").font(SP.rounded(14)).foregroundStyle(SP.dim)
                }
                Text(log.streakLine).font(SP.rounded(12)).foregroundStyle(SP.faint)
                    .fixedSize(horizontal: false, vertical: true)
                if log.bestStreak > log.streak {
                    Text("Best: \(log.bestStreak) days").font(SP.rounded(11)).foregroundStyle(SP.faint.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(log.streak) day streak. \(log.streakLine)")

            // Weekly goal ring
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(log.goalReached ? SP.goldGlow : LinearGradient(colors: [SP.accent, SP.indigo], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (log.goalReached ? SP.gold : SP.teal).opacity(0.35), radius: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.1), value: progress)
                VStack(spacing: 1) {
                    Text("\(Int(log.calendarWeekMinutes.rounded()))").font(SP.numbers(22)).foregroundStyle(SP.ink)
                    Text("of \(Int(log.weeklyGoal)) min").font(SP.rounded(9, .semibold)).tracking(0.6).foregroundStyle(SP.faint)
                }
            }
            .frame(width: 84, height: 84)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly goal: \(Int(log.calendarWeekMinutes.rounded())) of \(Int(log.weeklyGoal)) minutes this week")
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if log.goalReached {
                SPChip(text: "Goal met", color: SP.gold).padding(10)
            }
        }
        .onAppear { withAnimation { appeared = true } }
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
                Text("\(Int(log.weekMinutes.rounded())) min").font(SP.numbers(26)).foregroundStyle(SP.ink)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                if log.previousWeekMinutes > 0 || log.weekMinutes > 0 {
                    Text(deltaText).font(.footnote).foregroundStyle(delta >= 0 ? SP.teal : SP.rose)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityElement(children: .combine)
            Chart(log.lastWeek()) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.minutes))
                    .foregroundStyle(LinearGradient(colors: [SP.accent, SP.indigo.opacity(0.55)], startPoint: .top, endPoint: .bottom))
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
                    Text("What settles you most").font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink.opacity(0.85))
                    ForEach(best) { b in
                        HStack {
                            Text(b.title).font(.subheadline).foregroundStyle(SP.ink).lineLimit(2)
                            Spacer(minLength: 8)
                            Text("♥ −\(Int(b.avgDrop.rounded())) bpm").font(SP.rounded(12)).foregroundStyle(SP.rose)
                            Text("· \(b.count)×").font(SP.rounded(12)).foregroundStyle(SP.faint)
                        }
                    }
                }
            }
        }
        .spCard()
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
