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
    var tint: Color = Theme.glow
    var onSetLane: (Int) -> Void = { _ in }

    @State private var expanded = false
    @State private var from: Double = 0
    @State private var to: Double = 0
    @State private var changeStart: Date = .distantPast
    @State private var changeQuick = false
    @State private var changeLeft = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private static let hot = Color(red: 1, green: 0.3, blue: 0.6)
    private var size: CGSize { expanded ? CGSize(width: 210, height: 184) : CGSize(width: 150, height: 124) }
    private let slide = 0.55       // seconds for the truck to slide a lane
    private let pillTime = 1.7

    var body: some View {
        let animating = Date().timeIntervalSince(changeStart) < pillTime + 0.2
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce || (speed < 0.5 && !animating))) { tl in
            let now = tl.date
            let since = now.timeIntervalSince(changeStart)
            let p = reduce ? 1 : min(1, since / slide)
            let lane = from + (to - from) * Self.easeOutBack(p)
            let accent = changeQuick && since < pillTime ? Self.hot : tint
            ZStack(alignment: .top) {
                Canvas { ctx, sz in
                    drawRoad(&ctx, sz, t: now.timeIntervalSinceReferenceDate, lane: lane, p: p, accent: accent)
                }
                truck(size: size, lane: lane, p: p)
                if since < pillTime && changeStart != .distantPast {
                    pill(accent: accent)
                        .padding(.top, 8)
                        .transition(.scale.combined(with: .opacity))
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
        .onAppear { from = Double(laneIndex); to = from }
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
            if let s = shift, now.timeIntervalSince(s.at) < 1, s.to == new { changeQuick = s.quick; changeLeft = s.left }
            changeStart = now
            if changeQuick { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
            else { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lane \(laneIndex + 1) of \(laneCount)\(estimated ? ", estimated" : "")")
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

    /// x of lane boundary `k` (0...n, may be fractional) at depth `f` (0 = far, 1 = near).
    private func boundaryX(_ k: Double, _ f: CGFloat, _ w: CGFloat) -> CGFloat {
        let hw = halfWidth(f, w)
        return w / 2 - hw + 2 * hw * CGFloat(k / Double(max(1, laneCount)))
    }

    private func y(_ f: CGFloat, _ h: CGFloat) -> CGFloat { roadTop(h) + (roadBottom(h) - roadTop(h)) * f }

    private func lanePolygon(_ a: Double, _ b: Double, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: boundaryX(a, 0, w), y: y(0, h)))
            p.addLine(to: CGPoint(x: boundaryX(b, 0, w), y: y(0, h)))
            p.addLine(to: CGPoint(x: boundaryX(b, 1, w), y: y(1, h)))
            p.addLine(to: CGPoint(x: boundaryX(a, 1, w), y: y(1, h)))
            p.closeSubpath()
        }
    }

    private func drawRoad(_ ctx: inout GraphicsContext, _ sz: CGSize, t: Double, lane: Double, p: Double, accent: Color) {
        let w = sz.width, h = sz.height
        let n = max(1, laneCount)
        // Asphalt
        let road = lanePolygon(0, Double(n), w, h)
        ctx.fill(road, with: .linearGradient(Gradient(colors: [Color(white: 0.07), Color(white: 0.16)]),
                                             startPoint: CGPoint(x: w / 2, y: y(0, h)), endPoint: CGPoint(x: w / 2, y: y(1, h))))
        // Trail: the lanes you just swept across glow and fade.
        if p < 1 || Date().timeIntervalSince(changeStart) < pillTime {
            let fade = max(0, 1 - Date().timeIntervalSince(changeStart) / pillTime)
            let lo = min(from, lane), hi = max(from, lane) + 1
            ctx.fill(lanePolygon(lo, hi, w, h), with: .color(accent.opacity(0.22 * fade)))
        }
        // Your lane
        ctx.fill(lanePolygon(lane, lane + 1, w, h),
                 with: .linearGradient(Gradient(colors: [accent.opacity(0.05), accent.opacity(0.42)]),
                                       startPoint: CGPoint(x: w / 2, y: y(0, h)), endPoint: CGPoint(x: w / 2, y: y(1, h))))
        ctx.stroke(lanePolygon(lane, lane + 1, w, h), with: .color(accent.opacity(0.55)), lineWidth: 1)
        // Edge lines (solid): yellow on the left like a real carriageway, white on the right.
        for (k, color) in [(0.0, Color(red: 1, green: 0.82, blue: 0.3)), (Double(n), Color.white)] {
            ctx.stroke(Path { pp in
                pp.move(to: CGPoint(x: boundaryX(k, 0, w), y: y(0, h)))
                pp.addLine(to: CGPoint(x: boundaryX(k, 1, w), y: y(1, h)))
            }, with: .color(color.opacity(0.85)), lineWidth: 1.6)
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
                ctx.stroke(Path { pp in
                    pp.move(to: CGPoint(x: boundaryX(Double(k), f0, w), y: y(f0, h)))
                    pp.addLine(to: CGPoint(x: boundaryX(Double(k), f1, w), y: y(f1, h)))
                }, with: .color(.white.opacity(0.35 + 0.5 * Double(f1))), lineWidth: 0.8 + 1.8 * f1)
            }
        }
    }

    private func truck(size: CGSize, lane: Double, p: Double) -> some View {
        let f: CGFloat = 0.78
        let x = (boundaryX(lane, f, size.width) + boundaryX(lane + 1, f, size.width)) / 2
        let laneW = boundaryX(1, f, size.width) - boundaryX(0, f, size.width)
        let scale = min(expanded ? 0.62 : 0.48, max(0.3, laneW / 60))
        // Lean into the lane change, straighten out at the end.
        let lean = reduce ? 0 : (to > from ? 1.0 : -1.0) * 14 * sin(.pi * min(1, p))
        return TopDownTruck(bearing: (to == from ? 0 : lean), pitch: 35, speed: speed)
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
        let left = boundaryX(0, f, w), right = boundaryX(Double(laneCount), f, w)
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
