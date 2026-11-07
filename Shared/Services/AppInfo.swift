import Foundation

enum AppInfo {
    #if TRACK_APP
    static let name = "Roamr"
    #else
    static let name = "Rootbound"
    #endif
}
