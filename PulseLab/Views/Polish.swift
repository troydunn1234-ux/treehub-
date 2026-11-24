import SwiftUI

// MARK: - Sync pill

/// "SYNCED 3M AGO" next to each screen title; spins while a pull is running.
struct SyncPill: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HStack(spacing: 5) {
                if store.loading {
                    ProgressView().controlSize(.mini).tint(Lab.watch)
                    Text("Syncing…")
                } else if let t = store.lastPull {
                    Circle().fill(Lab.good).frame(width: 6, height: 6)
                    Text("Synced " + Self.ago(t, now: ctx.date))
                } else {
                    Circle().fill(Lab.faint).frame(width: 6, height: 6)
                    Text("Not synced")
                }
            }
            .font(.system(size: Lab.scaled(11), weight: .medium))
            .foregroundStyle(Lab.dim)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Lab.inset))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    static func ago(_ t: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(t)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }
}

// MARK: - Skeleton

/// Shimmering placeholder cards while the first pull runs.
struct SkeletonStack: View {
    var body: some View {
        VStack(spacing: 16) {
            // Shaped like the Today hero: lines on the left, the score ring on the right.
            SkeletonCard(height: 210, ring: true)
            SkeletonCard(height: 230)
            SkeletonCard(height: 140)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your data")
    }
}

struct SkeletonCard: View {
    let height: CGFloat
    /// A ring placeholder top-right (the Today hero's score ring).
    var ring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: Lab.radius, style: .continuous)
            .fill(Lab.panel)
            .frame(height: height)
            .overlay(
                VStack(alignment: .leading, spacing: 12) {
                    bar(90); bar(180); bar(140); Spacer(); bar(220)
                }
                .padding(18), alignment: .topLeading
            )
            .overlay(alignment: .topTrailing) {
                if ring {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 8)
                        .frame(width: 80, height: 80)
                        .padding(22)
                }
            }
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.4)
                }
                .clipShape(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous))
                .allowsHitTesting(false)
            )
            .overlay(RoundedRectangle(cornerRadius: Lab.radius, style: .continuous).strokeBorder(Lab.line))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }

    private func bar(_ w: CGFloat) -> some View {
        Capsule().fill(Color.white.opacity(0.07)).frame(width: w, height: 10)
    }
}

// MARK: - Empty states

struct LabEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let button: String?
    let tint: Color
    let action: (() -> Void)?

    @MainActor
    static func forStore(_ store: LabStore) -> LabEmptyState {
        if !store.healthAsked {
            return LabEmptyState(icon: "heart.text.square.fill", title: "Connect Apple Health",
                                 message: "Pulse Lab reads your Apple Watch data from Health (and anything WHOOP saves there). Nothing leaves your iPhone.",
                                 button: "Connect Apple Health", tint: Lab.watch) {
                Task { await store.connectHealth() }
            }
        }
        if !store.whoopConnected {
            return LabEmptyState(icon: "bolt.heart.fill", title: "No data yet",
                                 message: "Health didn't return anything yet. Wear your Watch for a day, check Settings → Health → Data Access → Pulse Lab, or connect WHOOP for the other half of the duel.",
                                 button: "Connect WHOOP", tint: Lab.whoop) {
                store.go(.settings)
            }
        }
        return LabEmptyState(icon: "hourglass", title: "Not enough days yet",
                             message: "Both trackers are connected. Comparisons fill in after a night or two of wearing both.",
                             button: "Sync now", tint: Lab.accent) {
            Task { await store.refresh() }
        }
    }

    var body: some View {
        LabPanel(tint: tint) {
            VStack(spacing: Lab.S.sm) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(tint.opacity(0.14)))
                    .accessibilityHidden(true)
                Text(L(title)).font(.title3.weight(.bold)).foregroundStyle(Lab.text)
                    .multilineTextAlignment(.center)
                Text(L(message)).font(.subheadline).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let button, let action {
                    Button(action: action) { Text(L(button)) }
                        .buttonStyle(LabPrimaryButton())
                        .padding(.top, Lab.S.xs)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Lab.S.s)
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        Group {
            if let t = store.toast {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Lab.warn)
                    Text(t).font(.footnote.weight(.semibold)).foregroundStyle(Lab.text)
                        .lineLimit(3)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Lab.warn.opacity(0.4)))
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation { store.toast = nil } }
                .task(id: t) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { store.toast = nil }
                }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: store.toast)
    }
}

// MARK: - Lab notes

struct InsightRow: View {
    let insight: Insight
    /// When set (e.g. inside a sheet), called instead of navigating directly.
    var onSelect: ((Insight) -> Void)? = nil
    @Environment(LabStore.self) private var store

    private var tint: Color { insight.source.map(Lab.color) ?? Lab.accent }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let onSelect { onSelect(insight) } else { store.go(insight.tab, metric: insight.metric) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.15)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title).font(.subheadline.weight(.semibold)).foregroundStyle(Lab.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.detail).font(.footnote).foregroundStyle(Lab.dim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Lab.faint)
                    .padding(.top, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the related chart")
    }
}

/// Top Lab notes on Today, with "See all".
struct LabNotesCard: View {
    let insights: [Insight]
    @State private var showAll = false

    var body: some View {
        LabPanel(tint: Lab.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTag("Lab notes")
                    Spacer()
                    if insights.count > 3 {
                        Button("See all \(insights.count)") { showAll = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Lab.accent)
                            .frame(minHeight: 44)
                    }
                }
                if insights.isEmpty {
                    EmptyNote(text: "Notes appear once both trackers have a few days of overlap.")
                } else {
                    ForEach(Array(insights.prefix(3).enumerated()), id: \.element.id) { i, ins in
                        if i > 0 { Divider().overlay(Lab.line) }
                        InsightRow(insight: ins)
                    }
                }
            }
        }
        .sheet(isPresented: $showAll) { AllNotesSheet(insights: insights) }
    }
}

struct AllNotesSheet: View {
    let insights: [Insight]
    @Environment(\.dismiss) private var dismiss
    @Environment(LabStore.self) private var store

    var body: some View {
        ZStack {
            LabBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ScreenTitle(kicker: "Findings", title: "Lab notes")
                        CloseButton { dismiss() }
                    }
                    ForEach(insights) { ins in
                        LabPanel(tint: ins.source.map(Lab.color) ?? Lab.accent) {
                            InsightRow(insight: ins) { picked in
                                dismiss()
                                // Let this sheet finish closing before another one opens.
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(450))
                                    store.go(picked.tab, metric: picked.metric)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .presentationBackground(Lab.bg)
    }
}

// MARK: - Crown chip

/// Small "winner" chip: 👑 Watch steadier / 👑 WHOOP reads higher. `label` arrives localized.
struct CrownChip: View {
    let source: Source
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill").font(.caption2.weight(.semibold))
            Text(verbatim: "\(source.label) \(label)").font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Lab.color(source))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Lab.color(source).opacity(0.14)))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(source.name) \(label)"))
    }
}

// MARK: - Streak chip

struct StreakChip: View {
    let days: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link").font(.footnote.weight(.semibold)).foregroundStyle(Lab.dim)
            Text("\(days)-day double-wear streak").font(.footnote.weight(.semibold)).foregroundStyle(Lab.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Lab.panel))
        .overlay(Capsule().strokeBorder(Lab.line))
        .accessibilityLabel("\(days) day streak wearing both trackers")
    }
}

/// Round close button for sheets (44 pt hit target).
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Lab.dim)
                .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.10)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}
