import SwiftUI

/// Three intro screens, then Apple Health, then WHOOP (skippable).
struct OnboardingView: View {
    var done: () -> Void
    @Environment(LabStore.self) private var store
    @State private var page = 0

    private let intro: [(String, String, String)] = [
        ("Two trackers.\nOne lab.", "Pulse Lab pulls everything your Apple Watch and WHOOP record and puts them side by side.", "waveform.path.ecg"),
        ("Every metric,\nhead to head.", "Resting HR, HRV, sleep stages, breathing, blood oxygen, temperature, calories and workouts.", "chart.xyaxis.line"),
        ("Who's right?", "Agreement scores, difference plots and a readiness score built from your Watch to sit next to WHOOP recovery.", "scope"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(0..<intro.count, id: \.self) { i in introPage(intro[i]).tag(i) }
                connectHealth.tag(3)
                connectWhoop.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            dots.padding(.bottom, 8)
            if page < 3 {
                Button { withAnimation(.snappy) { page += 1 } } label: { primary("Next") }
                    .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private func introPage(_ p: (String, String, String)) -> some View {
        VStack(spacing: 22) {
            Spacer()
            pulseArt
            Image(systemName: p.2).font(.system(size: 30, weight: .bold)).foregroundStyle(Lab.text.opacity(0.8))
            Text(p.0).font(Lab.display(40)).foregroundStyle(Lab.text).multilineTextAlignment(.center)
            Text(p.1).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
        }
    }

    /// Two glowing pulse lines (cyan Watch, amber WHOOP) that scroll.
    private var pulseArt: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: Lab.reduceMotion)) { tl in
        let phase = CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3)
        Canvas { context, size in
            for (i, color) in [Lab.watch, Lab.whoop].enumerated() {
                var ctx = context
                var path = Path()
                let mid = size.height / 2 + CGFloat(i) * 10 - 5
                for x in stride(from: 0, through: size.width, by: 2) {
                    let t = (x / size.width + phase + CGFloat(i) * 0.08).truncatingRemainder(dividingBy: 1)
                    var y = mid + sin(x / 18 + CGFloat(i)) * 3
                    if t > 0.42 && t < 0.5 { y = mid - sin((t - 0.42) / 0.08 * .pi) * (size.height * 0.42) * (i == 0 ? 1 : 0.8) }
                    if t > 0.5 && t < 0.55 { y = mid + sin((t - 0.5) / 0.05 * .pi) * size.height * 0.18 }
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.addFilter(.shadow(color: color, radius: 6))
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        }
        .frame(height: 120)
        .padding(.horizontal, 24)
        .accessibilityHidden(true)
    }

    private var connectHealth: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 64)).foregroundStyle(Lab.watch)
                .shadow(color: Lab.watch.opacity(0.7), radius: 16)
            Text("Connect Apple Health").font(Lab.display(32)).foregroundStyle(Lab.text)
            Text("Pulse Lab only reads. Tap Turn On All on the next screen so nothing is missing.")
                .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Button {
                Task { await store.connectHealth(); withAnimation(.snappy) { page = 4 } }
            } label: { primary("Connect Health") }
            Button("Not now") { withAnimation(.snappy) { page = 4 } }
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Lab.dim)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private var connectWhoop: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "bolt.heart.fill").font(.system(size: 56)).foregroundStyle(Lab.whoop)
                    .shadow(color: Lab.whoop.opacity(0.7), radius: 16).padding(.top, 40)
                Text("Connect WHOOP").font(Lab.display(32)).foregroundStyle(Lab.text)
                Text("For recovery, strain and WHOOP's own sleep stages. You can do this later in Settings.")
                    .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Lab.dim)
                    .multilineTextAlignment(.center)
                LabPanel(tint: Lab.whoop) { WhoopConnectView(accent: Lab.whoop) }
                Button { done() } label: { primary("Enter the lab") }
                Button("Skip WHOOP for now") { done() }
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Lab.dim)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(i == page ? AnyShapeStyle(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.15)))
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
    }

    private func primary(_ t: String) -> some View {
        Text(t).font(Lab.display(17, .heavy)).foregroundStyle(Lab.bg)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Capsule().fill(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: Lab.watch.opacity(0.4), radius: 14)
    }
}
