import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// Back camera with a photo output. Falls back gracefully (simulator, no permission).
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "foodbook.camera")
    private var configured = false
    private var completion: ((UIImage?) -> Void)?

    @Published var available = false
    @Published var denied = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.run() } else { self.denied = true }
                }
            }
        default:
            denied = true
        }
    }

    private func run() {
        queue.async {
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.available = false }
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.available = true }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        guard available else { done(nil); return }
        completion = done
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        DispatchQueue.main.async {
            self.completion?(image)
            self.completion = nil
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Live barcode scanner (VisionKit). Calls back once per appearance.
struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    @MainActor static var supported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var fired = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue, !value.isEmpty {
                    fired = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(value)
                    return
                }
            }
        }
    }
}
