import SwiftUI

/// A 1080×1350 poster of today's head-to-head, for sharing.
struct VSShareCard: View {
    let watch: DayStat?
    let whoop: DayStat?
    let readiness: Double?
    let recovery: Double?
    let watchSleep: SleepNight?
    let whoopSleep: SleepNight?

    var body: some View {
        ZStack {
            Lab.bg
            RadialGradient(colors: [Lab.violet.opacity(0.35), .clear], center: .top, startRadius: 20, endRadius: 900)
            RadialGradient(colors: [Lab.watch.opacity(0.18), .clear], center: .bottomLeading, startRadius: 20, endRadius: 800)
            RadialGradient(colors: [Lab.whoop.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 800)
            Canvas { ctx, size in
                var p = Path(); let step: CGFloat = 54
                var x: CGFloat = 0
                while x < size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(p, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
            }

            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Text("PULSE LAB").font(.system(size: 34, weight: .heavy, design: .monospaced)).tracking(12).foregroundStyle(Lab.dim)
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Lab.faint)
                }
                HStack(alignment: .center) {
                    side(.watch, score: readiness, label: "READINESS")
                    Text("VS").font(.system(size: 90, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Lab.violet.opacity(0.6), radius: 20)
                    side(.whoop, score: recovery, label: "RECOVERY")
                }
                VStack(spacing: 26) {
                    row("RESTING HR", "bpm", watch?.rhr, whoop?.rhr, 0)
                    row("HRV", "ms", watch?.hrv, whoop?.hrv, 0)
                    row("SLEEP", "h", watchSleep.map { $0.asleepMin / 60 }, whoopSleep.map { $0.asleepMin / 60 }, 1)
                    row("CALORIES", "kcal", watch?.totalKcal, whoop?.totalKcal, 0)
                }
                .padding(44)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Lab.panel.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.7), Lab.whoop.opacity(0.7)], startPoint: .leading, endPoint: .trailing), lineWidth: 3))
            }
            .padding(70)
        }
        .frame(width: 1080, height: 1350)
    }

    private func side(_ s: Source, score: Double?, label: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 22)
                Circle().trim(from: 0, to: (score ?? 0) / 100)
                    .stroke(Lab.color(s), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Lab.color(s).opacity(0.8), radius: 18)
                Text(score.map { "\(Int($0))" } ?? "––").font(.system(size: 92, weight: .heavy, design: .monospaced)).foregroundStyle(Lab.text)
            }
            .frame(width: 270, height: 270)
            Text(label).font(.system(size: 24, weight: .heavy, design: .monospaced)).tracking(4).foregroundStyle(Lab.color(s))
            Text(s.name.uppercased()).font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Lab.text)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ unit: String, _ a: Double?, _ b: Double?, _ d: Int) -> some View {
        HStack {
            Text(fmt(a, d)).font(.system(size: 58, weight: .heavy, design: .monospaced)).foregroundStyle(Lab.watch)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 22, weight: .heavy, design: .monospaced)).tracking(3).foregroundStyle(Lab.dim)
                Text(unit).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(Lab.faint)
            }
            Text(fmt(b, d)).font(.system(size: 58, weight: .heavy, design: .monospaced)).foregroundStyle(Lab.whoop)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func fmt(_ v: Double?, _ d: Int) -> String { v.map { $0.formatted(.number.precision(.fractionLength(d))) } ?? "––" }
}

/// Button that renders the poster and opens the share sheet.
struct ShareVSButton: View {
    @Environment(LabStore.self) private var store
    @State private var image: Image?
    @State private var showing = false

    var body: some View {
        Button {
            if Unlock.shared.gate("Sharing VS cards") { render() }
        } label: {
            Label("Share VS card", systemImage: Unlock.shared.isPro ? "square.and.arrow.up" : "lock.fill")
                .font(Lab.display(15, .heavy))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(LinearGradient(colors: [Lab.watch.opacity(0.22), Lab.whoop.opacity(0.22)], startPoint: .leading, endPoint: .trailing)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Lab.watch.opacity(0.6), Lab.whoop.opacity(0.6)], startPoint: .leading, endPoint: .trailing)))
                .foregroundStyle(Lab.text)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            if let image {
                SharePreviewSheet(image: image)
                    .presentationDetents([.large])
                    .presentationBackground(Lab.bg)
            }
        }
    }

    @MainActor
    private func render() {
        let card = VSShareCard(watch: store.today(.watch), whoop: store.today(.whoop),
                               readiness: store.readinessToday, recovery: store.recoveryToday,
                               watchSleep: store.lastNight(.watch), whoopSleep: store.lastNight(.whoop))
        let r = ImageRenderer(content: card)
        r.scale = 1
        r.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        guard let ui = r.uiImage else { store.toast = "Couldn't draw the card. Try again."; return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        image = Image(uiImage: ui)
        showing = true
    }
}

struct SharePreviewSheet: View {
    let image: Image
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                SectionTag("Your VS card", color: Lab.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Lab.dim)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.07)))
                }
                .accessibilityLabel("Close")
            }
            image.resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Lab.violet.opacity(0.4), radius: 20)
                .accessibilityLabel("Preview of today's Apple Watch versus WHOOP card")
            ShareLink(item: image, preview: SharePreview("Pulse Lab · Watch vs WHOOP", image: image)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(Lab.display(17, .heavy))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Capsule().fill(LinearGradient(colors: [Lab.watch, Lab.whoop], startPoint: .leading, endPoint: .trailing)))
                    .foregroundStyle(Lab.bg)
            }
        }
        .padding(20)
        .preferredColorScheme(.dark)
    }
}
