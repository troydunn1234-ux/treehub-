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
                    Text("SYNCING")
                } else if let t = store.lastPull {
                    Circle().fill(Lab.good).frame(width: 5, height: 5).shadow(color: Lab.good, radius: 3)
                    Text("SYNCED " + Self.ago(t, now: ctx.date))
                } else {
                    Circle().fill(Lab.faint).frame(width: 5, height: 5)
                    Text("NOT SYNCED")
                }
            }
            .font(Lab.label(9)).tracking(1.2)
            .foregroundStyle(Lab.dim)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    static func ago(_ t: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(t)))
        if s < 60 { return "JUST NOW" }
        if s < 3600 { return "\(s / 60)M AGO" }
        if s < 86_400 { return "\(s / 3600)H AGO" }
        return "\(s / 86_400)D AGO"
    }
}

// MARK: - Skeleton

/// Shimmering placeholder cards while the first pull runs.
struct SkeletonStack: View {
    var body: some View {
        VStack(spacing: 16) {
            SkeletonCard(height: 190)
            SkeletonCard(height: 230)
            SkeletonCard(height: 140)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your data")
    }
}

struct SkeletonCard: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Lab.panel.opacity(0.8))
            .frame(height: height)
            .overlay(
                VStack(alignment: .leading, spacing: 12) {
                    bar(90); bar(180); bar(140); Spacer(); bar(220)
                }
                .padding(18), alignment: .topLeading
            )
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
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
                             button: "Sync now", tint: Lab.violet) {
            Task { await store.refresh() }
        }
    }

    var body: some View {
        LabPanel(tint: tint) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.14)).frame(width: 74, height: 74)
                    Image(systemName: icon).font(.system(size: 30, weight: .bold)).foregroundStyle(tint)
                        .shadow(color: tint.opacity(0.7), radius: 10)
                }
                Text(title).font(Lab.display(20, .heavy)).foregroundStyle(Lab.text)
                Text(message).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                if let button, let action {
                    Button(action: action) {
                        Text(button).font(Lab.display(15, .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(tint.opacity(0.2)))
                            .overlay(Capsule().strokeBorder(tint.opacity(0.5)))
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
                    Text(t).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Lab.text)
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

    private var tint: Color { insight.source.map(Lab.color) ?? Lab.violet }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let onSelect { onSelect(insight) } else { store.go(insight.tab, metric: insight.metric) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: insight.icon).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Lab.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.detail).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(Lab.faint)
                    .padding(.top, 4)
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
        LabPanel(tint: Lab.violet) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "flask.fill").foregroundStyle(Lab.violet)
                    SectionTag("Lab notes", color: Lab.text)
                    Spacer()
                    if insights.count > 3 {
                        Button("SEE ALL \(insights.count)") { showAll = true }
                            .font(Lab.label(10)).foregroundStyle(Lab.watch)
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
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.07)))
                        }
                        .accessibilityLabel("Close")
                    }
                    ForEach(insights) { ins in
                        LabPanel(tint: ins.source.map(Lab.color) ?? Lab.violet) {
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

/// Small "winner" chip: 👑 WATCH STEADIER / 👑 WHOOP HIGHER.
struct CrownChip: View {
    let source: Source
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill").font(.system(size: 9, weight: .heavy))
            Text("\(source.short) \(label)").font(Lab.label(8)).tracking(1)
        }
        .foregroundStyle(Lab.color(source))
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(Lab.color(source).opacity(0.13)))
        .overlay(Capsule().strokeBorder(Lab.color(source).opacity(0.35)))
        .accessibilityLabel("\(source.name) \(label.lowercased())")
    }
}

// MARK: - Streak chip

struct StreakChip: View {
    let days: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link").font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing))
            Text("\(days)-DAY DOUBLE-WEAR STREAK").font(Lab.label(9)).tracking(1.2).foregroundStyle(Lab.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.6), Lab.whoop.opacity(0.6)], startPoint: .leading, endPoint: .trailing)))
        .accessibilityLabel("\(days) day streak wearing both trackers")
    }
}

// MARK: - Glow border (hero)

/// A slow breathing glow around a card. Static under Reduce Motion.
struct BreathingGlow: ViewModifier {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AngularGradient(colors: colors + [colors.first ?? .clear], center: .center), lineWidth: 1.5)
                    .opacity(on ? 0.9 : 0.35)
                    .blur(radius: on ? 0.5 : 0)
                    .allowsHitTesting(false)
            )
            .shadow(color: (colors.first ?? .clear).opacity(on ? 0.28 : 0.1), radius: on ? 22 : 12)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

extension View {
    func breathingGlow(_ colors: [Color]) -> some View { modifier(BreathingGlow(colors: colors)) }
}
