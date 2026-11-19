import Foundation

/// Rootbound -> Roamr: which of Roamr's recent walks, runs and hikes passed which of your trees (started or ended
/// within ~250 m, or a hug of the tree happened on the walk), published in rootbound.json as trip id + tree id and
/// name. The trees' coordinates never leave Rootbound; Roamr's trip page shows "Trees along this walk" from it.
/// Nil (nothing written) when Roamr hasn't shared any trips.
enum RoamrTreeLinks {
    static func compute(hugs: [Hug], trips: [WellnessBridge.Trip]? = WellnessBridge.roamr()?.trips) -> [WellnessBridge.TripTrees]? {
        guard let trips, !trips.isEmpty else { return nil }
        let spots = TreeSummary.build(from: hugs).map { t in
            WellnessConnect.TreeSpot(id: t.id, name: t.name, species: t.species,
                                     lat: t.coordinate?.latitude, lng: t.coordinate?.longitude,
                                     hugTimes: t.hugs.map { (start: $0.date, minutes: $0.durationMin) })
        }
        return WellnessConnect.tripTrees(trees: spots, trips: trips)
    }
}
