import PhotosUI
import SwiftUI
import UIKit

/// Full-screen camera: snap a meal, scan a barcode, or read a Nutrition Facts label.
struct SnapView: View {
    let day: String
    var onLogged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @StateObject private var camera = CameraModel()

    @State private var mode: SnapMode = .meal
    @State private var frozen: UIImage?
    @State private var analyzing = false
    @State private var status = ""
    @State private var flash = false
    @State private var result: SnapResult?
    @State private var pickItem: PhotosPickerItem?
    @State private var toast: String?
    @State private var scanToken = 0
    @State private var logged = false
    @Namespace private var ns

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            viewfinder.ignoresSafeArea()
            if mode != .barcode && frozen == nil { FrameGuide(mode: mode).allowsHitTesting(false) }
            if let frozen {
                Image(uiImage: frozen).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped().ignoresSafeArea()
                if analyzing { Shimmer().ignoresSafeArea().allowsHitTesting(false) }
            }
            Color.white.opacity(flash ? 0.9 : 0).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if analyzing {
                    Label(status, systemImage: "sparkles")
                        .font(Ember.font(16, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 20)
                } else if let toast {
                    Text(toast).font(Ember.font(15, .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Ember.pink.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 30).padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { if mode != .barcode || !BarcodeScanner.supported { camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: mode) { _, m in
            toast = nil
            if m == .barcode && BarcodeScanner.supported { camera.stop() } else { camera.start() }
        }
        .onChange(of: pickItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await analyze(img)
                }
                pickItem = nil
            }
        }
        .sheet(item: $result, onDismiss: {
            if logged { onLogged(); dismiss() } else { frozen = nil; scanToken += 1 }
        }) { r in
            SnapResultSheet(result: r, day: day) { logged = true }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Pieces

    @ViewBuilder private var viewfinder: some View {
        if mode == .barcode && BarcodeScanner.supported {
            BarcodeScanner { code in Task { await lookUp(code) } }
                .id(scanToken)
        } else if camera.available {
            CameraPreview(session: camera.session)
        } else {
            VStack(spacing: 14) {
                Image(systemName: camera.denied ? "camera.badge.ellipsis" : "camera.fill")
                    .font(.system(size: 44, weight: .bold)).foregroundStyle(Ember.fire)
                Text(camera.denied ? "Camera is off for Food Book" : "No camera here")
                    .font(Ember.font(20, .heavy)).foregroundStyle(Ember.cream)
                Text(camera.denied ? "Turn it on in Settings, or pick a photo instead." : "Pick a photo from your library instead.")
                    .font(Ember.font(15, .medium)).foregroundStyle(Ember.dim).multilineTextAlignment(.center)
                if camera.denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(Ember.font(15, .bold)).foregroundStyle(Ember.orange)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EmberBackground())
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close camera")
            Spacer()
            VStack(spacing: 1) {
                Text("FOOD BOOK").font(Ember.font(10, .heavy)).tracking(2.5).foregroundStyle(Ember.fire)
                Text(hint).font(Ember.font(15, .heavy)).foregroundStyle(.white)
                    .contentTransition(.opacity)
            }
            .shadow(color: .black.opacity(0.6), radius: 6)
            Spacer()
            PhotosPicker(selection: $pickItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Pick a photo")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var hint: String {
        switch mode {
        case .meal: return "Snap your plate"
        case .barcode: return "Point at a barcode"
        case .label: return "Snap the Nutrition Facts"
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            if mode != .barcode || !BarcodeScanner.supported {
                Button(action: shoot) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 5).frame(width: 84, height: 84)
                        Circle().fill(Ember.fire).frame(width: 66, height: 66)
                            .scaleEffect(flash ? 0.82 : 1)
                        Image(systemName: mode == .label ? "text.viewfinder" : "camera.fill")
                            .font(.system(size: 24, weight: .black)).foregroundStyle(.white)
                    }
                    .shadow(color: Ember.pink.opacity(0.6), radius: 18)
                }
                .buttonStyle(Squish())
                .disabled(analyzing || frozen != nil)
                .accessibilityLabel(mode == .label ? "Read label" : "Take photo")
            } else {
                Label("Scanning…", systemImage: "barcode.viewfinder")
                    .font(Ember.font(15, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(height: 84)
            }
            HStack(spacing: 4) {
                ForEach(SnapMode.allCases) { m in
                    Button {
                        guard m != mode else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = m }
                    } label: {
                        Label(m.rawValue, systemImage: m.symbol)
                            .font(Ember.font(12, .heavy)).tracking(1)
                            .foregroundStyle(mode == m ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 13).padding(.vertical, 10)
                            .background { if mode == m { Capsule().fill(Ember.fire).matchedGeometryEffect(id: "mode", in: ns) } }
                    }
                    .buttonStyle(Squish())
                    .accessibilityAddTraits(mode == m ? .isSelected : [])
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.bottom, 26)
    }

    // MARK: Actions

    private func shoot() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeIn(duration: 0.25)) { flash = false } }
        camera.capture { img in
            guard let img else { show("Couldn't take the photo. Try again."); return }
            Task { await analyze(img) }
        }
    }

    private func analyze(_ raw: UIImage) async {
        let img = FoodVision.prepared(raw)
        let started = Date()
        toast = nil
        withAnimation(.easeOut(duration: 0.2)) { frozen = img; analyzing = true }
        status = mode == .meal ? "Reading your plate…" : mode == .label ? "Reading the label…" : "Finding the barcode…"

        var next: SnapResult?
        var failure: String?
        switch mode {
        case .meal:
            let r = await FoodVision.recognizeMeal(img)
            next = SnapResult(image: img, mode: .meal, guesses: r.guesses, topLabel: r.topLabel)
        case .label:
            if let facts = await FoodVision.readLabel(img) {
                next = SnapResult(image: img, mode: .label, guesses: [FoodGuess(
                    name: facts.name ?? "Scanned label", serving: facts.serving ?? "1 serving",
                    cal: facts.cal, p: facts.protein, c: facts.carbs, f: facts.fat, source: .label)], topLabel: nil)
            } else {
                failure = "Couldn't read that label. Get it flat, close and well lit."
            }
        case .barcode:
            if let code = await FoodVision.barcode(in: img) {
                status = "Looking it up…"
                if let p = await FoodVision.product(barcode: code) {
                    next = SnapResult(image: img, mode: .barcode, guesses: [guess(p)], topLabel: nil)
                } else {
                    failure = "That one isn't in the food database. Snap its Nutrition Facts instead."
                }
            } else {
                failure = "No barcode in that photo."
            }
        }
        // Let the shimmer breathe a moment so it doesn't flash.
        let wait = 0.7 - Date().timeIntervalSince(started)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        withAnimation(.easeOut(duration: 0.2)) { analyzing = false }
        if let next {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            logged = false
            result = next
        } else {
            withAnimation { frozen = nil }
            show(failure ?? "Something went wrong.")
            if mode == .barcode, failure?.contains("Nutrition Facts") == true { withAnimation { mode = .label } }
        }
    }

    private func lookUp(_ code: String) async {
        withAnimation { analyzing = true }
        status = "Looking it up…"
        let p = await FoodVision.product(barcode: code)
        withAnimation { analyzing = false }
        if let p {
            logged = false
            result = SnapResult(image: nil, mode: .barcode, guesses: [guess(p)], topLabel: nil)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            show("That one isn't in the food database. Snap its Nutrition Facts instead.")
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = .label }
            scanToken += 1
        }
    }

    private func guess(_ p: FoodVision.Product) -> FoodGuess {
        FoodGuess(name: p.name, serving: p.serving, cal: p.cal, p: p.p, c: p.c, f: p.f, source: .barcode)
    }

    private func show(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if toast == text { withAnimation { toast = nil } }
        }
    }
}

/// Corner brackets that hint where to aim.
private struct FrameGuide: View {
    let mode: SnapMode
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.78
            let h = mode == .label ? w * 1.3 : w
            let rect = CGRect(x: (geo.size.width - w) / 2, y: (geo.size.height - h) / 2 - 20, width: w, height: h)
            Path { p in
                let l: CGFloat = 34
                let corners: [(CGPoint, CGFloat, CGFloat)] = [
                    (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
                    (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1)]
                for (corner, dx, dy) in corners {
                    p.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
                    p.addLine(to: corner)
                    p.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
                }
            }
            .stroke(Ember.fire, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .shadow(color: Ember.orange.opacity(0.7), radius: 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: mode)
    }
}

/// A glowing band sweeping over the photo while it's analyzed.
struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.25)
                LinearGradient(colors: [.clear, Ember.gold.opacity(0.35), Ember.pink.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.35)
                    .offset(y: phase * geo.size.height * 0.7)
                    .blendMode(.screen)
            }
        }
        .onAppear {
            guard !reduce else { phase = 0; return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { phase = 1 }
        }
    }
}
