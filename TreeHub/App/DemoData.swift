import SwiftUI
import SwiftData
import UIKit

/// Sample data used only when the app is launched with "-demo" (simulator screenshots). Never runs on your phone.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func seed(_ context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        let oakID = UUID(), redwoodID = UUID(), sycamoreID = UUID()
        let trees: [(UUID, String, String, Double, Double, String, Color)] = [
            (oakID, "Grandpa Oak", "Coast Live Oak", 37.2823, -121.9431, "Campbell Park, Campbell", Color(red: 0.35, green: 0.6, blue: 0.3)),
            (redwoodID, "The Giant", "Coast Redwood", 37.1700, -122.2230, "Big Basin, Boulder Creek", Color(red: 0.55, green: 0.3, blue: 0.2)),
            (sycamoreID, "Silver Arms", "California Sycamore", 37.2870, -121.9500, "Los Gatos Creek Trail, Campbell", Color(red: 0.6, green: 0.65, blue: 0.5)),
        ]
        let plan: [(Int, Int, Int, Double, Bool, [String], Int)] = [
            // (days ago, tree index, hour, minutes, barefoot, tags, mood after)
            (0, 0, 7, 12, true, ["chill", "park", "sober", "sunrise"], 5),
            (1, 2, 17, 10, true, ["hike", "trail", "solo"], 5),
            (2, 0, 8, 12, false, ["park", "chill"], 4),
            (6, 1, 11, 20, true, ["hike", "sober"], 5),
            (9, 0, 18, 8, false, ["park"], 4),
        ]
        let leaves = ["heart", "oak", "ginkgo", "moonlit", "maple"]
        for (i, p) in plan.enumerated() {
            let t = trees[p.1]
            let h = Hug()
            h.date = cal.date(bySettingHour: p.2, minute: 15, second: 0, of: cal.date(byAdding: .day, value: -p.0, to: now)!) ?? now
            h.treeID = t.0; h.treeName = t.1; h.species = t.2
            h.latitude = t.3; h.longitude = t.4; h.placeName = t.5
            h.treePhoto = image(t.6, symbol: "tree.fill")
            h.selfiePhoto = image(t.6.opacity(0.8), symbol: "figure.arms.open")
            h.barefoot = p.4
            h.tags = p.5
            h.exercise = "Tranquility"
            h.durationMin = p.3
            h.avgHR = 58 + Double(i)
            h.minHR = 51 + Double(i)
            h.maxHR = 72
            h.respRate = 5.5 + Double(i) * 0.3
            h.stressStart = 41
            h.stressEnd = 19
            h.bodyBattery = 4
            h.moodBefore = 3
            h.moodAfter = p.6
            h.weather = "Sunny"
            h.notes = i == 0 ? "Socks off, cold grass, twelve minutes of Tranquility. Felt the whole trunk breathing with me." : ""
            h.leafKey = leaves[i % leaves.count]
            h.xp = GameEngine.xp(for: h, existing: []).total
            context.insert(h)
        }
        // A walk around Campbell
        let a = Activity()
        a.kind = .hike
        a.start = cal.date(byAdding: .hour, value: -26, to: now)!
        a.end = a.start.addingTimeInterval(62 * 60)
        var pts: [RoutePoint] = []
        for k in 0..<240 {
            let ang = Double(k) / 240 * 2 * .pi
            let loc = CLLocationWrapper.make(lat: 37.2850 + 0.006 * sin(ang) + 0.0012 * sin(ang * 5),
                                             lng: -121.9480 + 0.009 * cos(ang),
                                             alt: 60 + 25 * sin(ang * 2),
                                             time: a.start.addingTimeInterval(Double(k) * 15.5))
            pts.append(loc)
        }
        a.route = pts
        a.distanceM = 4180
        a.movingSec = 3500
        a.elevGainM = 64
        a.startPlace = "Winchester Blvd, Campbell"
        a.endPlace = "Los Gatos Creek Trail, Campbell"
        context.insert(a)

        let d = Activity()
        d.kind = .drive
        d.title = "Drive to Big Basin"
        d.start = cal.date(byAdding: .day, value: -6, to: now)!
        d.end = d.start.addingTimeInterval(55 * 60)
        d.distanceM = 48_000
        d.movingSec = 3000
        d.maxSpeed = 29
        d.startPlace = "Campbell"
        d.endPlace = "Boulder Creek"
        context.insert(d)
        try? context.save()
    }

    static func image(_ color: Color, symbol: String) -> Data? {
        let size = CGSize(width: 600, height: 700)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = UIColor(color)
            let colors = [c.cgColor, UIColor(red: 0.04, green: 0.12, blue: 0.08, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let cfg = UIImage.SymbolConfiguration(pointSize: 260, weight: .regular)
            if let s = UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal) {
                s.draw(at: CGPoint(x: (size.width - s.size.width) / 2, y: (size.height - s.size.height) / 2))
            }
        }
        return img.jpegData(compressionQuality: 0.8)
    }
}

import CoreLocation
enum CLLocationWrapper {
    static func make(lat: Double, lng: Double, alt: Double, time: Date) -> RoutePoint {
        RoutePoint(CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), altitude: alt,
                              horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: time))
    }
}
