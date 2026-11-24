import SwiftUI
import SwiftData

@MainActor
struct HistoryView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]

    /// Re-renders the list when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false

    /// Roamr is drive-only now; walks / rides / hikes / runs recorded before stay here, folded away at the bottom.
    @State private var showOlder = false
    @State private var path = NavigationPath()
    /// Go together trips you took part in (kept on this phone).
    @ObservedObject private var groupLog = GroupHistory.shared
    /// A trip end being pinned under a name you type ("Her place").
    @State private var namingPin: NavPlace?
    @State private var pinName = ""
    @State private var pinned = 0

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

    /// Every drive, newest first.
    private var drives: [Activity] { activities.filter { $0.kind == .drive } }

    /// Walks, rides, hikes and runs from before Roamr went drive-only: kept exactly as they were.
    private var olderTrips: [Activity] { activities.filter { $0.kind != .drive } }

    private var groups: [WeekGroup] {
        let cal = Calendar.current
        let byWeek: [Date: [Activity]] = Dictionary(grouping: drives) { (a: Activity) -> Date in
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
        let list = drives
        let total: Double = list.reduce(0.0) { $0 + $1.distanceM }
        let noun = list.count == 1 ? "drive" : "drives"
        return "\(list.count) \(noun) · \(Format.distance(total)) driven"
    }

    var body: some View {
        let groupList = groups
        return NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    header
                        .padding(.horizontal, Theme.pad)

                    // The fuel log for these drives, one tap away.
                    fuelRow.padding(.horizontal, Theme.pad)

                    CommuteSection(activities: activities).padding(.horizontal, Theme.pad)

                    if !groupLog.trips.isEmpty {
                        togetherSection
                    }

                    FromYourAppsCard(me: WellnessConnect.roamr, accent: Theme.glow, metric: Units.metric).padding(.horizontal, Theme.pad)

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

                    if !olderTrips.isEmpty {
                        olderSection.padding(.horizontal, Theme.pad)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 130)
                .animation(Self.spring, value: showOlder)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
            .navigationDestination(for: String.self) { route in
                if route == "monthly" { MonthlyStatsView() }
                else if route.hasPrefix("commute:") { CommuteDetailView(routeID: String(route.dropFirst("commute:".count))) }
            }
            .alert(Text("Name this place"), isPresented: Binding(get: { namingPin != nil }, set: { if !$0 { namingPin = nil } })) {
                TextField(String(localized: "Her place"), text: $pinName)
                Button("Pin") {
                    let n = pinName.trimmingCharacters(in: .whitespaces)
                    if let p = namingPin, !n.isEmpty { PinTarget.custom(name: n, replacing: nil).apply(p); pinned += 1 }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: pinned)
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

    /// Opens the activity a "Drive finished" notification (or Rootbound's "Open in Roamr") pointed at, if there is
    /// one waiting. The request is used up either way: a trip that isn't here any more (deleted after Rootbound
    /// attached it as a walk) just leaves History open, instead of sending Roamr to History on every open.
    private func openPendingActivity() {
        guard let raw = UserDefaults.standard.string(forKey: DriveFinishedNotifier.pendingOpenKey) else { return }
        UserDefaults.standard.removeObject(forKey: DriveFinishedNotifier.pendingOpenKey)
        guard let id = UUID(uuidString: raw), activities.contains(where: { $0.id == id }) else { return }
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
                // The pill stays small; the tap area is a full 44 pt.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Monthly driving stats")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fuelRow: some View {
        Button { GasLogRequest.open() } label: {
            HStack(spacing: 10) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 30, height: 30)
                    .background(Theme.goldGradient, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gas & MPG").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                    Text("MPG per vehicle from these drives").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Theme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).strokeBorder(Theme.gold.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the gas log"))
    }

    // MARK: Week sections

    private func weekSection(_ group: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.weekTitle(group.week))
                    .font(Theme.rounded(20, .heavy))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("\(group.items.count) \(group.items.count == 1 ? "drive" : "drives") · \(Format.distance(group.totalDistance)) · \(Self.hoursMinutes(group.totalSeconds))")
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
                        .contextMenu { pinMenu(a) }
                        .cardAppear()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: Pin a trip's start or end

    @ViewBuilder private func pinMenu(_ a: Activity) -> some View {
        if let t = CommuteStore.trip(a) {
            pinSubmenu(String(localized: "Pin where it started"), NavPlace(name: t.fromName, subtitle: "", coordinate: t.from))
            pinSubmenu(String(localized: "Pin where it ended"), NavPlace(name: t.toName, subtitle: "", coordinate: t.to))
        }
    }

    private func pinSubmenu(_ title: String, _ place: NavPlace) -> some View {
        Menu {
            Button { PinTarget.home.apply(place); pinned += 1 } label: { Label("Home", systemImage: "house.fill") }
            Button { PinTarget.work.apply(place); pinned += 1 } label: { Label("Work", systemImage: "briefcase.fill") }
            Button { pinName = ""; namingPin = place } label: { Label("Name it…", systemImage: "pencil") }
        } label: {
            Label(title, systemImage: "mappin.and.ellipse")
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

    // MARK: Older walks & rides

    /// Trips from before Roamr went drive-only, folded into one row at the bottom. Nothing about them changes.
    private var olderSection: some View {
        let list = olderTrips
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Self.spring) { showOlder.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Older walks & rides (\(list.count))")
                            .font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        Text("Recorded before Roamr went drive-only · \(Format.distance(list.reduce(0.0) { $0 + $1.distanceM }))")
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                        .rotationEffect(.degrees(showOlder ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showOlder)
            .accessibilityValue(Text(showOlder ? "Shown" : "Hidden"))
            .accessibilityHint(Text(showOlder ? "Hides them" : "Shows them"))

            if showOlder {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(list) { (a: Activity) in
                        NavigationLink(value: a.id) { TripCard(activity: a, together: groupLog.log(for: a.id)?.withLabel) }
                            .pressable()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 14)
    }

    // MARK: Empty

    private var emptyState: some View {
        GlassCard(padding: 28) {
            VStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 80, height: 80)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text("No drives yet")
                    .font(Theme.rounded(20, .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Every drive lands here with its route on a night map. Turn on drive detect in Settings and Roamr catches drives as they start.")
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NotificationCenter.default.post(name: RoamrTabs.openTrack, object: nil)
                } label: {
                    Label("Start a drive", systemImage: "car.fill")
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
