import SwiftUI

/// First run: find the TV on Wi-Fi, then type the code it shows.
struct SetupView: View {
    /// Called after a TV pairs (used when adding another TV from a sheet).
    var onPaired: (() -> Void)? = nil
    @Environment(TVStore.self) private var store
    @State private var step: Step = .find
    @State private var chosen: VizioClient.TVInfo?
    @State private var pin = ""
    @State private var busy = false
    @State private var manualIP = ""
    @State private var pulse = false
    @FocusState private var pinFocused: Bool
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step { case find, pin }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            radar
            switch step {
            case .find: findStep
            case .pin: pinStep
            }
            if let e = store.errorText {
                Text(e).font(Look.font(14, .semibold)).foregroundStyle(.orange).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .onAppear {
            store.discovery.start()
            pulse = true
            if !reduceMotion { withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { sweep = true } }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var radar: some View {
        ZStack {
            // Radar sweep: a rotating wedge of light.
            Circle()
                .fill(AngularGradient(gradient: Gradient(stops: [
                    .init(color: Look.cyan.opacity(0.0), location: 0.0),
                    .init(color: Look.cyan.opacity(0.0), location: 0.72),
                    .init(color: Look.violet.opacity(0.25), location: 0.9),
                    .init(color: Look.cyan.opacity(0.55), location: 1.0)]), center: .center))
                .frame(width: 230, height: 230)
                .rotationEffect(.degrees(sweep ? 360 : 0))
                .mask(Circle().frame(width: 230, height: 230))
                .opacity(step == .find ? 1 : 0)
            Circle().stroke(Look.line, lineWidth: 1).frame(width: 230, height: 230)
            Circle().stroke(Look.line, lineWidth: 1).frame(width: 160, height: 160)
            ForEach(0..<3) { i in
                Circle().stroke(Look.accent, lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 2.2 : 0.6)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: pulse)
            }
            Circle().fill(Look.accent).frame(width: 96, height: 96)
                .shadow(color: Look.magenta.opacity(0.7), radius: 24)
            Image(systemName: step == .find ? "tv" : "lock.open.fill")
                .font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 240)
    }

    private var findStep: some View {
        VStack(spacing: 16) {
            Text("Let's find your TV").font(Look.font(28, .heavy)).foregroundStyle(.white)
            Text("Turn on your Vizio and make sure your phone is on the same Wi-Fi.")
                .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(store.discovery.found, id: \.host) { tv in
                    Button { Task { await pick(tv) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tv.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Look.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tv.name).font(Look.font(17, .heavy)).foregroundStyle(.white)
                                Text("\(tv.model) · \(tv.host)").font(Look.font(12, .medium)).foregroundStyle(Look.dim)
                            }
                            Spacer()
                            if busy && chosen?.host == tv.host { ProgressView().tint(.white) }
                            else { Image(systemName: "chevron.right").foregroundStyle(Look.dim) }
                        }
                        .padding(16)
                        .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Look.line))
                    }
                    .buttonStyle(SquishStyle(scale: 0.97))
                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity))
                }
                if store.discovery.searching {
                    HStack(spacing: 8) {
                        ProgressView(value: store.discovery.progress).tint(Look.magenta).frame(width: 120)
                        Text("Searching your Wi-Fi…").font(Look.font(13, .semibold)).foregroundStyle(Look.dim)
                    }
                    .padding(.top, 4)
                } else if store.discovery.found.isEmpty {
                    Text("No TV found yet.").font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
                    Button("Search again") { store.discovery.start() }
                        .font(Look.font(15, .bold)).foregroundStyle(Look.cyan)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.55), value: store.discovery.found.count)

            DisclosureGroup {
                HStack {
                    TextField("TV's IP address, like 192.168.1.40", text: $manualIP)
                        .keyboardType(.decimalPad).font(Look.font(15, .medium))
                    Button("Connect") {
                        Task {
                            busy = true
                            let ip = manualIP.trimmingCharacters(in: .whitespaces)
                            var found = await store.client.probe(host: ip, port: 7345, timeout: 4)
                            if found == nil { found = await store.client.probe(host: ip, port: 9000, timeout: 4) }
                            if let tv = found {
                                await pick(tv)
                            } else {
                                store.errorText = "No Vizio TV answered at \(ip). Find its IP on the TV under Network settings."
                            }
                            busy = false
                        }
                    }
                    .font(Look.font(15, .bold)).disabled(manualIP.isEmpty)
                }
                .padding(.top, 8)
            } label: {
                Text("Enter the TV's address yourself").font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
            }
            .tint(Look.dim)
            .padding(.top, 6)
        }
    }

    private var pinStep: some View {
        VStack(spacing: 16) {
            Text("Enter the code on your TV").font(Look.font(26, .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text("A 4-digit code just popped up on \(chosen?.name ?? "the TV").")
                .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
            ZStack {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        let ch = i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : ""
                        Text(ch)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 70)
                            .background(Look.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(i == pin.count ? AnyShapeStyle(Look.accent) : AnyShapeStyle(Look.line), lineWidth: i == pin.count ? 2 : 1))
                            .scaleEffect(ch.isEmpty ? 1 : 1.04)
                            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pin.count)
                    }
                }
                TextField("", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($pinFocused)
                    .opacity(0.02)
                    .frame(width: 280, height: 70)
                    .onChange(of: pin) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(4))
                        if digits != v { pin = digits }
                        if digits.count == 4 { Task { await submit() } }
                    }
            }
            .onTapGesture { pinFocused = true }
            if busy { ProgressView().tint(.white) }
            Button("Start over") {
                Task { await store.cancelPairing(); pin = ""; step = .find; store.discovery.start() }
            }
            .font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
        }
        .onAppear { pinFocused = true }
    }

    private func pick(_ tv: VizioClient.TVInfo) async {
        chosen = tv
        busy = true
        defer { busy = false }
        if await store.beginPairing(with: tv) {
            store.discovery.stop()
            pin = ""
            step = .pin
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        if await store.finishPairing(pin: pin) {
            onPaired?()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            pin = ""
        }
    }
}
