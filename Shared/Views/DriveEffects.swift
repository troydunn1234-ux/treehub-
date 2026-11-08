import SwiftUI
import MapKit

/// Speedometer + speed-limit sign shown while driving.
struct DriveHUD: View {
    let speed: Double                      // m/s
    let limit: SpeedLimitService.Limit?
    let over: Bool

    @State private var pulse = false

    private var shown: Int { Int((max(0, speed) * (Units.metric ? 3.6 : 2.236936)).rounded()) }
    private var unit: String { Units.metric ? "KM/H" : "MPH" }
    private var limitShown: Int? { limit.map { Int(($0.mps * (Units.metric ? 3.6 : 2.236936)).rounded()) } }
    private var fill: Double {
        guard let l = limit, l.mps > 0 else { return min(1, max(0, speed) / 40) }
        return min(1.25, max(0, speed) / l.mps) / 1.25
    }
    private var tint: Color {
        guard let l = limit else { return Theme.glow }
        return SpeedBand.of(speed: speed, limit: l.mps).color
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(.black.opacity(0.72))
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * fill)
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: tint.opacity(0.9), radius: 6)
                    .animation(.easeOut(duration: 0.5), value: fill)
                VStack(spacing: -2) {
                    Text("\(shown)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown)))
                        .animation(.snappy, value: shown)
                    Text(unit).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1).opacity(0.7)
                }
                .foregroundStyle(over ? Color(red: 1, green: 0.35, blue: 0.4) : .white)
            }
            .frame(width: 92, height: 92)
            .overlay(Circle().stroke(over ? Color.red : .clear, lineWidth: 3).scaleEffect(pulse ? 1.18 : 1).opacity(pulse ? 0 : 0.9))
            .onChange(of: over) { _, isOver in
                pulse = false
                if isOver { withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) { pulse = true } }
            }

            if let limitShown {
                VStack(spacing: 0) {
                    Text("SPEED").font(.system(size: 7, weight: .heavy))
                    Text("LIMIT").font(.system(size: 7, weight: .heavy))
                    Text("\(limitShown)").font(.system(size: 24, weight: .black)).monospacedDigit()
                    if limit?.estimated == true {
                        Text("EST.").font(.system(size: 6, weight: .heavy)).opacity(0.6)
                    }
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(minWidth: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black, lineWidth: 1.5).padding(3))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Speed limit \(limitShown)\(limit?.estimated == true ? ", estimated" : "")")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: limitShown)
    }
}

/// Marker for a stretch where you were well over the limit.
struct OverZoneBadge: View {
    let overMph: Double
    var body: some View {
        let shown = Units.metric ? Int((overMph * 1.609344).rounded()) : Int(overMph.rounded())
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 10, weight: .bold))
            Text("+\(shown)").font(.system(size: 12, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(SpeedBand.of(speed: overMph * 0.44704 + 20, limit: 20).color, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1.5))
        .shadow(color: .red.opacity(0.6), radius: 6)
    }
}

/// Speed streaks at the screen edges that grow with speed, plus a red edge glow when over the limit.
struct SpeedFX: View {
    let speed: Double        // m/s
    let overLimit: Bool

    private struct Streak { var x: Double; var y: Double; var len: Double; var phase: Double }
    @State private var streaks: [Streak] = (0..<26).map { _ in
        Streak(x: .random(in: 0...1), y: .random(in: 0...1), len: .random(in: 0.06...0.16), phase: .random(in: 0...1))
    }

    var body: some View {
        let intensity = min(1, max(0, (speed - 13) / 22))   // starts ~30 mph, full by ~78 mph
        ZStack {
            if intensity > 0.01 {
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let cx = size.width / 2, cy = size.height * 0.55
                        for s in streaks {
                            // Streaks fly outward from the center, only drawn near the edges.
                            let p = (s.phase + t * (0.35 + intensity * 0.9)).truncatingRemainder(dividingBy: 1)
                            let ang = s.x * .pi * 2
                            let r0 = 0.55 + p * 0.6
                            let r1 = r0 + s.len * (0.6 + intensity)
                            let rx = size.width * 0.75, ry = size.height * 0.6
                            var path = Path()
                            path.move(to: CGPoint(x: cx + cos(ang) * rx * r0, y: cy + sin(ang) * ry * r0))
                            path.addLine(to: CGPoint(x: cx + cos(ang) * rx * r1, y: cy + sin(ang) * ry * r1))
                            ctx.stroke(path, with: .color(.white.opacity(0.10 + 0.25 * intensity * (1 - p))),
                                       style: StrokeStyle(lineWidth: 1.5 + s.y * 1.5, lineCap: .round))
                        }
                    }
                }
                .transition(.opacity)
            }
            if overLimit {
                RadialGradient(colors: [.clear, .clear, Color.red.opacity(0.32)], center: .center, startRadius: 120, endRadius: 520)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: overLimit)
        .animation(.easeInOut(duration: 0.6), value: intensity > 0.01)
    }
}

// MARK: - Tap the route to see your speed


enum RouteProbe {
    /// The route point nearest a tap, if the tap is within ~44 pt of the line.
    @MainActor
    static func nearest(_ pts: [RoutePoint], tap: CGPoint, proxy: MapProxy) -> RoutePoint? {
        var best: (d: CGFloat, p: RoutePoint)?
        for p in pts {
            guard let s = proxy.convert(p.coordinate, to: .local) else { continue }
            let d = hypot(s.x - tap.x, s.y - tap.y)
            if best == nil || d < best!.d { best = (d, p) }
        }
        guard let b = best, b.d < 44 else { return nil }
        return b.p
    }
}

/// Small glass card above a point on the route: speed, limit, time.
struct SpeedCallout: View {
    let point: RoutePoint
    var body: some View {
        let toUnit = Units.metric ? 3.6 : 2.236936
        let speed = max(0, point.speed) * toUnit
        let band = SpeedBand.of(speed: point.speed, limit: point.limit)
        VStack(spacing: 4) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(point.speed >= 0 ? "\(Int(speed.rounded()))" : "—")
                        .font(.system(size: 26, weight: .black, design: .rounded)).monospacedDigit()
                    Text(Units.metric ? "km/h" : "mph").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
                }
                if point.limit > 0 {
                    let lim = Int((point.limit * toUnit).rounded())
                    let over = Int(((point.speed - point.limit) * toUnit).rounded())
                    Text(over > 0 ? "+\(over) over \(lim)" : "limit \(lim)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(over > 0 ? band.color : .white.opacity(0.75))
                }
                Text(Date(timeIntervalSince1970: point.t).formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(band.color, lineWidth: 1.5))
            .shadow(color: band.color.opacity(0.5), radius: 8)
            Circle().fill(band.color).frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: band.color, radius: 6)
        }
        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
    }
}
