import SwiftUI
import UIKit

/// Live lane strip for drives: a little perspective road with your truck in the lane you're in.
/// When you change lanes the truck slides over, the lanes it crosses light up, and a
/// "LANE CHANGE" (or "CUT!" for a quick one) pill flashes. Tap to expand; when expanded,
/// tap a lane to correct where you are (the starting lane is a guess).
struct LaneHUD: View {
    let laneCount: Int
    let laneIndex: Int            // 0 = leftmost lane going your way
    let estimated: Bool
    let shift: RouteTracker.LaneShift?
    let speed: Double             // m/s
    /// How much the real road bends over the next ~200 m (degrees, + = left).
    var bend: Double = 0
    /// The road is curving here: show a small CURVE tag (and never call it a lane change).
    var curving = false
    var tint: Color = Theme.glow
    var onSetLane: (Int) -> Void = { _ in }

    @State private var expanded = false
    @State private var from: Double = 0
    @State private var to: Double = 0
    @State private var changeStart: Date = .distantPast
    @State private var changeQuick = false
    @State private var changeLeft = false
    @State private var pillAt: Date = .distantPast     // only confirmed lane changes show the pill
    @State private var bendFrom: Double = 0
    @State private var bendTo: Double = 0
    @State private var bendStart: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduce

    private static let hot = Color(red: 1, green: 0.3, blue: 0.6)
    private var size: CGSize { expanded ? CGSize(width: 210, height: 184) : CGSize(width: 150, height: 124) }
    private let slide = 0.55       // seconds for the truck to slide a lane
    private let pillTime = 1.7
    private let bendTime = 0.9

    /// Road bend shown right now (eased toward the latest value), as -1...1 of the max on-screen bend.
    private func bendNorm(at now: Date) -> Double {
        let p = reduce ? 1 : min(1, now.timeIntervalSince(bendStart) / bendTime)
        let e = p * p * (3 - 2 * p)
        let deg = bendFrom + (bendTo - bendFrom) * e
        return max(-1, min(1, deg / 45))
    }

    var body: some View {
        let animating = Date().timeIntervalSince(changeStart) < pillTime + 0.2 || Date().timeIntervalSince(bendStart) < bendTime + 0.1
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce || (speed < 0.5 && !animating))) { tl in
            let now = tl.date
            let since = now.timeIntervalSince(changeStart)
            let sincePill = now.timeIntervalSince(pillAt)
            let p = reduce ? 1 : min(1, since / slide)
            let lane = from + (to - from) * Self.easeOutBack(p)
            let accent = changeQuick && sincePill < pillTime ? Self.hot : tint
            let b = bendNorm(at: now)
            ZStack(alignment: .top) {
                Canvas { ctx, sz in
                    drawRoad(&ctx, sz, t: now.timeIntervalSinceReferenceDate, lane: lane, p: p, accent: accent, bend: b, sincePill: sincePill)
                }
                truck(size: size, lane: lane, p: p, bend: b)
                if sincePill < pillTime && pillAt != .distantPast {
                    pill(accent: accent)
                        .padding(.top, 8)
                        .transition(.scale.combined(with: .opacity))
                } else if curving {
                    HStack {
                        Spacer()
                        Label("CURVE", systemImage: bend >= 0 ? "arrow.turn.up.left" : "arrow.turn.up.right")
                            .font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .padding(.top, 7).padding(.trailing, 8)
                    .transition(.opacity)
                }
                VStack {
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("LANE \(laneIndex + 1) OF \(laneCount)")
                            .font(.system(size: expanded ? 11 : 9, weight: .heavy, design: .rounded)).tracking(1.2)
                            .monospacedDigit()
                        if estimated {
                            Text("EST.").font(.system(size: 7, weight: .heavy)).opacity(0.55)
                        }
                        Spacer(minLength: 0)
                        if expanded {
                            Text("tap a lane").font(.system(size: 8, weight: .bold, design: .rounded)).opacity(0.55)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.bottom, 7)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), tint.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { e in tapped(at: e.location) })
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: expanded)
        .onAppear { from = Double(laneIndex); to = from; bendFrom = bend; bendTo = bend }
        .onChange(of: bend) { _, new in
            let now = Date()
            let p = min(1, now.timeIntervalSince(bendStart) / bendTime)
            bendFrom = bendFrom + (bendTo - bendFrom) * (p * p * (3 - 2 * p))
            bendTo = new
            bendStart = now
        }
        .onChange(of: laneCount) { _, _ in
            // New road / merge: jump without a slide.
            from = Double(laneIndex); to = from; changeStart = .distantPast
        }
        .onChange(of: laneIndex) { old, new in
            let now = Date()
            let since = now.timeIntervalSince(changeStart)
            let current = reduce ? to : from + (to - from) * Self.easeOutBack(min(1, since / slide))
            from = current
            to = Double(new)
            changeLeft = new < old
            changeQuick = false
            changeStart = now
            // Only a confirmed lane change gets the pill and buzz; turns, merges and your own taps just slide.
            if let s = shift, now.timeIntervalSince(s.at) < 1, s.to == new, !s.manual {
                changeQuick = s.quick; changeLeft = s.left
                pillAt = now
                if changeQuick { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
                else { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lane \(laneIndex + 1) of \(laneCount)\(estimated ? ", estimated" : "")\(curving ? ", road curving" : "")")
        .accessibilityHint(expanded ? "Tap a lane to set where you are" : "Tap to expand")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onSetLane(min(laneCount - 1, laneIndex + 1))
            case .decrement: onSetLane(max(0, laneIndex - 1))
            @unknown default: break
            }
        }
    }

    // MARK: Geometry

    /// Road edges: narrow at the top (far), wide at the bottom (near).
    private func halfWidth(_ f: CGFloat, _ w: CGFloat) -> CGFloat { (w * 0.30 + (w * 0.92 - w * 0.30) * f) / 2 }
    private func roadTop(_ h: CGFloat) -> CGFloat { h * 0.10 }
    private func roadBottom(_ h: CGFloat) -> CGFloat { h * 0.86 }

    /// Sideways shift of the road at depth f for a bend b (-1...1, + = left): none up close,
    /// most at the horizon, so the road sweeps off the way the real one does.
    private func bendShift(_ f: CGFloat, _ w: CGFloat, _ b: Double) -> CGFloat {
        let far = 1 - f
        return -CGFloat(b) * w * 0.36 * far * far
    }

    /// x of lane boundary `k` (0...n, may be fractional) at depth `f` (0 = far, 1 = near).
    private func boundaryX(_ k: Double, _ f: CGFloat, _ w: CGFloat, _ b: Double = 0) -> CGFloat {
        let hw = halfWidth(f, w)
        return w / 2 - hw + 2 * hw * CGFloat(k / Double(max(1, laneCount))) + bendShift(f, w, b)
    }

    private func y(_ f: CGFloat, _ h: CGFloat) -> CGFloat { roadTop(h) + (roadBottom(h) - roadTop(h)) * f }

    private static let depthSteps: [CGFloat] = (0...10).map { CGFloat($0) / 10 }

    /// A lane band from boundary a to b, traced down both edges so it can curve.
    private func lanePolygon(_ a: Double, _ b: Double, _ w: CGFloat, _ h: CGFloat, _ bend: Double = 0) -> Path {
        Path { p in
            let steps = Self.depthSteps
            p.move(to: CGPoint(x: boundaryX(a, 0, w, bend), y: y(0, h)))
            for f in steps.dropFirst() { p.addLine(to: CGPoint(x: boundaryX(a, f, w, bend), y: y(f, h))) }
            for f in steps.reversed() { p.addLine(to: CGPoint(x: boundaryX(b, f, w, bend), y: y(f, h))) }
            p.closeSubpath()
        }
    }

    private func boundaryLine(_ k: Double, _ w: CGFloat, _ h: CGFloat, _ bend: Double, from f0: CGFloat = 0, to f1: CGFloat = 1) -> Path {
        Path { p in
            let n = 6
            for i in 0...n {
                let f = f0 + (f1 - f0) * CGFloat(i) / CGFloat(n)
                let pt = CGPoint(x: boundaryX(k, f, w, bend), y: y(f, h))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func drawRoad(_ ctx: inout GraphicsContext, _ sz: CGSize, t: Double, lane: Double, p: Double, accent: Color, bend: Double, sincePill: Double) {
        let w = sz.width, h = sz.height
        let n = max(1, laneCount)
        // Asphalt
        let road = lanePolygon(0, Double(n), w, h, bend)
        ctx.fill(road, with: .linearGradient(Gradient(colors: [Color(white: 0.07), Color(white: 0.16)]),
                                             startPoint: CGPoint(x: w / 2, y: y(0, h)), endPoint: CGPoint(x: w / 2, y: y(1, h))))
        // Trail: the lanes you just swept across glow and fade.
        if sincePill < pillTime {
            let fade = max(0, 1 - sincePill / pillTime)
            let lo = min(from, lane), hi = max(from, lane) + 1
            ctx.fill(lanePolygon(lo, hi, w, h, bend), with: .color(accent.opacity(0.22 * fade)))
        }
        // Your lane
        ctx.fill(lanePolygon(lane, lane + 1, w, h, bend),
                 with: .linearGradient(Gradient(colors: [accent.opacity(0.05), accent.opacity(0.42)]),
                                       startPoint: CGPoint(x: w / 2, y: y(0, h)), endPoint: CGPoint(x: w / 2, y: y(1, h))))
        ctx.stroke(lanePolygon(lane, lane + 1, w, h, bend), with: .color(accent.opacity(0.55)), lineWidth: 1)
        // Edge lines (solid): yellow on the left like a real carriageway, white on the right.
        for (k, color) in [(0.0, Color(red: 1, green: 0.82, blue: 0.3)), (Double(n), Color.white)] {
            ctx.stroke(boundaryLine(k, w, h, bend), with: .color(color.opacity(0.85)), lineWidth: 1.6)
        }
        // Dashed lane lines, flowing toward you with speed.
        guard n > 1 else { return }
        let flow = reduce ? 0 : (t * max(0.2, speed) * 0.09).truncatingRemainder(dividingBy: 1)
        let dashes = 6
        for k in 1..<n {
            for d in 0..<dashes {
                let u0 = (Double(d) + flow) / Double(dashes)
                let u1 = u0 + 0.45 / Double(dashes)
                guard u0 < 1 else { continue }
                // Perspective: far dashes are bunched up and thin.
                let f0 = CGFloat(pow(u0, 1.7)), f1 = CGFloat(pow(min(1, u1), 1.7))
                ctx.stroke(boundaryLine(Double(k), w, h, bend, from: f0, to: f1),
                           with: .color(.white.opacity(0.35 + 0.5 * Double(f1))), lineWidth: 0.8 + 1.8 * f1)
            }
        }
    }

    private func truck(size: CGSize, lane: Double, p: Double, bend: Double) -> some View {
        let f: CGFloat = 0.78
        let x = (boundaryX(lane, f, size.width, bend) + boundaryX(lane + 1, f, size.width, bend)) / 2
        let laneW = boundaryX(1, f, size.width) - boundaryX(0, f, size.width)
        let scale = min(expanded ? 0.62 : 0.48, max(0.3, laneW / 60))
        // Lean into the lane change, straighten out at the end.
        let lean = reduce ? 0 : (to > from ? 1.0 : -1.0) * 14 * sin(.pi * min(1, p))
        // Point the truck a little into the bend (left bend → nose left).
        let follow = -bend * 12
        return TopDownTruck(bearing: (to == from ? 0 : lean) + follow, pitch: 35, speed: speed)
            .scaleEffect(scale)
            .position(x: x, y: y(f, size.height) - 4)
            .allowsHitTesting(false)
    }

    private func pill(accent: Color) -> some View {
        HStack(spacing: 4) {
            if changeLeft { Image(systemName: "arrow.left").font(.system(size: 9, weight: .black)) }
            Text(changeQuick ? "CUT!" : "LANE CHANGE")
                .font(.system(size: changeQuick ? 12 : 9, weight: .black, design: .rounded)).tracking(1)
            if !changeLeft { Image(systemName: "arrow.right").font(.system(size: 9, weight: .black)) }
        }
        .foregroundStyle(changeQuick ? .white : .black)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(accent, in: Capsule())
        .shadow(color: accent.opacity(0.8), radius: 6)
    }

    // MARK: Input

    private func tapped(at pt: CGPoint) {
        guard expanded else { expanded = true; return }
        let w = size.width, h = size.height
        // Tap near the top-right corner collapses.
        if pt.y < h * 0.12 && pt.x > w * 0.75 { expanded = false; return }
        let f = max(0, min(1, (pt.y - roadTop(h)) / (roadBottom(h) - roadTop(h))))
        let b = bendNorm(at: Date())
        let left = boundaryX(0, f, w, b), right = boundaryX(Double(laneCount), f, w, b)
        guard pt.x >= left - 10, pt.x <= right + 10 else { expanded = false; return }
        let i = Int((pt.x - left) / max(1, right - left) * CGFloat(laneCount))
        onSetLane(max(0, min(laneCount - 1, i)))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Slight overshoot so the slide feels springy.
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}
