import SwiftUI

struct TraditionsView: View {
    private let lib = PracticeLibrary.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Traditions").font(SP.serif(34, .light)).foregroundStyle(SP.ink).padding(.top, 8)
                    Text("Ways of breathing and sitting, gathered from around the world.")
                        .font(SP.rounded(15)).foregroundStyle(SP.dim)
                    ForEach(lib.traditions) { t in
                        NavigationLink(value: t) { TraditionCard(tradition: t) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .background(DuskBackground())
            .navigationDestination(for: Tradition.self) { t in TraditionView(tradition: t) }
            .navigationDestination(for: Practice.self) { p in PracticeDetailView(practice: p) }
        }
    }
}

struct TraditionCard: View {
    let tradition: Tradition
    var body: some View {
        let count = PracticeLibrary.shared.practices(in: tradition).count
        ZStack(alignment: .bottomLeading) {
            PaintedScene(kind: tradition.scene, tint: tradition.tint)
            LinearGradient(colors: [.clear, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if !tradition.region.isEmpty { SPChip(text: tradition.region, color: tradition.tint) }
                    SPChip(text: "\(count) practice\(count == 1 ? "" : "s")", color: SP.ink.opacity(0.8))
                }
                Text(tradition.name).font(SP.serif(26, .light)).foregroundStyle(SP.ink)
                if !tradition.summary.isEmpty {
                    Text(tradition.summary).font(SP.rounded(13)).foregroundStyle(SP.ink.opacity(0.75)).lineLimit(2)
                }
            }
            .padding(18)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
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
    private let lib = PracticeLibrary.shared

    private var tradition: Tradition? { lib.tradition(practice.traditionId) }
    private var plan: SessionPlan {
        let w = warmUpId.isEmpty ? nil : lib.practice(warmUpId)
        return SessionPlan(warmUp: w, warmUpMinutes: w?.minutes.first ?? 2, practice: practice, minutes: minutes)
    }

    var body: some View {
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
                .frame(height: 280)

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            if let t = tradition { SPChip(text: t.name, color: t.tint) }
                            SPChip(text: practice.level, color: SP.ink.opacity(0.75))
                            if practice.isMovement { SPChip(text: "Warm up", color: SP.teal) }
                        }
                        Text(practice.title).font(SP.serif(34, .light)).foregroundStyle(SP.ink)
                        if let p = practice.pattern { PatternStrip(pattern: p).padding(.top, 4) }
                    }

                    // Length
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LENGTH").font(SP.rounded(11, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                        HStack(spacing: 8) {
                            ForEach(practice.minutes, id: \.self) { m in
                                Button { minutes = m } label: {
                                    Text("\(m) min").font(SP.rounded(14))
                                        .foregroundStyle(minutes == m ? Color.black.opacity(0.85) : SP.ink)
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .background(Capsule().fill(minutes == m ? AnyShapeStyle(SP.goldGlow) : AnyShapeStyle(SP.card)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SP.card))
                        }
                    }

                    VStack(spacing: 10) {
                        Button { router.run(plan) } label: {
                            Label("Practice on iPhone", systemImage: "iphone")
                                .font(SP.rounded(17, .medium)).foregroundStyle(Color.black.opacity(0.85))
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(Capsule().fill(SP.goldGlow))
                        }
                        Button {
                            link.startOnWatch(plan) { ok in sentToWatch = ok }
                        } label: {
                            Label(sentToWatch ? "Starting on your Watch…" : "Start on Apple Watch", systemImage: "applewatch")
                                .font(SP.rounded(17)).foregroundStyle(link.canUseWatch ? SP.ink : SP.faint)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .disabled(!link.canUseWatch)
                        if !link.canUseWatch {
                            Text("Install Still Point on your Apple Watch to start from here.")
                                .font(SP.rounded(12)).foregroundStyle(SP.faint)
                        }
                    }

                    if !practice.about.isEmpty { prose("About", practice.about) }
                    if !practice.why.isEmpty { prose("Why it helps", practice.why) }
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
                                        if !s.how.isEmpty { Text(s.how).font(SP.rounded(13)).foregroundStyle(SP.dim) }
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
        .background(DuskBackground(glow: tradition?.tint ?? SP.amber))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { prefs.toggleFavorite(practice.id) } label: {
                    Image(systemName: prefs.isFavorite(practice.id) ? "heart.fill" : "heart")
                }
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
