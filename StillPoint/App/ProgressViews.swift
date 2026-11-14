import SwiftUI
import Charts

/// Navigation value for the Progress screen (pushed from Journey).
enum ProgressRoute: Hashable { case main }

extension ActivityCategory {
    var tint: Color {
        switch self {
        case .joint: return BodyFocus.joint.tint
        case .lymph: return BodyFocus.lymph.tint
        case .stretch: return BodyFocus.stretch.tint
        case .breathe: return BodyFocus.breathe.tint
        case .sauna: return HeatKind.sauna.tint
        case .steam: return HeatKind.steam.tint
        }
    }
}

// MARK: - Journey entry card

/// A small card at the top of Journey that opens Progress: streak, best, and the last 12 weeks in miniature.
struct ProgressEntryCard: View {
    @EnvironmentObject var log: SessionLog

    var body: some View {
        NavigationLink(value: ProgressRoute.main) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROGRESS").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                    Text(summary).font(SP.serif(17)).foregroundStyle(SP.ink).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Streaks, minutes by kind, milestones").font(SP.rounded(12)).foregroundStyle(SP.faint)
                }
                Spacer(minLength: 0)
                Image(systemName: "chart.bar.xaxis").font(.system(size: 20, weight: .light)).foregroundStyle(SP.amber)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(SP.faint)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SP.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SP.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPress())
        .accessibilityLabel("Progress. \(summary)")
        .accessibilityHint("Opens streaks, minutes by kind and milestones")
    }

    private var summary: String {
        let earned = log.milestones.filter(\.earned).count
        if log.activeDays.isEmpty { return "Your first session starts the calendar." }
        return earned == 1 ? "1 milestone so far" : "\(earned) milestones so far"
    }
}

// MARK: - Progress screen

struct PracticeProgressView: View {
    @EnvironmentObject var log: SessionLog
    @EnvironmentObject var router: Router
    @State private var selectedDay: DayPick? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Progress").font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                    Text("Any session of a minute or more keeps the streak, sauna and steam included.")
                        .font(SP.rounded(13)).foregroundStyle(SP.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                if log.activeDays.isEmpty {
                    emptyState
                }

                StreakPairCard()
                CategoryWeekCard()
                HeatmapCard(selectedDay: $selectedDay)
                MilestonesCard()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .background(DuskBackground())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selectedDay?.id)
        .sheet(item: $selectedDay) { pick in
            DaySessionsSheet(day: pick.day)
                .environmentObject(log)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "leaf").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(SP.teal)
                .accessibilityHidden(true)
            Text("Nothing here yet, and that's fine.")
                .font(SP.serif(19)).foregroundStyle(SP.ink)
            Text("One minute of breathing, a few joint circles or a round in the sauna lights the first square of your calendar.")
                .font(SP.rounded(14)).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                router.tab = 0
            } label: {
                Label("Find a practice", systemImage: "sun.horizon")
                    .font(SP.rounded(15, .medium))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Capsule().fill(SP.goldGlow))
            }
            .buttonStyle(SoftPress())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }
}

/// Current and longest streak side by side.
struct StreakPairCard: View {
    @EnvironmentObject var log: SessionLog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            block(value: log.streak, label: log.streak == 1 ? "day now" : "days now", lit: log.streak > 0,
                  caption: log.streakLine, pulse: log.practicedToday && log.streak > 0)
            block(value: log.bestStreak, label: "longest", lit: log.bestStreak > 0,
                  caption: log.bestStreak > 0 && log.bestStreak == log.streak ? "You're on your best run." : "Your best run so far.",
                  pulse: false)
        }
    }

    private func block(value: Int, label: String, lit: Bool, caption: String, pulse: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: lit ? "flame.fill" : "flame")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(lit ? SP.goldGlow : LinearGradient(colors: [SP.faint, SP.faint], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: pulse && !reduceMotion)
                    .accessibilityHidden(true)
                Text("\(value)").font(SP.numbers(36)).foregroundStyle(SP.ink)
                Text(label).font(SP.rounded(13)).foregroundStyle(SP.dim)
            }
            Text(caption).font(SP.rounded(12)).foregroundStyle(SP.faint).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(value == 1 ? "day" : "days") \(label == "longest" ? "longest streak" : "current streak"). \(caption)")
    }
}

/// This calendar week's minutes, one bar per kind of practice.
struct CategoryWeekCard: View {
    @EnvironmentObject var log: SessionLog

    var body: some View {
        let rows = log.thisWeekByCategory()
        let total = rows.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("THIS WEEK BY KIND").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Spacer()
                Text("\(Int(total.rounded())) min").font(SP.rounded(13)).foregroundStyle(SP.dim)
            }
            Chart(rows) { row in
                BarMark(x: .value("Kind", row.category.title), y: .value("Minutes", row.minutes))
                    .foregroundStyle(LinearGradient(colors: [row.category.tint, row.category.tint.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                    .cornerRadius(6)
                    .annotation(position: .top, spacing: 3) {
                        if row.minutes >= 0.5 {
                            Text("\(Int(row.minutes.rounded()))").font(SP.rounded(10, .semibold)).foregroundStyle(row.category.tint)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(SP.rounded(10)).foregroundStyle(SP.faint) }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(SP.faint)
                }
            }
            .chartYScale(domain: 0...max(10, (rows.map(\.minutes).max() ?? 0) * 1.2))
            .frame(height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(rows))
            if total < 0.5 {
                Text("A fresh week. Every kind of practice gets its own bar here.")
                    .font(SP.rounded(12)).foregroundStyle(SP.faint)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }

    private func accessibilitySummary(_ rows: [CategoryMinutes]) -> String {
        let parts = rows.filter { $0.minutes >= 0.5 }.map { "\($0.category.title) \(Int($0.minutes.rounded())) minutes" }
        return parts.isEmpty ? "No practice yet this week" : "This week: " + parts.joined(separator: ", ")
    }
}

/// The last 12 weeks as a calendar: one square per day, warmer for more minutes. Tap a day to see its sessions.
struct HeatmapCard: View {
    @EnvironmentObject var log: SessionLog
    @Binding var selectedDay: DayPick?
    private let weeks = 12

    private var cal: Calendar { Calendar.current }

    /// First day of the oldest week shown.
    private var gridStart: Date {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        return cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
    }

    var body: some View {
        let start = gridStart
        let minutes = log.dailyActivity(since: start)
        let today = cal.startOfDay(for: Date())
        let activeCount = minutes.values.filter { $0 >= 1 }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("12 WEEKS").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Spacer()
                Text(activeCount == 1 ? "1 day practiced" : "\(activeCount) days practiced").font(SP.rounded(12)).foregroundStyle(SP.dim)
            }
            HStack(alignment: .top, spacing: 6) {
                // Weekday initials, in the locale's order.
                VStack(spacing: 4) {
                    Text(" ").font(SP.rounded(9))
                    ForEach(0..<7, id: \.self) { row in
                        Text(weekdaySymbol(row)).font(SP.rounded(9, .semibold)).foregroundStyle(SP.faint)
                            .frame(height: 18)
                    }
                }
                ForEach(0..<weeks, id: \.self) { col in
                    let weekStart = cal.date(byAdding: .day, value: col * 7, to: start) ?? start
                    VStack(spacing: 4) {
                        Text(monthLabel(col: col, weekStart: weekStart)).font(SP.rounded(9)).foregroundStyle(SP.faint)
                            .lineLimit(1).fixedSize()
                            .frame(height: 11)
                        ForEach(0..<7, id: \.self) { row in
                            let day = cal.date(byAdding: .day, value: row, to: weekStart) ?? weekStart
                            cell(day: day, minutes: minutes[cal.startOfDay(for: day)] ?? 0, today: today)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(SP.rounded(10)).foregroundStyle(SP.faint)
                ForEach([0.0, 5, 15, 30, 45], id: \.self) { m in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color(for: m)).frame(width: 12, height: 12)
                }
                Text("More").font(SP.rounded(10)).foregroundStyle(SP.faint)
            }
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar of the last 12 weeks: \(activeCount) days with practice")
    }

    @ViewBuilder
    private func cell(day: Date, minutes: Double, today: Date) -> some View {
        let future = day > today
        let isToday = cal.isDate(day, inSameDayAs: today)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(future ? Color.clear : color(for: minutes))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isToday ? SP.gold : (future ? Color.white.opacity(0.06) : .clear), lineWidth: isToday ? 1.2 : 0.8)
            )
            .frame(height: 18)
            .contentShape(Rectangle())
            .onTapGesture {
                let d = cal.startOfDay(for: day)
                if !log.sessions(on: d).isEmpty { selectedDay = DayPick(day: d) }
            }
            .accessibilityElement()
            .accessibilityLabel(future ? "" : "\(day.formatted(.dateTime.weekday(.wide).month().day())): \(minutes >= 1 ? "\(Int(minutes.rounded())) minutes" : "no practice")")
            .accessibilityHidden(future)
            .accessibilityAddTraits(log.sessions(on: day).isEmpty ? [] : .isButton)
    }

    private func color(for minutes: Double) -> Color {
        switch minutes {
        case ..<1: return Color.white.opacity(0.06)
        case ..<10: return SP.amber.opacity(0.30)
        case ..<20: return SP.amber.opacity(0.52)
        case ..<40: return SP.amber.opacity(0.75)
        default: return SP.gold
        }
    }

    private func weekdaySymbol(_ row: Int) -> String {
        let symbols = cal.veryShortWeekdaySymbols
        let i = (cal.firstWeekday - 1 + row) % 7
        return symbols.indices.contains(i) ? symbols[i] : ""
    }

    /// Month name above the first column of each month.
    private func monthLabel(col: Int, weekStart: Date) -> String {
        let prev = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        if col == 0 || cal.component(.month, from: prev) != cal.component(.month, from: weekStart) {
            return weekStart.formatted(.dateTime.month(.abbreviated))
        }
        return ""
    }
}

/// Gentle milestones: earned ones glow, the rest show how close they are.
struct MilestonesCard: View {
    @EnvironmentObject var log: SessionLog
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let all = log.milestones
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("MILESTONES").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Spacer()
                Text("\(all.filter(\.earned).count) of \(all.count)").font(SP.rounded(12)).foregroundStyle(SP.dim)
            }
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(all) { m in MilestoneBadge(milestone: m) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }
}

struct MilestoneBadge: View {
    let milestone: Milestone

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(milestone.earned ? SP.gold.opacity(0.16) : Color.white.opacity(0.04))
                Circle()
                    .trim(from: 0, to: milestone.earned ? 1 : max(0.001, milestone.progress))
                    .stroke(milestone.earned ? SP.goldGlow : LinearGradient(colors: [SP.teal.opacity(0.7), SP.indigo.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: milestone.symbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(milestone.earned ? SP.goldGlow : LinearGradient(colors: [SP.faint, SP.faint], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: 58, height: 58)
            .shadow(color: milestone.earned ? SP.amber.opacity(0.35) : .clear, radius: 8)
            Text(milestone.title).font(SP.serif(13)).foregroundStyle(milestone.earned ? SP.ink : SP.dim)
                .multilineTextAlignment(.center).lineLimit(2)
            Text(milestone.detail).font(SP.rounded(10)).foregroundStyle(SP.faint)
                .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(milestone.title), \(milestone.earned ? "earned" : "not yet"). \(milestone.detail)")
    }
}
