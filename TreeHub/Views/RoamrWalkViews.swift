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
                            .listRowBackground(RB.cardFill)
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
                Text(w.summary).font(RB.text(.headline, .bold)).foregroundStyle(.white)
                Text(LinkedWalkCard.timeRange(w) + " · " + w.source)
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
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
        VStack(alignment: .leading, spacing: RB.m) {
            HStack(alignment: .center, spacing: RB.m) {
                Image(systemName: walk.symbol)
                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.glow)
                    .frame(width: 36, height: 36)
                    .background(Theme.glow.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(walk.summary).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                    Text(Self.timeRange(walk) + " · " + walk.source)
                        .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
            }
            if !compact {
                RBGrid(minimum: 92) {
                    ForEach(metrics, id: \.1) { m in RBMetric(value: m.0, label: m.1) }
                }
                if walk.fromRoamr { OpenInRoamrButton(tripID: walk.id) }
            }
        }
        .padding(RB.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbInner()
        .accessibilityElement(children: .contain)
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
                .font(RB.text(.footnote, .bold))
                .foregroundStyle(Theme.glow)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
        .font(RB.text(.subheadline, .bold))
        .lineLimit(2)
        .foregroundStyle(Theme.glow)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Theme.glow.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Shown when Roamr isn't installed (or hasn't shared yet): what it does and where to get it.
struct GetRoamrCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: RB.m) {
            Image(systemName: "location.north.circle.fill")
                .font(.title3.weight(.bold)).foregroundStyle(Theme.forestDeep)
                .frame(width: 44, height: 44)
                .background(Theme.leafGradient, in: RoundedRectangle(cornerRadius: RB.inner, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Record walks with Roamr").font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                Text("Your walks and hikes land under the hugs they passed. Walks other apps save to Apple Health count too.")
                    .font(RB.text(.caption)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let u = WellnessLinks.storeURL(bundleID: WellnessLinks.roamrBundleID) {
                Button("Get") { openURL(u) }
                    .font(RB.text(.subheadline, .heavy))
                    .padding(.horizontal, RB.l)
                    .frame(minHeight: 36)
                    .background(Theme.glow, in: Capsule())
                    .foregroundStyle(Theme.forestDeep)
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Get Roamr on the App Store")
            }
        }
        .padding(RB.m)
        .rbInner()
    }
}

/// A tree's page: the walks that brought you to it.
struct TreeWalksCard: View {
    let hugs: [Hug]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let walks = GameEngine.uniqueWalks(hugs).sorted { $0.start > $1.start }
        if !walks.isEmpty {
            RBCard {
                VStack(alignment: .leading, spacing: RB.m) {
                    RBSectionTitle(title: "Walks", symbol: "figure.walk")
                    LazyVGrid(columns: rbColumns(3, typeSize), spacing: RB.s) {
                        RBStatTile(value: LinkedWalk.distance(walks.reduce(0) { $0 + $1.distanceM }), label: "\(walks.count) walk\(walks.count == 1 ? "" : "s")")
                        RBStatTile(value: Format.minutes((walks.reduce(0) { $0 + $1.seconds } / 60).rounded()), label: "Walking")
                        RBStatTile(value: "+" + Format.elevation(walks.reduce(0) { $0 + $1.elevGainM }), label: "Climbed")
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
                    .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
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
