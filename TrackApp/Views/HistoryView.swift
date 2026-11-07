import SwiftUI
import SwiftData

@MainActor
struct HistoryView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]

    /// nil means "All".
    @State private var filter: ActivityKind? = nil

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("History").font(Theme.title(36)).foregroundStyle(.white).padding(.top, 8)

                    filterRow

                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            monthSection(group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let a = activities.first(where: { $0.id == id }) { ActivityDetailView(activity: a) }
            }
        }
    }

    // MARK: Filter chips

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) { filter = nil }
                } label: {
                    Chip(label: "All", symbol: "square.grid.2x2.fill", selected: filter == nil)
                }
                .buttonStyle(.plain)
                .haptic()

                ForEach(ActivityKind.allCases) { (k: ActivityKind) in
                    Button {
                        withAnimation(.snappy) { filter = (filter == k) ? nil : k }
                    } label: {
                        Chip(label: k.title, symbol: k.symbol, selected: filter == k)
                    }
                    .buttonStyle(.plain)
                    .haptic()
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    // MARK: Month sections

    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.monthFormatter.string(from: group.month))
                    .font(Theme.rounded(17, .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(group.items.count) \(group.items.count == 1 ? "trip" : "trips") · \(Format.distance(group.totalDistance))")
                    .font(Theme.rounded(13, .bold))
                    .foregroundStyle(Theme.glow)
            }
            .padding(.top, 6)

            ForEach(group.items) { (a: Activity) in
                NavigationLink(value: a.id) { ActivityRow(activity: a) }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: filter?.symbol ?? "map")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.leafGradient)
                Text("No trips yet")
                    .font(Theme.rounded(18, .bold))
                    .foregroundStyle(.white)
                Text("Start a trip from the Track tab and it will show up here.")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
    }
}
