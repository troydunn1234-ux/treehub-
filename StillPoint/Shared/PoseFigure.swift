import SwiftUI

// MARK: - Pose

/// A minimal figure described by joint angles, in degrees.
/// Limb angles are measured from "hanging straight down" (0) and turn clockwise
/// on screen for the figure's right side; the left side mirrors automatically
/// so a positive shoulder angle always means "arm away from the body".
///   shoulder 0 = arm down, 90 = out to the side, 180 = straight overhead
///   elbow    0 = straight, 90 = bent at a right angle (toward the front of the figure)
///   hip      0 = leg straight down, 90 = leg out to the side / forward
///   knee     0 = straight, 90 = bent
///   lean     torso lean from vertical: + leans toward the figure's right, − toward its left
///   bow      forward fold from the hips (0 upright, 90 folded flat), drawn as the torso tilting in profile
///   headTilt + tilts toward the figure's right
///   lift     0…1 rises onto the toes / stretches tall
///   crouch   0…1 sinks the hips (horse stance, chair)
///   seated   draws the figure sitting (legs folded forward) instead of standing
///   prone    draws the figure lying face-down (cobra, plank); hips/knees still apply
///   hands    glyph at the hands: .open, .fist, .palmUp, .palmDown
struct Pose: Equatable {
    enum Hands: Equatable { case open, fist, palmUp, palmDown }

    var lean: Double = 0
    var bow: Double = 0
    var headTilt: Double = 0
    var headTurn: Double = 0      // + looks over the right shoulder
    var lShoulder: Double = 12, lElbow: Double = 0
    var rShoulder: Double = 12, rElbow: Double = 0
    var lHip: Double = 6, lKnee: Double = 0
    var rHip: Double = 6, rKnee: Double = 0
    var lift: Double = 0
    var crouch: Double = 0
    var seated = false
    var prone = false
    var hands: Hands = .open

    static let neutral = Pose()

    func mirrored() -> Pose {
        var p = self
        p.lean = -lean; p.headTilt = -headTilt; p.headTurn = -headTurn
        swap(&p.lShoulder, &p.rShoulder); swap(&p.lElbow, &p.rElbow)
        swap(&p.lHip, &p.rHip); swap(&p.lKnee, &p.rKnee)
        return p
    }

    /// Linear blend; booleans switch at the halfway point.
    static func blend(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        let t = min(1, max(0, t))
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var p = Pose()
        p.lean = m(a.lean, b.lean); p.bow = m(a.bow, b.bow)
        p.headTilt = m(a.headTilt, b.headTilt); p.headTurn = m(a.headTurn, b.headTurn)
        p.lShoulder = m(a.lShoulder, b.lShoulder); p.lElbow = m(a.lElbow, b.lElbow)
        p.rShoulder = m(a.rShoulder, b.rShoulder); p.rElbow = m(a.rElbow, b.rElbow)
        p.lHip = m(a.lHip, b.lHip); p.lKnee = m(a.lKnee, b.lKnee)
        p.rHip = m(a.rHip, b.rHip); p.rKnee = m(a.rKnee, b.rKnee)
        p.lift = m(a.lift, b.lift); p.crouch = m(a.crouch, b.crouch)
        p.seated = t < 0.5 ? a.seated : b.seated
        p.prone = t < 0.5 ? a.prone : b.prone
        p.hands = t < 0.5 ? a.hands : b.hands
        return p
    }
}

/// A step's movement: the figure eases from `from` to `to` and back, once per `cycle` seconds.
struct PoseMotion: Equatable {
    var from: Pose
    var to: Pose
    var cycle: Double = 3.6
    /// For harder moves: an ordered set of key positions, each with a short caption.
    /// When set, the figure walks through them in order (pausing on each), and `cycle` is seconds per key.
    var keys: [Pose] = []
    var labels: [String] = []

    var isSequence: Bool { keys.count > 2 }

    /// `true` for movements that should loop in one direction (circles), drawn as a smooth 0→1→0 anyway.
    static func still(_ p: Pose) -> PoseMotion { PoseMotion(from: p, to: p, cycle: 3.6) }

    /// A step-by-step move. `peak` is the key shown in still thumbnails.
    static func seq(_ items: [(Pose, String)], beat: Double = 2.0, peak: Int = 1) -> PoseMotion {
        let ps = items.map { $0.0 }
        let p = ps.isEmpty ? Pose() : ps[min(max(0, peak), ps.count - 1)]
        return PoseMotion(from: ps.first ?? p, to: p, cycle: beat, keys: ps, labels: items.map { $0.1 })
    }
}

// MARK: - Drawing

/// Draws a `Pose` inside its frame. Pure geometry; cheap enough to run every frame.
struct PoseShape: Shape {
    var pose: Pose

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let u = min(rect.width, rect.height) / 10          // body unit
        let cx = rect.midX
        let floor = rect.maxY - u * 0.6
        let p = pose

        func rad(_ d: Double) -> CGFloat { CGFloat(d * .pi / 180) }
        func pt(_ from: CGPoint, _ angleFromDown: CGFloat, _ len: CGFloat, mirror: CGFloat) -> CGPoint {
            // angle measured from straight down, turning toward the figure's outside (mirror = ±1)
            CGPoint(x: from.x + sin(angleFromDown) * len * mirror, y: from.y + cos(angleFromDown) * len)
        }

        if p.prone {
            // Lying face-down along the floor: head at the right, feet at the left.
            let torsoLen = u * 3.2, legLen = u * 3.0, armLen = u * 2.2
            let hip = CGPoint(x: cx - u * 0.8, y: floor - u * 0.5 - CGFloat(p.crouch) * u * 2.2)
            // torso rises toward the head by `bow` (cobra lifts the chest)
            let chestAngle = rad(p.bow)                                  // 0 flat, 60 lifted
            let shoulder = CGPoint(x: hip.x + cos(chestAngle) * torsoLen, y: hip.y - sin(chestAngle) * torsoLen)
            let headC = CGPoint(x: shoulder.x + cos(chestAngle + rad(p.headTilt)) * u * 0.9,
                                y: shoulder.y - sin(chestAngle + rad(p.headTilt)) * u * 0.9)
            path.addEllipse(in: CGRect(x: headC.x - u * 0.55, y: headC.y - u * 0.55, width: u * 1.1, height: u * 1.1))
            path.move(to: hip); path.addLine(to: shoulder)
            // legs back along the floor, hips may be high (downward dog uses crouch<0 via lift)
            let kneeA = rad(p.rKnee)
            let knee = CGPoint(x: hip.x - cos(kneeA) * legLen * 0.5, y: hip.y + sin(kneeA) * legLen * 0.5)
            let foot = CGPoint(x: knee.x - legLen * 0.5, y: min(floor, knee.y + sin(kneeA) * legLen * 0.3))
            path.move(to: hip); path.addLine(to: knee); path.addLine(to: foot)
            // arms: shoulder angle here = how far the hand is in front of the shoulder (0 under, 90 forward)
            let armA = rad(p.rShoulder)
            let elbow = CGPoint(x: shoulder.x + sin(armA) * armLen * 0.5, y: min(floor, shoulder.y + cos(armA) * armLen * 0.5))
            let hand = CGPoint(x: elbow.x + sin(armA + rad(p.rElbow)) * armLen * 0.5, y: min(floor, elbow.y + cos(armA + rad(p.rElbow)) * armLen * 0.5))
            path.move(to: shoulder); path.addLine(to: elbow); path.addLine(to: hand)
            return path
        }

        // Standing or seated, drawn front-on with a hint of profile when bowing.
        let legLen: CGFloat = p.seated ? u * 1.6 : u * 3.1
        let torsoLen: CGFloat = u * 3.0
        let armLen: CGFloat = u * 2.5
        let sink = CGFloat(p.crouch) * u * 1.1 - CGFloat(p.lift) * u * 0.45
        let hipY = p.seated ? floor - u * 1.1 : floor - legLen * cos(rad(p.rKnee * 0.5)) + sink
        let hip = CGPoint(x: cx, y: hipY)

        // Legs
        if p.seated {
            // Folded forward: thighs out to the sides and shins crossing in front.
            for side in [CGFloat(-1), 1] {
                let hipA = rad(side < 0 ? p.lHip : p.rHip) + rad(70)
                let knee = pt(hip, hipA, u * 1.5, mirror: side)
                let foot = CGPoint(x: cx - side * u * 0.4, y: knee.y + u * 0.35)
                path.move(to: hip); path.addLine(to: knee); path.addLine(to: foot)
            }
        } else {
            for side in [CGFloat(-1), 1] {
                let hipA = rad(side < 0 ? p.lHip : p.rHip)
                let kneeA = rad(side < 0 ? p.lKnee : p.rKnee)
                let knee = pt(hip, hipA, legLen * 0.5, mirror: side)
                // the knee bends forward (toward viewer) — show as a slight outward kink plus shortening
                let shin = pt(knee, hipA - kneeA * 0.55, legLen * 0.5 * (1 - 0.25 * CGFloat(abs(sin(kneeA)))), mirror: side)
                let foot = CGPoint(x: shin.x, y: min(shin.y, floor - CGFloat(p.lift) * u * 0.45))
                path.move(to: hip); path.addLine(to: knee); path.addLine(to: foot)
                if p.lift > 0.05 {
                    // on tiptoe: a small heel mark lifted off the floor
                    path.move(to: CGPoint(x: foot.x - side * u * 0.25, y: foot.y)); path.addLine(to: CGPoint(x: foot.x + side * u * 0.25, y: foot.y))
                }
            }
        }

        // Torso: lean sideways, and bow forward (shown as the torso shortening + tipping)
        let bowT = CGFloat(min(1, max(0, p.bow / 90)))
        let leanA = rad(p.lean)
        let torsoVisible = torsoLen * (1 - 0.72 * bowT)
        let shoulder = CGPoint(x: hip.x + sin(leanA) * torsoVisible + bowT * u * 0.1, y: hip.y - cos(leanA) * torsoVisible)
        path.move(to: hip); path.addLine(to: shoulder)
        if bowT > 0.15 {
            // show the back as a gentle arc when folded
            let back = CGPoint(x: shoulder.x + sin(leanA) * u * 1.4 * bowT, y: shoulder.y + u * 0.3 * bowT)
            path.move(to: shoulder); path.addQuadCurve(to: back, control: CGPoint(x: shoulder.x + u * 0.9 * bowT, y: shoulder.y - u * 0.4 * bowT))
        }

        // Head
        let headA = leanA + rad(p.headTilt)
        let headDrop = bowT * u * 1.1
        let headC = CGPoint(x: shoulder.x + sin(headA) * u * 0.95 + bowT * u * 1.2, y: shoulder.y - cos(headA) * u * 0.95 + headDrop)
        let headR = u * 0.55 * (1 - 0.1 * CGFloat(abs(p.headTurn) / 90))
        path.addEllipse(in: CGRect(x: headC.x - headR, y: headC.y - headR, width: headR * 2, height: headR * 2))
        if abs(p.headTurn) > 20 {
            // looking back: a small nose tick on the turned side
            let s: CGFloat = p.headTurn > 0 ? 1 : -1
            path.move(to: CGPoint(x: headC.x + s * headR, y: headC.y)); path.addLine(to: CGPoint(x: headC.x + s * (headR + u * 0.25), y: headC.y - u * 0.05))
        }

        // Arms (from the shoulder line, slightly inside the shoulder point)
        for side in [CGFloat(-1), 1] {
            let shA = rad(side < 0 ? p.lShoulder : p.rShoulder) + leanA * side
            let elA = rad(side < 0 ? p.lElbow : p.rElbow)
            let origin = CGPoint(x: shoulder.x + side * u * 0.22, y: shoulder.y + u * 0.1 + bowT * u * 0.3)
            // arms follow the fold: when bowed, they hang toward the floor regardless
            let armA = shA * (1 - bowT) + bowT * rad(10)
            let elbow = pt(origin, armA, armLen * 0.5, mirror: side)
            let hand = pt(elbow, armA - elA, armLen * 0.5, mirror: side)
            path.move(to: origin); path.addLine(to: elbow); path.addLine(to: hand)
            // hand glyph
            switch p.hands {
            case .fist:
                path.addEllipse(in: CGRect(x: hand.x - u * 0.2, y: hand.y - u * 0.2, width: u * 0.4, height: u * 0.4))
            case .palmUp, .palmDown:
                let dir: CGFloat = p.hands == .palmUp ? -1 : 1
                path.move(to: CGPoint(x: hand.x - u * 0.28, y: hand.y + dir * u * 0.02)); path.addLine(to: CGPoint(x: hand.x + u * 0.28, y: hand.y + dir * u * 0.02))
            case .open: break
            }
        }
        return path
    }
}

// MARK: - Views

/// Animated figure: eases between two poses and back on a slow loop.
/// Reduce Motion shows the `to` pose, still.
struct PoseFigureView: View {
    let motion: PoseMotion
    var mirrored = false
    var tint: Color = SP.gold
    var glow: Color = SP.teal
    var lineWidth: CGFloat = 3
    /// Show the key-position caption and progress dots for step-by-step moves.
    var captions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if motion.isSequence {
            sequence
        } else if reduceMotion || motion.from == motion.to {
            figure(progress: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: motion.cycle)) / motion.cycle   // 0→1
                let tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2                           // 0→1→0
                let eased = tri * tri * (3 - 2 * tri)                                         // smoothstep
                figure(progress: eased)
            }
        }
    }

    // MARK: Step-by-step

    /// Walks through the key positions: hold on each (so you can see the shape), then flow to the next.
    /// A faint dashed ghost shows where the body is heading; dots show which part of the move you're on.
    private var sequence: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
            let fr = frame(at: reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate)
            VStack(spacing: lineWidth * 1.5) {
                ZStack {
                    if fr.ghostAlpha > 0.01 { ghost(fr.ghost, visible: fr.ghostAlpha) }
                    figure(pose: fr.pose)
                }
                if captions { captionBlock(shown: fr.shown) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(motion.labels.joined(separator: ", then "))
    }

    private struct SeqFrame { var pose: Pose; var ghost: Pose; var ghostAlpha: Double; var shown: Int }

    /// Where the figure is at time `t`: hold on key i, then ease to key i+1.
    private func frame(at t: Double) -> SeqFrame {
        let keys = motion.keys
        let n = keys.count
        if reduceMotion {
            let peak = keys.firstIndex(of: motion.to) ?? 0
            return SeqFrame(pose: motion.to, ghost: motion.to, ghostAlpha: 0, shown: peak)
        }
        let beat = max(0.8, motion.cycle)
        let pos = t.truncatingRemainder(dividingBy: beat * Double(n)) / beat
        let i = min(n - 1, Int(pos))
        let f = pos - Double(i)
        let next = (i + 1) % n
        let hold = 0.45
        let raw = f < hold ? 0 : (f - hold) / (1 - hold)
        let e = raw * raw * (3 - 2 * raw)
        let pose = Pose.blend(keys[i], keys[next], e)
        let alpha = f < hold ? 0.22 : 0.22 * (1 - e)
        return SeqFrame(pose: pose, ghost: keys[next], ghostAlpha: alpha, shown: e < 0.5 ? i : next)
    }

    @ViewBuilder
    private func captionBlock(shown: Int) -> some View {
        if motion.labels.indices.contains(shown) {
            Text(motion.labels[shown])
                .font(.system(size: max(9, lineWidth * 3.6), weight: .semibold, design: .rounded))
                .foregroundStyle(tint.opacity(0.95))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.35)))
        }
        HStack(spacing: lineWidth * 1.2) {
            ForEach(0..<motion.keys.count, id: \.self) { k in
                Circle().fill(k == shown ? tint : tint.opacity(0.25))
                    .frame(width: lineWidth * 1.8, height: lineWidth * 1.8)
            }
        }
    }

    private func ghost(_ p: Pose, visible: Double) -> some View {
        PoseShape(pose: mirrored ? p.mirrored() : p)
            .stroke(tint.opacity(visible), style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round, dash: [lineWidth * 1.4, lineWidth * 1.6]))
            .padding(lineWidth * 2)
    }

    private func figure(progress: Double) -> some View {
        figure(pose: Pose.blend(motion.from, motion.to, progress))
    }

    private func figure(pose base: Pose) -> some View {
        var pose = base
        if mirrored { pose = pose.mirrored() }
        let shape = PoseShape(pose: pose)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        return ZStack {
            shape.stroke(glow.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth * 3.2, lineCap: .round, lineJoin: .round))
                .blur(radius: lineWidth * 2.2)
            shape.stroke(tint, style: style)
        }
        .padding(lineWidth * 2)
        .accessibilityHidden(true)
    }
}

/// Small still figure for lists.
struct PoseThumb: View {
    let motion: PoseMotion
    var mirrored = false
    var body: some View {
        PoseShape(pose: mirrored ? motion.to.mirrored() : motion.to)
            .stroke(SP.teal.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .padding(3)
            .accessibilityHidden(true)
    }
}

// MARK: - Library

/// Picks a figure for a step: exact name first, then keywords, then a generic reach.
enum PoseLibrary {
    static func motion(for step: MoveStep) -> PoseMotion {
        let name = step.name.lowercased()
        if let m = sequences[name], m.isSequence { return m }
        if let m = byName[name] { return m }
        let text = name + " " + step.how.lowercased()
        for (keys, m) in rules where keys.contains(where: { text.contains($0) }) { return m }
        return fallback
    }

    /// Whether to draw the figure mirrored (left-side steps).
    static func mirrored(for step: MoveStep) -> Bool { step.side == "left" }

    // Building blocks
    private static func standing(_ edit: (inout Pose) -> Void) -> Pose { var p = Pose(); edit(&p); return p }
    private static func seated(_ edit: (inout Pose) -> Void) -> Pose { var p = Pose(); p.seated = true; p.lShoulder = 20; p.rShoulder = 20; edit(&p); return p }

    static let stand = Pose()
    static let armsOut = standing { $0.lShoulder = 90; $0.rShoulder = 90 }
    static let armsUp = standing { $0.lShoulder = 170; $0.rShoulder = 170; $0.lift = 0.6 }
    static let armsUpPalms = standing { $0.lShoulder = 175; $0.rShoulder = 175; $0.lElbow = 10; $0.rElbow = 10; $0.hands = .palmUp; $0.lift = 0.9 }
    static let horse = standing { $0.lHip = 28; $0.rHip = 28; $0.lKnee = 45; $0.rKnee = 45; $0.crouch = 0.8; $0.lShoulder = 30; $0.rShoulder = 30; $0.lElbow = 70; $0.rElbow = 70 }
    static let bowDraw = standing { $0.lHip = 28; $0.rHip = 28; $0.lKnee = 45; $0.rKnee = 45; $0.crouch = 0.8; $0.rShoulder = 92; $0.rElbow = 0; $0.lShoulder = 80; $0.lElbow = 120; $0.hands = .fist }
    static let heavenEarth = standing { $0.rShoulder = 175; $0.rElbow = 5; $0.lShoulder = 10; $0.lElbow = -5; $0.hands = .palmDown }
    static let lookBack = standing { $0.headTurn = 75; $0.lShoulder = 14; $0.rShoulder = 14 }
    static let swayLeft = standing { $0.lHip = 30; $0.rHip = 30; $0.lKnee = 40; $0.rKnee = 40; $0.crouch = 0.7; $0.lean = -32; $0.headTilt = -10; $0.lShoulder = 60; $0.rShoulder = 60; $0.lElbow = 60; $0.rElbow = 60 }
    static let fold = standing { $0.bow = 85; $0.lShoulder = 20; $0.rShoulder = 20 }
    static let halfFold = standing { $0.bow = 45; $0.lShoulder = 30; $0.rShoulder = 30 }
    static let punchR = standing { $0.lHip = 28; $0.rHip = 28; $0.lKnee = 45; $0.rKnee = 45; $0.crouch = 0.8; $0.rShoulder = 88; $0.rElbow = 0; $0.lShoulder = 20; $0.lElbow = 110; $0.hands = .fist }
    static let tiptoe = standing { $0.lift = 1; $0.lShoulder = 8; $0.rShoulder = 8 }
    static let handsBelly = standing { $0.lShoulder = 18; $0.rShoulder = 18; $0.lElbow = 95; $0.rElbow = 95 }
    static let wuji = standing { $0.lHip = 2; $0.rHip = 2; $0.lShoulder = 8; $0.rShoulder = 8 }
    static let floatArms = standing { $0.lHip = 12; $0.rHip = 12; $0.lKnee = 15; $0.rKnee = 15; $0.lShoulder = 85; $0.rShoulder = 85; $0.lElbow = 25; $0.rElbow = 25; $0.hands = .palmDown }
    static let cloudL = standing { $0.lHip = 22; $0.rHip = 22; $0.lKnee = 30; $0.rKnee = 30; $0.crouch = 0.5; $0.lean = -12; $0.lShoulder = 95; $0.lElbow = 50; $0.rShoulder = 35; $0.rElbow = 80 }
    static let cloudR = cloudL.mirrored()
    static let crossArms = standing { $0.lShoulder = 55; $0.rShoulder = 55; $0.lElbow = 130; $0.rElbow = 130 }
    static let kneeBounce = standing { $0.lKnee = 30; $0.rKnee = 30; $0.crouch = 0.35; $0.lShoulder = 40; $0.rShoulder = 40 }
    static let armSwingBack = standing { $0.lShoulder = -25; $0.rShoulder = -25 }
    static let chestOpen = standing { $0.lShoulder = 100; $0.rShoulder = 100; $0.lElbow = -15; $0.rElbow = -15; $0.lean = 0; $0.lift = 0.2 }
    static let sideBendR = standing { $0.lean = 28; $0.lShoulder = 170; $0.lElbow = 5; $0.rShoulder = 10; $0.headTilt = 12 }
    static let backBend = standing { $0.bow = -20; $0.lShoulder = 30; $0.rShoulder = 30; $0.lElbow = 120; $0.rElbow = 120; $0.lean = 0 }
    static let twistR = standing { $0.headTurn = 50; $0.lShoulder = 85; $0.lElbow = 60; $0.rShoulder = 70; $0.rElbow = -30 }
    static let handsShoulders = standing { $0.lShoulder = 30; $0.rShoulder = 30; $0.lElbow = 150; $0.rElbow = 150; $0.hands = .fist }
    static let punchUp = standing { $0.lShoulder = 178; $0.rShoulder = 178; $0.hands = .fist; $0.lift = 0.5 }
    static let diagDown = standing { $0.bow = 40; $0.lean = -20; $0.lShoulder = 60; $0.rShoulder = 20; $0.lKnee = 20; $0.rKnee = 20 }
    static let circleHi = standing { $0.lean = 20; $0.lShoulder = 160; $0.rShoulder = 160; $0.bow = -10 }
    static let circleLo = standing { $0.lean = -20; $0.bow = 60; $0.lShoulder = 40; $0.rShoulder = 40 }
    static let hop = standing { $0.lift = 1; $0.lKnee = 12; $0.rKnee = 12; $0.lShoulder = 25; $0.rShoulder = 25 }
    static let butterfly = seated { $0.lHip = 40; $0.rHip = 40; $0.lShoulder = 25; $0.rShoulder = 25 }
    static let butterflyFold = seated { $0.lHip = 40; $0.rHip = 40; $0.bow = 60; $0.lShoulder = 30; $0.rShoulder = 30; $0.lElbow = 40; $0.rElbow = 40 }
    static let longSit = seated { $0.lHip = -55; $0.rHip = -55; $0.lShoulder = 25; $0.rShoulder = 25 }
    static let longSitFold = seated { $0.lHip = -55; $0.rHip = -55; $0.bow = 70; $0.lShoulder = 60; $0.rShoulder = 60; $0.lElbow = 5; $0.rElbow = 5; $0.hands = .palmDown }
    static let wideSit = seated { $0.lHip = 10; $0.rHip = 10; $0.lShoulder = 25; $0.rShoulder = 25 }
    static let wideSitFold = seated { $0.lHip = 10; $0.rHip = 10; $0.bow = 65; $0.lShoulder = 55; $0.rShoulder = 55; $0.lElbow = 5; $0.rElbow = 5; $0.hands = .palmDown }
    static let kneelRecline = seated { $0.lHip = -70; $0.rHip = -70; $0.bow = -35; $0.lShoulder = -40; $0.rShoulder = -40; $0.lElbow = -20; $0.rElbow = -20 }
    static let prayer = standing { $0.lShoulder = 25; $0.rShoulder = 25; $0.lElbow = 125; $0.rElbow = 125 }
    static let raisedArmsBack = standing { $0.lShoulder = 172; $0.rShoulder = 172; $0.bow = -18; $0.lift = 0.4 }
    // Front thigh level, shin upright; back knee dropped toward the floor; arms overhead, slight lift of the chest.
    static let lungeR = standing { $0.rHip = 85; $0.rKnee = 90; $0.lHip = -35; $0.lKnee = 75; $0.crouch = 1.0; $0.lShoulder = 170; $0.rShoulder = 170; $0.lElbow = 5; $0.rElbow = 5; $0.bow = -12 }
    static let downDog: Pose = { var p = Pose(); p.prone = true; p.bow = 50; p.crouch = 1; p.rShoulder = 110; p.rElbow = 0; p.rKnee = 15; p.headTilt = -40; return p }()
    static let eightPoint: Pose = { var p = Pose(); p.prone = true; p.bow = 5; p.crouch = 0.45; p.rShoulder = 40; p.rElbow = 90; p.rKnee = 70; return p }()
    static let cobra: Pose = { var p = Pose(); p.prone = true; p.bow = 50; p.crouch = 0; p.rShoulder = 20; p.rElbow = 60; p.rKnee = 0; p.headTilt = 10; return p }()
    static let lieFlat: Pose = { var p = Pose(); p.prone = true; p.bow = 0; p.rShoulder = 70; p.rElbow = 60; return p }()
    static let faceRub = standing { $0.lShoulder = 25; $0.rShoulder = 25; $0.lElbow = 160; $0.rElbow = 160 }
    static let neckStretchR = standing { $0.headTilt = 30; $0.rShoulder = 25; $0.rElbow = 150; $0.lShoulder = 20; $0.lElbow = -10 }
    static let pushForward = standing { $0.lShoulder = 85; $0.rShoulder = 85; $0.lElbow = 5; $0.rElbow = 5; $0.hands = .palmDown }
    static let twistSitR = seated { $0.lHip = -40; $0.rHip = 30; $0.rKnee = 60; $0.headTurn = 55; $0.lShoulder = 70; $0.lElbow = 40; $0.rShoulder = 30; $0.rElbow = -20 }
    static let kneeHugR = standing { $0.rHip = 75; $0.rKnee = 120; $0.lShoulder = 40; $0.rShoulder = 40; $0.lElbow = 110; $0.rElbow = 110 }
    static let sitTall = seated { $0.lHip = 35; $0.rHip = 35; $0.lShoulder = 28; $0.rShoulder = 28; $0.lElbow = 60; $0.rElbow = 60 }
    static let scalpTap = standing { $0.lShoulder = 40; $0.rShoulder = 40; $0.lElbow = 165; $0.rElbow = 165 }
    static let shoulderTapR = standing { $0.lShoulder = 45; $0.lElbow = 150; $0.rShoulder = 15 }
    static let armTapR = standing { $0.rShoulder = 80; $0.rElbow = 0; $0.lShoulder = 45; $0.lElbow = 110 }
    static let chestTap = standing { $0.lShoulder = 30; $0.rShoulder = 30; $0.lElbow = 130; $0.rElbow = 130; $0.hands = .fist }
    static let lowBack = standing { $0.lShoulder = -20; $0.rShoulder = -20; $0.lElbow = -70; $0.rElbow = -70 }
    static let legTap = standing { $0.bow = 35; $0.lKnee = 20; $0.rKnee = 20; $0.lShoulder = 30; $0.rShoulder = 30 }
    static let chinChest = standing { $0.headTilt = 0; $0.bow = 8; $0.lShoulder = 10; $0.rShoulder = 10 }
    static let shouldersUp = standing { $0.lShoulder = 10; $0.rShoulder = 10; $0.lift = 0.3; $0.lElbow = 15; $0.rElbow = 15 }
    static let shouldersBack = standing { $0.lShoulder = -12; $0.rShoulder = -12; $0.lElbow = 10; $0.rElbow = 10; $0.bow = -6 }
    static let wrists = standing { $0.lShoulder = 60; $0.rShoulder = 60; $0.lElbow = 90; $0.rElbow = 90; $0.hands = .fist }
    static let wristsOpen = standing { $0.lShoulder = 60; $0.rShoulder = 60; $0.lElbow = 90; $0.rElbow = 90; $0.hands = .palmUp }
    static let spineRound = standing { $0.bow = 55; $0.lShoulder = 15; $0.rShoulder = 15 }
    static let spineOpen = standing { $0.bow = -15; $0.lShoulder = 120; $0.rShoulder = 120; $0.lift = 0.3 }
    static let hipsL = standing { $0.lean = -14; $0.lShoulder = 55; $0.rShoulder = 55; $0.lElbow = 120; $0.rElbow = 120 }
    static let kneeCircle = standing { $0.lKnee = 35; $0.rKnee = 35; $0.crouch = 0.4; $0.bow = 30; $0.lShoulder = 30; $0.rShoulder = 30; $0.lElbow = 70; $0.rElbow = 70 }
    static let ankleLift = standing { $0.rHip = 25; $0.rKnee = 70; $0.lShoulder = 15; $0.rShoulder = 15 }
    static let shake = standing { $0.lShoulder = 35; $0.rShoulder = 35; $0.lElbow = 40; $0.rElbow = 40; $0.lKnee = 15; $0.rKnee = 15; $0.lean = 6 }

    static let armsHigh = standing { $0.lShoulder = 165; $0.rShoulder = 165 }
    static let armsLow = standing { $0.lShoulder = 20; $0.rShoulder = 20 }
    static let breathArms = standing { $0.lShoulder = 150; $0.rShoulder = 150; $0.lElbow = 20; $0.rElbow = 20 }
    static let breathArmsLow = standing { $0.lShoulder = 60; $0.rShoulder = 60; $0.lElbow = 20; $0.rElbow = 20 }
    static let kneel = seated { $0.lHip = -70; $0.rHip = -70 }
    static let handsNearFace = standing { $0.lShoulder = 20; $0.rShoulder = 20; $0.lElbow = 140; $0.rElbow = 140 }
    static let scalpTapWide = standing { $0.lShoulder = 50; $0.rShoulder = 50; $0.lElbow = 150; $0.rElbow = 150 }
    static let earsRub = standing { $0.lShoulder = 45; $0.rShoulder = 45; $0.lElbow = 155; $0.rElbow = 155 }
    static let armTapR2 = standing { $0.rShoulder = 80; $0.lShoulder = 75; $0.lElbow = 40 }
    static let lowBack2 = standing { $0.lShoulder = -25; $0.rShoulder = -25; $0.lElbow = -90; $0.rElbow = -90 }
    static let plank: Pose = { var p = Pose(); p.prone = true; p.crouch = 0.5; p.rShoulder = 90; return p }()

    static let fallback = PoseMotion(from: stand, to: armsOut)

    // Extra key positions used by the step-by-step sequences.
    static let palmsToChest = standing { $0.lShoulder = 55; $0.rShoulder = 55; $0.lElbow = 130; $0.rElbow = 130; $0.hands = .palmUp; $0.lift = 0.3 }
    static let floatDown = standing { $0.lShoulder = 90; $0.rShoulder = 90; $0.hands = .palmDown }
    static let horseCross = standing { $0.lHip = 28; $0.rHip = 28; $0.lKnee = 45; $0.rKnee = 45; $0.crouch = 0.8; $0.lShoulder = 60; $0.rShoulder = 60; $0.lElbow = 120; $0.rElbow = 120 }
    static let horseFists = standing { $0.lHip = 28; $0.rHip = 28; $0.lKnee = 45; $0.rKnee = 45; $0.crouch = 0.8; $0.lShoulder = 15; $0.rShoulder = 15; $0.lElbow = 110; $0.rElbow = 110; $0.hands = .fist }
    static let swayLow = standing { $0.lHip = 30; $0.rHip = 30; $0.lKnee = 40; $0.rKnee = 40; $0.crouch = 0.8; $0.bow = 45; $0.lShoulder = 40; $0.rShoulder = 40; $0.lElbow = 60; $0.rElbow = 60 }
    static let rollUp = standing { $0.bow = 30; $0.lKnee = 10; $0.rKnee = 10; $0.lShoulder = 10; $0.rShoulder = 10 }
    static let cloudMid = standing { $0.lHip = 22; $0.rHip = 22; $0.lKnee = 30; $0.rKnee = 30; $0.crouch = 0.5; $0.lShoulder = 65; $0.rShoulder = 65; $0.lElbow = 65; $0.rElbow = 65 }
    static let kneelLean = seated { $0.lHip = -70; $0.rHip = -70; $0.bow = -15; $0.lShoulder = -30; $0.rShoulder = -30; $0.lElbow = -10; $0.rElbow = -10 }
    static let lungeLow = standing { $0.rHip = 85; $0.rKnee = 90; $0.lHip = -35; $0.lKnee = 75; $0.crouch = 1.0; $0.lShoulder = 15; $0.rShoulder = 15; $0.bow = 25 }

    /// Step-by-step breakdowns for the moves that are hard to follow from a two-pose loop.
    static let sequences: [String: PoseMotion] = [
        "hold up the heavens": .seq([(handsBelly, "Palms up at the belly"), (palmsToChest, "Lift to the chest"),
                                     (armsUpPalms, "Turn palms, press up"), (floatDown, "Float arms down")], beat: 2.2, peak: 2),
        "draw the bow": .seq([(wuji, "Stand tall"), (horse, "Sink into horse"), (horseCross, "Cross wrists"),
                              (bowDraw, "Draw the bow, look out"), (horse, "Release")], beat: 2.0, peak: 3),
        "separate heaven and earth": .seq([(handsBelly, "Hands at belly"), (heavenEarth, "Right up, left down"),
                                           (handsBelly, "Return"), (heavenEarth.mirrored(), "Switch sides")], beat: 2.2),
        "sway head and tail": .seq([(horse, "Horse stance"), (swayLeft, "Lean left"),
                                    (swayLow, "Swing through low"), (swayLeft.mirrored(), "Lean right")], beat: 2.0),
        "touch the toes": .seq([(armsHigh, "Reach up"), (halfFold, "Hinge at hips"), (fold, "Hands to toes"),
                                (rollUp, "Roll up slowly")], beat: 2.2, peak: 2),
        "punch with angry eyes": .seq([(horseFists, "Fists at the waist"), (punchR, "Punch right, eyes wide"),
                                       (horseFists, "Pull back"), (punchR.mirrored(), "Punch left")], beat: 1.4),
        "cloud hands left": .seq([(cloudR, "Right hand high"), (cloudMid, "Turn through centre"), (cloudL, "Left hand high")], beat: 2.0, peak: 2),
        "cloud hands right": .seq([(cloudL, "Left hand high"), (cloudMid, "Turn through centre"), (cloudR, "Right hand high")], beat: 2.0, peak: 2),
        "arm circles": .seq([(armsLow, "Arms down"), (armsOut, "Out wide"), (armsUp, "Overhead"), (armsOut, "Back down wide")], beat: 0.9, peak: 2),
        "body circles": .seq([(circleHi, "Reach up"), (sideBendR, "Arc to the side"), (circleLo, "Sweep low"),
                              (sideBendR.mirrored(), "Up the other side")], beat: 1.2),
        "kneeling recline": .seq([(kneel, "Kneel, sit on heels"), (kneelLean, "Hands behind, lean back"),
                                  (kneelRecline, "Recline only if easy")], beat: 2.6, peak: 2),
        "twisting hermit": .seq([(sitTall, "Sit tall"), (twistSitR, "Twist right"), (sitTall, "Back to centre"),
                                 (twistSitR.mirrored(), "Twist left")], beat: 2.4),
        "knee-hug": .seq([(stand, "Stand tall"), (kneeHugR, "Hug right knee"), (stand, "Lower"),
                          (kneeHugR.mirrored(), "Hug left knee")], beat: 2.2),
        "low lunge": .seq([(fold, "Hands down"), (lungeLow, "Step back, drop the knee"), (lungeR, "Arms overhead")], beat: 2.4, peak: 2),
        "mountain / downward dog": .seq([(lieFlat, "Hands under shoulders"), (plank, "Plank"), (downDog, "Hips up and back")], beat: 2.4, peak: 2),
        "eight-point bow": .seq([(downDog, "From down dog"), (plank, "Lower to plank"), (eightPoint, "Knees, chest, chin down")], beat: 2.4, peak: 2),
        "butterfly bow": .seq([(butterfly, "Soles together"), (sitTall, "Sit tall"), (butterflyFold, "Fold forward on exhale")], beat: 2.4, peak: 2),
        "straight-leg bow": .seq([(longSit, "Legs long, spine tall"), (longSitFold, "Reach toward the toes")], beat: 2.6),
        "wide-leg bow": .seq([(wideSit, "Legs wide"), (wideSitFold, "Walk hands forward")], beat: 2.6),
    ]

    /// Exact step names (lowercased) from practices.json.
    static let byName: [String: PoseMotion] = [
        // Baduanjin
        "ready stance": PoseMotion(from: wuji, to: handsBelly, cycle: 4.5),
        "hold up the heavens": PoseMotion(from: handsBelly, to: armsUpPalms, cycle: 4.5),
        "draw the bow": PoseMotion(from: horse, to: bowDraw, cycle: 4),
        "separate heaven and earth": PoseMotion(from: heavenEarth.mirrored(), to: heavenEarth, cycle: 4),
        "look back": PoseMotion(from: lookBack.mirrored(), to: lookBack, cycle: 5),
        "sway head and tail": PoseMotion(from: swayLeft, to: swayLeft.mirrored(), cycle: 4.5),
        "touch the toes": PoseMotion(from: armsHigh, to: fold, cycle: 5),
        "punch with angry eyes": PoseMotion(from: punchR.mirrored(), to: punchR, cycle: 2.6),
        "bounce on the heels": PoseMotion(from: wuji, to: tiptoe, cycle: 2.2),
        "close": PoseMotion.still(handsBelly),
        // Tai chi
        "wuji standing": PoseMotion.still(wuji),
        "commencing form": PoseMotion(from: wuji, to: floatArms, cycle: 5),
        "cloud hands left": PoseMotion(from: cloudR, to: cloudL, cycle: 4.5),
        "cloud hands right": PoseMotion(from: cloudL, to: cloudR, cycle: 4.5),
        "closing form": PoseMotion(from: crossArms, to: wuji, cycle: 5),
        // Rajio Taisō
        "stretch up": PoseMotion(from: stand, to: armsUp, cycle: 3),
        "arm swing & knee bend": PoseMotion(from: armSwingBack, to: kneeBounce, cycle: 1.8),
        "arm circles": PoseMotion(from: armsLow, to: armsUp, cycle: 2.4),
        "chest opener": PoseMotion(from: crossArms, to: chestOpen, cycle: 2.6),
        "side bend": PoseMotion(from: sideBendR.mirrored(), to: sideBendR, cycle: 3.4),
        "forward & back bend": PoseMotion(from: fold, to: backBend, cycle: 4),
        "body twist": PoseMotion(from: twistR.mirrored(), to: twistR, cycle: 2.6),
        "arms up & down": PoseMotion(from: handsShoulders, to: punchUp, cycle: 2),
        "diagonal bend & chest": PoseMotion(from: diagDown, to: chestOpen, cycle: 3),
        "body circles": PoseMotion(from: circleHi, to: circleLo, cycle: 3.6),
        "hops": PoseMotion(from: kneeBounce, to: hop, cycle: 1.2),
        "deep breath": PoseMotion(from: stand, to: breathArms, cycle: 6),
        // Makkō-hō
        "butterfly bow": PoseMotion(from: butterfly, to: butterflyFold, cycle: 5),
        "straight-leg bow": PoseMotion(from: longSit, to: longSitFold, cycle: 5),
        "wide-leg bow": PoseMotion(from: wideSit, to: wideSitFold, cycle: 5),
        "kneeling recline": PoseMotion(from: kneel, to: kneelRecline, cycle: 6),
        // Sūrya Namaskār
        "prayer pose": PoseMotion.still(prayer),
        "raised arms": PoseMotion(from: prayer, to: raisedArmsBack, cycle: 5),
        "forward fold": PoseMotion(from: halfFold, to: fold, cycle: 5),
        "low lunge": PoseMotion(from: fold, to: lungeR, cycle: 5),
        "mountain / downward dog": PoseMotion(from: lieFlat, to: downDog, cycle: 5),
        "eight-point bow": PoseMotion(from: downDog, to: eightPoint, cycle: 5),
        "cobra": PoseMotion(from: lieFlat, to: cobra, cycle: 5),
        // Ruesi Dat Ton
        "face & eye massage": PoseMotion(from: handsNearFace, to: faceRub, cycle: 3),
        "neck stretch": PoseMotion(from: neckStretchR.mirrored(), to: neckStretchR, cycle: 5),
        "shoulder & arm pull": PoseMotion(from: pushForward, to: armsUpPalms, cycle: 4.5),
        "twisting hermit": PoseMotion(from: sitTall, to: twistSitR, cycle: 5),
        "forward-reaching hermit": PoseMotion(from: longSit, to: longSitFold, cycle: 5),
        "knee-hug": PoseMotion(from: kneeHugR.mirrored(), to: kneeHugR, cycle: 5),
        "rest": PoseMotion.still(sitTall),
        // Do-in
        "scalp tapping": PoseMotion(from: scalpTap, to: scalpTapWide, cycle: 1.4),
        "face & ears": PoseMotion(from: faceRub, to: earsRub, cycle: 2.4),
        "neck & shoulders": PoseMotion(from: shoulderTapR.mirrored(), to: shoulderTapR, cycle: 3),
        "arms": PoseMotion(from: armTapR, to: armTapR2, cycle: 2.2),
        "chest & belly": PoseMotion(from: chestTap, to: handsBelly, cycle: 2.6),
        "lower back": PoseMotion(from: lowBack, to: lowBack2, cycle: 1.6),
        "legs & feet": PoseMotion(from: legTap, to: fold, cycle: 3),
        // Lu Jong-style
        "settle": PoseMotion.still(wuji),
        "neck": PoseMotion(from: chinChest, to: neckStretchR, cycle: 5),
        "shoulders": PoseMotion(from: shouldersUp, to: shouldersBack, cycle: 3),
        "wrists & hands": PoseMotion(from: wrists, to: wristsOpen, cycle: 2.4),
        "spine": PoseMotion(from: spineRound, to: spineOpen, cycle: 5),
        "hips": PoseMotion(from: hipsL, to: hipsL.mirrored(), cycle: 3.6),
        "knees & ankles": PoseMotion(from: kneeCircle, to: ankleLift, cycle: 4),
        "shake out": PoseMotion(from: shake, to: shake.mirrored(), cycle: 0.9),
    ]

    /// Keyword fallbacks for steps added later.
    static let rules: [([String], PoseMotion)] = [
        (["downward dog", "down dog"], PoseMotion(from: lieFlat, to: downDog, cycle: 5)),
        (["cobra", "upward dog"], PoseMotion(from: lieFlat, to: cobra, cycle: 5)),
        (["plank"], PoseMotion.still(plank)),
        (["lunge"], PoseMotion(from: fold, to: lungeR, cycle: 5)),
        (["chair", "squat", "horse stance"], PoseMotion(from: stand, to: horse, cycle: 4)),
        (["fold", "toes", "touch the floor"], PoseMotion(from: halfFold, to: fold, cycle: 5)),
        (["twist"], PoseMotion(from: twistR.mirrored(), to: twistR, cycle: 3)),
        (["side bend", "bend sideways"], PoseMotion(from: sideBendR.mirrored(), to: sideBendR, cycle: 3.4)),
        (["neck", "ear toward", "chin"], PoseMotion(from: chinChest, to: neckStretchR, cycle: 5)),
        (["shoulder roll", "shoulders"], PoseMotion(from: shouldersUp, to: shouldersBack, cycle: 3)),
        (["wrist", "fingers"], PoseMotion(from: wrists, to: wristsOpen, cycle: 2.4)),
        (["hip"], PoseMotion(from: hipsL, to: hipsL.mirrored(), cycle: 3.6)),
        (["knee", "ankle"], PoseMotion(from: kneeCircle, to: ankleLift, cycle: 4)),
        (["punch", "fist"], PoseMotion(from: punchR.mirrored(), to: punchR, cycle: 2.6)),
        (["overhead", "skyward", "reach up", "arms up", "stretch tall"], PoseMotion(from: handsBelly, to: armsUpPalms, cycle: 4.5)),
        (["bow", "arrow"], PoseMotion(from: horse, to: bowDraw, cycle: 4)),
        (["look back", "look behind"], PoseMotion(from: lookBack.mirrored(), to: lookBack, cycle: 5)),
        (["toe", "heel", "bounce", "hop", "jump"], PoseMotion(from: wuji, to: tiptoe, cycle: 2.2)),
        (["massage", "rub", "tap"], PoseMotion(from: faceRub, to: chestTap, cycle: 2.6)),
        (["kneel"], PoseMotion(from: kneel, to: kneelRecline, cycle: 6)),
        (["sit", "seated"], PoseMotion(from: sitTall, to: longSitFold, cycle: 5)),
        (["shake"], PoseMotion(from: shake, to: shake.mirrored(), cycle: 0.9)),
        (["breath", "breathe", "stand", "settle", "rest", "still"], PoseMotion(from: wuji, to: breathArmsLow, cycle: 6)),
    ]

    /// Posture hint for sitting practices (breathing/focus): cross-legged or on a chair.
    static let seatedCrossLegged = PoseMotion.still(seated { $0.lHip = 35; $0.rHip = 35; $0.lShoulder = 24; $0.rShoulder = 24; $0.lElbow = 55; $0.rElbow = 55; $0.hands = .palmUp })
    static let seatedChair = PoseMotion.still(seated { $0.lHip = -20; $0.rHip = -20; $0.lShoulder = 20; $0.rShoulder = 20; $0.lElbow = 70; $0.rElbow = 70; $0.hands = .palmDown })
}
