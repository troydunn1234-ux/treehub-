import SwiftUI
import UIKit

// Walks under tree hugs: synced from Roamr (or any app's walk in Apple Health). Rootbound itself no longer records them.

/// Multi-select sheet: which walks / hikes go with this hug (overlapping it or within ±2 h).
@MainActor
struct WalkPickerSheet: View {
    let around: Date
    let candidates: [LinkedWalk]
    @State var selected: Set<UUID>
    var onDone: ([LinkedWalk]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { w in
                        Button { toggle(w) } label: { row(w) }
                            .listRowBackground(Theme.card)
                    }
                } header: {
                    Text("Within 2 hours of \(around.formatted(date: .omitted, time: .shortened))")
                } footer: {
                    Text("Checked walks show under this hug and count toward the tree's miles.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ForestBackground())
            .navigationTitle("Walks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Attach none" : "Attach \(selected.count)") {
                        onDone(candidates.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ w: LinkedWalk) {
        if selected.contains(w.id) { selected.remove(w.id) } else { selected.insert(w.id) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func row(_ w: LinkedWalk) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected.contains(w.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected.contains(w.id) ? Theme.glow : Theme.textDim)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.summary).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                Text(LinkedWalkCard.timeRange(w) + " · " + w.source)
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
            Image(systemName: w.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.glow)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected.contains(w.id) ? .isSelected : [])
    }
}

/// One walk under a hug: "Walk · 2.3 mi · 48 min · +410 ft", then its numbers.
struct LinkedWalkCard: View {
    let walk: LinkedWalk
    var compact = false

    static func timeRange(_ w: LinkedWalk) -> String {
        let day = Calendar.current.isDateInToday(w.start) ? "" : w.start.formatted(.dateTime.month(.abbreviated).day()) + ", "
        return day + "\(w.start.formatted(date: .omitted, time: .shortened))–\(w.end.formatted(date: .omitted, time: .shortened))"
    }

    private var metrics: [(String, String)] {
        var m: [(String, String)] = []
        if walk.distanceM > 0 { m.append((walk.distanceText, "Distance")) }
        m.append((walk.timeText, "Time"))
        if let c = walk.climbText { m.append((c, "Climb")) }
        if walk.distanceM > 20 {
            m.append((Format.paceOrSpeed(distance: walk.distanceM, seconds: walk.seconds, kind: .walk), "Avg pace"))
        }
        if let v = walk.topSpeed { m.append((Format.speed(v), "Top speed")) }
        if let v = walk.avgHR { m.append(("\(Int(v.rounded()))", "Avg bpm")) }
        return m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: walk.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.glow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(walk.summary).font(Theme.rounded(16, .bold)).foregroundStyle(.white)
                    Text(Self.timeRange(walk) + " · " + walk.source)
                        .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
            }
            if !compact {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(metrics, id: \.1) { m in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.0).font(Theme.rounded(17, .bold)).foregroundStyle(.white).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(m.1).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.textDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                if walk.fromRoamr { OpenInRoamrButton(tripID: walk.id) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// roamr://trip?id=… when Roamr is installed, else its App Store page.
struct OpenInRoamrButton: View {
    var tripID: UUID? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if WellnessLinks.roamrInstalled {
                var c = URLComponents()
                c.scheme = "roamr"
                if let tripID {
                    c.host = "trip"
                    c.queryItems = [URLQueryItem(name: "id", value: tripID.uuidString)]
                } else {
                    c.host = "history"
                }
                WellnessLinks.open(c.url ?? WellnessLinks.roamrHome)
            } else if let u = WellnessLinks.storeURL(bundleID: WellnessLinks.roamrBundleID) {
                openURL(u)
            }
        } label: {
            Label(WellnessLinks.roamrInstalled ? "Open in Roamr" : "Get Roamr", systemImage: "location.north.circle.fill")
                .font(Theme.rounded(13, .bold))
                .foregroundStyle(Theme.glow)
        }
        .buttonStyle(.plain)
    }
}

/// "Sync Roamr": the button style used on Home and in the hug logger.
struct SyncRoamrLabel: View {
    var busy = false
    var title = "Sync Roamr"

    var body: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(Theme.glow) }
            else { Image(systemName: "arrow.triangle.2.circlepath") }
            Text(busy ? "Syncing…" : title)
        }
        .font(Theme.rounded(15, .bold))
        .lineLimit(1).minimumScaleFactor(0.75)
        .foregroundStyle(Theme.glow)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Theme.glow.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Shown when Roamr isn't installed (or hasn't shared yet): what it does and where to get it.
struct GetRoamrCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.forestDeep)
                .frame(width: 42, height: 42)
                .background(Theme.leafGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Record walks with Roamr").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                Text("Your walks and hikes land under the hugs they passed. Walks other apps save to Apple Health count too.")
                    .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let u = WellnessLinks.storeURL(bundleID: WellnessLinks.roamrBundleID) {
                Button("Get") { openURL(u) }
                    .font(Theme.rounded(14, .heavy))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.glow, in: Capsule())
                    .foregroundStyle(Theme.forestDeep)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A tree's page: the walks that brought you to it.
struct TreeWalksCard: View {
    let hugs: [Hug]

    var body: some View {
        let walks = GameEngine.uniqueWalks(hugs).sorted { $0.start > $1.start }
        if !walks.isEmpty {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Walks", symbol: "figure.walk")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        StatTile(value: LinkedWalk.distance(walks.reduce(0) { $0 + $1.distanceM }), label: "\(walks.count) walk\(walks.count == 1 ? "" : "s")")
                        StatTile(value: Format.minutes((walks.reduce(0) { $0 + $1.seconds } / 60).rounded()), label: "Walking")
                        StatTile(value: "+" + Format.elevation(walks.reduce(0) { $0 + $1.elevGainM }), label: "Climbed")
                    }
                    ForEach(walks.prefix(10)) { w in LinkedWalkCard(walk: w, compact: true) }
                }
            }
        }
    }
}

/// Settings › Past strolls: walks recorded in Rootbound before walks moved to Roamr. Read-only history.
struct PastStrollsView: View {
    let activities: [Activity]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Walks Rootbound recorded before they moved to Roamr. New walks come from Roamr and show under your hugs.")
                    .font(Theme.rounded(13, .medium)).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(activities) { a in
                    NavigationLink { ActivityDetailView(activity: a) } label: { ActivityRow(activity: a) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 12)
        }
        .forestScreen()
        .navigationTitle("Past strolls")
        .navigationBarTitleDisplayMode(.inline)
    }
}
