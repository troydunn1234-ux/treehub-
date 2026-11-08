import SwiftUI

/// First run: find the TV on Wi-Fi (any supported brand), then approve this phone the way that
/// TV wants: type the code it shows, choose Allow on the TV, or nothing at all (Roku).
struct SetupView: View {
    /// Called after a TV pairs (used when adding another TV from a sheet).
    var onPaired: (() -> Void)? = nil
    @Environment(TVStore.self) private var store
    @State private var step: Step = .find
    @State private var chosen: DiscoveredTV?
    @State private var showCompat = false
    @State private var pin = ""
    @State private var busy = false
    @State private var manualIP = ""
    @FocusState private var pinFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step { case find, pin, allow, done }

    private var pinLength: Int { chosen?.brand == .googleTV ? 6 : 4 }
    private var pinIsHex: Bool { chosen?.brand == .googleTV }

    var body: some View {
        ScrollView {
            VStack(spacing: Look.S.xl) {
                if onPaired == nil {
                    HStack(spacing: Look.S.s) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Look.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("COUCH REMOTE").font(Look.font(14, .black)).tracking(3.5).foregroundStyle(Look.accentH)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Couch Remote")
                }
                RadarView(scanning: step == .find || step == .allow,
                          icon: step == .find ? "tv" : step == .allow ? "hand.tap.fill" : step == .done ? "checkmark" : "lock.open.fill",
                          blips: step == .find ? store.discovery.found.count : 0,
                          diameter: 250)
                    .padding(.vertical, Look.S.s)
                switch step {
                case .find: findStep
                case .pin: pinStep
                case .allow: allowStep
                case .done: doneStep
                }
                if let e = store.errorText {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(Look.font(14, .semibold)).foregroundStyle(.white)
                        .padding(Look.S.m)
                        .frame(maxWidth: .infinity)
                        .glass(18, tint: .orange, glow: .orange, strength: 1.5)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Look.S.xl)
            .padding(.top, Look.S.xl)
            .padding(.bottom, Look.S.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { store.discovery.start() }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .sheet(isPresented: $showCompat) { CompatibilityView().presentationDetents([.large]) }
    }

    private var findStep: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("Step 1 of 2", color: Look.cyan)
                Text("Let's find\nyour TV.").font(Look.display(38)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Turn on your TV and keep your phone on the same Wi-Fi. We'll spot VIZIO, Roku, Samsung, LG and Google TV sets in a few seconds.")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showCompat = true } label: {
                    Label("Which TVs work?", systemImage: "questionmark.circle.fill")
                        .font(Look.font(13, .heavy)).foregroundStyle(Look.cyan)
                }
                .frame(minHeight: 32)
            }

            VStack(spacing: Look.S.s) {
                ForEach(store.discovery.found) { tv in
                    Button { Task { await pick(tv) } } label: {
                        DeviceRow(icon: "tv.fill", title: tv.name, subtitle: "\(tv.model) · \(tv.host)",
                                  busy: busy && chosen?.id == tv.id)
                            .overlay(alignment: .topTrailing) { BrandChip(brand: tv.brand).padding(8) }
                    }
                    .buttonStyle(SquishStyle(scale: 0.97))
                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity))
                    .accessibilityLabel("Pair with \(tv.name), \(tv.brand.displayName)")
                }
                if store.discovery.searching {
                    HStack(spacing: Look.S.s) {
                        ProgressView(value: store.discovery.progress).tint(Look.magenta).frame(width: 110)
                        Text("Scanning your Wi-Fi…").font(Look.font(13, .bold)).foregroundStyle(Look.dim)
                    }
                    .padding(.top, Look.S.xs)
                } else if store.discovery.found.isEmpty {
                    Text("No TV found yet.").font(Look.font(14, .semibold)).foregroundStyle(Look.dim)
                    Button("Search again") { store.discovery.start() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.55), value: store.discovery.found.count)

            DisclosureGroup {
                HStack(spacing: Look.S.s) {
                    TextField("", text: $manualIP, prompt: Text("TV's IP, like 192.168.1.40").foregroundStyle(Look.faint))
                        .keyboardType(.decimalPad).font(Look.font(15, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, Look.S.m).frame(height: 48)
                        .glass(14)
                    Button("Connect") {
                        Task {
                            busy = true
                            let ip = manualIP.trimmingCharacters(in: .whitespaces)
                            if let tv = await store.discovery.probe(host: ip) {
                                await pick(tv)
                            } else {
                                store.errorText = "No TV answered at \(ip). Find its IP on the TV under Network settings."
                            }
                            busy = false
                        }
                    }
                    .font(Look.font(15, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, Look.S.l).frame(height: 48)
                    .background(Look.accentH, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(manualIP.isEmpty ? 0.4 : 1)
                    .disabled(manualIP.isEmpty)
                }
                .padding(.top, Look.S.s)
            } label: {
                Text("Enter the TV's address yourself").font(Look.font(14, .bold)).foregroundStyle(Look.dim)
            }
            .tint(Look.dim)
            .padding(.top, Look.S.xs)

            Button { store.startDemo() } label: {
                Label("No TV handy? Try the demo", systemImage: "sparkles")
                    .font(Look.font(15, .heavy))
                    .foregroundStyle(Look.accentH)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Capsule().stroke(Look.accentH, lineWidth: 1.5))
            }
            .padding(.top, Look.S.s)
            .accessibilityHint("Explore the app with pretend TVs")
        }
    }

    private var pinStep: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("Step 2 of 2", color: Look.cyan)
                Text("Type the code\non your TV.").font(Look.display(34)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("A \(pinLength)-\(pinIsHex ? "character" : "digit") code just popped up on \(chosen?.name ?? "the TV").")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
            }
            ZStack {
                CodeBoxes(code: pin, count: pinLength, boxWidth: pinLength > 4 ? 44 : 60, boxHeight: 74, focused: pinFocused)
                TextField("", text: $pin)
                    .keyboardType(pinIsHex ? .asciiCapable : .numberPad)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .focused($pinFocused)
                    .opacity(0.02)
                    .frame(width: 290, height: 74)
                    .onChange(of: pin) { _, v in
                        let allowed: (Character) -> Bool = pinIsHex ? { $0.isHexDigit } : { $0.isNumber }
                        let cleaned = String(v.uppercased().filter(allowed).prefix(pinLength))
                        if cleaned != v { pin = cleaned }
                        if cleaned.count == pinLength { Task { await submit() } }
                    }
                    .accessibilityLabel("TV code")
            }
            .onTapGesture { pinFocused = true }
            if busy { ProgressView().tint(.white) }
            Button("Start over") {
                Task { await store.cancelPairing(); pin = ""; step = .find; store.discovery.start() }
            }
            .font(Look.font(14, .bold)).foregroundStyle(Look.dim)
            .frame(minHeight: 44)
        }
        .onAppear { pinFocused = true }
    }

    private var allowStep: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("Step 2 of 2", color: Look.cyan)
                Text("Look at\nyour TV.").font(Look.display(38)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("\(chosen?.name ?? "Your TV") is asking if Couch Remote can control it. Pick **Allow** with your TV remote.")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AllowPulse()
            if !busy {
                Button("Ask again") { if let tv = chosen { Task { await pick(tv) } } }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button("Start over") {
                Task { await store.cancelPairing(); step = .find; store.errorText = nil; store.discovery.start() }
            }
            .font(Look.font(14, .bold)).foregroundStyle(Look.dim)
            .frame(minHeight: 44)
        }
    }

    private var doneStep: some View {
        VStack(spacing: Look.S.m) {
            Text("You're in.").font(Look.display(40)).tracking(-1).foregroundStyle(Look.accentH)
            Text("\(chosen?.name ?? "Your TV") is ready. Your phone is the remote now.")
                .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
        }
        .transition(.scale(scale: 0.7).combined(with: .opacity))
    }

    private func pick(_ tv: DiscoveredTV) async {
        chosen = tv
        store.errorText = nil
        busy = true
        defer { busy = false }
        switch tv.brand.pairing {
        case .pinOnTV:
            if await store.beginPairing(with: tv) {
                store.discovery.stop()
                pin = ""
                step = .pin
            }
        case .allowPromptOnTV:
            store.discovery.stop()
            step = .allow
            if await store.beginPairing(with: tv) { await celebrate() }
        case .none:
            if await store.beginPairing(with: tv) {
                store.discovery.stop()
                await celebrate()
            }
        }
    }

    /// Success burst, then hand over to the app.
    private func celebrate() async {
        step = .done
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        onPaired?()
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        if await store.finishPairing(pin: pin) {
            await celebrate()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            pin = ""
        }
    }
}

/// Small brand tag on a found TV.
struct BrandChip: View {
    let brand: TVBrand
    var body: some View {
        Text(brand.shortName.uppercased())
            .font(Look.font(10, .black)).tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(brand.tint.opacity(0.85), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// "Choose Allow on your TV": a TV with a pulsing check prompt.
private struct AllowPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Look.accentH, lineWidth: 3)
                .frame(width: 220, height: 128)
            VStack(spacing: 10) {
                Text("Allow Couch Remote?").font(Look.font(13, .heavy)).foregroundStyle(.white)
                HStack(spacing: 10) {
                    Text("Deny").font(Look.font(12, .bold)).foregroundStyle(Look.dim)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    Text("Allow").font(Look.font(12, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Look.accentH, in: Capsule())
                        .scaleEffect(on ? 1.12 : 1)
                        .shadow(color: Look.magenta.opacity(on ? 0.8 : 0.2), radius: on ? 14 : 4)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your TV shows a prompt. Choose Allow.")
    }
}

extension TVBrand {
    var shortName: String {
        switch self {
        case .vizio: return "VIZIO"
        case .roku: return "Roku"
        case .samsung: return "Samsung"
        case .lg: return "LG"
        case .googleTV: return "Google TV"
        }
    }
    var tint: Color {
        switch self {
        case .vizio: return Color(hex: 0x6B4BFF)
        case .roku: return Color(hex: 0x6C2BD9)
        case .samsung: return Color(hex: 0x1F4FD8)
        case .lg: return Color(hex: 0xC8102E)
        case .googleTV: return Color(hex: 0x1A9E5C)
        }
    }
}
