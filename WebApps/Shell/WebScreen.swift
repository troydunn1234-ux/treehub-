import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Hosts the bundled web app. Pages load from app://local/ so relative files,
/// saved photos (/_blob/…) and the storage bridge all live on one origin.
struct WebScreen: UIViewRepresentable {
    var onReady: () -> Void

    func makeCoordinator() -> Bridge { Bridge(onReady: onReady) }

    func makeUIView(context: Context) -> ShakeWebView {
        let bridge = context.coordinator
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(bridge, forURLScheme: "app")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let ucc = config.userContentController
        ucc.addScriptMessageHandler(bridge, contentWorld: .page, name: "native")
        ucc.add(bridge, name: "fx")
        ucc.addUserScript(WKUserScript(source: Bridge.bootScript(initialStore: bridge.store.json),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Bridge.funScript(accent: ShellConfig.info["WebShellAccent"] as? String ?? "#ffffff"),
                                       injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let web = ShakeWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.keyboardDismissMode = .interactive
        web.navigationDelegate = bridge
        web.uiDelegate = bridge
        web.allowsLinkPreview = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        web.onShake = { [weak web] in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            web?.evaluateJavaScript("window.__shellConfetti && window.__shellConfetti()")
        }
        bridge.web = web
        web.load(URLRequest(url: URL(string: "app://local/index.html")!))
        return web
    }

    func updateUIView(_ uiView: ShakeWebView, context: Context) {}
}

/// Shake the phone for confetti.
final class ShakeWebView: WKWebView {
    var onShake: (() -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { DispatchQueue.main.async { self.becomeFirstResponder() } }
    }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake?() } else { super.motionEnded(motion, with: event) }
    }
}

// MARK: - Local storage

/// The app's data: one JSON object of document path → document. Saved in Documents.
final class LocalStore {
    private let url: URL
    private(set) var json: String

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("store.json")
        if let saved = try? String(contentsOf: url, encoding: .utf8), !saved.isEmpty {
            json = saved
        } else if let seedURL = Bundle.main.url(forResource: "seed", withExtension: "json"),
                  let seed = try? String(contentsOf: seedURL, encoding: .utf8) {
            json = seed
        } else {
            json = "{}"
        }
    }

    func save(_ newJSON: String) {
        json = newJSON
        let data = Data(newJSON.utf8)
        let target = url
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: target, options: [.atomic, .completeFileProtection])
        }
    }

    static var blobDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("blobs")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

// MARK: - Bridge

final class Bridge: NSObject, WKURLSchemeHandler, WKScriptMessageHandlerWithReply, WKScriptMessageHandler,
                    WKNavigationDelegate, WKUIDelegate {
    let store = LocalStore()
    weak var web: WKWebView?
    private let onReady: () -> Void
    private var readySent = false
    private let tapper = UIImpactFeedbackGenerator(style: .light)
    private let selector = UISelectionFeedbackGenerator()

    init(onReady: @escaping () -> Void) { self.onReady = onReady }

    // Files: bundle "web" folder, plus saved photos under /_blob/.
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let fileURL: URL?
        if path.hasPrefix("/_blob/") {
            let id = String(path.dropFirst("/_blob/".count)).replacingOccurrences(of: "/", with: "")
            fileURL = LocalStore.blobDir.appendingPathComponent(id)
        } else {
            let rel = String(path.dropFirst()).removingPercentEncoding ?? String(path.dropFirst())
            fileURL = Bundle.main.resourceURL?.appendingPathComponent("web").appendingPathComponent(rel)
        }
        guard let f = fileURL, !f.path.contains(".."), let data = try? Data(contentsOf: f) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            task.didReceive(r); task.didFinish(); return
        }
        let mime = path.hasPrefix("/_blob/") ? "image/jpeg"
            : (UTType(filenameExtension: f.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime, "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"])!
        task.didReceive(r)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // Async calls from the page: save store, save photo, share a file.
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "bad message"); return
        }
        switch op {
        case "store":
            store.save(body["json"] as? String ?? "{}")
            replyHandler(true, nil)
        case "blob":
            guard let b64 = body["data"] as? String, let data = Data(base64Encoded: b64) else { replyHandler(nil, "bad data"); return }
            let id = "p" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            do {
                try data.write(to: LocalStore.blobDir.appendingPathComponent(id), options: .atomic)
                replyHandler(id, nil)
            } catch { replyHandler(nil, "write failed") }
        case "share":
            guard let b64 = body["data"] as? String, let data = Data(base64Encoded: b64) else { replyHandler(nil, "bad data"); return }
            let name = (body["filename"] as? String ?? "file").replacingOccurrences(of: "/", with: "-")
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: tmp, options: .atomic)
            share(tmp) { done in replyHandler(done, done ? nil : "declined") }
        default:
            replyHandler(nil, "unknown op")
        }
    }

    // Fire-and-forget effects: haptics.
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.body as? String {
        case "tap": tapper.impactOccurred(intensity: 0.7)
        case "select": selector.selectionChanged()
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        default: break
        }
    }

    private func share(_ file: URL, done: @escaping (Bool) -> Void) {
        guard let root = web?.window?.rootViewController else { done(false); return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in done(completed) }
        vc.popoverPresentationController?.sourceView = web
        top.present(vc, animated: true)
    }

    // Links to the web open in Safari; everything local stays in the app.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        if url.scheme == "app" || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" || !action.targetFrame.isMainFrame {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme != "app" { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !readySent else { return }
        readySent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.onReady() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    // Native alerts for alert()/confirm()/prompt().
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        present(alert(message, actions: [("OK", .default, completionHandler)]), fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        present(alert(message, actions: [("Cancel", .cancel, { completionHandler(false) }),
                                          ("OK", .default, { completionHandler(true) })]),
                fallback: { completionHandler(false) })
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, fallback: { completionHandler(nil) })
    }

    private func alert(_ msg: String, actions: [(String, UIAlertAction.Style, () -> Void)]) -> UIAlertController {
        let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        for (t, s, h) in actions { a.addAction(UIAlertAction(title: t, style: s) { _ in h() }) }
        return a
    }

    private func present(_ vc: UIViewController, fallback: () -> Void) {
        guard var top = web?.window?.rootViewController else { fallback(); return }
        while let p = top.presentedViewController { top = p }
        top.present(vc, animated: true)
    }
}
