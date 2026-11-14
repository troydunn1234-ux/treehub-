import Foundation
import SwiftData

// Gas & MPG log. Both models follow the CloudKit rules (every field has a default, no unique
// constraints, no relationships) so they sync through the same private iCloud store as trips.

@Model
final class GasVehicle {
    var id: UUID = UUID()
    var name: String = ""
    var created: Date = Date()

    init(name: String) {
        self.name = name
        self.created = Date()
    }
}

@Model
final class FillUp {
    var id: UUID = UUID()
    var vehicleID: UUID?
    var date: Date = Date()
    var gallons: Double = 0
    /// Price per gallon in dollars (0 = unknown).
    var pricePerGallon: Double = 0
    /// What you paid in dollars (0 = unknown).
    var total: Double = 0
    /// Odometer in miles (nil = not entered).
    var odometer: Double?
    var station: String = ""
    /// Filled the tank all the way (MPG is only figured between full fill-ups).
    var full: Bool = true
    var notes: String = ""

    init(vehicleID: UUID?, date: Date, gallons: Double, pricePerGallon: Double, total: Double,
         odometer: Double?, station: String, full: Bool = true) {
        self.vehicleID = vehicleID
        self.date = date
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.total = total
        self.odometer = odometer
        self.station = station
        self.full = full
    }

    /// Total cost, worked out from price × gallons when only the price was entered.
    var cost: Double { total > 0 ? total : pricePerGallon * gallons }
    /// Price per gallon, worked out from total ÷ gallons when only the total was entered.
    var unitPrice: Double { pricePerGallon > 0 ? pricePerGallon : (gallons > 0 ? total / gallons : 0) }
}

enum GasMath {
    struct MPGPoint: Identifiable {
        var id: UUID
        var date: Date
        var miles: Double
        var gallons: Double
        var mpg: Double
        /// true = from odometer readings, false = from drives Roamr recorded in between.
        var fromOdometer: Bool
    }

    struct MonthSpend: Identifiable {
        var id: Date { month }
        var month: Date
        var dollars: Double
        var gallons: Double
    }

    static let metersPerMile = 1609.344

    /// MPG for each full fill-up after the first: miles driven since the previous full fill-up
    /// (odometer difference when both have one, otherwise Roamr-recorded drive miles in between)
    /// divided by the gallons put in since then (partial fill-ups in between included).
    static func mpg(fills: [FillUp], drives: [Activity]) -> [MPGPoint] {
        let sorted = fills.sorted { $0.date < $1.date }
        let driveList = drives.filter { $0.kind == .drive }
        var out: [MPGPoint] = []
        var lastFull: FillUp?
        var gallonsSince = 0.0
        for f in sorted {
            guard let prev = lastFull else {
                if f.full { lastFull = f; gallonsSince = 0 }
                continue
            }
            gallonsSince += f.gallons
            guard f.full else { continue }
            var miles = 0.0
            var fromOdo = false
            if let a = prev.odometer, let b = f.odometer, b > a {
                miles = b - a
                fromOdo = true
            } else {
                miles = driveList
                    .filter { $0.start >= prev.date && $0.start < f.date }
                    .reduce(0) { $0 + $1.distanceM } / metersPerMile
            }
            if miles > 1, gallonsSince > 0.1 {
                let v = miles / gallonsSince
                if v.isFinite && v < 200 {
                    out.append(MPGPoint(id: f.id, date: f.date, miles: miles, gallons: gallonsSince, mpg: v, fromOdometer: fromOdo))
                }
            }
            lastFull = f
            gallonsSince = 0
        }
        return out
    }

    static func monthly(_ fills: [FillUp], calendar: Calendar = .current) -> [MonthSpend] {
        var buckets: [Date: (Double, Double)] = [:]
        for f in fills {
            let m = calendar.date(from: calendar.dateComponents([.year, .month], from: f.date)) ?? f.date
            let cur = buckets[m] ?? (0, 0)
            buckets[m] = (cur.0 + f.cost, cur.1 + f.gallons)
        }
        return buckets.map { MonthSpend(month: $0.key, dollars: $0.value.0, gallons: $0.value.1) }
            .sorted { $0.month < $1.month }
    }

    /// Rough fuel cost of a drive: miles ÷ average MPG × latest price per gallon.
    static func driveCost(meters: Double, fills: [FillUp], drives: [Activity]) -> Double? {
        let points = mpg(fills: fills, drives: drives).suffix(5)
        guard !points.isEmpty else { return nil }
        let avg = points.reduce(0) { $0 + $1.miles } / max(0.1, points.reduce(0) { $0 + $1.gallons })
        guard let price = fills.sorted(by: { $0.date > $1.date }).first(where: { $0.unitPrice > 0 })?.unitPrice,
              avg > 0 else { return nil }
        return meters / metersPerMile / avg * price
    }
}
