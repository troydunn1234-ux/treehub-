import SwiftUI
import WatchKit

/// Live recording: big speed ring with the limit badge, lane dots, distance and time.
struct LiveView: View {
    @Environment(PhoneLink.self) private var link
    @Environment(\.isLuminanceReduced) private var dimmed

    private var s: RoamrState { link.state }

    private var ringColor: Color {
        if s.over { return RW.red }
        if let l = s.limitValue, s.speedValue > l { return RW.amber }
        return RW.green
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 6) {
                speedRing
                if s.kind == "drive" { LaneDots(lane: s.lane, lanes: s.lanes, over: s.over) }
                HStack {
                    stat(String(format: "%.1f", s.distValue), s.distUnit)
                    Spacer()
                    stat(RW.clock(elapsed(at: ctx.date)), s.paused ? "paused" : "time")
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle {
            Label(RW.title(s.kind), systemImage: RW.symbol(s.kind))
                .foregroundStyle(RW.amber)
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { link.pause() } label: {
                    Image(systemName: s.paused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(s.paused ? "Resume" : "Pause")
                Spacer()
                Button(role: .destructive) { link.stop() } label: {
                    Image(systemName: "stop.fill")
                }
                .tint(RW.red)
                .accessibilityLabel("Finish and save")
            }
        }
    }

    private func elapsed(at now: Date) -> Double {
        guard !s.paused, let last = link.lastUpdate else { return s.elapsed }
        return s.elapsed + min(now.timeIntervalSince(last), 30)
    }

    private var speedRing: some View {
        let top = max((s.limitValue ?? 0) * 1.35, s.kind == "drive" ? 90 : 25)
        let frac = min(1, s.speedValue / top)
        return ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * frac)
                .stroke(AngularGradient(colors: [RW.orange, ringColor], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: ringColor.opacity(dimmed ? 0 : 0.7), radius: 6)
                .animation(.easeOut(duration: 0.6), value: frac)
            VStack(spacing: -2) {
                Text("\(Int(s.speedValue.rounded()))")
                    .font(RW.font(40, .black))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: s.speedValue))
                    .foregroundStyle(s.over ? RW.red : .white)
                Text(s.speedUnit).font(RW.font(11, .semibold)).foregroundStyle(.secondary)
            }
            if let l = s.limitValue {
                LimitBadge(value: Int(l.rounded()), estimated: s.limitEstimated, over: s.over)
                    .offset(x: 46, y: 38)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(s.speedValue.rounded())) \(s.speedUnit)" + (s.limitValue.map { ", limit \(Int($0.rounded()))" } ?? ""))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(RW.font(17, .heavy)).monospacedDigit().foregroundStyle(.white)
            Text(label.uppercased()).font(RW.font(9, .bold)).foregroundStyle(.secondary)
        }
    }
}

/// Little white speed-limit sign; pulses red when you're over.
struct LimitBadge: View {
    var value: Int
    var estimated: Bool
    var over: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Text("LIMIT").font(.system(size: 6, weight: .heavy))
            Text("\(value)").font(.system(size: 15, weight: .black, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(.black)
        .frame(width: 30, height: 34)
        .background(RoundedRectangle(cornerRadius: 5).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(over ? RW.red : .black.opacity(0.7), lineWidth: over ? 3 : 1.5).padding(1.5))
        .opacity(estimated ? 0.75 : 1)
        .scaleEffect(over && pulse ? 1.12 : 1)
        .onChange(of: over) { _, o in
            if o { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true } }
            else { pulse = false }
        }
    }
}

/// One capsule per lane; yours glows.
struct LaneDots: View {
    var lane: Int
    var lanes: Int
    var over: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(lanes, 6), id: \.self) { i in
                Capsule()
                    .fill(i == lane ? (over ? AnyShapeStyle(RW.red) : AnyShapeStyle(RW.fire)) : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: i == lane ? 18 : 12, height: 6)
                    .shadow(color: i == lane ? RW.orange.opacity(0.8) : .clear, radius: 4)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: lane)
        .accessibilityLabel("Lane \(lane + 1) of \(lanes)")
    }
}

/// Not recording: big Drive button plus Walk / Ride.
struct StartView: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        VStack(spacing: 8) {
            Button { link.start("drive") } label: {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill").font(.system(size: 20, weight: .black))
                    Text("Start drive").font(RW.font(17, .heavy))
                }
                .foregroundStyle(RW.navy)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RW.fire, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: RW.orange.opacity(0.5), radius: 8)
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                small("walk", "Walk")
                small("bike", "Ride")
                small("run", "Run")
            }
            if link.sending { ProgressView().tint(RW.amber) }
            else if !link.reachable && !PhoneLink.demo {
                Label("iPhone not in reach", systemImage: "iphone.slash")
                    .font(RW.font(11, .semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
        .navigationTitle {
            Text("Roamr").font(RW.font(16, .black)).foregroundStyle(RW.amber)
        }
    }

    private func small(_ kind: String, _ title: String) -> some View {
        Button { link.start(kind) } label: {
            VStack(spacing: 3) {
                Image(systemName: RW.symbol(kind)).font(.system(size: 16, weight: .bold))
                Text(title).font(RW.font(11, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Your last three trips.
struct TripsView: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        let s = link.state
        List {
            if s.trips.isEmpty {
                Text("Your trips show up here after you finish one.")
                    .font(RW.font(13, .medium)).foregroundStyle(.secondary)
            }
            ForEach(s.trips) { t in
                HStack(spacing: 10) {
                    Image(systemName: RW.symbol(t.kind))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(RW.navy)
                        .frame(width: 30, height: 30)
                        .background(RW.fire, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title.isEmpty ? RW.title(t.kind) : t.title).font(RW.font(14, .bold)).lineLimit(1)
                        Text(String(format: "%.1f %@ · %@", t.dist / (s.metric ? 1000 : 1609.344), s.distUnit, RW.clock(t.dur)))
                            .font(RW.font(11, .semibold)).monospacedDigit().foregroundStyle(.secondary)
                        Text(Date(timeIntervalSince1970: t.date), format: .relative(presentation: .named))
                            .font(RW.font(10, .medium)).foregroundStyle(RW.amber.opacity(0.8))
                    }
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
            }
        }
        .navigationTitle("Recent")
    }
}
