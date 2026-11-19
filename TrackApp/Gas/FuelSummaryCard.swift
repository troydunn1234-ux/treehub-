import SwiftUI
import SwiftData

/// Stats tab: fuel and vehicles at a glance (per vehicle: average MPG and this month's fuel spend), so the gas log
/// isn't hidden in Settings. Read-only: it uses the same models and math as the Gas & MPG screen.
@MainActor
struct FuelSummaryCard: View {
    @Query(sort: \GasVehicle.created) private var vehicles: [GasVehicle]
    @Query(sort: \FillUp.date, order: .reverse) private var fills: [FillUp]
    @Query(filter: #Predicate<Activity> { $0.kindRaw == "drive" }, sort: \Activity.start) private var drives: [Activity]

    private struct Row: Identifiable {
        let id: UUID
        let name: String
        let mpg: Double?
        let month: Double
        let fillCount: Int
    }

    /// Same split as GasLogView: fill-ups without a vehicle belong to the first one.
    private var rows: [Row] {
        if vehicles.isEmpty {
            guard !fills.isEmpty else { return [] }
            return [row(id: UUID(), name: String(localized: "My car"), fills)]
        }
        let firstID = vehicles.first?.id
        return vehicles.map { v in
            row(id: v.id, name: v.name, fills.filter { $0.vehicleID == v.id || (v.id == firstID && $0.vehicleID == nil) })
        }
    }

    private func row(id: UUID, name: String, _ list: [FillUp]) -> Row {
        let points = GasMath.mpg(fills: list, drives: drives)
        let miles = points.reduce(0) { $0 + $1.miles }, gallons = points.reduce(0) { $0 + $1.gallons }
        let month = list.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.cost }
        return Row(id: id, name: name, mpg: gallons > 0 ? miles / gallons : nil, month: month, fillCount: list.count)
    }

    var body: some View {
        let list = rows
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Fuel & vehicles"), symbol: "fuelpump.fill")
            if list.isEmpty { empty } else { filled(list) }
        }
    }

    private var empty: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Track fuel for every vehicle")
                    .font(Theme.rounded(17, .heavy)).foregroundStyle(.white)
                Text("Log a fill-up and Roamr works out MPG from the drives it mapped, plus what you spend on gas each month.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button { GasLogRequest.open(adding: true) } label: {
                    Label("Log a fill-up", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 2)
            }
        }
    }

    private func filled(_ list: [Row]) -> some View {
        Button { GasLogRequest.open() } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                        vehicleRow(r)
                    }
                    HStack(spacing: 4) {
                        Text("Open Gas & MPG").font(Theme.rounded(13, .bold))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.glow)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the gas log"))
    }

    private func vehicleRow(_ r: Row) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                vehicleName(r)
                Spacer(minLength: 8)
                numbers(r)
            }
            VStack(alignment: .leading, spacing: 8) {
                vehicleName(r)
                numbers(r)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(r)))
    }

    private func vehicleName(_ r: Row) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.forestDeep)
                .frame(width: 32, height: 32)
                .background(Theme.goldGradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(Theme.rounded(15, .bold)).foregroundStyle(.white).lineLimit(2)
                Text("\(r.fillCount) fill-ups").font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private func numbers(_ r: Row) -> some View {
        HStack(spacing: 16) {
            stat(r.mpg.map { String(format: "%.1f", $0) } ?? String(localized: "After 2 fills"),
                 String(localized: "Avg MPG"), dim: r.mpg == nil)
            stat(r.month.formatted(.currency(code: GasFormat.currency)), String(localized: "This month"), dim: false)
        }
    }

    private func stat(_ value: String, _ label: String, dim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(dim ? Theme.rounded(13, .bold) : Theme.rounded(18, .black))
                .monospacedDigit()
                .foregroundStyle(dim ? Theme.textDim : .white)
            Text(label).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
        }
    }

    private func spoken(_ r: Row) -> String {
        let mpg = r.mpg.map { String(localized: "average \(String(format: "%.1f", $0)) miles per gallon") }
            ?? String(localized: "MPG after your second full fill-up")
        return String(localized: "\(r.name), \(mpg), \(r.month.formatted(.currency(code: GasFormat.currency))) on fuel this month")
    }
}
