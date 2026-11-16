import SwiftUI
import StoreKit
import UIKit

/// "More apps by Troy": a small cross-promo list of the other apps, shared by every app.
///
/// The one table of App Store IDs lives here (`MoreApps.all`). An app shows up only once it's
/// actually on the App Store: the list asks the public App Store lookup which IDs are live in this
/// person's country (and borrows the real icon from it), so apps still in review or not released
/// yet stay hidden. The app you're in is never listed.
struct MoreApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let pitch: String
    let symbol: String
    let tint: Color
    /// App Store Connect "Apple ID" = the number in apps.apple.com/app/id<N>. nil = no listing yet.
    let appStoreID: Int?
    var id: String { bundleID }
    /// Bundled icon (Shared/Store/MoreAppsIcons.xcassets), e.g. "moreapps-roamr".
    var iconAsset: String { "moreapps-" + (bundleID.split(separator: ".").last.map(String.init) ?? "") }
    /// The App Store app's page for this app, or nil when there's no listing yet.
    var appStoreURL: URL? { appStoreID.flatMap { URL(string: "itms-apps://apps.apple.com/app/id\($0)") } }
}

enum MoreApps {
    /// Every app, in the order they're listed. App Store IDs come from App Store Connect (status.yml prints them).
    static let all: [MoreApp] = [
        MoreApp(bundleID: "com.troydunn.rootbound", name: "Rootbound",
                pitch: "Hug trees, breathe with them and grow a grove of your own.",
                symbol: "tree.fill", tint: Color(red: 0.30, green: 0.68, blue: 0.36), appStoreID: 6832122198),
        MoreApp(bundleID: "com.troydunn.stillpoint", name: "Still Pointz",
                pitch: "102 breathing, meditation and movement practices for iPhone and Watch.",
                symbol: "wind", tint: Color(red: 0.36, green: 0.42, blue: 0.95), appStoreID: 6832615273),
        MoreApp(bundleID: "com.troydunn.roamr", name: "Roamr",
                pitch: "Every walk, run, ride and drive, on a map.",
                symbol: "location.north.circle.fill", tint: Color(red: 1.0, green: 0.55, blue: 0.20), appStoreID: 6832123417),
        MoreApp(bundleID: "com.troydunn.pulselab", name: "Pulse Lab",
                pitch: "Your watch and your WHOOP, head to head.",
                symbol: "waveform.path.ecg", tint: Color(red: 1.0, green: 0.30, blue: 0.36), appStoreID: 6832409394),
        MoreApp(bundleID: "com.troydunn.clicker", name: "Couch Remote",
                pitch: "One remote for every smart TV in the house, plus your PC.",
                symbol: "tv.fill", tint: Color(red: 0.55, green: 0.45, blue: 1.0), appStoreID: 6832160195),
        MoreApp(bundleID: "com.troydunn.natalorbit", name: "Natal Orbit",
                pitch: "Your birth chart as a living 3D sky.",
                symbol: "sparkles", tint: Color(red: 0.6, green: 0.55, blue: 1.0), appStoreID: 6832136754),
        // Not listed: Ride Quest (private, TestFlight only) and Food Book (retired).
    ]

    /// The other apps that have an App Store ID (the view then keeps only the live ones).
    static var others: [MoreApp] {
        let me = Bundle.main.bundleIdentifier ?? ""
        return all.filter { $0.appStoreID != nil && me != $0.bundleID && !me.hasPrefix($0.bundleID + ".") }
    }
}

/// Which of the other apps are live right now, with their real icon.
@MainActor
final class MoreAppsStore: ObservableObject {
    static let shared = MoreAppsStore()

    struct Listing: Codable, Hashable { let name: String; let artwork: URL? }
    /// App Store ID → live listing. Cached so the list shows instantly (and offline) next time.
    @Published private(set) var live: [Int: Listing]
    @Published private(set) var checked = false
    private static let cacheKey = "moreApps.live"
    private var lastCheck: Date?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let saved = try? JSONDecoder().decode([Int: Listing].self, from: data) {
            live = saved
        } else {
            live = [:]
        }
        // First use (a settings screen with the More apps row): find out which apps are live.
        Task { await refresh() }
    }

    var apps: [MoreApp] { MoreApps.others.filter { app in app.appStoreID.map { live[$0] != nil } ?? false } }

    func refresh() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 600 { return }
        let ids = MoreApps.others.compactMap(\.appStoreID)
        guard !ids.isEmpty, var comps = URLComponents(string: "https://itunes.apple.com/lookup") else { checked = true; return }
        var items = [URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ","))]
        if let region = Locale.current.region?.identifier, region.count == 2 {
            items.append(URLQueryItem(name: "country", value: region.lowercased()))
        }
        comps.queryItems = items
        guard let url = comps.url,
              let reply = try? await URLSession.shared.data(from: url),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: reply.0) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { checked = true; return }  // offline: keep what we knew
        var found: [Int: Listing] = [:]
        for r in results {
            guard let id = (r["trackId"] as? NSNumber)?.intValue else { continue }
            let art = (r["artworkUrl512"] as? String) ?? (r["artworkUrl100"] as? String)
            found[id] = Listing(name: (r["trackName"] as? String) ?? "", artwork: art.flatMap { URL(string: $0) })
        }
        live = found
        lastCheck = Date()
        checked = true
        if let data = try? JSONEncoder().encode(found) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }
}

/// The full "More apps by Troy" screen. Present it in a sheet (it brings its own Done button).
struct MoreAppsView: View {
    @ObservedObject private var store = MoreAppsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var overlayID: Int?
    @State private var showOverlay = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Small, private apps made by one person. No ads, no tracking.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    if store.apps.isEmpty {
                        if store.checked {
                            FamilyEmptyState(symbol: "square.grid.2x2", title: "More apps are on the way",
                                             message: "Check back soon.")
                        } else {
                            ForEach(0..<3, id: \.self) { _ in placeholderRow }
                        }
                    }
                    ForEach(store.apps) { app in row(app) }
                }
                .padding(.horizontal, FamilySpacing.screen)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("More apps by Troy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .task { await store.refresh() }
        .appStoreOverlay(isPresented: $showOverlay) {
            SKOverlay.AppConfiguration(appIdentifier: String(overlayID ?? 0), position: .bottom)
        }
        .sensoryFeedback(.selection, trigger: showOverlay)
    }

    private var placeholderRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.08)).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("App name").font(.headline)
                Text("A short line about what the app does.").font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .redacted(reason: .placeholder)
        .familyCard(padding: 14)
        .accessibilityHidden(true)
    }

    private func row(_ app: MoreApp) -> some View {
        let listing = app.appStoreID.flatMap { store.live[$0] }
        return HStack(spacing: 14) {
            MoreAppIcon(app: app, artwork: listing?.artwork, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline)
                Text(app.pitch).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button {
                overlayID = app.appStoreID
                showOverlay = true
            } label: {
                Text("GET").font(.subheadline.weight(.heavy))
                    .foregroundStyle(app.tint)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(app.tint.opacity(0.16)).frame(height: 32))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get \(app.name)")
        }
        .familyCard(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture { if let id = app.appStoreID { StoreProductPage.open(id) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if let id = app.appStoreID { StoreProductPage.open(id) } }
    }
}

/// "More apps by Troy" as plain rows (icon, name, one line, App Store link), for an About section or card.
/// Lists only the other apps that are live on the App Store; renders nothing until one is.
///
///     Section("More apps by Troy") { MoreAppsList() }        // inside a List / Form
///     MoreAppsList().familyCard()                             // or as a card
struct MoreAppsList: View {
    var iconSize: CGFloat = 44
    @ObservedObject private var store = MoreAppsStore.shared

    var body: some View {
        ForEach(store.apps) { app in
            if let url = app.appStoreURL {
                Link(destination: url) { label(app) }
                    .accessibilityHint("Opens the App Store")
            } else {
                label(app)
            }
        }
        .task { await store.refresh() }
    }

    private func label(_ app: MoreApp) -> some View {
        HStack(spacing: 12) {
            MoreAppIcon(app: app, artwork: app.appStoreID.flatMap { store.live[$0]?.artwork }, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(app.pitch).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The app's icon: the copy bundled in MoreAppsIcons.xcassets, else the App Store artwork, else a symbol on the app's color.
struct MoreAppIcon: View {
    let app: MoreApp
    var artwork: URL?
    var size: CGFloat = 56

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            if let bundled = UIImage(named: app.iconAsset) {
                Image(uiImage: bundled).resizable().scaledToFill()
            } else {
                shape.fill(LinearGradient(colors: [app.tint, app.tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: app.symbol)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                if let artwork {
                    AsyncImage(url: artwork) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The in-app App Store page (SKStoreProductViewController), shown over whatever is on screen.
enum StoreProductPage {
    @MainActor static func open(_ appStoreID: Int) {
        let vc = SKStoreProductViewController()
        vc.delegate = StoreProductDismisser.shared
        vc.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: NSNumber(value: appStoreID)]) { _, _ in }
        topController()?.present(vc, animated: true)
    }

    @MainActor static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

private final class StoreProductDismisser: NSObject, SKStoreProductViewControllerDelegate {
    static let shared = StoreProductDismisser()
    func productViewControllerDidFinish(_ vc: SKStoreProductViewController) {
        vc.dismiss(animated: true)
    }
}

/// A plain "More apps" row for settings screens. Tapping it presents `MoreAppsView`.
/// Hidden until at least one other app is live on the App Store (so App Review never sees an empty
/// "More apps are on the way" screen); wrap any panel around it in `MoreAppsGate` so the panel hides too.
struct MoreAppsRow: View {
    var tint: Color = .accentColor
    @State private var show = false
    @ObservedObject private var store = MoreAppsStore.shared

    var body: some View {
        if !store.apps.isEmpty {
            row
        } else {
            EmptyView()
        }
    }

    private var row: some View {
        Button { show = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("More apps by Troy").font(.subheadline.weight(.semibold))
                    Text("Small, private apps. No ads.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) { MoreAppsView() }
    }
}

/// Shows its content (a panel holding `MoreAppsRow`) only once another app is live on the App Store.
struct MoreAppsGate<Content: View>: View {
    @ObservedObject private var store = MoreAppsStore.shared
    @ViewBuilder var content: Content

    var body: some View {
        if !store.apps.isEmpty {
            content
        } else {
            EmptyView()
        }
    }
}

/// Presents the "More apps by Troy" sheet from anywhere (the web-shell apps' bridge uses this).
enum MoreAppsSheet {
    @MainActor static func present() {
        StoreProductPage.topController()?.present(UIHostingController(rootView: MoreAppsView()), animated: true)
    }
}
