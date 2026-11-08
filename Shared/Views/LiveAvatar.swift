import SwiftUI

/// A little toy-model marker that rides along the live route instead of the blue dot:
/// a 90s full-size pickup for drives, a mini you walking, running or hiking, and an e-bike.
/// Everything is drawn in one Canvas, driven by one TimelineView.
struct LiveAvatar: View {
    let kind: ActivityKind          // .walk, .run, .hike, .bike, .drive
    let speed: Double               // m/s, current
    let course: Double              // degrees clockwise from north, -1 if unknown
    let mapHeading: Double          // current map camera heading in degrees
    var overLimit: Bool = false     // driving over the speed limit → red glow, tail light, speed lines

    @State private var facingLeft = false

    private static let side: CGFloat = 80

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let s = min(size.width, size.height) / Self.side
                var ctx = context
                ctx.scaleBy(x: s, y: s)
                drawGround(ctx, t: t)
                var fig = ctx
                if facingLeft {
                    fig.translateBy(x: Self.side, y: 0)
                    fig.scaleBy(x: -1, y: 1)
                }
                switch kind {
                case .drive: drawTruck(fig, t: t)
                case .bike: drawBike(fig, t: t)
                case .walk, .run, .hike: drawPerson(fig, t: t)
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .onChange(of: course, initial: true) { _, _ in updateFacing() }
        .onChange(of: mapHeading) { _, _ in updateFacing() }
        .accessibilityHidden(true)
    }

    // MARK: - Shared bits

    private var moving: Bool { speed >= 0.3 }

    /// Course relative to the screen, degrees (0 = up, 90 = right).
    private var screenBearing: Double { course - mapHeading }

    private func updateFacing() {
        guard course >= 0 else { return }   // unknown course: keep the last facing
        let b = screenBearing * .pi / 180
        let s = sin(b)
        if abs(s) > 0.08 { facingLeft = s < 0 }   // small dead zone so it doesn't flicker heading straight up/down
    }

    private var ringColor: Color { overLimit ? Color(red: 1, green: 0.22, blue: 0.25) : Theme.glow }

    private func drawGround(_ ctx: GraphicsContext, t: Double) {
        let ring = CGRect(x: 12, y: 59, width: 56, height: 14)
        // Soft glow + ring
        ctx.fill(Path(ellipseIn: ring), with: .color(ringColor.opacity(overLimit ? 0.22 + 0.12 * sin(t * 10) : 0.16)))
        ctx.stroke(Path(ellipseIn: ring), with: .color(ringColor.opacity(0.75)), lineWidth: 1.6)
        // Contact shadow
        ctx.fill(Path(ellipseIn: CGRect(x: 19, y: 62, width: 42, height: 8)), with: .color(.black.opacity(0.32)))

        // Direction chevron on the ring
        guard course >= 0 else { return }
        let b = screenBearing * .pi / 180
        let dx = sin(b), dy = -cos(b) * 0.25          // squash onto the ground ellipse
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let ux = dx / len, uy = dy / len
        let c = CGPoint(x: 40 + CGFloat(sin(b)) * 31, y: 66 + CGFloat(-cos(b)) * 8)
        let px = CGFloat(-uy), py = CGFloat(ux)        // perpendicular
        let tip = CGPoint(x: c.x + CGFloat(ux) * 4.5, y: c.y + CGFloat(uy) * 4.5)
        let l = CGPoint(x: c.x - CGFloat(ux) * 2.5 + px * 3.5, y: c.y - CGFloat(uy) * 2.5 + py * 3.5)
        let r = CGPoint(x: c.x - CGFloat(ux) * 2.5 - px * 3.5, y: c.y - CGFloat(uy) * 2.5 - py * 3.5)
        var chev = Path()
        chev.move(to: l); chev.addLine(to: tip); chev.addLine(to: r)
        ctx.stroke(chev, with: .color(ringColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// Rotate a path around a pivot.
    private static func rotated(_ p: Path, by angle: Double, around c: CGPoint) -> Path {
        let tr = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: CGFloat(angle))
            .translatedBy(x: -c.x, y: -c.y)
        return p.applying(tr)
    }

    /// A capsule "limb" from `a` to `b`.
    private static func limb(_ a: CGPoint, _ b: CGPoint, width w: CGFloat) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    private static func point(_ o: CGPoint, angle: Double, length: CGFloat) -> CGPoint {
        // angle 0 = straight down, positive swings forward (to the right).
        CGPoint(x: o.x + CGFloat(sin(angle)) * length, y: o.y + CGFloat(cos(angle)) * length)
    }

    private static func wheel(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, angle: Double,
                              tire: Color, hub: Color, spokes: Int, spokeColor: Color, tireWidth: CGFloat) {
        let outer = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: outer), with: .color(tire))
        let inner = r - tireWidth
        let rim = CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)
        ctx.fill(Path(ellipseIn: rim), with: .color(hub))
        var sp = Path()
        for i in 0..<spokes {
            let a = angle + Double(i) * 2 * .pi / Double(spokes)
            sp.move(to: c)
            sp.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * inner, y: c.y + CGFloat(sin(a)) * inner))
        }
        ctx.stroke(sp, with: .color(spokeColor), lineWidth: max(0.8, inner * 0.22))
        let cap = inner * 0.32
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - cap, y: c.y - cap, width: cap * 2, height: cap * 2)), with: .color(spokeColor))
    }

    // MARK: - Pickup truck

    private func drawTruck(_ base: GraphicsContext, t: Double) {
        let red = Color(red: 0.55, green: 0.06, blue: 0.09)
        let redHi = Color(red: 0.72, green: 0.12, blue: 0.14)
        let silver = Color(red: 0.74, green: 0.76, blue: 0.80)
        let chrome = Color(red: 0.90, green: 0.92, blue: 0.95)
        let glass = Color(red: 0.12, green: 0.18, blue: 0.26)
        let tireC = Color(red: 0.08, green: 0.08, blue: 0.09)

        // Speed lines and exhaust sit behind the truck (unbobbed).
        if overLimit {
            for i in 0..<3 {
                let ph = (t * 3.2 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let y = CGFloat(30 + i * 9)
                let x0 = CGFloat(-4 + ph * 3)
                var line = Path()
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: x0 + CGFloat(6 + (1 - ph) * 6), y: y))
                base.stroke(line, with: .color(.white.opacity(0.75 * (1 - ph))),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        if moving {
            for i in 0..<3 {
                let p = (t * 1.3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(1.6 + p * 3.6)
                let c = CGPoint(x: CGFloat(5 - p * 13), y: CGFloat(54 - p * 7))
                base.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .color(Color(white: 0.85).opacity(0.45 * (1 - p))))
            }
        }

        var ctx = base
        let bob = moving ? sin(t * 13) * 0.55 : sin(t * 2.2) * 0.25
        ctx.translateBy(x: 0, y: CGFloat(bob))

        // Wheel wells
        for x in [CGFloat(19), CGFloat(63)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 10.5, y: 46, width: 21, height: 21)), with: .color(.black.opacity(0.55)))
        }

        // Bed (long box)
        let bed = Path(roundedRect: CGRect(x: 4, y: 33, width: 37, height: 21), cornerRadius: 2)
        ctx.fill(bed, with: .color(red))
        // Bed rail highlight
        ctx.fill(Path(roundedRect: CGRect(x: 4, y: 33, width: 37, height: 2.4), cornerRadius: 1.2), with: .color(redHi))

        // Cab: tall, squared-off
        var cab = Path()
        cab.move(to: CGPoint(x: 40, y: 54))
        cab.addLine(to: CGPoint(x: 40, y: 21))
        cab.addLine(to: CGPoint(x: 55, y: 21))
        cab.addLine(to: CGPoint(x: 59, y: 33))
        cab.addLine(to: CGPoint(x: 59, y: 54))
        cab.closeSubpath()
        ctx.fill(cab, with: .color(red))
        ctx.fill(Path(roundedRect: CGRect(x: 40, y: 21, width: 15, height: 2), cornerRadius: 1), with: .color(redHi))

        // Tall hood running to the big upright grille
        let hood = Path(roundedRect: CGRect(x: 58, y: 33, width: 17, height: 21), cornerRadius: 1.5)
        ctx.fill(hood, with: .color(red))
        ctx.fill(Path(roundedRect: CGRect(x: 58, y: 33, width: 17, height: 2.2), cornerRadius: 1.1), with: .color(redHi))

        // Tinted window (slight rake at the front)
        var win = Path()
        win.move(to: CGPoint(x: 43, y: 24))
        win.addLine(to: CGPoint(x: 53.5, y: 24))
        win.addLine(to: CGPoint(x: 56.5, y: 33))
        win.addLine(to: CGPoint(x: 43, y: 33))
        win.closeSubpath()
        ctx.fill(win, with: .color(glass))
        var glint = Path()
        glint.move(to: CGPoint(x: 46, y: 32))
        glint.addLine(to: CGPoint(x: 50, y: 25.5))
        ctx.stroke(glint, with: .color(.white.opacity(0.35)), lineWidth: 1.2)
        // Door seam + handle
        var seam = Path()
        seam.move(to: CGPoint(x: 42, y: 35)); seam.addLine(to: CGPoint(x: 42, y: 47))
        ctx.stroke(seam, with: .color(.black.opacity(0.3)), lineWidth: 0.6)
        ctx.fill(Path(roundedRect: CGRect(x: 52, y: 36.5, width: 4, height: 1.4), cornerRadius: 0.7), with: .color(chrome))
        // Side mirror
        ctx.fill(Path(roundedRect: CGRect(x: 57, y: 29, width: 4.5, height: 4), cornerRadius: 1), with: .color(Color(white: 0.15)))

        // Two-tone silver lower band
        ctx.fill(Path(roundedRect: CGRect(x: 4, y: 47, width: 71, height: 7), cornerRadius: 1.5), with: .color(silver))
        var pin = Path()
        pin.move(to: CGPoint(x: 4, y: 47)); pin.addLine(to: CGPoint(x: 75, y: 47))
        ctx.stroke(pin, with: .color(.black.opacity(0.25)), lineWidth: 0.6)

        // Upright chrome grille with crosshair bars, and big rectangular headlight
        let grille = CGRect(x: 74, y: 35, width: 4, height: 13)
        ctx.fill(Path(roundedRect: grille, cornerRadius: 0.8), with: .color(chrome))
        var bars = Path()
        bars.move(to: CGPoint(x: 74, y: 41.5)); bars.addLine(to: CGPoint(x: 78, y: 41.5))
        bars.move(to: CGPoint(x: 76, y: 35)); bars.addLine(to: CGPoint(x: 76, y: 48))
        ctx.stroke(bars, with: .color(Color(white: 0.45)), lineWidth: 0.8)
        let lamp = CGRect(x: 71.5, y: 36, width: 3, height: 4.5)
        ctx.fill(Path(roundedRect: lamp, cornerRadius: 0.6), with: .color(Color(red: 1, green: 0.97, blue: 0.85)))
        if moving {
            var beam = Path()
            beam.move(to: CGPoint(x: 78, y: 37)); beam.addLine(to: CGPoint(x: 80, y: 35.5))
            beam.addLine(to: CGPoint(x: 80, y: 41)); beam.closeSubpath()
            ctx.fill(beam, with: .color(Color(red: 1, green: 0.95, blue: 0.7).opacity(0.35)))
        }

        // Chrome bumpers
        ctx.fill(Path(roundedRect: CGRect(x: 72, y: 50, width: 7, height: 4.5), cornerRadius: 1.4), with: .color(chrome))
        ctx.fill(Path(roundedRect: CGRect(x: 1.5, y: 50, width: 6, height: 4.5), cornerRadius: 1.4), with: .color(chrome))

        // Tail light (glows and flashes when over the limit)
        let tail = CGRect(x: 3, y: 35, width: 3, height: 8)
        if overLimit {
            let a = 0.45 + 0.35 * (0.5 + 0.5 * sin(t * 14))
            ctx.fill(Path(ellipseIn: tail.insetBy(dx: -4, dy: -4)), with: .color(Color.red.opacity(a * 0.55)))
        }
        ctx.fill(Path(roundedRect: tail, cornerRadius: 0.8),
                 with: .color(overLimit ? Color(red: 1, green: 0.25, blue: 0.25) : Color(red: 0.75, green: 0.08, blue: 0.1)))

        // Chunky tires with chrome hubs
        let spin = moving ? t * min(speed / 0.38, 16) : 0
        for x in [CGFloat(19), CGFloat(63)] {
            Self.wheel(ctx, center: CGPoint(x: x, y: 57), radius: 8.5, angle: spin,
                       tire: tireC, hub: Color(white: 0.55), spokes: 5, spokeColor: chrome, tireWidth: 3.6)
        }
    }

    // MARK: - Mini person

    private func drawPerson(_ base: GraphicsContext, t: Double) {
        let isRun = kind == .run
        let isHike = kind == .hike
        let skin = Color(red: 0.93, green: 0.74, blue: 0.58)
        let hoodie = Theme.sky
        let hoodieDark = Color(red: 0.28, green: 0.52, blue: 0.75)
        let pants = Color(red: 0.16, green: 0.20, blue: 0.32)
        let pantsBack = Color(red: 0.11, green: 0.14, blue: 0.23)
        let shoe = Color.white
        let cap = Color(red: 0.12, green: 0.12, blue: 0.14)

        let baseHz = isRun ? 2.8 : 1.8
        let refSpeed = isRun ? 3.2 : 1.4
        let hz = baseHz * min(max(speed / refSpeed, 0.7), 1.4)
        let phase = t * 2 * .pi * hz
        let swing: Double = moving ? (isRun ? 0.85 : 0.5) : 0
        let armSwing: Double = moving ? (isRun ? 1.0 : 0.55) : 0.08

        var ctx = base
        let bob = moving ? -abs(sin(phase)) * (isRun ? 2.2 : 1.3) : sin(t * 2.2) * 0.45
        ctx.translateBy(x: 0, y: CGFloat(bob))
        if moving {
            // Lean forward around the feet
            ctx.translateBy(x: 40, y: 64)
            ctx.rotate(by: .degrees(isRun ? 9 : 3))
            ctx.translateBy(x: -40, y: -64)
        }

        let hip = CGPoint(x: 40, y: 46)
        let shoulder = CGPoint(x: 40, y: 34)
        let legLen: CGFloat = 16
        let armLen: CGFloat = 12.5

        let legA = sin(phase) * swing
        let legB = -legA
        let armA = -sin(phase) * armSwing
        let armB = -armA

        func leg(_ a: Double, color: Color) {
            // Knee bend on the back-swing for a livelier stride
            let knee = Self.point(hip, angle: a, length: legLen * 0.52)
            let bend = moving ? max(0, -a) * (isRun ? 1.4 : 0.9) : 0
            let foot = Self.point(knee, angle: a - bend, length: legLen * 0.48)
            ctx.fill(Self.limb(hip, knee, width: 6), with: .color(color))
            ctx.fill(Self.limb(knee, foot, width: 5.5), with: .color(color))
            let sh = Path(roundedRect: CGRect(x: foot.x - 3, y: foot.y - 1.5, width: 7.5, height: 4), cornerRadius: 2)
            ctx.fill(sh, with: .color(shoe))
            ctx.fill(Path(roundedRect: CGRect(x: foot.x - 3, y: foot.y + 1.6, width: 7.5, height: 1.2), cornerRadius: 0.6),
                     with: .color(Color(white: 0.6)))
        }
        func arm(_ a: Double, color: Color) -> CGPoint {
            let elbow = Self.point(shoulder, angle: a, length: armLen * 0.5)
            let bend = isRun && moving ? -1.2 : -0.25
            let hand = Self.point(elbow, angle: a - bend, length: armLen * 0.5)
            ctx.fill(Self.limb(shoulder, elbow, width: 4.6), with: .color(color))
            ctx.fill(Self.limb(elbow, hand, width: 4.2), with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: hand.x - 2, y: hand.y - 2, width: 4, height: 4)), with: .color(skin))
            return hand
        }

        // Back limbs first
        leg(legB, color: pantsBack)
        _ = arm(armB, color: hoodieDark)

        // Backpack for hikes (on the back = left side)
        if isHike {
            ctx.fill(Path(roundedRect: CGRect(x: 27.5, y: 32, width: 8, height: 14), cornerRadius: 2.5),
                     with: .color(Color(red: 0.85, green: 0.45, blue: 0.15)))
            ctx.fill(Path(roundedRect: CGRect(x: 27.5, y: 37, width: 8, height: 2), cornerRadius: 1),
                     with: .color(Color(red: 0.6, green: 0.3, blue: 0.1)))
        }

        // Hoodie torso
        ctx.fill(Path(roundedRect: CGRect(x: 33.5, y: 31, width: 13, height: 17), cornerRadius: 5), with: .color(hoodie))
        ctx.fill(Path(roundedRect: CGRect(x: 36, y: 42, width: 8, height: 3.5), cornerRadius: 1.5), with: .color(hoodieDark))
        var string = Path()
        string.move(to: CGPoint(x: 42.5, y: 32)); string.addLine(to: CGPoint(x: 42.5, y: 37))
        ctx.stroke(string, with: .color(.white.opacity(0.8)), lineWidth: 0.7)

        // Front leg
        leg(legA, color: pants)

        // Head + backwards cap (brim points back)
        let head = CGRect(x: 32, y: 13, width: 17, height: 17)
        ctx.fill(Path(ellipseIn: head), with: .color(skin))
        var dome = Path()
        dome.addArc(center: CGPoint(x: 40.5, y: 21), radius: 8.6, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.closeSubpath()
        ctx.fill(dome, with: .color(cap))
        ctx.fill(Path(roundedRect: CGRect(x: 26.5, y: 18.5, width: 8, height: 2.6), cornerRadius: 1.3), with: .color(cap))
        // Eye + smile
        ctx.fill(Path(ellipseIn: CGRect(x: 44, y: 22.5, width: 2, height: 2.4)), with: .color(Color(white: 0.1)))
        var smile = Path()
        smile.addArc(center: CGPoint(x: 44.5, y: 25.5), radius: 2.2, startAngle: .degrees(20), endAngle: .degrees(110), clockwise: false)
        ctx.stroke(smile, with: .color(Color(white: 0.15)), lineWidth: 0.8)

        // Front arm (and walking stick on hikes)
        let hand = arm(armA, color: hoodie)
        if isHike {
            var stick = Path()
            stick.move(to: CGPoint(x: hand.x + 0.5, y: hand.y - 4))
            stick.addLine(to: CGPoint(x: hand.x + 3.5, y: 64))
            ctx.stroke(stick, with: .color(Theme.bark), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    // MARK: - E-bike

    private func drawBike(_ base: GraphicsContext, t: Double) {
        let frameC = Theme.glow
        let skin = Color(red: 0.93, green: 0.74, blue: 0.58)
        let hoodie = Theme.sky
        let pants = Color(red: 0.16, green: 0.20, blue: 0.32)
        let pantsBack = Color(red: 0.11, green: 0.14, blue: 0.23)
        let cap = Color(red: 0.12, green: 0.12, blue: 0.14)

        var ctx = base
        let bob = moving ? sin(t * 9) * 0.35 : sin(t * 2.2) * 0.3
        ctx.translateBy(x: 0, y: CGFloat(bob))

        let rear = CGPoint(x: 20, y: 54)
        let front = CGPoint(x: 61, y: 54)
        let bb = CGPoint(x: 38, y: 54)
        let seat = CGPoint(x: 34, y: 36)
        let head = CGPoint(x: 55, y: 37)
        let bar = CGPoint(x: 53, y: 30)

        // Wheels (spinning spokes)
        let spin = moving ? t * min(speed / 0.35, 20) : 0
        for c in [rear, front] {
            Self.wheel(ctx, center: c, radius: 11, angle: spin, tire: Color(white: 0.08), hub: Color(white: 0.2),
                       spokes: 8, spokeColor: Color(white: 0.75), tireWidth: 2.6)
        }

        // Pedalling: crank around the bottom bracket
        let cadence = moving ? min(max(speed / 5.5, 0.6), 1.6) * 2 * .pi * 1.2 : 0
        let theta = t * cadence
        let crankR: CGFloat = 4.5
        let pedalA = CGPoint(x: bb.x + CGFloat(cos(theta)) * crankR, y: bb.y + CGFloat(sin(theta)) * crankR)
        let pedalB = CGPoint(x: bb.x - CGFloat(cos(theta)) * crankR, y: bb.y - CGFloat(sin(theta)) * crankR)
        let hip = CGPoint(x: 35, y: 33)

        func legTo(_ foot: CGPoint, color: Color) {
            let knee = Self.knee(hip: hip, foot: foot, thigh: 12.5, shin: 12.5)
            ctx.fill(Self.limb(hip, knee, width: 5.5), with: .color(color))
            ctx.fill(Self.limb(knee, foot, width: 5), with: .color(color))
            ctx.fill(Path(roundedRect: CGRect(x: foot.x - 2.5, y: foot.y - 1.5, width: 6.5, height: 3.4), cornerRadius: 1.6),
                     with: .color(.white))
        }

        // Back leg behind the frame
        legTo(pedalB, color: pantsBack)

        // Frame
        var frame = Path()
        frame.move(to: rear); frame.addLine(to: bb)          // chainstay
        frame.move(to: rear); frame.addLine(to: seat)        // seatstay
        frame.move(to: bb); frame.addLine(to: seat)          // seat tube
        frame.move(to: seat); frame.addLine(to: head)        // top tube
        frame.move(to: head); frame.addLine(to: bb)          // down tube
        frame.move(to: head); frame.addLine(to: front)       // fork
        frame.move(to: head); frame.addLine(to: bar)         // stem
        ctx.stroke(frame, with: .color(frameC), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        // Handlebar + saddle
        ctx.fill(Path(roundedRect: CGRect(x: bar.x - 1.5, y: bar.y - 1.2, width: 6, height: 2.4), cornerRadius: 1.2),
                 with: .color(Color(white: 0.15)))
        ctx.fill(Path(roundedRect: CGRect(x: seat.x - 4, y: seat.y - 2.5, width: 9, height: 3), cornerRadius: 1.5),
                 with: .color(Color(white: 0.12)))

        // Battery block on the down tube with a tiny lightning bolt
        let mid = CGPoint(x: (head.x + bb.x) / 2, y: (head.y + bb.y) / 2)
        let ang = atan2(Double(bb.y - head.y), Double(bb.x - head.x))
        let batt = Path(roundedRect: CGRect(x: mid.x - 7, y: mid.y - 2.6, width: 14, height: 5.2), cornerRadius: 1.6)
        ctx.fill(Self.rotated(batt, by: ang, around: mid), with: .color(Color(white: 0.16)))
        var bolt = Path()
        bolt.move(to: CGPoint(x: mid.x + 0.6, y: mid.y - 2.2))
        bolt.addLine(to: CGPoint(x: mid.x - 1.4, y: mid.y + 0.3))
        bolt.addLine(to: CGPoint(x: mid.x + 0.2, y: mid.y + 0.3))
        bolt.addLine(to: CGPoint(x: mid.x - 0.6, y: mid.y + 2.4))
        bolt.addLine(to: CGPoint(x: mid.x + 1.6, y: mid.y - 0.4))
        bolt.addLine(to: CGPoint(x: mid.x, y: mid.y - 0.4))
        bolt.closeSubpath()
        ctx.fill(bolt, with: .color(Color(red: 1, green: 0.88, blue: 0.1)))

        // Crank arm
        var crank = Path()
        crank.move(to: pedalA); crank.addLine(to: pedalB)
        ctx.stroke(crank, with: .color(Color(white: 0.3)), lineWidth: 1.4)

        // Rider torso leaning forward to the bars
        let shoulder = CGPoint(x: 45, y: 22)
        ctx.fill(Self.limb(hip, shoulder, width: 10), with: .color(hoodie))
        // Arm to handlebar
        ctx.fill(Self.limb(shoulder, CGPoint(x: bar.x + 1, y: bar.y - 0.5), width: 4.4), with: .color(hoodie))
        ctx.fill(Path(ellipseIn: CGRect(x: bar.x - 1, y: bar.y - 2.5, width: 4, height: 4)), with: .color(skin))

        // Head + backwards cap
        let hc = CGPoint(x: 48.5, y: 14.5)
        ctx.fill(Path(ellipseIn: CGRect(x: hc.x - 7, y: hc.y - 7, width: 14, height: 14)), with: .color(skin))
        var dome = Path()
        dome.addArc(center: hc, radius: 7.2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.closeSubpath()
        ctx.fill(dome, with: .color(cap))
        ctx.fill(Path(roundedRect: CGRect(x: hc.x - 13, y: hc.y - 2, width: 7, height: 2.2), cornerRadius: 1.1), with: .color(cap))
        ctx.fill(Path(ellipseIn: CGRect(x: hc.x + 2.5, y: hc.y + 1, width: 1.8, height: 2.1)), with: .color(Color(white: 0.1)))

        // Front leg over the frame
        legTo(pedalA, color: pants)
    }

    /// Two-bone IK: knee position for a leg from hip to foot, bending forward (+x).
    private static func knee(hip: CGPoint, foot: CGPoint, thigh: CGFloat, shin: CGFloat) -> CGPoint {
        let dx = Double(foot.x - hip.x), dy = Double(foot.y - hip.y)
        var d = (dx * dx + dy * dy).squareRoot()
        let a = Double(thigh), b = Double(shin)
        d = min(max(d, abs(a - b) + 0.01), a + b - 0.01)
        let cosA = (a * a + d * d - b * b) / (2 * a * d)
        let angA = acos(min(max(cosA, -1), 1))
        let base = atan2(dy, dx)
        // Bend toward the front: rotate counter-clockwise on screen (knee sits ahead of the hip→foot line)
        let k = base - angA
        return CGPoint(x: hip.x + CGFloat(cos(k) * a), y: hip.y + CGFloat(sin(k) * a))
    }
}

#Preview {
    HStack(spacing: 4) {
        LiveAvatar(kind: .drive, speed: 28, course: 90, mapHeading: 0, overLimit: true)
        LiveAvatar(kind: .walk, speed: 1.4, course: 90, mapHeading: 0)
        LiveAvatar(kind: .run, speed: 3.4, course: 270, mapHeading: 0)
        LiveAvatar(kind: .hike, speed: 1.1, course: 45, mapHeading: 0)
        LiveAvatar(kind: .bike, speed: 7, course: 120, mapHeading: 0)
    }
    .padding()
    .background(Color(red: 0.1, green: 0.14, blue: 0.12))
}
