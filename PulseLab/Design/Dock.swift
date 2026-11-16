import SwiftUI

/// Floating dock with the main tabs. The selected tab gets a sliding tinted pill in the accent colour
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
                            .font(.system(size: 17, weight: .semibold))
                            .symbolEffect(.bounce, value: tab == t)
                        Text(t.title).font(.system(size: 10, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(tab == t ? Lab.accent : Lab.dim)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 4)
                    .background {
                        if tab == t {
                            Capsule()
                                .fill(Lab.accent.opacity(0.16))
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
        .background(Capsule().fill(Lab.panel.opacity(0.7)))
        .overlay(Capsule().strokeBorder(Lab.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Lab.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Lab.panel))
                .overlay(Circle().strokeBorder(Lab.line))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
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
                    .stroke(Lab.watch, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .offset(y: merge ? 0 : -26)
                PulseLineShape(phase: 0.5)
                    .trim(from: 0, to: draw)
                    .stroke(Lab.whoop, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .offset(y: merge ? 0 : 26)
            }
            .frame(width: 240, height: 90)
            VStack {
                Spacer()
                Text("Pulse Lab").font(.title3.weight(.semibold)).tracking(0.4).foregroundStyle(Lab.text)
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
