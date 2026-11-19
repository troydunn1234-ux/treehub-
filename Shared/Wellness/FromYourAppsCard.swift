import SwiftUI
import UIKit

/// "From your other apps": the same small card in Rootbound, Still Pointz, Roamr and Pulse Lab. The newest things
/// the sibling apps shared in the last two days (a tree hug, a breath, a walk, today's readiness), each with where
/// it came from and how long ago; a tap opens it in that app (WellnessConnect.open: its App Store page when it's
/// gone). Read from the shared feed (WellnessFamily.swift); hidden when no sibling app is installed or none shared
/// anything recently. `accent` is the host app's color (header symbol); each row keeps its own app's color.
@MainActor
struct FromYourAppsCard: View {
    let me: WellnessConnect.Peer
    var accent: Color
    var metric: Bool = WellnessConnect.localeMetric
    @State private var taps = 0
    private var feed: WellnessFeed { WellnessFeed.shared }

    var body: some View {
        let items = rows
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("From your other apps").font(.headline).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent)
                    }
                    .accessibilityAddTraits(.isHeader)
                    Text("The last two days. Tap one to open it there.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TimelineView(.everyMinute) { ctx in
                    VStack(spacing: 8) {
                        ForEach(items) { row($0, now: ctx.date) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .sensoryFeedback(.selection, trigger: taps)
            .transition(.opacity)
            .onAppear { feed.refreshIfStale() }
        }
    }

    private var rows: [WellnessConnect.FamilyItem] {
        if WellnessConnect.isDemo { return Array(WellnessConnect.sampleFamilyItems(for: me, metric: metric).prefix(4)) }
        return WellnessConnect.familyItems(for: me, metric: metric, installed: { feed.has($0) },
                                           stillPoint: feed.stillPoint, rootbound: feed.rootbound,
                                           roamr: feed.roamr, pulseLab: feed.pulseLab)
    }

    private func row(_ item: WellnessConnect.FamilyItem, now: Date) -> some View {
        let tint = Self.tint(item.peer)
        let ago = Self.ago(item.date, now: now)
        return Button {
            taps += 1
            WellnessConnect.open(item.url, in: item.peer)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(item.peer.name) · \(ago)").font(.caption).foregroundStyle(tint.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.detail). From \(item.peer.name), \(ago)")
        .accessibilityHint("Opens in \(item.peer.name)")
        .accessibilityAddTraits(.isButton)
    }

    /// "just now", "12 min ago", "3 h ago", "yesterday".
    static func ago(_ date: Date, now: Date) -> String {
        let s = now.timeIntervalSince(date)
        if s < 90 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if Calendar.current.isDate(date, inSameDayAs: now) || s < 6 * 3600 { return "\(Int(s / 3600)) h ago" }
        let cal = Calendar.current
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "yesterday" }
        return "2 days ago"
    }

    /// Each family app's own accent.
    static func tint(_ peer: WellnessConnect.Peer) -> Color {
        switch peer.scheme {
        case WellnessConnect.rootbound.scheme: return Color(red: 0.45, green: 0.80, blue: 0.45)
        case WellnessConnect.stillPoint.scheme: return Color(red: 0.56, green: 0.64, blue: 1.0)
        case WellnessConnect.roamr.scheme: return Color(red: 1.0, green: 0.58, blue: 0.28)
        default: return Color(red: 1.0, green: 0.42, blue: 0.45)
        }
    }
}
