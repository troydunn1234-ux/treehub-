import SwiftUI
import UIKit
import SwiftData

/// Track tab, top left over the idle map: Roamr's signature at a glance. "Every mile mapped", the miles mapped
/// in the last 7 days and whether drive auto-detect is on. Tap: History (or Settings when auto-detect is off).
@MainActor
struct MilesMappedChip: View {
    var onOpenHistory: () -> Void
    var onOpenSettings: () -> Void

    @Query private var week: [Activity]
    @State private var detector = DriveDetector.shared
    /// Re-renders when the unit setting changes.
    @AppStorage("useMetric") private var useMetric = false

    init(onOpenHistory: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onOpenHistory = onOpenHistory
        self.onOpenSettings = onOpenSettings
        let since = Date().addingTimeInterval(-7 * 86_400)
        _week = Query(filter: #Predicate<Activity> { $0.start >= since })
    }

    private var autoOn: Bool { detector.enabled && detector.hasAlways }
    private var meters: Double { week.reduce(0) { $0 + $1.distanceM } }

    private var milesText: String {
        week.isEmpty ? String(localized: "Nothing mapped this week") : String(localized: "\(Format.distance(meters)) this week")
    }

    private var statusText: String { autoOn ? String(localized: "Drive detect on") : String(localized: "Drive detect off") }

    /// Follows the text size, but only up to 1.2x: the chip sits between the Directions and Go together buttons and
    /// must never cover them (VoiceOver reads the whole thing from the label below).
    private static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 1.2), weight: weight, design: .rounded)
    }

    var body: some View {
        Button { autoOn ? onOpenHistory() : onOpenSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.forestDeep)
                    .frame(width: 28, height: 28)
                    .background(Theme.leafGradient, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("EVERY MILE MAPPED")
                            .font(Self.font(9, .heavy)).tracking(1.1)
                            .foregroundStyle(Theme.glow)
                        // Drive auto-detect: lit when on, dim when off (spelled out for VoiceOver below).
                        Circle().fill(autoOn ? Theme.glow : Color.white.opacity(0.3)).frame(width: 6, height: 6)
                    }
                    Text(milesText)
                        .font(Self.font(13, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.glow.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(Text("Every mile mapped. \(milesText). \(statusText)."))
        .accessibilityHint(autoOn ? Text("Opens your trip history") : Text("Opens Settings to turn on drive detection"))
    }
}
