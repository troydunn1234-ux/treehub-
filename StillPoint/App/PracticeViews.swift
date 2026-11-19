import SwiftUI
import Charts

/// The library: search, goal tabs (Healing, Calm & Anxiety, Sleep…), favorites and recents, and the traditions.
struct TraditionsView: View {
    @EnvironmentObject var prefs: Prefs
    @ObservedObject private var log = SessionLog.shared
    @State private var query = ""
    @State private var tab: String = LibraryTab.traditions
    @State private var sort: LibrarySort = .suggested
    private let lib = PracticeLibrary.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library").font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                        Text("\(lib.practices.count) practices from \(lib.traditions.count) traditions, each with what it does and how.")
                            .font(SP.rounded(15)).foregroundStyle(SP.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, SP.screenPadding)

                    LibraryTabBar(selection: $tab)

                    Group {
                        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            searchResults
                        } else if tab == LibraryTab.traditions {
                            traditionsHome
                        } else if tab == LibraryTab.all {
                            categoryPage(nil)
                        } else if let c = lib.category(tab) {
                            categoryPage(c)
                        }
                    }
                    .padding(.horizontal, SP.screenPadding)
                    .animation(.easeInOut(duration: 0.25), value: tab)
                }
                .padding(.bottom, SP.s8)
            }
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search: sleep, anxiety, box, 5 min…"))
            .background(DuskBackground())
            .navigationDestination(for: Tradition.self) { t in TraditionView(tradition: t) }
            .navigationDestination(for: Practice.self) { p in PracticeDetailView(practice: p) }
        }
    }

    // MARK: Search

    private var searchResults: some View {
        let found = searchMatches
        return VStack(alignment: .leading, spacing: 12) {
            if found.isEmpty {
                SPEmptyState(symbol: "magnifyingglass", title: String(localized: "No practices match"),
                             hint: String(localized: "Try a feeling (stress, sleep) or a length (3 min)."),
                             actionTitle: String(localized: "Clear search")) { query = "" }
                    .spCard()
            } else {
                Text(String(localized: "\(found.count) matching practices"))
                    .font(.footnote).foregroundStyle(SP.dim)
                PracticeStack(practices: found)
            }
        }
    }

    /// Words plus "3 min" style lengths.
    private var searchMatches: [Practice] {
        var q = query.lowercased()
        var maxMinutes: Int? = nil
        if let r = q.range(of: #"(\d+)\s*(min|mins|minutes|minute|m)\b"#, options: .regularExpression) {
            maxMinutes = Int(q[r].filter(\.isNumber))
            q.removeSubrange(r)
        }
        var list = q.trimmingCharacters(in: .whitespaces).isEmpty ? lib.practices : lib.search(q)
        if let m = maxMinutes { list = list.filter { ($0.minutes.min() ?? 99) <= m } }
        return list
    }

    // MARK: Traditions tab (with favorites, recents, works best)

    private var traditionsHome: some View {
        VStack(alignment: .leading, spacing: 22) {
            let favs = prefs.favorites.compactMap { lib.practice($0) }
            if !favs.isEmpty { section(String(localized: "Favorites"), "heart.fill", favs.prefix(5).map { $0 }) }
            let recent = prefs.recents.compactMap { lib.practice($0) }.filter { p in !favs.prefix(5).contains(p) }
            if !recent.isEmpty { section(String(localized: "Recently used"), "clock.arrow.circlepath", Array(recent.prefix(4))) }
            let best = log.worksBest().compactMap { lib.practice($0) }
            if !best.isEmpty {
                section(String(localized: "Works best for you"), "arrow.down.heart.fill", best,
                        note: String(localized: "Your biggest average heart-rate drops (3+ sessions)."))
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(String(localized: "Traditions"), "globe.asia.australia")
                ForEach(lib.traditions) { t in
                    NavigationLink(value: t) { TraditionRow(tradition: t) }.buttonStyle(SoftPress())
                }
            }
        }
    }

    private func section(_ title: String, _ icon: String, _ ps: [Practice], note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title, icon)
            if let note { Text(note).font(SP.rounded(12)).foregroundStyle(SP.faint) }
            PracticeStack(practices: ps)
        }
    }

    private func sectionTitle(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline).foregroundStyle(SP.ink)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: A goal tab

    private func categoryPage(_ c: PracticeCategory?) -> some View {
        let base = c.map { lib.practices(inCategory: $0.id) } ?? lib.practices
        let list = sorted(base)
        let tint = c.map { Color(spHex: $0.color) } ?? SP.accent
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: c?.symbol ?? "books.vertical.fill").font(.system(size: 22, weight: .light)).foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(c?.localizedName ?? String(localized: "All practices")).font(SP.serif(26, .light)).foregroundStyle(SP.ink)
                }
                Text(c?.localizedSummary ?? String(localized: "Everything in the library, from 1-minute resets to 30-minute sits."))
                    .font(SP.rounded(15)).foregroundStyle(SP.dim).fixedSize(horizontal: false, vertical: true)
                if let n = c?.localizedNote {
                    Label(n, systemImage: "info.circle").font(SP.rounded(13)).foregroundStyle(SP.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("\(list.count) practices").font(SP.rounded(13)).foregroundStyle(SP.faint)
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(LibrarySort.allCases) { s in Text(s.title).tag(s) }
                        }
                    } label: {
                        Label(sort.title, systemImage: "arrow.up.arrow.down")
                            .font(SP.rounded(13, .medium)).foregroundStyle(SP.accent)
                            .frame(minHeight: 44)
                    }
                }
            }
            .spCard(tint: tint)
            PracticeStack(practices: list)
        }
    }

    private func sorted(_ ps: [Practice]) -> [Practice] {
        switch sort {
        case .suggested:
            // Open ones first, then easiest, keeping the library's own order within each.
            return ps.enumerated().sorted { a, b in
                let la = lib.isLocked(a.element), lb = lib.isLocked(b.element)
                if la != lb { return !la }
                let ea = a.element.level == "easy", eb = b.element.level == "easy"
                if ea != eb { return ea }
                return a.offset < b.offset
            }.map(\.element)
        case .worksBest:
            let drops = log.dropByPractice()
            return ps.enumerated().sorted { a, b in
                let da = drops[a.element.id], db = drops[b.element.id]
                switch (da, db) {
                case let (x?, y?): return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.offset < b.offset
                }
            }.map(\.element)
        case .shortest:
            return ps.sorted { ($0.minutes.min() ?? 99, $0.title) < ($1.minutes.min() ?? 99, $1.title) }
        case .az:
            return ps.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

enum LibraryTab {
    static let traditions = "traditions"
    static let all = "all"
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case suggested, worksBest, shortest, az
    var id: String { rawValue }
    var title: String {
        switch self {
        case .suggested: return String(localized: "Suggested")
        case .worksBest: return String(localized: "Works best for you")
        case .shortest: return String(localized: "Shortest first")
        case .az: return String(localized: "A–Z")
        }
    }
}

/// Horizontal goal chips: Traditions, then each goal, then All.
struct LibraryTabBar: View {
    @Binding var selection: String
    private let lib = PracticeLibrary.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(LibraryTab.traditions, String(localized: "Traditions"), "globe.asia.australia", SP.accent)
                    ForEach(lib.categories) { c in
                        chip(c.id, c.localizedName, c.symbol, Color(spHex: c.color))
                    }
                    chip(LibraryTab.all, String(localized: "All"), "books.vertical.fill", SP.ink)
                }
                .padding(.horizontal, SP.screenPadding)
            }
            .sensoryFeedback(.selection, trigger: selection)
            .onChange(of: selection) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
    }

    private func chip(_ id: String, _ title: String, _ icon: String, _ c: Color) -> some View {
        let on = selection == id
        return Button { selection = id } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(on ? Color.white : c)
            }
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : SP.ink.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(on ? AnyShapeStyle(SP.accentFill) : AnyShapeStyle(SP.card)))
                .overlay(Capsule().stroke(on ? Color.white.opacity(0.14) : SP.stroke, lineWidth: 1))
                .contentShape(Capsule())
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A compact, scannable tradition row: color thumbnail, name, one-line description, practice count.
struct TraditionRow: View {
    let tradition: Tradition
    var body: some View {
        let count = PracticeLibrary.shared.practices(in: tradition).count
        HStack(spacing: 14) {
            PaintedScene(kind: tradition.scene, tint: tradition.tint)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tradition.name).font(SP.serif(19)).foregroundStyle(SP.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !tradition.blurb.isEmpty {
                    Text(tradition.blurb).font(SP.rounded(14)).foregroundStyle(SP.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(count == 1 ? String(localized: "1 practice") : String(localized: "\(count) practices"))
                    .font(SP.rounded(12, .semibold)).foregroundStyle(tradition.tint)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(SP.faint)
        }
        .spCard(padding: SP.s3)
        .accessibilityElement(children: .combine)
    }
}

struct TraditionCard: View {
    let tradition: Tradition
    var body: some View { TraditionRow(tradition: tradition) }
}

struct TraditionView: View {
    let tradition: Tradition
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaintedScene(kind: tradition.scene, tint: tradition.tint)
                    .frame(height: 260)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text([tradition.region, tradition.origin].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                                .font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.ink.opacity(0.75))
                            Text(tradition.name).font(SP.serif(32, .light)).foregroundStyle(SP.ink)
                        }
                        .padding(22)
                    }
                VStack(alignment: .leading, spacing: 18) {
                    if !tradition.summary.isEmpty {
                        Text(tradition.summary).font(SP.serif(18, .light)).foregroundStyle(SP.dim).lineSpacing(5)
                    }
                    PracticeStack(practices: PracticeLibrary.shared.practices(in: tradition))
                }
                .padding(22)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(DuskBackground(glow: tradition.tint))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PracticeDetailView: View {
    let practice: Practice
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var router: Router
    @EnvironmentObject var link: PhoneLink
    @State private var minutes = 5
    @State private var warmUpId = ""
    @State private var sentToWatch = false
    @State private var showPaywall = false
    private let lib = PracticeLibrary.shared
    private var locked: Bool { lib.isLocked(practice) }

    private var tradition: Tradition? { lib.tradition(practice.traditionId) }
    private var plan: SessionPlan {
        let w = warmUpId.isEmpty ? nil : lib.practice(warmUpId)
        return SessionPlan(warmUp: w, warmUpMinutes: w?.minutes.first ?? 2, practice: practice, minutes: minutes)
    }

    var body: some View {
        content.paywall(isPresented: $showPaywall, spec: StillPointPro.spec, context: practice.title)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    PaintedScene(kind: tradition?.scene ?? .water, tint: tradition?.tint ?? SP.teal)
                    if !practice.isMovement {
                        BreathOrb(scale: 0.78, phase: .still, accent: tradition?.tint).frame(width: 150, height: 150)
                    } else if let first = practice.steps.first {
                        // Hero: the routine's first move, slowly looping
                        PoseFigureView(motion: PoseLibrary.motion(for: first), mirrored: PoseLibrary.mirrored(for: first), lineWidth: 3)
                            .frame(width: 190, height: 190)
                    } else {
                        Image(systemName: "figure.cooldown").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(SP.ink.opacity(0.9))
                    }
                    if !practice.isMovement && practice.kind != "walking" {
                        // Posture hint: sit cross-legged or on a chair
                        PoseThumb(motion: PoseLibrary.seatedCrossLegged)
                            .frame(width: 44, height: 56)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(18)
                            .opacity(0.8)
                    }
                }
                .frame(height: 300)
                .overlay(alignment: .bottom) {
                    // Soft fade so the hero melts into the page.
                    LinearGradient(colors: [.clear, SP.night.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                        .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            if let t = tradition { SPChip(text: t.name, color: t.tint) }
                            if practice.isMovement { SPChip(text: "Warm up", color: SP.teal) }
                            Spacer()
                            PracticeInfoButton(practice: practice, size: 20)
                        }
                        Text(practice.title).font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !practice.tagline.isEmpty {
                            Text(practice.tagline).font(SP.serif(20, .light)).foregroundStyle(SP.ink.opacity(0.92))
                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                        PracticeMetaRow(practice: practice)
                        if let p = practice.pattern { PatternStrip(pattern: p).padding(.top, 4) }
                    }

                    // Length
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LENGTH").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                        SPFlow(spacing: 8) {
                            ForEach(practice.minutes, id: \.self) { m in
                                Button { minutes = m } label: {
                                    Text("\(m) min").font(.subheadline.weight(minutes == m ? .semibold : .regular)).monospacedDigit()
                                        .foregroundStyle(minutes == m ? Color.white : SP.ink)
                                        .padding(.horizontal, 16).frame(minHeight: 44)
                                        .background(Capsule().fill(minutes == m ? AnyShapeStyle(SP.accentFill) : AnyShapeStyle(SP.card)))
                                        .overlay(Capsule().stroke(SP.stroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(minutes == m ? .isSelected : [])
                            }
                        }
                        .sensoryFeedback(.selection, trigger: minutes)
                    }

                    if !practice.isMovement && !lib.warmUps.isEmpty {
                        Menu {
                            Button("No warm-up") { warmUpId = "" }
                            ForEach(lib.warmUps) { w in Button(w.title) { warmUpId = w.id } }
                        } label: {
                            HStack {
                                Image(systemName: "figure.cooldown")
                                Text(warmUpId.isEmpty ? "Warm up first?" : "Warm up: \(lib.practice(warmUpId)?.title ?? "")")
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12))
                            }
                            .font(SP.rounded(15)).foregroundStyle(SP.ink)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: SP.innerRadius + 2, style: .continuous).fill(SP.card))
                            .overlay(RoundedRectangle(cornerRadius: SP.innerRadius + 2, style: .continuous).stroke(SP.stroke, lineWidth: 1))
                        }
                    }

                    VStack(spacing: 10) {
                        Button { if locked { showPaywall = true } else { router.run(plan) } } label: {
                            Label(locked ? "Unlock to practice" : "Begin · \(minutes) min", systemImage: locked ? "lock.fill" : "play.fill")
                        }
                        .buttonStyle(SPPrimaryButtonStyle())
                        Button {
                            if locked { showPaywall = true } else { link.startOnWatch(plan) { ok in sentToWatch = ok } }
                        } label: {
                            Label(sentToWatch ? "Starting on your Watch…" : "Start on Apple Watch", systemImage: "applewatch")
                                .frame(minHeight: 50)
                        }
                        .buttonStyle(SPSecondaryButtonStyle(tint: SP.ink, fullWidth: true))
                        .sensoryFeedback(.success, trigger: sentToWatch)
                        .disabled(!link.canUseWatch)
                        if !link.canUseWatch {
                            Text("Install Still Pointz on your Apple Watch to start from here.")
                                .font(SP.rounded(12)).foregroundStyle(SP.faint)
                        }
                    }

                    PracticeLabels(practice: practice)
                    PracticeStatsCard(practiceId: practice.id, tint: tradition?.tint ?? SP.teal)
                    if !practice.about.isEmpty { prose(String(localized: "About"), practice.about) }
                    if !practice.why.isEmpty && practice.why != practice.howItWorks { prose(String(localized: "Why it helps"), practice.why) }
                    if practice.isMovement && !practice.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("STEPS").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                            ForEach(Array(practice.scaledSteps(minutes: minutes).enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(i + 1)").font(SP.numbers(15)).foregroundStyle(SP.teal).frame(width: 20)
                                    PoseThumb(motion: PoseLibrary.motion(for: s), mirrored: PoseLibrary.mirrored(for: s))
                                        .frame(width: 34, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name + (s.sideLetter.map { " · \($0)" } ?? "")).font(SP.serif(16)).foregroundStyle(SP.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if !s.how.isEmpty {
                                            Text(s.how).font(SP.rounded(13)).foregroundStyle(SP.dim)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Spacer()
                                    Text("\(Int(s.seconds))s").font(SP.rounded(12)).foregroundStyle(SP.faint)
                                }
                            }
                        }
                    }
                    if !practice.cues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ALONG THE WAY").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                            ForEach(practice.cues, id: \.self) { c in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(spFormatClock(c.at)).font(SP.rounded(12)).foregroundStyle(SP.faint).frame(width: 40, alignment: .leading)
                                    Text(c.text).font(SP.serif(15, .light)).foregroundStyle(SP.dim)
                                }
                            }
                        }
                    }
                    if let s = practice.safety, !s.isEmpty {
                        Label { Text(s).font(SP.rounded(13)).foregroundStyle(SP.ink.opacity(0.85)) } icon: {
                            Image(systemName: "heart.text.square").foregroundStyle(SP.rose)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.rose.opacity(0.10)))
                    }
                    if !practice.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SOURCES").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                            ForEach(practice.sources, id: \.self) { s in
                                Text(lib.note(for: s)).font(SP.rounded(12)).foregroundStyle(SP.faint)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(22)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(DuskBackground(glow: tradition?.tint ?? SP.indigo))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { prefs.toggleFavorite(practice.id) } label: {
                    Image(systemName: prefs.isFavorite(practice.id) ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: prefs.isFavorite(practice.id))
                .accessibilityLabel(prefs.isFavorite(practice.id) ? "Remove from favorites" : "Add to favorites")
            }
        }
        .onAppear {
            let d = prefs.settings.defaultMinutes
            minutes = practice.minutes.contains(d) ? d : practice.defaultMinutes
        }
    }

    private func prose(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
            Text(text).font(SP.serif(17, .light)).foregroundStyle(SP.ink.opacity(0.9)).lineSpacing(5)
        }
    }
}


// MARK: - Plain-English labels

/// Length, level and goal tabs, wrapping onto more lines at large text sizes.
struct PracticeMetaRow: View {
    let practice: Practice
    var body: some View {
        let lib = PracticeLibrary.shared
        SPFlow(spacing: 6) {
            SPChip(text: practice.minutesLabel, color: SP.accent)
            SPChip(text: practice.levelLabel, color: SP.ink.opacity(0.75))
            ForEach(lib.categories(for: practice).filter { $0.id != PracticeCategory.quickID && $0.id != PracticeCategory.beginnerID }) { c in
                SPChip(text: c.localizedName, color: Color(spHex: c.color))
            }
        }
    }
}

/// "Good for", "How it works", step-by-step, and the Healing note.
struct PracticeLabels: View {
    let practice: Practice
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !practice.goodFor.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    heading(String(localized: "Good for"))
                    ForEach(practice.goodFor, id: \.self) { g in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SP.teal).font(.system(size: 15))
                                .accessibilityHidden(true)
                            Text(g).font(SP.rounded(17)).foregroundStyle(SP.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !practice.howItWorks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    heading(String(localized: "How it works"))
                    Text(practice.howItWorks).font(SP.serif(17, .light)).foregroundStyle(SP.ink.opacity(0.9))
                        .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !practice.howTo.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    heading(String(localized: "How to do it"))
                    ForEach(Array(practice.howTo.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(SP.numbers(17)).foregroundStyle(SP.gold).frame(minWidth: 18)
                            Text(step).font(SP.rounded(16)).foregroundStyle(SP.ink.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if practice.isIn("healing") {
                Label(String(localized: "Not medical advice. These practices can help you feel calmer and more comfortable; they don't diagnose or treat anything."),
                      systemImage: "info.circle")
                    .font(SP.rounded(13)).foregroundStyle(SP.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heading(_ t: String) -> some View {
        Text(t.uppercased()).font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
    }
}

/// Simple wrapping layout for chips.
struct SPFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Your stats for one practice

/// Times done, minutes, average heart-rate drop, best session, last done, and the drop over time.
struct PracticeStatsCard: View {
    let practiceId: String
    var tint: Color = SP.teal
    @ObservedObject private var log = SessionLog.shared

    var body: some View {
        let st = log.stats(for: practiceId)
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Your results").uppercased()).font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
            if st.count == 0 {
                Text("Not tried yet. After each session your heart-rate results show up here, so you can see which practices settle you most.")
                    .font(SP.rounded(14)).foregroundStyle(SP.dim).fixedSize(horizontal: false, vertical: true)
            } else {
                if log.worksBest().contains(practiceId) {
                    Label("Works best for you", systemImage: "arrow.down.heart.fill")
                        .font(SP.rounded(14, .semibold)).foregroundStyle(SP.rose)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], alignment: .leading, spacing: 10) {
                    tile("\(st.count)", st.count == 1 ? String(localized: "time done") : String(localized: "times done"))
                    tile("\(Int(st.totalMinutes.rounded()))", String(localized: "minutes total"))
                    if let d = st.avgDrop {
                        tile((d >= 0 ? "−" : "+") + "\(Int(abs(d).rounded()))", String(localized: "avg bpm drop"))
                    }
                    if let last = st.lastDone {
                        tile(last.formatted(.relative(presentation: .named)), String(localized: "last done"))
                    }
                }
                if let b = st.best, let d = b.hrDrop {
                    NavigationLink { SessionDetailView(recordId: b.id) } label: {
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(SP.gold).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Best session: −\(Int(d.rounded())) bpm").font(SP.rounded(15, .medium)).foregroundStyle(SP.ink)
                                Text(b.start.formatted(.dateTime.month().day().hour().minute())).font(SP.rounded(12)).foregroundStyle(SP.faint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(SP.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                let trend = st.dropTrend
                if trend.count >= 2 {
                    Chart {
                        RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Color.white.opacity(0.15))
                        ForEach(Array(trend.enumerated()), id: \.offset) { i, p in
                            BarMark(x: .value("Session", i + 1), y: .value("Drop", p.drop))
                                .foregroundStyle(p.drop >= 0 ? tint : SP.rose.opacity(0.7))
                                .cornerRadius(3)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel().foregroundStyle(SP.faint)
                        }
                    }
                    .frame(height: 90)
                    .accessibilityLabel("Heart-rate drop for each of your last \(trend.count) sessions")
                    Text("Heart-rate drop per session, oldest to newest.").font(SP.rounded(11)).foregroundStyle(SP.faint)
                } else if st.withHeart.isEmpty {
                    Text("Wear your Apple Watch while you practice to see your heart-rate drop here.")
                        .font(SP.rounded(13)).foregroundStyle(SP.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card))
    }

    private func tile(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).font(SP.numbers(20)).foregroundStyle(SP.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(SP.rounded(11)).foregroundStyle(SP.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
