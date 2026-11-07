import SwiftUI

/// Branded ~1.6 s intro shown on cold launch. Calls `onFinished` exactly once when done.
@MainActor
struct LaunchSplash: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emblemIn: Bool = false
    @State private var draw: CGFloat = 0
    @State private var leafT: CGFloat = 0
    @State private var pulse: Bool = false
    @State private var titleIn: Bool = false
    @State private var taglineIn: Bool = false
    @State private var exiting: Bool = false
    @State private var didFinish: Bool = false

    #if TRACK_APP
    static let tagline: String = "Every mile, mapped."
    #else
    static let tagline: String = "Hug trees. Breathe. Grow."
    #endif

    var body: some View {
        ZStack {
            ForestBackground()
            VStack(spacing: 30) {
                BrandEmblem(appear: emblemIn, progress: draw, leafT: leafT, pulse: pulse)
                    .frame(width: 190, height: 190)
                titleBlock
            }
            .padding(.horizontal, Theme.pad)
            .opacity(exiting ? 0 : 1)
            .scaleEffect(exiting && !reduceMotion ? 1.06 : 1)
            .blur(radius: exiting && !reduceMotion ? 6 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AppInfo.name). \(LaunchSplash.tagline)")
        .accessibilityIdentifier("launch-splash")
        .task { await run() }
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            Text(AppInfo.name)
                .font(Theme.title(44))
                .foregroundStyle(.white)
                .shadow(color: Theme.glow.opacity(0.35), radius: 16)
                .opacity(titleIn ? 1 : 0)
                .offset(y: titleIn || reduceMotion ? 0 : 18)
            Text(LaunchSplash.tagline)
                .font(Theme.rounded(16, .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textDim)
                .opacity(taglineIn ? 1 : 0)
                .offset(y: taglineIn || reduceMotion ? 0 : 12)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Sequencing

    private func run() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) {
                emblemIn = true
                draw = 1
                titleIn = true
                taglineIn = true
            }
            guard await pause(0.85) else { return }
            withAnimation(.easeIn(duration: 0.2)) { exiting = true }
            guard await pause(0.2) else { return }
            finish()
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { emblemIn = true }
        withAnimation(.easeInOut(duration: 0.85)) { draw = 1 }
        withAnimation(.easeOut(duration: 1.3)) { leafT = 1 }
        withAnimation(BrandEmblem.pulseAnimation) { pulse = true }

        guard await pause(0.55) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { titleIn = true }
        guard await pause(0.15) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { taglineIn = true }
        guard await pause(0.65) else { return }
        withAnimation(.easeIn(duration: 0.25)) { exiting = true }
        guard await pause(0.25) else { return }
        finish()
    }

    /// Sleeps; returns false if the task was cancelled (view went away).
    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

// MARK: - Emblem (shared with onboarding)

/// The app's animated emblem: a glowing ring with a growing tree (Rootbound)
/// or a self-drawing route ending in a pulsing location dot (Roamr).
struct BrandEmblem: View {
    var appear: Bool
    /// 0...1: ring / route draw progress.
    var progress: CGFloat
    /// 0...1: floating leaves progress (Rootbound only).
    var leafT: CGFloat = 0
    var pulse: Bool = false

    #if TRACK_APP
    static let pulseAnimation: Animation = .easeOut(duration: 1.1).repeatForever(autoreverses: false)
    #else
    static let pulseAnimation: Animation = .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
    #endif

    var body: some View {
        #if TRACK_APP
        routeEmblem
        #else
        treeEmblem
        #endif
    }

    // MARK: Rootbound

    private var treeEmblem: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.glow.opacity(0.45), Theme.leaf.opacity(0.12), Color.clear],
                                     center: .center, startRadius: 6, endRadius: 100))
                .scaleEffect(pulse ? 1.12 : 0.94)
                .opacity(appear ? 1 : 0)
            Circle()
                .fill(LinearGradient(colors: [Theme.moss.opacity(0.9), Theme.forestDeep.opacity(0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .padding(28)
                .scaleEffect(appear ? 1 : 0.6)
                .opacity(appear ? 1 : 0)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.leafGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(16)
                .shadow(color: Theme.glow.opacity(0.6), radius: 8)
            Image(systemName: "tree.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.leafGradient)
                .shadow(color: Theme.glow.opacity(0.5), radius: 12)
                .scaleEffect(appear ? 1 : 0.15, anchor: .bottom)
                .opacity(appear ? 1 : 0)
            ForEach(0..<4, id: \.self) { i in
                floatingLeaf(i)
            }
        }
    }

    private func floatingLeaf(_ i: Int) -> some View {
        let xs: [CGFloat] = [-46, 40, -18, 58]
        let sizes: [CGFloat] = [14, 12, 10, 13]
        let shapes: [LeafShape] = [.oval, .heart, .oval, .ginkgo]
        let delays: [CGFloat] = [0, 0.12, 0.22, 0.3]
        let even: Bool = i % 2 == 0
        return LeafPath(shape: shapes[i])
            .fill(even ? Theme.glow : Theme.leaf)
            .frame(width: sizes[i], height: sizes[i] * 1.25)
            .modifier(FloatUpEffect(t: leafT, delay: delays[i], rise: 92,
                                    drift: even ? 10 : -10, spin: even ? 90 : -110))
            .offset(x: xs[i], y: -12)
            .allowsHitTesting(false)
    }

    // MARK: Roamr

    private var routeEmblem: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.leaf.opacity(0.28), Color.clear],
                                     center: .center, startRadius: 4, endRadius: 100))
                .opacity(appear ? 1 : 0)
            SplashRouteShape()
                .stroke(Color.white.opacity(0.14),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [1, 11]))
                .opacity(appear ? 1 : 0)
            SplashRouteShape()
                .trim(from: 0, to: progress)
                .stroke(Theme.leafGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.leaf.opacity(0.7), radius: 10)
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Theme.glow)
                        .frame(width: 12, height: 12)
                        .opacity(appear ? 1 : 0)
                        .position(x: geo.size.width * SplashRouteShape.start.x,
                                  y: geo.size.height * SplashRouteShape.start.y)
                    locationDot
                        .modifier(ArriveEffect(t: progress))
                        .position(x: geo.size.width * SplashRouteShape.end.x,
                                  y: geo.size.height * SplashRouteShape.end.y)
                }
            }
        }
        .scaleEffect(appear ? 1 : 0.85)
    }

    private var locationDot: some View {
        ZStack {
            Circle()
                .stroke(Theme.leaf, lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(pulse ? 2.4 : 1)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(Theme.leaf.opacity(0.25))
                .frame(width: 34, height: 34)
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
            Circle()
                .fill(Theme.leafGradient)
                .frame(width: 15, height: 15)
        }
        .shadow(color: Theme.leaf.opacity(0.8), radius: 10)
    }
}

/// Curved route used by the Roamr emblem, in a unit square.
private struct SplashRouteShape: Shape {
    static let start: CGPoint = CGPoint(x: 0.14, y: 0.80)
    static let end: CGPoint = CGPoint(x: 0.84, y: 0.22)

    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        var path = Path()
        path.move(to: p(SplashRouteShape.start.x, SplashRouteShape.start.y))
        path.addCurve(to: p(0.50, 0.58), control1: p(0.30, 0.98), control2: p(0.52, 0.86))
        path.addCurve(to: p(SplashRouteShape.end.x, SplashRouteShape.end.y), control1: p(0.48, 0.30), control2: p(0.86, 0.48))
        return path
    }
}

/// Rises, drifts, spins and fades in/out as `t` animates 0 → 1.
private struct FloatUpEffect: ViewModifier, Animatable {
    var t: CGFloat
    var delay: CGFloat
    var rise: CGFloat
    var drift: CGFloat
    var spin: Double

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let local: CGFloat = max(0, min(1, (t - delay) / max(0.01, 1 - delay)))
        let fade: Double = Double(sin(local * CGFloat.pi))
        let dx: CGFloat = drift * sin(local * CGFloat.pi * 1.5)
        return content
            .rotationEffect(.degrees(spin * Double(local)))
            .offset(x: dx, y: -rise * local)
            .opacity(fade)
    }
}

/// Pops a view in over the last stretch of a 0 → 1 progress animation.
private struct ArriveEffect: ViewModifier, Animatable {
    var t: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let local: CGFloat = max(0, min(1, (t - 0.82) / 0.18))
        return content
            .scaleEffect(local)
            .opacity(Double(local))
    }
}
