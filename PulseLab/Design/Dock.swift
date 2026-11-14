import SwiftUI

/// Floating glass dock with five tabs. The selected tab gets a sliding pill in the duel gradient
/// and its icon bounces. Settings isn't here; it lives behind the gear in each header.
struct LabDock: View {
    @Binding var tab: LabTab
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tabs: [LabTab] = [.today, .sleep, .heart, .activity, .stack, .compare]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.tabs) { t in
                Button {
                    guard tab != t else { return }
                    withAnimation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.78)) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 18, weight: .bold))
                            .symbolEffect(.bounce, value: tab == t)
                        Text(t.dockTitle).font(Lab.label(8)).tracking(1)
                    }
                    .foregroundStyle(tab == t ? Lab.bg : Lab.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if tab == t {
                            Capsule()
                                .fill(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: Lab.watch.opacity(0.5), radius: 10)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Lab.bg.opacity(0.55)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.45), Color.white.opacity(0.06), Lab.whoop.opacity(0.45)], startPoint: .leading, endPoint: .trailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .padding(.horizontal, 14)
    }
}

/// Header gear (opens Settings) or close (on Settings), passed down from the root.
struct LabNav {
    var openSettings: () -> Void = {}
    var closeSettings: () -> Void = {}
}

private struct LabNavKey: EnvironmentKey { static let defaultValue = LabNav() }

extension EnvironmentValues {
    var labNav: LabNav {
        get { self[LabNavKey.self] }
        set { self[LabNavKey.self] = newValue }
    }
}

/// Round glass icon button used in headers.
struct HeaderIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Lab.text)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Launch splash

/// Two pulse lines (Watch cyan, WHOOP amber) race in and merge into the logo. ~0.9 s.
struct LaunchSplash: View {
    var done: () -> Void
    @State private var draw: CGFloat = 0
    @State private var merge = false
    @State private var fade = false

    var body: some View {
        ZStack {
            Lab.bg.ignoresSafeArea()
            ZStack {
                PulseLineShape(phase: 0)
                    .trim(from: 0, to: draw)
                    .stroke(Lab.watch, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: Lab.watch, radius: 10)
                    .offset(y: merge ? 0 : -26)
                PulseLineShape(phase: 0.5)
                    .trim(from: 0, to: draw)
                    .stroke(Lab.whoop, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: Lab.whoop, radius: 10)
                    .offset(y: merge ? 0 : 26)
            }
            .frame(width: 240, height: 90)
            VStack {
                Spacer()
                Text("PULSE LAB").font(Lab.label(14)).tracking(8).foregroundStyle(Lab.text)
                    .opacity(merge ? 1 : 0)
                    .padding(.bottom, 120)
            }
        }
        .opacity(fade ? 0 : 1)
        .scaleEffect(fade ? 1.08 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { draw = 1 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.4)) { merge = true }
            withAnimation(.easeIn(duration: 0.22).delay(0.72)) { fade = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { done() }
        }
        .accessibilityHidden(true)
    }
}

/// One heartbeat drawn across the rect (flat, P, QRS spike, T, flat).
struct PulseLineShape: Shape {
    var phase: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY, h = r.height / 2
        let pts: [(CGFloat, CGFloat)] = [
            (0, 0), (0.28, 0), (0.33, -0.12), (0.37, 0), (0.42, 0.18), (0.47, -0.95 + phase * 0.25),
            (0.52, 0.55), (0.56, 0), (0.66, -0.22), (0.74, 0), (1, 0)
        ]
        for (i, pt) in pts.enumerated() {
            let q = CGPoint(x: r.minX + pt.0 * r.width, y: mid + pt.1 * h)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }
}
