import Foundation

/// Where an app keeps its SwiftData store.
///
/// SwiftData's default location moves into the first App Group container once the app has an
/// App Group entitlement. Rootbound and Roamr gained the shared wellness group, which silently
/// pointed them at a new, empty store in the group container — the owner's hugs and trips
/// looked gone (they were still on the phone, in the old file). Every app pins the original,
/// app-private location here so adding or removing App Groups can never move the store again.
/// The empty store SwiftData created in the group container is left untouched.
enum LocalStore {
    /// `Library/Application Support/default.store` inside the app's own sandbox — the file
    /// SwiftData used before any App Group was added.
    static var url: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "default.store")
    }
}
