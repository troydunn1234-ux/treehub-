import Foundation
import MapKit
import CoreLocation
import AVFoundation
import UIKit

/// A place you can drive to: a search result, a recent, Home or Work.
struct NavPlace: Codable, Hashable, Identifiable {
    var name: String
    var subtitle: String
    var lat: Double
    var lng: Double
    var id: String { "\(name)|\(String(format: "%.5f,%.5f", lat, lng))" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    init(name: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        self.name = name; self.subtitle = subtitle; lat = coordinate.latitude; lng = coordinate.longitude
    }
    init(_ item: MKMapItem) {
        let pm = item.placemark
        let parts = [pm.thoroughfare.map { t in pm.subThoroughfare.map { "\($0) \(t)" } ?? t }, pm.locality, pm.administrativeArea]
        self.init(name: item.name ?? pm.name ?? "Pinned place",
                  subtitle: parts.compactMap { $0 }.joined(separator: ", "),
                  coordinate: pm.coordinate)
    }
    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }
}

/// One turn (or the arrival) on a route.
struct NavStep: Identifiable {
    let id = UUID()
    let instruction: String
    /// Distance along the route (meters) where this maneuver happens.
    var along: Double = 0
    let coordinate: CLLocationCoordinate2D

    var symbol: String { NavStep.symbol(for: instruction) }
    /// "onto Stevens Creek Blvd" → "Stevens Creek Blvd"
    var road: String {
        let lower = instruction.lowercased()
        for key in [" onto ", " on ", " toward ", " towards ", " to "] {
            if let r = lower.range(of: key) {
                let start = instruction.index(instruction.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: r.upperBound))
                return String(instruction[start...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return instruction
    }

    static func symbol(for instruction: String) -> String {
        let s = instruction.lowercased()
        if s.contains("arrive") || s.contains("destination") { return "flag.checkered" }
        if s.contains("u-turn") || s.contains("make a u") { return "arrow.uturn.left" }
        if s.contains("roundabout") || s.contains("traffic circle") { return "arrow.triangle.turn.up.right.circle" }
        if s.contains("merge") { return "arrow.merge" }
        if s.contains("exit") || s.contains("ramp") {
            return s.contains("left") ? "arrow.up.left" : "arrow.up.right"
        }
        if s.contains("slight left") || s.contains("keep left") || s.contains("bear left") { return "arrow.up.left" }
        if s.contains("slight right") || s.contains("keep right") || s.contains("bear right") { return "arrow.up.right" }
        if s.contains("left") { return "arrow.turn.up.left" }
        if s.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// A route reduced to what navigation needs (so a fake demo route works the same way).
struct NavRoute: Identifiable {
    let id = UUID()
    let name: String
    let coords: [CLLocationCoordinate2D]
    /// Cumulative distance (m) at each coordinate.
    let cumulative: [Double]
    var steps: [NavStep]
    let distance: Double
    let expectedTime: TimeInterval

    init(name: String, coords: [CLLocationCoordinate2D], steps: [(String, CLLocationCoordinate2D)], expectedTime: TimeInterval) {
        self.name = name
        self.coords = coords
        var cum: [Double] = [0]
        for i in 1..<max(coords.count, 1) where coords.count > 1 {
            cum.append(cum[i - 1] + Navigator.meters(coords[i - 1], coords[i]))
        }
        let total = cum.last ?? 0
        cumulative = cum
        distance = total
        self.expectedTime = expectedTime
        // Place each maneuver at the closest point of the line (in order, so loops don't confuse it).
        var out: [NavStep] = []
        var from = 0
        for (text, c) in steps where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            var best = from, bestD = Double.greatestFiniteMagnitude
            for i in from..<coords.count {
                let d = Navigator.meters(coords[i], c)
                if d < bestD { bestD = d; best = i }
            }
            from = best
            var s = NavStep(instruction: text, coordinate: c)
            s.along = cum.indices.contains(best) ? cum[best] : 0
            out.append(s)
        }
        if out.last.map({ !NavStep.symbol(for: $0.instruction).contains("flag") }) ?? true, let end = coords.last {
            var s = NavStep(instruction: "Arrive at your destination", coordinate: end)
            s.along = total
            out.append(s)
        }
        self.steps = out
    }

    init(_ r: MKRoute) {
        let pl = r.polyline
        var pts = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pl.pointCount)
        pl.getCoordinates(&pts, range: NSRange(location: 0, length: pl.pointCount))
        let steps: [(String, CLLocationCoordinate2D)] = r.steps.map { st in
            var c = kCLLocationCoordinate2DInvalid
            if st.polyline.pointCount > 0 {
                var first = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: 1)
                st.polyline.getCoordinates(&first, range: NSRange(location: 0, length: 1))
                c = first[0]
            }
            return (st.instructions, c)
        }.filter { CLLocationCoordinate2DIsValid($0.1) }
        self.init(name: r.name, coords: pts, steps: steps, expectedTime: r.expectedTravelTime)
    }
}

enum NavMode: String, CaseIterable, Identifiable {
    case drive, walk
    var id: String { rawValue }
    var title: String { self == .drive ? "Drive" : "Walk" }
    var symbol: String { self == .drive ? "car.fill" : "figure.walk" }
    var transport: MKDirectionsTransportType { self == .drive ? .automobile : .walking }
    var activity: ActivityKind { self == .drive ? .drive : .walk }
}

/// Search → route → turn-by-turn. Feed it locations with `update(_:speed:)` while driving.
@MainActor
@Observable
final class Navigator {
    static let shared = Navigator()

    enum Phase: Equatable { case idle, planning, preview, navigating, arrived }

    private(set) var phase: Phase = .idle
    private(set) var destination: NavPlace?
    private(set) var routes: [NavRoute] = []
    var selected = 0
    var mode: NavMode = .drive
    private(set) var error: String?

    private(set) var active: NavRoute?
    private(set) var stepIndex = 0
    private(set) var traveled: Double = 0
    private(set) var toManeuver: Double = 0
    private(set) var remaining: Double = 0
    private(set) var remainingTime: TimeInterval = 0
    private(set) var rerouting = false
    private(set) var startedAt: Date?
    /// Index into active.coords up to which the route has been driven (for dimming).
    private(set) var traveledIndex = 0

    var muted: Bool = UserDefaults.standard.bool(forKey: "navMuted") {
        didSet { UserDefaults.standard.set(muted, forKey: "navMuted"); if muted { voice.stopSpeaking(at: .immediate) } }
    }

    private(set) var recents: [NavPlace] = (Navigator.load("navRecents") as [NavPlace]?) ?? []
    private(set) var home: NavPlace? = Navigator.load("navHome") as NavPlace?
    private(set) var work: NavPlace? = Navigator.load("navWork") as NavPlace?
    /// Starred destinations, shown as chips above the search (after Home and Work).
    private(set) var favorites: [NavPlace] = (Navigator.load("navFavorites") as [NavPlace]?) ?? []

    var isNavigating: Bool { phase == .navigating || phase == .arrived }
    var currentStep: NavStep? { active.flatMap { $0.steps.indices.contains(stepIndex) ? $0.steps[stepIndex] : nil } }
    var nextStep: NavStep? { active.flatMap { $0.steps.indices.contains(stepIndex + 1) ? $0.steps[stepIndex + 1] : nil } }
    var eta: Date { Date().addingTimeInterval(remainingTime) }

    @ObservationIgnored private let voice = AVSpeechSynthesizer()
    @ObservationIgnored private var spoken: Set<String> = []
    @ObservationIgnored private var offRouteSince: Date?
    @ObservationIgnored private var lastReroute = Date.distantPast
    @ObservationIgnored private var lastSearchHere: CLLocationCoordinate2D?

    static let demo = ProcessInfo.processInfo.arguments.contains("-demo") && ProcessInfo.processInfo.arguments.contains("-nav")

    // MARK: Planning

    func plan(to place: NavPlace, from origin: CLLocationCoordinate2D?) async {
        destination = place
        phase = .planning
        error = nil
        remember(place)
        if Self.demo { routes = [Self.demoRoute()]; selected = 0; phase = .preview; return }
        let req = MKDirections.Request()
        req.source = origin.map { MKMapItem(placemark: MKPlacemark(coordinate: $0)) } ?? MKMapItem.forCurrentLocation()
        req.destination = place.mapItem
        req.transportType = mode.transport
        req.requestsAlternateRoutes = true
        do {
            let res = try await MKDirections(request: req).calculate()
            routes = Array(res.routes.prefix(3)).map(NavRoute.init)
            selected = 0
            phase = routes.isEmpty ? .idle : .preview
            if routes.isEmpty { error = "No route found." }
        } catch {
            self.error = "Couldn't get directions. Check your connection and try again."
            phase = .idle
        }
    }

    func cancel() {
        voice.stopSpeaking(at: .immediate)
        phase = .idle; routes = []; active = nil; destination = nil; error = nil
        stepIndex = 0; traveled = 0; traveledIndex = 0; offRouteSince = nil; rerouting = false; startedAt = nil
        deactivateAudio()
    }

    /// Start following the selected route.
    func go() {
        guard routes.indices.contains(selected) else { return }
        active = routes[selected]
        stepIndex = 0; traveled = 0; traveledIndex = 0; spoken = []; offRouteSince = nil
        remaining = active?.distance ?? 0
        remainingTime = active?.expectedTime ?? 0
        toManeuver = active?.steps.first?.along ?? 0
        startedAt = Date()
        phase = .navigating
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let s = currentStep { say("Let's go. " + phrase(for: s, in: toManeuver)) }
    }

    // MARK: Following

    func update(_ here: CLLocationCoordinate2D, speed: Double) {
        guard phase == .navigating, let r = active, r.coords.count > 1 else { return }
        // Project onto the route, searching a window ahead of where we were (and a little behind).
        let lo = max(0, traveledIndex - 5), hi = r.coords.count - 1
        var best = (dist: Double.greatestFiniteMagnitude, along: traveled, idx: traveledIndex)
        for i in lo..<hi {
            let (d, t) = Self.project(here, r.coords[i], r.coords[i + 1])
            if d < best.dist {
                let seg = r.cumulative[i + 1] - r.cumulative[i]
                best = (d, r.cumulative[i] + seg * t, i)
            }
            if d < 15 && i > traveledIndex + 400 { break }
        }
        // Off route? Re-plan after 8 s more than 60 m away.
        if best.dist > 60 {
            if offRouteSince == nil { offRouteSince = Date() }
            if let since = offRouteSince, Date().timeIntervalSince(since) > 8, !rerouting, Date().timeIntervalSince(lastReroute) > 15 {
                reroute(from: here)
            }
            return
        }
        offRouteSince = nil
        traveled = max(traveled, best.along)
        traveledIndex = max(traveledIndex, best.idx)
        remaining = max(0, r.distance - traveled)
        let avg = r.distance > 0 ? r.expectedTime / r.distance : 0
        remainingTime = speed > 3 ? min(remaining * avg * 1.4, max(remaining / speed, remaining * avg * 0.7)) : remaining * avg

        while stepIndex < r.steps.count - 1, r.steps[stepIndex].along < traveled - 8 { stepIndex += 1 }
        let step = r.steps[stepIndex]
        toManeuver = max(0, step.along - traveled)

        if remaining < 30 || (stepIndex == r.steps.count - 1 && toManeuver < 25) {
            arrive(); return
        }
        announce(step)
    }

    private func announce(_ step: NavStep) {
        let walking = mode == .walk
        let far: Double = walking ? 150 : 805, near: Double = walking ? 40 : 152, now: Double = walking ? 12 : 35
        let key = step.id.uuidString
        if toManeuver <= now, !spoken.contains(key + "now") {
            spoken.formUnion([key + "now", key + "near", key + "far"])
            say(step.instruction)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } else if toManeuver <= near, toManeuver > now, !spoken.contains(key + "near") {
            spoken.formUnion([key + "near", key + "far"])
            say(phrase(for: step, in: toManeuver))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else if toManeuver <= far, toManeuver > near * 2, !spoken.contains(key + "far") {
            spoken.insert(key + "far")
            say(phrase(for: step, in: toManeuver))
        }
    }

    private func arrive() {
        guard phase == .navigating else { return }
        phase = .arrived
        remaining = 0; remainingTime = 0
        if let r = active { traveled = r.distance; traveledIndex = r.coords.count - 1 }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        say("You've arrived" + (destination.map { " at \($0.name)" } ?? "") + ". Nice drive.")
    }

    private func reroute(from here: CLLocationCoordinate2D) {
        guard let dest = destination, !Self.demo else { return }
        rerouting = true
        lastReroute = Date()
        say("Rerouting.")
        Task {
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: here))
            req.destination = dest.mapItem
            req.transportType = mode.transport
            if let r = try? await MKDirections(request: req).calculate().routes.first {
                active = NavRoute(r)
                stepIndex = 0; traveled = 0; traveledIndex = 0; spoken = []
                remaining = r.distance; remainingTime = r.expectedTravelTime
                if let s = currentStep { say(phrase(for: s, in: s.along)) }
            }
            offRouteSince = nil
            rerouting = false
        }
    }

    // MARK: Voice

    private func phrase(for step: NavStep, in meters: Double) -> String {
        if step.symbol == "flag.checkered" { return "In \(Self.spokenDistance(meters)), you'll arrive." }
        let lowered = step.instruction.prefix(1).lowercased() + String(step.instruction.dropFirst())
        return "In \(Self.spokenDistance(meters)), \(lowered)"
    }

    private func say(_ text: String) {
        guard !muted, !Self.demo else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? s.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        voice.speak(u)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !self.voice.isSpeaking else { return }
            self.deactivateAudio()
        }
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Places

    func setHome(_ p: NavPlace) { home = p; Self.save(p, "navHome") }
    func setWork(_ p: NavPlace) { work = p; Self.save(p, "navWork") }
    func removeRecent(_ p: NavPlace) { recents.removeAll { $0.id == p.id }; Self.save(recents, "navRecents") }

    func isFavorite(_ p: NavPlace) -> Bool { favorites.contains { $0.id == p.id } }

    /// Stars a place, or un-stars it if it was starred already.
    func toggleFavorite(_ p: NavPlace) {
        if isFavorite(p) {
            favorites.removeAll { $0.id == p.id }
        } else {
            favorites.append(p)
            favorites = Array(favorites.prefix(20))
        }
        Self.save(favorites, "navFavorites")
    }

    func removeFavorite(_ p: NavPlace) {
        favorites.removeAll { $0.id == p.id }
        Self.save(favorites, "navFavorites")
    }

    private func remember(_ p: NavPlace) {
        recents.removeAll { $0.id == p.id }
        recents.insert(p, at: 0)
        recents = Array(recents.prefix(8))
        Self.save(recents, "navRecents")
    }

    nonisolated private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    nonisolated private static func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: Geometry

    nonisolated static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Distance (m) from p to segment ab, and how far along ab (0…1) the closest point is.
    nonisolated static func project(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> (Double, Double) {
        let k = cos(a.latitude * .pi / 180) * 111_320
        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * k, by = (b.latitude - a.latitude) * 111_320
        let px = (p.longitude - a.longitude) * k, py = (p.latitude - a.latitude) * 111_320
        let len2 = bx * bx + by * by
        let t = len2 > 0 ? max(0, min(1, ((px - ax) * bx + (py - ay) * by) / len2)) : 0
        let dx = px - bx * t, dy = py - by * t
        return ((dx * dx + dy * dy).squareRoot(), t)
    }

    static func shortDistance(_ m: Double) -> String {
        if Units.metric {
            return m < 950 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000)
        }
        let ft = m * 3.28084
        return ft < 1000 ? "\(max(0, Int((ft / 50).rounded()) * 50)) ft" : String(format: "%.1f mi", m / 1609.344)
    }

    static func spokenDistance(_ m: Double) -> String {
        if Units.metric { return m < 950 ? "\(Int((m / 50).rounded()) * 50) meters" : String(format: "%.1f kilometers", m / 1000) }
        let ft = m * 3.28084
        if ft < 1000 { return "\(max(50, Int((ft / 50).rounded()) * 50)) feet" }
        let mi = m / 1609.344
        if abs(mi - 0.5) < 0.08 { return "half a mile" }
        if abs(mi - 0.25) < 0.06 { return "a quarter mile" }
        return String(format: "%.1f miles", mi)
    }

    // MARK: Demo (-demo -nav): westbound I-280 from Cupertino, matching the screenshot drive.

    static func demoRoute() -> NavRoute {
        let pts: [CLLocationCoordinate2D] = [
            .init(latitude: 37.3229, longitude: -122.0322), .init(latitude: 37.3248, longitude: -122.0371),
            .init(latitude: 37.3271, longitude: -122.0424), .init(latitude: 37.3302, longitude: -122.0480),
            .init(latitude: 37.3321, longitude: -122.0545), .init(latitude: 37.3333, longitude: -122.0611),
            .init(latitude: 37.3340, longitude: -122.0680), .init(latitude: 37.3352, longitude: -122.0745),
            .init(latitude: 37.3380, longitude: -122.0790), .init(latitude: 37.3420, longitude: -122.0812),
            .init(latitude: 37.3466, longitude: -122.0830),
        ]
        return NavRoute(name: "I-280 N", coords: pts, steps: [
            ("Keep left to stay on I-280 N", pts[2]),
            ("Take exit 13 toward Foothill Expy", pts[7]),
            ("Turn right onto Foothill Expy", pts[9]),
        ], expectedTime: 7 * 60)
    }

    static let demoPlace = NavPlace(name: "Rancho San Antonio", subtitle: "Cupertino, CA",
                                    coordinate: .init(latitude: 37.3466, longitude: -122.0830))
}
