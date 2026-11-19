import SwiftUI

/// Home's lead card: what Rootbound is for. Real tree hugs, timed on Apple Watch with your heart rate settling,
/// pinned on your own tree map, each tree with a name, a species and a friendship that grows.
/// New users get the three steps; after the first hug it shows this week, the calm from the last timed hug and
/// the last tree.
struct HugSignatureCard: View {
    let hugs: [Hug]
    var logHug: () -> Void
    var openMap: () -> Void

    private var weekHugs: [Hug] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return hugs.filter { $0.date >= start }
    }
    /// The newest hug with heart data from the Watch (start and end heart rate).
    private var lastTimed: Hug? { hugs.first { $0.hrDrop != nil } }
    private var mappedTrees: Int { Set(hugs.filter { $0.coordinate != nil }.map(\.treeID)).count }

    var body: some View {
        RBCard(tint: Theme.glow) {
            if hugs.isEmpty { firstSteps } else { summary }
        }
    }

    // MARK: New user

    private var firstSteps: some View {
        VStack(alignment: .leading, spacing: RB.l) {
            VStack(alignment: .leading, spacing: RB.xs) {
                Text("Hug a real tree")
                    .font(RB.text(.title3, .bold)).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("Rootbound logs the time you spend holding a tree, and how your body settles while you do.")
                    .font(RB.text(.subheadline)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            step("applewatch", "Time it on your Watch",
                 "Live heart rate while you hold the tree, and the drop from start to finish when you let go.")
            step("map.fill", "Pin it on your tree map",
                 "Every tree you hug gets a pin, so you can find your way back.")
            step("leaf.fill", "Get to know the tree",
                 "Give it a name, see a suggested species and a fact, and grow your friendship hug by hug.")
            Button(action: logHug) { Label("Log your first hug", systemImage: "heart.fill") }
                .buttonStyle(RBPrimaryButtonStyle())
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: RB.m) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.forestDeep)
                .frame(width: 36, height: 36)
                .background(Theme.glow, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                Text(detail).font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Returning user

    private var summary: some View {
        VStack(alignment: .leading, spacing: RB.m) {
            Label("Your tree hugs", systemImage: "heart.fill")
                .font(RB.text(.headline, .bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: RB.m) {
                RBMetric(value: "\(weekHugs.count)", label: "This week")
                RBMetric(value: calmValue, label: calmLabel, tint: lastTimed == nil ? Theme.textDim : Theme.glow)
                RBMetric(value: "\(mappedTrees)", label: mappedTrees == 1 ? "Tree on your map" : "Trees on your map")
            }
            if let last = hugs.first {
                HStack(spacing: RB.m) {
                    RBPhotoView(data: last.treePhoto ?? last.selfiePhoto, points: 48)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: RB.inner, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(last.treeName.isEmpty ? "Unnamed tree" : last.treeName)
                            .font(RB.text(.subheadline, .bold)).foregroundStyle(.white)
                            .lineLimit(2)
                        Text(lastLine(last))
                            .font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if lastTimed == nil {
                Label("Start a hug from Rootbound on your Apple Watch to see your heart rate settle.", systemImage: "applewatch")
                    .font(RB.text(.footnote, .medium)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: openMap) { Label("Open tree map", systemImage: "map.fill") }
                .buttonStyle(RBSecondaryButtonStyle())
                .accessibilityHint("Shows every tree you've hugged on a map")
        }
    }

    private var calmValue: String {
        guard let d = lastTimed?.hrDrop else { return "Not yet" }
        let n = Int(d.rounded())
        return n > 0 ? "−\(n) bpm" : n == 0 ? "Steady" : "+\(-n) bpm"
    }
    private var calmLabel: String { lastTimed == nil ? "Heart rate on Watch" : "Last Watch hug" }

    private func lastLine(_ h: Hug) -> String {
        var parts: [String] = []
        if !h.species.isEmpty { parts.append(h.species) }
        parts.append(Format.day(h.date))
        if let a = h.hrStart, let b = h.hrEnd { parts.append("\(Int(a.rounded())) → \(Int(b.rounded())) bpm") }
        else if h.durationMin > 0 { parts.append(Format.minutes(h.durationMin)) }
        return parts.joined(separator: " · ")
    }
}
