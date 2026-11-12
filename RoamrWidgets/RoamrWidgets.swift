import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RoamrWidgets: WidgetBundle {
    var body: some Widget {
        TrackingLiveActivity()
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
}

// MARK: - Live Activity

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            RMLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(Palette.amber)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RMExpandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RMExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    RMExpandedCenter(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RMExpandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                RMKindIcon(symbol: context.attributes.kindSymbol, paused: context.state.isPaused, size: 14)
            } compactTrailing: {
                RMCompactTimer(state: context.state)
            } minimal: {
                RMKindIcon(symbol: context.attributes.kindSymbol, paused: context.state.isPaused, size: 13)
            }
            .keylineTint(Palette.orange)
        }
    }
}

// MARK: - Shared pieces

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

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Palette.accent(paused: paused))
                .frame(width: 6, height: 6)
            Text(paused ? "PAUSED" : "RECORDING")
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
        let parts: (value: String, unit: String) = TrackingActivityAttributes.valueAndUnit(text)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RMLockHeader(attributes: attributes, state: state)
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

            RMStatusPill(paused: state.isPaused)
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
                .font(.system(size: 40, weight: .semibold, design: .rounded))
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

    var body: some View {
        HStack(spacing: 8) {
            RMKindIcon(symbol: attributes.kindSymbol, paused: state.isPaused, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(attributes.kindTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text(state.isPaused ? "Paused" : "Recording")
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

private struct RMExpandedCenter: View {
    let attributes: TrackingActivityAttributes

    var body: some View {
        Text(attributes.appName)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.amber)
            .lineLimit(1)
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
