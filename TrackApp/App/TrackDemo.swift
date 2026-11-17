import Foundation
import SwiftData
import CoreLocation

/// Sample trips used only when launched with "-demo" (simulator screenshots).
enum TrackDemo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-demo -open <screen>` (simulator QA): lifetime, monthly, activity, recap, moreapps.
    static var open: String? { isOn ? argument(after: "-open") : nil }

    @MainActor private static var seeded = false

    @MainActor
    static func seed(_ context: ModelContext) {
        guard !seeded else { return }
        seeded = true
        let now = Date()
        // (days ago, kind, distance m, minutes, climb m, center lat, lng, size, title, start, end)
        let trips: [(Int, ActivityKind, Double, Double, Double, Double, Double, Double, String, String, String)] = [
            (0, .run, 5200, 27, 22, 37.7772, -122.4500, 0.008, "", "Haight St, San Francisco", "Fell St, San Francisco"),
            (1, .drive, 14_000, 32, 0, 37.7750, -122.4700, 0.03, "Drive to Lands End", "Mission District, San Francisco", "Lands End"),
            (1, .hike, 9300, 140, 160, 37.7850, -122.5050, 0.012, "Coastal Trail", "Lands End", "Lands End"),
            (3, .bike, 21_000, 64, 120, 37.7500, -122.4300, 0.03, "", "The Panhandle", "Stow Lake"),
            (5, .run, 10_300, 55, 40, 37.7772, -122.4500, 0.012, "First 10K!", "Golden Gate Park", "Golden Gate Park"),
            (8, .walk, 3100, 41, 10, 37.7750, -122.4480, 0.006, "", "Hayes Valley", "Hayes Valley"),
            (12, .drive, 31_000, 70, 0, 37.7600, -122.4400, 0.04, "", "San Francisco", "San Francisco"),
            (16, .run, 6400, 33, 30, 37.7772, -122.4500, 0.009, "", "San Francisco", "San Francisco"),
            (24, .hike, 7200, 120, 120, 37.7989, -122.4662, 0.01, "", "Presidio, San Francisco", "Presidio, San Francisco"),
        ]
        let cal = Calendar.current
        for t in trips {
            let a = Activity()
            a.kind = t.1
            a.title = t.8
            let day = cal.date(byAdding: .day, value: -t.0, to: now) ?? now
            a.start = cal.date(bySettingHour: t.1 == .run ? 7 : 15, minute: 10, second: 0, of: day) ?? day
            a.end = a.start.addingTimeInterval(t.3 * 60)
            a.distanceM = t.2
            a.movingSec = t.3 * 60 * 0.95
            a.elevGainM = t.4
            a.maxSpeed = t.1 == .drive ? 31 : (t.1 == .bike ? 11 : 4.5)
            a.startPlace = t.9
            a.endPlace = t.10
            var pts: [RoutePoint] = []
            let n = 200
            for k in 0..<n {
                let ang = Double(k) / Double(n) * 2 * .pi
                let lat = t.5 + t.7 * 0.6 * sin(ang) + t.7 * 0.12 * sin(ang * 4)
                let lng = t.6 + t.7 * cos(ang)
                let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                     altitude: 50 + t.4 / 2 * sin(ang), horizontalAccuracy: 5, verticalAccuracy: 5,
                                     timestamp: a.start.addingTimeInterval(t.3 * 60 * Double(k) / Double(n)))
                pts.append(RoutePoint(loc))
            }
            a.route = pts
            context.insert(a)
        }
        try? context.save()
    }
}
