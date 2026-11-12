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

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting).font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                        Text(log.streak > 1 ? "\(log.streak) days of stillness in a row." : "Take a few slow breaths with me.")
                            .font(SP.rounded(15)).foregroundStyle(SP.dim)
                        Text(DailyThought.today)
                            .font(SP.serif(15).italic()).foregroundStyle(SP.gold.opacity(0.85))
                            .padding(.top, 6)
                        WeekDots(days: log.lastWeek())
                            .padding(.top, 10)
                    }
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                    // A running sauna / steam session jumps to the top so "I'm out" is one tap away.
                    if heat.active != nil { HeatCard() }

                    FeaturedCard(practice: featured)

                    SectionHeader("Your body", detail: "Move, release, breathe")
                    FocusGrid()

                    if heat.active == nil { HeatCard() }

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

                    let favs = prefs.favorites.compactMap { lib.practice($0) }
                    if !favs.isEmpty {
                        SectionHeader("Favorites")
                        PracticeStack(practices: favs)
                    }
                    let recents = prefs.recents.dropFirst().compactMap { lib.practice($0) }
                    if !recents.isEmpty {
                        SectionHeader("Recently")
                        PracticeStack(practices: Array(recents.prefix(4)))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .background(ZStack { DuskBackground(); Fireflies() })
            .onAppear { withAnimation(.easeOut(duration: 0.9)) { appeared = true } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
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

struct SectionHeader: View {
    let title: String
    var detail: String? = nil
    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(SP.serif(22)).foregroundStyle(SP.ink)
            Spacer()
            if let detail { Text(detail).font(SP.rounded(12)).foregroundStyle(SP.faint) }
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
                        Label("Begin · \(mins) min", systemImage: "circle.circle")
                            .font(SP.rounded(16, .medium))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Capsule().fill(SP.goldGlow))
                            .shadow(color: SP.gold.opacity(0.45), radius: 14, y: 4)
                    }
                    .buttonStyle(SoftPress())
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
    var body: some View {
        let t = PracticeLibrary.shared.tradition(practice.traditionId)
        HStack(spacing: 14) {
            ZStack {
                let tint = practice.focus?.tint ?? t?.tint ?? SP.teal
                Circle().fill(tint.opacity(0.16))
                Image(systemName: practice.focus?.symbol ?? (practice.pattern == nil ? "circle.dotted" : "wind"))
                    .font(.system(size: 17, weight: .light)).foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(practice.title).font(SP.serif(18)).foregroundStyle(SP.ink).lineLimit(1)
                Text([t?.name, practice.level].compactMap { $0 }.joined(separator: " · "))
                    .font(SP.rounded(12)).foregroundStyle(SP.faint).lineLimit(1)
            }
            Spacer()
            if let p = practice.pattern { Text(p.shortLabel).font(SP.rounded(12)).foregroundStyle(SP.dim) }
            if PracticeLibrary.shared.isLocked(practice) { ProLockBadge(tint: SP.gold) }
            PracticeInfoButton(practice: practice, size: 16)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(SP.faint)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SP.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SP.stroke, lineWidth: 1))
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
