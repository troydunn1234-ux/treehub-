import Foundation
import CoreLocation

enum Units {
    static var metric: Bool { UserDefaults.standard.bool(forKey: "useMetric") }
}

enum Format {
    static func distance(_ meters: Double) -> String {
        if Units.metric {
            return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.2f km", meters / 1000)
        }
        let miles = meters / 1609.344
        return miles < 0.1 ? "\(Int((meters * 3.28084).rounded())) ft" : String(format: "%.2f mi", miles)
    }

    /// Number only, for big stat displays.
    static func distanceValue(_ meters: Double) -> String {
        Units.metric ? String(format: "%.2f", meters / 1000) : String(format: "%.2f", meters / 1609.344)
    }

    static var distanceUnit: String { Units.metric ? "km" : "mi" }

    static func elevation(_ meters: Double) -> String {
        Units.metric ? "\(Int(meters.rounded())) m" : "\(Int((meters * 3.28084).rounded())) ft"
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds).rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func minutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let h = Int(minutes) / 60, m = Int(minutes.rounded()) % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return minutes == minutes.rounded() ? "\(Int(minutes)) min" : String(format: "%.1f min", minutes)
    }

    /// Pace for on-foot activities (min per mi/km), speed for rides and drives.
    static func paceOrSpeed(distance: Double, seconds: Double, kind: ActivityKind) -> String {
        guard distance > 20, seconds > 0 else { return "--" }
        if kind.isOnFoot {
            let unit = Units.metric ? 1000.0 : 1609.344
            let secPer = seconds / (distance / unit)
            guard secPer.isFinite, secPer < 3600 else { return "--" }
            return String(format: "%d:%02d /%@", Int(secPer) / 60, Int(secPer) % 60, distanceUnit)
        }
        return speed(distance / seconds)
    }

    static func speed(_ mps: Double) -> String {
        guard mps.isFinite, mps >= 0 else { return "--" }
        return Units.metric ? String(format: "%.0f km/h", mps * 3.6) : String(format: "%.0f mph", mps * 2.236936)
    }

    static func partOfDay(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f
    }()

    static func day(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func dayTime(_ d: Date) -> String { dayTimeFormatter.string(from: d) }

    static func coord(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    static func number(_ v: Double?) -> String {
        guard let v else { return "--" }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

enum Geo {
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Short "Street, City" style label.
    static func label(for placemark: CLPlacemark) -> String {
        var parts: [String] = []
        if let name = placemark.name, placemark.areasOfInterest?.contains(name) == true {
            parts.append(name)
        } else if let street = placemark.thoroughfare {
            parts.append(street)
        } else if let name = placemark.name {
            parts.append(name)
        }
        if let city = placemark.locality, !parts.contains(city) { parts.append(city) }
        return parts.joined(separator: ", ")
    }

    static func placeName(for coordinate: CLLocationCoordinate2D) async -> String {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(loc), let mark = marks.first else { return "" }
        return label(for: mark)
    }

    /// Accepts "37.28, -121.95", Apple/Google Maps links with coordinates, and DMS.
    static func parseCoordinates(_ raw: String) -> CLLocationCoordinate2D? {
        let text = (raw.removingPercentEncoding ?? raw)
        let num = #"(-?\d{1,3}(?:\.\d+)?)"#
        let patterns = [
            #"@"# + num + #","# + num,
            #"(?:ll|q|query|coordinate|sll|daddr|destination)="# + num + #",\s*"# + num,
            #"/place/"# + num + #","# + num,
            "^\\s*" + num + #"\s*[, ]\s*"# + num + "\\s*$",
            num + #",\s*"# + num,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               m.numberOfRanges >= 3,
               let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text),
               let lat = Double(text[r1]), let lng = Double(text[r2]),
               valid(lat, lng) {
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }
        // Degrees / minutes / seconds, e.g. 37°17'13.9"N 121°57'00.0"W
        let dms = #"(\d{1,3})[°\s]+(\d{1,2})['’′\s]+(\d{1,2}(?:\.\d+)?)["”″\s]*([NSns])[\s,]+(\d{1,3})[°\s]+(\d{1,2})['’′\s]+(\d{1,2}(?:\.\d+)?)["”″\s]*([EWew])"#
        if let re = try? NSRegularExpression(pattern: dms),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            func g(_ i: Int) -> String { Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
            var lat = (Double(g(1)) ?? 0) + (Double(g(2)) ?? 0) / 60 + (Double(g(3)) ?? 0) / 3600
            var lng = (Double(g(5)) ?? 0) + (Double(g(6)) ?? 0) / 60 + (Double(g(7)) ?? 0) / 3600
            if g(4).uppercased() == "S" { lat = -lat }
            if g(8).uppercased() == "W" { lng = -lng }
            if valid(lat, lng) { return CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        }
        return nil
    }

    private static func valid(_ lat: Double, _ lng: Double) -> Bool {
        abs(lat) <= 90 && abs(lng) <= 180 && !(lat == 0 && lng == 0)
    }
}
