import SwiftUI

@main
struct StillPointWatchApp: App {
    @StateObject private var prefs = Prefs.shared
    @StateObject private var log = SessionLog.shared
    @StateObject private var link = WatchLink.shared

    init() {
        WatchLink.shared.activate()
        MindfulHealth.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(prefs)
                .environmentObject(log)
                .environmentObject(link)
        }
    }
}

/// Home: one big Begin, three intentions, More. Everything is ≤ 2 taps away.
struct WatchRoot: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var link: WatchLink
    @State private var running: SessionPlan? = nil
    private let lib = PracticeLibrary.shared

    private var beginPractice: Practice {
        if let id = prefs.recents.first, let p = lib.practice(id), !p.isMovement { return p }
        return lib.quickPractice
    }

    private var homeIntentions: [Intention] {
        let wanted = ["calm", "sleep", "focus"]
        var out = wanted.compactMap { w in lib.intentions.first { $0.id.lowercased() == w || $0.name.lowercased() == w } }
        for i in lib.intentions where out.count < 3 && !out.contains(i) { out.append(i) }
        return Array(out.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Button { start(beginPractice, minutes: preferredMinutes(beginPractice)) } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                BreathOrb(scale: 0.8, phase: .still)
                                    .frame(width: 78, height: 78)
                                Text("Begin").font(SP.serif(20)).foregroundStyle(SP.ink)
                            }
                            Text("\(beginPractice.title) · \(preferredMinutes(beginPractice)) min")
                                .font(SP.rounded(12)).foregroundStyle(SP.dim).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Begin \(beginPractice.title), \(preferredMinutes(beginPractice)) minutes")

                    HStack(spacing: 8) {
                        ForEach(homeIntentions) { i in
                            NavigationLink(value: i) {
                                VStack(spacing: 3) {
                                    Image(systemName: i.symbol).font(.system(size: 16, weight: .light))
                                        .foregroundStyle(SP.teal)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(SP.teal.opacity(0.12)))
                                    Text(i.name).font(SP.rounded(11)).foregroundStyle(SP.ink).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        NavigationLink(value: "more") {
                            Text("More").font(SP.rounded(14)).foregroundStyle(SP.amber)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: "journey") {
                            Label("Journey", systemImage: "waveform.path.ecg")
                                .font(SP.rounded(14)).foregroundStyle(SP.teal)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            .background(DuskBackground().opacity(0.9))
            .navigationTitle("Still Point")
            .navigationDestination(for: Intention.self) { i in
                PracticeList(title: i.name, practices: lib.practices(for: i), onStart: start)
            }
            .navigationDestination(for: String.self) { key in
                if key == "journey" { WatchJourneyView() } else { MoreView(onStart: start) }
            }
            .navigationDestination(for: Practice.self) { p in SetupView(practice: p, onStart: startPlan) }
        }
        .fullScreenCover(item: $running) { plan in
            RunView(plan: plan) { running = nil }
                .environmentObject(prefs)
        }
        .onChange(of: link.pendingStart?.practiceId) { _, _ in consumePending() }
        .onAppear {
            consumePending()
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-session"), i + 1 < args.count, let p = lib.practice(args[i + 1]) {
                start(p, minutes: p.defaultMinutes)
            }
        }
    }

    private func preferredMinutes(_ p: Practice) -> Int {
        p.minutes.contains(prefs.settings.defaultMinutes) ? prefs.settings.defaultMinutes : p.defaultMinutes
    }

    private func start(_ p: Practice, minutes: Int) {
        startPlan(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: p, minutes: minutes))
    }

    private func startPlan(_ plan: SessionPlan) {
        prefs.markRecent(plan.practice.id)
        running = plan
    }

    private func consumePending() {
        guard let s = link.pendingStart, let p = lib.practice(s.practiceId) else { return }
        link.pendingStart = nil
        let w = s.warmUpId.flatMap { lib.practice($0) }
        startPlan(SessionPlan(warmUp: w, warmUpMinutes: w?.minutes.first ?? 2, practice: p, minutes: s.minutes))
    }
}

/// A calm list of practices.
struct PracticeList: View {
    let title: String
    let practices: [Practice]
    let onStart: (Practice, Int) -> Void

    var body: some View {
        List {
            ForEach(practices) { p in
                NavigationLink(value: p) { PracticeRow(practice: p) }
                    .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            }
        }
        .navigationTitle(title)
    }
}

struct PracticeRow: View {
    let practice: Practice
    var body: some View {
        let t = PracticeLibrary.shared.tradition(practice.traditionId)
        VStack(alignment: .leading, spacing: 3) {
            Text(practice.title).font(SP.serif(16)).foregroundStyle(SP.ink).lineLimit(2)
            HStack(spacing: 6) {
                Circle().fill(t?.tint ?? SP.teal).frame(width: 6, height: 6)
                Text(t?.name ?? (practice.isMovement ? "Warm up" : "Practice"))
                    .font(SP.rounded(11)).foregroundStyle(SP.dim).lineLimit(1)
                Spacer(minLength: 0)
                if let p = practice.pattern { Text(p.shortLabel).font(SP.rounded(11)).foregroundStyle(SP.faint) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Everything else: favorites, recent, warm ups, traditions, all.
struct MoreView: View {
    @EnvironmentObject var prefs: Prefs
    let onStart: (Practice, Int) -> Void
    @State private var tradition: String? = nil
    private let lib = PracticeLibrary.shared

    var body: some View {
        List {
            if !prefs.favorites.isEmpty {
                Section("Favorites") { rows(prefs.favorites.compactMap { lib.practice($0) }) }
            }
            if !prefs.recents.isEmpty {
                Section("Recent") { rows(prefs.recents.prefix(4).compactMap { lib.practice($0) }) }
            }
            if !lib.warmUps.isEmpty {
                Section("Warm up") { rows(lib.warmUps) }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(nil, "All", SP.amber)
                        ForEach(lib.traditions) { t in chip(t.id, t.name, t.tint) }
                    }
                }
                .listRowBackground(Color.clear)
                rows(lib.meditations.filter { tradition == nil || $0.traditionId == tradition })
            } header: { Text("Traditions") }
        }
        .navigationTitle("More")
    }

    @ViewBuilder private func rows(_ ps: [Practice]) -> some View {
        ForEach(ps) { p in
            NavigationLink(value: p) { PracticeRow(practice: p) }
        }
    }

    private func chip(_ id: String?, _ name: String, _ c: Color) -> some View {
        Button { tradition = id } label: {
            SPChip(text: name, color: c, filled: tradition == id)
        }
        .buttonStyle(.plain)
    }
}
