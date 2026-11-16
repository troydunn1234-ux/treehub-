import SwiftUI

struct HomeView: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var router: Router
    @EnvironmentObject var log: SessionLog
    @EnvironmentObject var heat: HeatStore
    private let lib = PracticeLibrary.shared
    @State private var appeared = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Rest well"
        }
    }

    private var featured: Practice {
        if let id = prefs.recents.first, let p = lib.practice(id), !p.isMovement { return p }
        return lib.quickPractice
    }

    /// One-tap short practices (shortest length), the ones people reach for most.
    private var quickStarts: [Practice] {
        ["calm-sos", "sigh", "box", "478", "focus-reset", "resonance"].compactMap { lib.practice($0) }
    }

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: SP.s6) {
                    VStack(alignment: .leading, spacing: SP.s1) {
                        Text(greeting).font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(DailyThought.today)
                            .font(SP.serif(15).italic()).foregroundStyle(SP.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, SP.s2)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                    // Hero: one practice for this moment, from WHOOP / Watch numbers in Health and Pulse Lab.
                    RightNowCard()

                    TodaySummaryCard()

                    // Sauna / steam: one tap as you walk in (shows the live timer while one is running).
                    HeatCard()

                    let favs = prefs.favorites.compactMap { lib.practice($0) }
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Favorites", detail: favs.isEmpty ? nil : "\(favs.count)")
                        if favs.isEmpty {
                            HStack(spacing: SP.s3) {
                                Image(systemName: "heart").font(.system(size: 18, weight: .light)).foregroundStyle(SP.accent)
                                    .frame(width: 40, height: 40).background(Circle().fill(SP.accent.opacity(0.12)))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("No favorites yet").font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink)
                                    Text("Tap the heart on any practice to keep it here.").font(.footnote).foregroundStyle(SP.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Button("Browse") { router.tab = 1 }
                                    .buttonStyle(SPSecondaryButtonStyle())
                            }
                            .spCard(padding: SP.s3)
                        } else {
                            PracticeStack(practices: favs)
                        }
                    }

                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Quick starts", detail: "Begins straight away")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SP.s3) {
                                ForEach(quickStarts) { p in QuickStartTile(practice: p) }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Your body", detail: "Move, release, breathe")
                        FocusGrid()
                    }

                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader("Intentions")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(lib.intentions) { i in
                                    NavigationLink(value: i) { IntentionBubble(intention: i) }
                                        .buttonStyle(SoftPress())
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    let recents = prefs.recents.dropFirst().compactMap { lib.practice($0) }
                    if !recents.isEmpty {
                        VStack(alignment: .leading, spacing: SP.s3) {
                            SectionHeader("Recently")
                            PracticeStack(practices: Array(recents.prefix(4)))
                        }
                    }
                }
                .padding(.horizontal, SP.screenPadding)
                .padding(.bottom, SP.s8)
            }
            .background(ZStack { DuskBackground(); Fireflies() })
            .onAppear { withAnimation(.easeOut(duration: 0.9)) { appeared = true } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Intention.self) { i in IntentionView(intention: i) }
            .navigationDestination(for: Practice.self) { p in PracticeDetailView(practice: p) }
            .navigationDestination(for: Tradition.self) { t in TraditionView(tradition: t) }
            .navigationDestination(for: BodyFocus.self) { f in FocusView(focus: f) }
            .navigationDestination(for: HeatRoute.self) { _ in HeatLogView() }
        }
    }
}

/// Streak, today's minutes and the last seven days, in one quiet card. Taps through to Journey.
struct TodaySummaryCard: View {
    @EnvironmentObject var log: SessionLog
    @EnvironmentObject var router: Router

    var body: some View {
        let week = log.lastWeek()
        let today = week.last?.minutes ?? 0
        Button { router.tab = 2 } label: {
            VStack(alignment: .leading, spacing: SP.s3) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SP.s4) { streak; Divider().frame(height: 36).overlay(SP.stroke); minutes(today); Spacer(minLength: 0); chevron }
                    VStack(alignment: .leading, spacing: SP.s3) { streak; minutes(today) }
                }
                WeekDots(days: week)
                Text(log.streakLine).font(.footnote).foregroundStyle(SP.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .spCard()
            .contentShape(RoundedRectangle(cornerRadius: SP.radius, style: .continuous))
        }
        .buttonStyle(SoftPress())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your journey")
    }

    private var streak: some View {
        HStack(spacing: SP.s2) {
            Image(systemName: log.streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 20))
                .foregroundStyle(log.streak > 0 ? AnyShapeStyle(SP.goldGlow) : AnyShapeStyle(SP.faint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(log.streak)").font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(SP.ink).contentTransition(.numericText())
                Text("day streak").font(.caption).foregroundStyle(SP.faint)
            }
        }
    }

    private func minutes(_ m: Double) -> some View {
        HStack(spacing: SP.s2) {
            Image(systemName: "clock").font(.system(size: 18)).foregroundStyle(SP.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(m.rounded()))").font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(SP.ink).contentTransition(.numericText())
                Text("minutes today").font(.caption).foregroundStyle(SP.faint)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(SP.faint).accessibilityHidden(true)
    }
}

/// A small one-tap start: icon, name, shortest length.
struct QuickStartTile: View {
    let practice: Practice
    @EnvironmentObject var router: Router
    @State private var taps = 0

    var body: some View {
        let lib = PracticeLibrary.shared
        let tint = lib.tradition(practice.traditionId)?.tint ?? SP.teal
        let mins = practice.minutes.min() ?? practice.defaultMinutes
        Button {
            taps += 1
            router.handle(practiceId: practice.id, minutes: mins)
        } label: {
            VStack(alignment: .leading, spacing: SP.s2) {
                HStack {
                    Image(systemName: practice.pattern == nil ? "circle.dotted" : "wind")
                        .font(.system(size: 16)).foregroundStyle(tint)
                        .frame(width: 34, height: 34).background(Circle().fill(tint.opacity(0.16)))
                    Spacer(minLength: 0)
                    if lib.isLocked(practice) { ProLockBadge(tint: SP.gold) }
                    else { Image(systemName: "play.fill").font(.caption).foregroundStyle(SP.accent) }
                }
                Text(practice.title).font(.subheadline.weight(.semibold)).foregroundStyle(SP.ink)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(mins) min").font(.footnote).monospacedDigit().foregroundStyle(SP.faint)
            }
            .padding(SP.s3)
            .frame(width: 148, height: 132, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).fill(SP.card))
            .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        }
        .buttonStyle(SoftPress())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel("Start \(practice.title), \(mins) minutes")
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(SP.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail { Text(detail).font(.footnote).foregroundStyle(SP.faint).multilineTextAlignment(.trailing) }
        }
    }
}

/// The big calm "Begin" card.
struct FeaturedCard: View {
    let practice: Practice
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var link: PhoneLink
    @State private var beginTaps = 0

    var body: some View {
        let t = PracticeLibrary.shared.tradition(practice.traditionId)
        let mins = practice.minutes.contains(prefs.settings.defaultMinutes) ? prefs.settings.defaultMinutes : practice.defaultMinutes
        ZStack(alignment: .bottomLeading) {
            PaintedScene(kind: t?.scene ?? .water, tint: t?.tint ?? SP.teal)
            LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            BreathOrb(scale: 0.8, phase: .still, accent: t?.tint)
                .frame(width: 120, height: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
            VStack(alignment: .leading, spacing: 8) {
                Text((t?.name ?? "Breathe").uppercased()).font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.ink.opacity(0.75))
                Text(practice.title).font(SP.serif(30, .light)).foregroundStyle(SP.ink)
                HStack(spacing: 10) {
                    Button {
                        beginTaps += 1
                        router.run(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: practice, minutes: mins))
                    } label: {
                        Label("Begin · \(mins) min", systemImage: "play.fill")
                    }
                    .buttonStyle(SPPrimaryButtonStyle(fullWidth: false))
                    .sensoryFeedback(.impact(weight: .light), trigger: beginTaps)
                    if link.canUseWatch {
                        Button {
                            link.startOnWatch(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: practice, minutes: mins)) { _ in }
                        } label: {
                            Image(systemName: "applewatch")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(SP.ink)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .accessibilityLabel("Start on Apple Watch")
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: (t?.tint ?? SP.teal).opacity(0.25), radius: 30, y: 12)
    }
}

struct IntentionBubble: View {
    let intention: Intention
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: intention.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(SP.teal)
                .frame(width: 66, height: 66)
                .background(Circle().fill(RadialGradient(colors: [SP.teal.opacity(0.22), SP.teal.opacity(0.04)], center: .center, startRadius: 2, endRadius: 40)))
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            Text(intention.name).font(SP.rounded(13)).foregroundStyle(SP.ink).lineLimit(1)
        }
        .frame(width: 78)
    }
}

struct MiniCard: View {
    let practice: Practice
    var body: some View {
        let t = PracticeLibrary.shared.tradition(practice.traditionId)
        VStack(alignment: .leading, spacing: 0) {
            PaintedScene(kind: t?.scene ?? .mist, tint: t?.tint ?? SP.teal).frame(height: 90)
                .overlay(alignment: .topTrailing) {
                    if PracticeLibrary.shared.isLocked(practice) { ProLockBadge(tint: SP.gold).padding(8) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(practice.title).font(SP.serif(16)).foregroundStyle(SP.ink).lineLimit(2)
                Text("\(practice.minutes.map { String($0) }.joined(separator: " / ")) min")
                    .font(SP.rounded(12)).foregroundStyle(SP.faint)
            }
            .padding(12)
        }
        .frame(width: 180, alignment: .leading)
        .background(SP.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SP.stroke, lineWidth: 1))
    }
}

/// Vertical list of practice rows.
struct PracticeStack: View {
    let practices: [Practice]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(practices) { p in
                NavigationLink(value: p) { PracticeCardRow(practice: p) }.buttonStyle(SoftPress())
            }
        }
    }
}

struct PracticeCardRow: View {
    let practice: Practice
    @ObservedObject private var log = SessionLog.shared
    var body: some View {
        let lib = PracticeLibrary.shared
        let t = lib.tradition(practice.traditionId)
        let tint = practice.focus?.tint ?? t?.tint ?? SP.teal
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: practice.focus?.symbol ?? (practice.pattern == nil ? "circle.dotted" : "wind"))
                    .font(.system(size: 17, weight: .light)).foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(practice.title).font(.body.weight(.semibold)).foregroundStyle(SP.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if lib.isLocked(practice) { ProLockBadge(tint: SP.gold) }
                }
                if !practice.tagline.isEmpty {
                    Text(practice.tagline).font(.subheadline).foregroundStyle(SP.ink.opacity(0.75))
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                SPFlow(spacing: 10) {
                    Label(practice.minutesLabel, systemImage: "clock").monospacedDigit()
                    Label(practice.levelLabel, systemImage: "chart.bar")
                    if let name = t?.name { Text(name) }
                }
                .font(.caption).foregroundStyle(SP.faint)
                .labelStyle(SPCompactLabel())
                if log.worksBest().contains(practice.id) {
                    Label("Works best for you", systemImage: "arrow.down.heart.fill")
                        .font(SP.rounded(12, .semibold)).foregroundStyle(SP.rose)
                }
            }
            VStack(spacing: 10) {
                PracticeInfoButton(practice: practice, size: 16)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(SP.faint)
            }
        }
        .spCard(padding: 14)
    }
}

/// Icon + title with tight spacing, for meta rows.
struct SPCompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title }
    }
}

struct IntentionView: View {
    let intention: Intention
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: intention.symbol).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(SP.teal)
                Text(intention.name).font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                PracticeStack(practices: PracticeLibrary.shared.practices(for: intention))
            }
            .padding(22)
        }
        .background(DuskBackground())
        .navigationBarTitleDisplayMode(.inline)
    }
}
