import SwiftUI

/// Per-app look and behaviour, read from Info.plist so one shell serves every web app.
enum ShellConfig {
    static let info = Bundle.main.infoDictionary ?? [:]
    static var name: String { info["CFBundleDisplayName"] as? String ?? "App" }
    static var background: Color { Color(hex: info["WebShellBackground"] as? String ?? "#000000") }
    static var accent: Color { Color(hex: info["WebShellAccent"] as? String ?? "#ffffff") }
    static var symbol: String { info["WebShellSymbol"] as? String ?? "sparkles" }
}

@main
struct WebShellApp: App {
    var body: some Scene {
        WindowGroup {
            ShellRoot()
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
struct ShellRoot: View {
    @State private var webReady = false
    @State private var splashDone = false

    var body: some View {
        ZStack {
            ShellConfig.background.ignoresSafeArea()
            WebScreen(onReady: { withAnimation(.easeOut(duration: 0.5)) { webReady = true } })
                .ignoresSafeArea()
                .opacity(webReady && splashDone ? 1 : 0)
                .scaleEffect(webReady && splashDone ? 1 : 0.96)
            if !(webReady && splashDone) {
                SplashView().transition(.opacity.combined(with: .scale(scale: 1.15)))
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { splashDone = true }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

struct SplashView: View {
    @State private var pop = false
    @State private var spin = false
    var body: some View {
        ZStack {
            ShellConfig.background.ignoresSafeArea()
            RadialGradient(colors: [ShellConfig.accent.opacity(0.35), .clear], center: .center, startRadius: 4, endRadius: 260)
                .scaleEffect(pop ? 1.15 : 0.6)
                .opacity(pop ? 1 : 0)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(AngularGradient(colors: [ShellConfig.accent.opacity(0), ShellConfig.accent], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 132, height: 132)
                .rotationEffect(.degrees(spin ? 360 : 0))
            VStack(spacing: 14) {
                Image(systemName: ShellConfig.symbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(ShellConfig.accent)
                    .shadow(color: ShellConfig.accent.opacity(0.8), radius: 18)
                    .scaleEffect(pop ? 1 : 0.4)
                Text(ShellConfig.name.uppercased())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.9))
                    .opacity(pop ? 1 : 0)
                    .offset(y: pop ? 0 : 8)
                    .padding(.top, 70)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { pop = true }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
