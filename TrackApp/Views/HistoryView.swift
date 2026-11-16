import SwiftUI
import SwiftData

@MainActor
struct HistoryView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]

    /// Re-renders the list when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false

    /// nil means "All".
    @State private var filter: ActivityKind? = nil
    @State private var path = NavigationPath()
    /// Go together trips you took part in (kept on this phone).
    @ObservedObject private var groupLog = GroupHistory.shared

    /// One calendar week of trips, split into days, with totals for the header.
    private struct WeekGroup: Identifiable {
        let week: Date
        let days: [DayGroup]
        var id: Date { week }
        var items: [Activity] { days.flatMap(\.items) }
        var totalDistance: Double { items.reduce(0.0) { $0 + $1.distanceM } }
        var totalSeconds: Double { items.reduce(0.0) { $0 + $1.elapsedSec } }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Activity]
        var id: Date { day }
        var totalDistance: Double { items.reduce(0.0) { $0 + $1.distanceM } }
    }

    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let shortDayYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()

    /// "This week", "Last week", or "Nov 2 – Nov 8" (with the year when it isn't this year).
    private static func weekTitle(_ start: Date) -> String {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start
        if start == thisWeek { return String(localized: "This week") }
        if let thisWeek, let last = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek), start == last {
            return String(localized: "Last week")
        }
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let sameYear = cal.isDate(start, equalTo: Date(), toGranularity: .year)
        let f = sameYear ? shortDay : shortDayYear
        return "\(shortDay.string(from: start)) – \(f.string(from: end))"
    }

    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return String(localized: "Today") }
        if cal.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return weekdayFormatter.string(from: day)
    }

    /// "2h 05m" / "45m" for week totals.
    private static func hoursMinutes(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m)m"
    }

    private static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    private var filtered: [Activity] {
        guard let filter else { return activities }
        return activities.filter { $0.kind == filter }
    }

    private var groups: [WeekGroup] {
        let cal = Calendar.current
        let byWeek: [Date: [Activity]] = Dictionary(grouping: filtered) { (a: Activity) -> Date in
            cal.dateInterval(of: .weekOfYear, for: a.start)?.start ?? cal.startOfDay(for: a.start)
        }
        return byWeek.keys.sorted(by: >).map { (week: Date) -> WeekGroup in
            let byDay: [Date: [Activity]] = Dictionary(grouping: byWeek[week] ?? []) { cal.startOfDay(for: $0.start) }
            let days: [DayGroup] = byDay.keys.sorted(by: >).map { (d: Date) -> DayGroup in
                DayGroup(day: d, items: (byDay[d] ?? []).sorted { $0.start > $1.start })
            }
            return WeekGroup(week: week, days: days)
        }
    }

    private var subtitle: String {
        let list = filtered
        let total: Double = list.reduce(0.0) { $0 + $1.distanceM }
        let noun = list.count == 1 ? "trip" : "trips"
        return "\(list.count) \(noun) · \(Format.distance(total))"
    }

    var body: some View {
        let groupList = groups
        return NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    header
                        .padding(.horizontal, Theme.pad)

                    filterRow

                    if filter == nil, !groupLog.trips.isEmpty {
                        togetherSection
                    }

                    if groupList.isEmpty {
                        emptyState
                            .padding(.horizontal, Theme.pad)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        LazyVStack(alignment: .leading, spacing: Theme.gap) {
                            ForEach(groupList) { group in
                                weekSection(group)
                            }
                        }
                        .padding(.horizontal, Theme.pad)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 130)
                .animation(Self.spring, value: filter)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
            .navigationDestination(for: String.self) { route in
                if route == "monthly" { MonthlyStatsView() }
            }
            .onAppear { openPendingActivity() }
            .task {
                // -demo -open monthly / activity / recap (simulator QA), once the demo trips are in.
                guard let open = TrackDemo.open, ["monthly", "activity", "recap"].contains(open) else { return }
                try? await Task.sleep(for: .seconds(1))
                guard path.isEmpty else { return }
                // "-openDrive" picks the first drive, so QA can see the speed-colored route.
                let wantsDrive = ProcessInfo.processInfo.arguments.contains("-openDrive")
                if open == "monthly" { path.append("monthly") }
                else if let a = wantsDrive ? (activities.first { $0.kind == .drive } ?? activities.first) : activities.first { path.append(a.id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: DriveFinishedNotifier.openActivityNote)) { _ in
                openPendingActivity()
            }
        }
    }

    /// Opens the activity a "Drive finished" notification pointed at, if there is one waiting.
    private func openPendingActivity() {
        guard let raw = UserDefaults.standard.string(forKey: DriveFinishedNotifier.pendingOpenKey),
              let id = UUID(uuidString: raw) else { return }
        guard activities.contains(where: { $0.id == id }) else { return }
        UserDefaults.standard.removeObject(forKey: DriveFinishedNotifier.pendingOpenKey)
        path = NavigationPath()
        path.append(id)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(Theme.title(34))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(Theme.rounded(14, .semibold))
                    .foregroundStyle(Theme.textDim)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            NavigationLink(value: "monthly") {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                    Text("Monthly")
                        .font(Theme.rounded(13, .bold))
                }
                .foregroundStyle(Theme.glow)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.glow.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityLabel("Monthly driving stats")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Filter chips

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(Self.spring) { filter = nil }
                } label: {
                    Chip(label: "All", symbol: "square.grid.2x2.fill", selected: filter == nil)
                }
                .pressable()

                ForEach(ActivityKind.allCases) { (k: ActivityKind) in
                    Button {
                        withAnimation(Self.spring) { filter = (filter == k) ? nil : k }
                    } label: {
                        Chip(label: k.title, symbol: k.symbol, selected: filter == k)
                    }
                    .pressable()
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, Theme.pad, for: .scrollContent)
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: Week sections

    private func weekSection(_ group: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.weekTitle(group.week))
                    .font(Theme.rounded(20, .heavy))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("\(group.items.count) \(group.items.count == 1 ? "trip" : "trips") · \(Format.distance(group.totalDistance)) · \(Self.hoursMinutes(group.totalSeconds))")
                    .font(Theme.rounded(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.glow.opacity(0.9))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            .padding(.top, 14)

            ForEach(group.days) { day in
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.dayTitle(day.day).uppercased())
                        .font(Theme.rounded(12, .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    if day.items.count > 1 {
                        Text(Format.distance(day.totalDistance))
                            .font(Theme.rounded(12, .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)

                ForEach(day.items) { (a: Activity) in
                    NavigationLink(value: a.id) { TripCard(activity: a, together: groupLog.log(for: a.id)?.withLabel) }
                        .pressable()
                        .cardAppear()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: Go together

    private var togetherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GO TOGETHER")
                    .font(Theme.rounded(12, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(groupLog.trips.count) group \(groupLog.trips.count == 1 ? "trip" : "trips")")
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(Theme.sky.opacity(0.9))
            }
            .padding(.horizontal, Theme.pad + 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(groupLog.trips) { g in
                        let saved = g.activityID.flatMap { id in activities.first { $0.id == id } }
                        if let saved {
                            NavigationLink(value: saved.id) { togetherCard(g, activity: saved) }
                                .pressable()
                                .accessibilityHint("Opens that trip")
                        } else {
                            togetherCard(g, activity: nil)
                                .contextMenu {
                                    Button(role: .destructive) { groupLog.remove(g.id) } label: { Label("Remove", systemImage: "trash") }
                                }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .contentMargins(.horizontal, Theme.pad, for: .scrollContent)
        }
    }

    private func togetherCard(_ g: GroupTripLog, activity: Activity?) -> some View {
        let distance = activity?.distanceM ?? g.distanceM
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: g.kind.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 28, height: 28)
                    .background(LinearGradient(colors: [Theme.sky, Theme.glow], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                Text(Format.day(g.date).uppercased())
                    .font(Theme.rounded(11, .heavy)).tracking(1)
                    .foregroundStyle(Theme.textDim)
                Spacer(minLength: 0)
                if g.hosted {
                    Image(systemName: "crown.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.gold)
                        .accessibilityLabel("You hosted")
                }
            }
            Text(g.withLabel)
                .font(Theme.rounded(15, .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(distance > 0 ? Format.distance(distance) : g.kind.title)
                    .font(Theme.rounded(13, .heavy))
                    .foregroundStyle(Theme.glow)
                Spacer(minLength: 0)
                if activity != nil {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textDim)
                } else {
                    Text("Not saved").font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
                }
            }
        }
        .padding(14)
        .frame(width: 190, height: 132, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial).opacity(0.5)
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.sky.opacity(0.08))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.sky.opacity(0.25)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Group \(g.kind.title.lowercased()) on \(Format.day(g.date)), \(g.withLabel)\(distance > 0 ? ", " + Format.distance(distance) : "")\(activity == nil ? ", recording not saved" : "")")
    }

    // MARK: Empty

    private var emptyState: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: filter?.symbol ?? "map.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 80, height: 80)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(filter == nil ? "No trips yet" : "No \(filter?.title.lowercased() ?? "") trips yet")
                    .font(Theme.rounded(20, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(filter == nil ? "Every walk, run, ride and drive you record lands here with its map."
                                   : "Pick \(filter?.title ?? "it") on the Track tab before you start, or change a trip's type from its page.")
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if filter != nil {
                        withAnimation(Self.spring) { filter = nil }
                    } else {
                        NotificationCenter.default.post(name: RoamrTabs.openTrack, object: nil)
                    }
                } label: {
                    Label(filter != nil ? "Show all trips" : "Start a trip",
                          systemImage: filter != nil ? "square.grid.2x2.fill" : "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
    }
}

/// Lets a screen send you to another tab (e.g. History's empty state -> Track).
enum RoamrTabs {
    static let openTrack = Notification.Name("roamr.openTrackTab")
}
