import SwiftUI

/// Your streaming apps as big glowing tiles. Tap one and it opens on the TV.
struct AppsView: View {
    @Environment(TVStore.self) private var store
    @State private var editing = false
    @State private var launching: String?
    @State private var appeared = false

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let now = store.nowPlaying { nowPlayingCard(now) }
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(Array(store.favoriteApps.enumerated()), id: \.element.id) { i, app in
                        AppTile(app: app, isPlaying: store.nowPlaying == app.name, launching: launching == app.name) {
                            Task {
                                launching = app.name
                                await store.launch(app)
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                launching = nil
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(Double(i) * 0.04), value: appeared)
                        .contextMenu {
                            Button(role: .destructive) { store.toggleFavorite(app) } label: { Label("Remove from my apps", systemImage: "minus.circle") }
                        }
                    }
                    Button { editing = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 26, weight: .bold))
                            Text("Add apps").font(Look.font(14))
                        }
                        .foregroundStyle(Look.dim)
                        .frame(maxWidth: .infinity, minHeight: 112)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Look.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))
                    }
                    .buttonStyle(SquishStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .sheet(isPresented: $editing) { AppPicker().environment(store) }
        .onAppear { appeared = true }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WATCH ON").font(Look.font(12, .heavy)).tracking(2).foregroundStyle(Look.dim)
                Text(store.tv?.name ?? "Your TV").font(Look.font(30, .heavy)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(store.reachable ? Color.green : Color.orange).frame(width: 8, height: 8)
                    .shadow(color: store.reachable ? .green : .orange, radius: 4)
                Text(store.reachable ? "Connected" : "Offline").font(Look.font(12, .bold)).foregroundStyle(Look.dim)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Look.card, in: Capsule())
        }
        .padding(.top, 8)
    }

    private func nowPlayingCard(_ name: String) -> some View {
        let app = store.catalog.first { $0.name == name }
        return HStack(spacing: 12) {
            EqualizerBars(color: app?.colors.first ?? Look.magenta)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("NOW ON TV").font(Look.font(10, .heavy)).tracking(1.5).foregroundStyle(Look.dim)
                Text(name).font(Look.font(18, .heavy)).foregroundStyle(.white)
            }
            Spacer()
            Button { store.press(.home) } label: {
                Image(systemName: "house.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Look.card, in: Circle())
            }
            .buttonStyle(SquishStyle())
            .accessibilityLabel("Go to the TV home screen")
        }
        .padding(14)
        .background(
            LinearGradient(colors: (app?.colors ?? [Look.violet, Look.bg]).map { $0.opacity(0.55) }, startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct AppTile: View {
    let app: StreamingApp
    let isPlaying: Bool
    let launching: Bool
    let action: () -> Void
    @State private var shimmer = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                // Glossy highlight + moving sheen.
                LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .rotationEffect(.degrees(20))
                    .offset(x: shimmer ? 240 : -240)
                    .blendMode(.plusLighter)
                Text(app.initials)
                    .font(.system(size: app.initials.count <= 3 ? 46 : 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
                VStack(alignment: .leading, spacing: 4) {
                    if isPlaying {
                        Label("On TV", systemImage: "tv.fill").font(Look.font(10, .heavy))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                    Text(app.name).font(Look.font(18, .heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                }
                .padding(14)
                if launching {
                    Color.black.opacity(0.25)
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isPlaying ? Color.white.opacity(0.9) : Color.white.opacity(0.10), lineWidth: isPlaying ? 2 : 1))
            .shadow(color: (app.colors.first ?? .clear).opacity(isPlaying ? 0.8 : 0.35), radius: isPlaying ? 18 : 10, y: 6)
        }
        .buttonStyle(SquishStyle(scale: 0.95))
        .accessibilityLabel("Open \(app.name) on the TV")
        .onChange(of: launching) { _, now in
            if now { withAnimation(.easeInOut(duration: 0.7)) { shimmer = true } } else { shimmer = false }
        }
    }
}

struct EqualizerBars: View {
    let color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4) { i in
                    Capsule().fill(color)
                        .frame(width: 4, height: 6 + 16 * abs(sin(t * (2.2 + Double(i) * 0.7) + Double(i))))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Pick which apps show up on the main screen.
struct AppPicker: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let apps = store.catalog.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                ForEach(apps) { app in
                    Button { store.toggleFavorite(app) } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Text(app.name).font(Look.font(16, .semibold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: store.favorites.contains(app.name) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(store.favorites.contains(app.name) ? Look.cyan : Look.dim)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Look.bg)
            .searchable(text: $query, prompt: "Search apps")
            .navigationTitle("My apps")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
