import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RootboundWidgets: WidgetBundle {
    var body: some Widget {
        TrackingLiveActivity()
        if #available(iOS 18.0, *) {
            LogTreeHugControl()
            StartStrollControl()
        }
    }
}

// MARK: - Palette (hard-coded: the extension does not compile the app's Theme)

private enum Palette {
    static let background: Color = Color(red: 0.04, green: 0.13, blue: 0.09)
    static let glow: Color = Color(red: 0.74, green: 0.96, blue: 0.55)
    static let leaf: Color = Color(red: 0.36, green: 0.72, blue: 0.42)
    static let amber: Color = Color(red: 0.98, green: 0.80, blue: 0.42)
    static let text: Color = Color.white
    static let secondary: Color = Color.white.opacity(0.62)
    static let card: Color = Color.white.opacity(0.07)

    static func accent(paused: Bool) -> Color { paused ? amber : glow }
}

// MARK: - Live Activity

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            RBLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.background)
                .activitySystemActionForegroundColor(Palette.glow)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RBExpandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RBExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    RBExpandedCenter(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RBExpandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                RBKindIcon(symbol: context.attributes.kindSymbol, paused: context.state.isPaused, size: 14)
            } compactTrailing: {
                RBCompactTimer(state: context.state)
            } minimal: {
                RBKindIcon(symbol: context.attributes.kindSymbol, paused: context.state.isPaused, size: 13)
            }
            .keylineTint(Palette.glow)
        }
    }
}

// MARK: - Shared pieces

/// Live-ticking timer while recording, frozen elapsed time while paused.
private struct RBTimerText: View {
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

private struct RBKindIcon: View {
    let symbol: String
    let paused: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: paused ? "pause.fill" : symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.accent(paused: paused))
    }
}

private struct RBStatusPill: View {
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

private struct RBHugsPill: View {
    let hugs: Int

    var body: some View {
        Text("🌳 \(hugs) \(hugs == 1 ? "hug" : "hugs")")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.text)
            .contentTransition(.numericText())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.leaf.opacity(0.28)))
    }
}

private struct RBStat: View {
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

private struct RBLockScreenView: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RBLockHeader(attributes: attributes, state: state)
            HStack(alignment: .bottom, spacing: 12) {
                RBLockTimer(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RBLockStats(attributes: attributes, state: state)
                    .fixedSize()
            }
        }
        .padding(16)
    }
}

private struct RBLockHeader: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.glow, Palette.leaf],
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
                    .foregroundStyle(Palette.leaf)
                Text(attributes.kindTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            if state.hugs > 0 {
                RBHugsPill(hugs: state.hugs)
            }
            RBStatusPill(paused: state.isPaused)
        }
    }
}

private struct RBLockTimer: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ELAPSED")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Palette.secondary)
            RBTimerText(state: state)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.isPaused ? Palette.secondary : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct RBLockStats: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            RBStat(label: "DISTANCE", text: state.distanceText, alignment: .trailing)
            Rectangle()
                .fill(Palette.secondary.opacity(0.35))
                .frame(width: 0.5, height: 30)
            RBStat(label: attributes.showsPace ? "PACE" : "SPEED", text: state.paceOrSpeed, alignment: .trailing)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Dynamic Island

private struct RBExpandedLeading: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            RBKindIcon(symbol: attributes.kindSymbol, paused: state.isPaused, size: 18)
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

private struct RBExpandedTrailing: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        RBTimerText(state: state)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(state.isPaused ? Palette.secondary : Palette.glow)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: 110, alignment: .trailing)
            .padding(.trailing, 4)
    }
}

private struct RBExpandedCenter: View {
    let attributes: TrackingActivityAttributes

    var body: some View {
        Text(attributes.appName)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.leaf)
            .lineLimit(1)
    }
}

private struct RBExpandedBottom: View {
    let attributes: TrackingActivityAttributes
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            RBStat(label: "DISTANCE", text: state.distanceText, alignment: .leading)
            Spacer(minLength: 8)
            if state.hugs > 0 {
                RBHugsPill(hugs: state.hugs)
                Spacer(minLength: 8)
            }
            RBStat(label: attributes.showsPace ? "PACE" : "SPEED", text: state.paceOrSpeed, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}

private struct RBCompactTimer: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        RBTimerText(state: state)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.accent(paused: state.isPaused))
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 50, alignment: .trailing)
    }
}
