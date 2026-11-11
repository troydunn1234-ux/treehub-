import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shares the current TV with widgets / complications through the App Group.
/// (The Watch app writes the same keys on the watch: App Group defaults do not sync between devices.)
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    static let appGroup = "group.com.troydunn.clicker"
    static let tvNameKey = "tvName"
    static let updatedKey = "updatedAt"

    private weak var store: TVStore?
    private var timer: Timer?
    private var last = ""

    func attach(_ store: TVStore) {
        self.store = store
        write()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.write() }
        }
    }

    /// Write the active TV's name if it changed.
    func write() {
        let name = store?.tv?.name ?? ""
        guard name != last else { return }
        last = name
        Self.write(tvName: name)
    }

    static func write(tvName: String) {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        d.set(tvName, forKey: tvNameKey)
        d.set(Date().timeIntervalSince1970, forKey: updatedKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
