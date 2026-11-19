import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RoamrWidgets: WidgetBundle {
    var body: some Widget {
        TrackingLiveActivity()
        RoamrQuickStartWidget()
        if #available(iOS 18.0, *) {
            StartTrackingControl()
            StartDriveControl()
        }
    }
}

// MARK: - Palette (hard-coded: the extension does not compile the app's Theme)

private enum Palette {
    static let background: Color = Color(red: 0.03, green: 0.05, blue: 0.10)
    static let amber: Color = Color(red: 1.0, green: 0.74, blue: 0.32)
    static let orange: Color = Color(red: 1.0, green: 0.42, blue: 0.20)
    static let paused: Color = Color(red: 0.62, green: 0.70, blue: 0.86)
    static let text: Color = Color.white
    static let secondary: Color = Color.white.opacity(0.6)
    static let card: Color = Color.white.opacity(0.07)

    static func accent(paused isPaused: Bool) -> Color { isPaused ? paused : orange }

    /// A tap on the Live Activity opens the live recording (Track tab), see RoamrWellness.handle(url:).
    static let liveURL: URL? = URL(string: "roamr://track")
}

// MARK: - Live Activity

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            RMLockScreenView(attributes: context.attributes, state: context.state.shown(stale: context.isStale), stale: context.isStale)
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(Palette.amber)
                .widgetURL(Palette.liveURL)
        } dynamicIsland: { context in
            let state = context.state.shown(stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RMExpandedLeading(attributes: context.attributes, state: state, stale: context.isStale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RMExpandedTrailing(state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RMExpandedBottom(attributes: context.attributes, state: state)
                }
            } compactLeading: {
                RMKindIcon(symbol: context.attributes.kindSymbol, paused: state.isPaused, size: 14)
            } compactTrailing: {
                RMCompactTimer(state: state)
            } minimal: {
                RMKindIcon(symbol: context.attributes.kindSymbol, paused: state.isPaused, size: 13)
            }
            .keylineTint(Palette.orange)
            .widgetURL(Palette.liveURL)
        }
    }
}

// MARK: - Shared pieces

private extension TrackingActivityAttributes.ContentState {
    /// Gone stale = the app stopped sending updates (closed or crashed). Freeze the clock at the
    /// last known time and show it like a pause, instead of a timer ticking on with nothing recording.
    func shown(stale: Bool) -> Self {
        guard stale, !isPaused else { return self }
        var s = self
        s.isPaused = true
        return s
    }
}

/// Live-ticking timer while recording, frozen elapsed time while paused.
private struct RMTimerText: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(TrackingActivityAttributes.clock(state.elapsed))
                .contentTransition(.numericText())
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
        }
    }
}

private struct RMKindIcon: View {
    let symbol: String
    let paused: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: paused ? "pause.fill" : symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.accent(paused: paused))
    }
}

private struct RMStatusPill: View {
    let paused: Bool
    var stale: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Palette.accent(paused: paused))
                .frame(width: 6, height: 6)
            Text(stale ? "OPEN ROAMR" : paused ? "PAUSED" : "RECORDING")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Palette.accent(paused: paused))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Palette.accent(paused: paused).opacity(0.16))
        )
        .overlay(
            Capsule().strokeBorder(Palette.accent(paused: paused).opacity(0.35), lineWidth: 0.5)
        )
    }
}

private struct RMStat: View {
    let label: String
    let text: String
    let alignment: HorizontalAlignment

    var body: some View {
        // "--" means "not enough data yet" (first seconds of a recording): show a calm dash instead.
        let clean: String = text.trimmingCharacters(in: .whitespaces) == "--" ? "—" : text
        let parts: (value: String, unit: String) = TrackingActivityAttributes.valueAndUnit(clean)
        return VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Lock Screen

private struct RMLockScreenView: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState
    var stale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RMLockHeader(attributes: attributes, state: state, stale: stale)
            HStack(alignment: .bottom, spacing: 12) {
                RMLockTimer(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RMLockStats(attributes: attributes, state: state)
                    .fixedSize()
            }
        }
        .padding(16)
    }
}

private struct RMLockHeader: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState
    var stale: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.amber, Palette.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: attributes.kindSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.background)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text(attributes.appName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(Palette.amber)
                Text(attributes.kindTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            RMStatusPill(paused: state.isPaused, stale: stale)
        }
    }
}

private struct RMLockTimer: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ELAPSED")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Palette.secondary)
            RMTimerText(state: state)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.isPaused ? Palette.secondary : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct RMLockStats: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            RMStat(label: "DISTANCE", text: state.distanceText, alignment: .trailing)
            Rectangle()
                .fill(Palette.secondary.opacity(0.35))
                .frame(width: 0.5, height: 30)
            RMStat(label: attributes.showsPace ? "PACE" : "SPEED", text: state.paceOrSpeed, alignment: .trailing)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Dynamic Island

private struct RMExpandedLeading: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState
    var stale: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Palette.accent(paused: state.isPaused).opacity(0.18))
                RMKindIcon(symbol: attributes.kindSymbol, paused: state.isPaused, size: 15)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(attributes.kindTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text(stale ? "Open Roamr" : state.isPaused ? "Paused" : "Recording")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.accent(paused: state.isPaused))
            }
            .lineLimit(1)
        }
        .padding(.leading, 4)
    }
}

private struct RMExpandedTrailing: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        RMTimerText(state: state)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(state.isPaused ? Palette.secondary : Palette.amber)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: 110, alignment: .trailing)
            .padding(.trailing, 4)
    }
}

private struct RMExpandedBottom: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            RMStat(label: "DISTANCE", text: state.distanceText, alignment: .leading)
            Spacer(minLength: 8)
            RMStat(label: attributes.showsPace ? "PACE" : "SPEED", text: state.paceOrSpeed, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}

private struct RMCompactTimer: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        RMTimerText(state: state)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.accent(paused: state.isPaused))
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 50, alignment: .trailing)
    }
}
