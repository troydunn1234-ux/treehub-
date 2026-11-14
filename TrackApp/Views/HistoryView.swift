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

    private struct MonthGroup: Identifiable {
        let month: Date
        let items: [Activity]
        var id: Date { month }
        var totalDistance: Double { items.reduce(0.0) { $0 + $1.distanceM } }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    private var filtered: [Activity] {
        guard let filter else { return activities }
        return activities.filter { $0.kind == filter }
    }

    private var groups: [MonthGroup] {
        let cal = Calendar.current
        let dict: [Date: [Activity]] = Dictionary(grouping: filtered) { (a: Activity) -> Date in
            cal.dateInterval(of: .month, for: a.start)?.start ?? cal.startOfDay(for: a.start)
        }
        let keys: [Date] = dict.keys.sorted(by: >)
        return keys.map { (key: Date) -> MonthGroup in
            let items: [Activity] = (dict[key] ?? []).sorted { $0.start > $1.start }
            return MonthGroup(month: key, items: items)
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
                                monthSection(group)
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

    // MARK: Month sections

    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.monthFormatter.string(from: group.month).uppercased())
                    .font(Theme.rounded(12, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(group.items.count) \(group.items.count == 1 ? "trip" : "trips") · \(Format.distance(group.totalDistance))")
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(Theme.glow.opacity(0.9))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)

            ForEach(group.items) { (a: Activity) in
                NavigationLink(value: a.id) { ActivityRow(activity: a, together: groupLog.log(for: a.id)?.withLabel) }
                    .pressable()
                    .cardAppear()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                Image(systemName: filter?.symbol ?? "map")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                    .frame(width: 76, height: 76)
                    .background(Theme.glow.opacity(0.12), in: Circle())
                Text(filter == nil ? "No trips yet" : "No \(filter?.title.lowercased() ?? "") trips yet")
                    .font(Theme.rounded(18, .bold))
                    .foregroundStyle(.white)
                Text(filter == nil ? "Start a trip from the Track tab and it will show up here."
                                   : "Pick \(filter?.title ?? "it") on the Track tab before you start, or change a trip's type from its page.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                if filter != nil {
                    Button {
                        withAnimation(Self.spring) { filter = nil }
                    } label: {
                        Text("Show all trips")
                            .font(Theme.rounded(14, .heavy))
                            .foregroundStyle(Theme.forestDeep)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Theme.leafGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
    }
}
