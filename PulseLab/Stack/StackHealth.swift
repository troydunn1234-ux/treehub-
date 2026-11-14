import Foundation
import HealthKit

/// Writes checked-off supplements to Apple Health as nutrients, when the dose has a real amount
/// (e.g. "2000 IU" vitamin D, "400 mg" magnesium). Counts like "1 capsule" can't be converted, so they're skipped.
/// Unchecking a dose removes what was written for it.
enum StackHealth {
    private static let store = HKHealthStore()
    private static let doseKey = "PulseLabStackDose"

    struct Target { let type: HKQuantityTypeIdentifier; let unit: HKUnit; let factor: Double }

    /// Which Health nutrient a supplement maps to, and how to convert its dose.
    static func target(name: String, dose: String) -> Target? {
        let n = name.lowercased()
        let d = DoseParts(dose)
        let u = d.unit.lowercased()
        let mg = HKUnit.gramUnit(with: .milli), mcg = HKUnit.gramUnit(with: .micro), g = HKUnit.gram()
        func mass(_ type: HKQuantityTypeIdentifier, _ want: HKUnit) -> Target? {
            switch u {
            case "mg": return Target(type: type, unit: mg, factor: 1)
            case "mcg": return Target(type: type, unit: mcg, factor: 1)
            case "g": return Target(type: type, unit: g, factor: 1)
            default: return nil
            }
        }
        if n.contains("vitamin d") || n.contains("d3") {
            if u == "iu" { return Target(type: .dietaryVitaminD, unit: mcg, factor: 0.025) }  // 40 IU = 1 mcg
            return mass(.dietaryVitaminD, mcg)
        }
        if n.contains("vitamin c") { return mass(.dietaryVitaminC, mg) }
        if n.contains("b12") { return mass(.dietaryVitaminB12, mcg) }
        if n.contains("magnesium") { return mass(.dietaryMagnesium, mg) }
        if n.contains("zinc") { return mass(.dietaryZinc, mg) }
        if n.contains("iron") { return mass(.dietaryIron, mg) }
        if n.contains("calcium") { return mass(.dietaryCalcium, mg) }
        if n.contains("potassium") { return mass(.dietaryPotassium, mg) }
        if n.contains("caffeine") || n.contains("pre-workout") || n.contains("preworkout") { return mass(.dietaryCaffeine, mg) }
        if n.contains("protein") { return u == "g" ? Target(type: .dietaryProtein, unit: g, factor: 1) : nil }
        return nil
    }

    /// True when this supplement will show up in Health.
    static func syncs(_ s: Supplement) -> Bool { target(name: s.name, dose: s.dose) != nil }

    static func logged(_ s: Supplement, day: String) {
        guard HKHealthStore.isHealthDataAvailable(), let t = target(name: s.name, dose: s.dose),
              let type = HKQuantityType.quantityType(forIdentifier: t.type) else { return }
        let amount = DoseParts(s.dose).amount * t.factor
        guard amount > 0 else { return }
        // Today: now. A past day you're catching up on: midday that day.
        let isToday = day == Day.key(Date())
        let when = isToday ? Date() : (Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Day.date(day)) ?? Day.date(day))
        store.requestAuthorization(toShare: [type], read: []) { ok, _ in
            guard ok, store.authorizationStatus(for: type) == .sharingAuthorized else { return }
            let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: t.unit, doubleValue: amount),
                                          start: when, end: when,
                                          metadata: [doseKey: "\(s.id.uuidString)-\(day)", HKMetadataKeyFoodType: s.name])
            store.save(sample) { _, _ in }
        }
    }

    static func unlogged(_ s: Supplement, day: String) {
        guard HKHealthStore.isHealthDataAvailable(), let t = target(name: s.name, dose: s.dose),
              let type = HKQuantityType.quantityType(forIdentifier: t.type) else { return }
        let pred = HKQuery.predicateForObjects(withMetadataKey: doseKey, allowedValues: ["\(s.id.uuidString)-\(day)"])
        store.deleteObjects(of: type, predicate: pred) { _, _, _ in }
    }
}
