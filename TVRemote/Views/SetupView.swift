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
    @FocusState private var pinFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step { case find, pin }

    var body: some View {
        ScrollView {
            VStack(spacing: Look.S.xl) {
                if onPaired == nil {
                    HStack(spacing: Look.S.s) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Look.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("CLANKERR").font(Look.font(14, .black)).tracking(3.5).foregroundStyle(Look.accentH)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Clankerr")
                }
                RadarView(scanning: step == .find,
                          icon: step == .find ? "tv" : "lock.open.fill",
                          blips: step == .find ? store.discovery.found.count : 0,
                          diameter: 250)
                    .padding(.vertical, Look.S.s)
                switch step {
                case .find: findStep
                case .pin: pinStep
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
    }

    private var findStep: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("Step 1 of 2", color: Look.cyan)
                Text("Let's find\nyour TV.").font(Look.display(38)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Turn on your TV and keep your phone on the same Wi-Fi. We'll spot it in a few seconds.")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Look.S.s) {
                ForEach(store.discovery.found, id: \.host) { tv in
                    Button { Task { await pick(tv) } } label: {
                        DeviceRow(icon: "tv.fill", title: tv.name, subtitle: "\(tv.model) · \(tv.host)",
                                  busy: busy && chosen?.host == tv.host)
                    }
                    .buttonStyle(SquishStyle(scale: 0.97))
                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity))
                    .accessibilityLabel("Pair with \(tv.name)")
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
                            var found = await store.client.probe(host: ip, port: 7345, timeout: 4)
                            if found == nil { found = await store.client.probe(host: ip, port: 9000, timeout: 4) }
                            if let tv = found {
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
        }
    }

    private var pinStep: some View {
        VStack(spacing: Look.S.l) {
            VStack(spacing: Look.S.s) {
                CapsLabel("Step 2 of 2", color: Look.cyan)
                Text("Type the code\non your TV.").font(Look.display(34)).tracking(-1).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("A 4-digit code just popped up on \(chosen?.name ?? "the TV").")
                    .font(Look.font(15, .medium)).foregroundStyle(Look.dim).multilineTextAlignment(.center)
            }
            ZStack {
                CodeBoxes(code: pin, count: 4, boxWidth: 60, boxHeight: 74, focused: pinFocused)
                TextField("", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($pinFocused)
                    .opacity(0.02)
                    .frame(width: 290, height: 74)
                    .onChange(of: pin) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(4))
                        if digits != v { pin = digits }
                        if digits.count == 4 { Task { await submit() } }
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
