import SwiftUI

// Nature Roll's judgement: is this photo a real nature/outdoor shot, and which categories is it?
// Everything here is pure Swift (no Vision, no Photos) so it can be unit-tested with made-up labels.

// MARK: - Categories

enum NatureCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case sunrises, trails, mountains, forests, water, sky, wildlife, flowers

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sunrises: return "Sunrises & Sunsets"
        case .trails: return "Trails & Hikes"
        case .mountains: return "Mountains & Views"
        case .forests: return "Forests"
        case .water: return "Water"
        case .sky: return "Sky & Stars"
        case .wildlife: return "Wildlife"
        case .flowers: return "Flowers & Plants"
        }
    }

    var short: String {
        switch self {
        case .sunrises: return "Sunsets"
        case .trails: return "Trails"
        case .mountains: return "Mountains"
        case .forests: return "Forests"
        case .water: return "Water"
        case .sky: return "Sky & Stars"
        case .wildlife: return "Wildlife"
        case .flowers: return "Flowers"
        }
    }

    var symbol: String {
        switch self {
        case .sunrises: return "sun.horizon.fill"
        case .trails: return "figure.hiking"
        case .mountains: return "mountain.2.fill"
        case .forests: return "tree.fill"
        case .water: return "water.waves"
        case .sky: return "moon.stars.fill"
        case .wildlife: return "bird.fill"
        case .flowers: return "camera.macro"
        }
    }

    var tint: Color {
        switch self {
        case .sunrises: return Theme.gold
        case .trails: return Theme.glow
        case .mountains: return Color(red: 0.75, green: 0.7, blue: 0.62)
        case .forests: return Theme.leaf
        case .water: return Theme.sky
        case .sky: return Color(red: 0.6, green: 0.6, blue: 1)
        case .wildlife: return Color(red: 0.95, green: 0.6, blue: 0.3)
        case .flowers: return Color(red: 1, green: 0.55, blue: 0.75)
        }
    }
}

// MARK: - Strictness

enum NatureStrictness: Int, CaseIterable, Codable, Identifiable {
    case strict, balanced, everything

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .strict: return "Strict"
        case .balanced: return "Balanced"
        case .everything: return "Everything"
        }
    }

    var blurb: String {
        switch self {
        case .strict: return "Only real nature shots: trails, peaks, sunsets, wildlife."
        case .balanced: return "Also looser outdoor scenes and park shots."
        case .everything: return "Anything with some nature in it."
        }
    }

    /// Cutoffs for this level. Confidences are Vision's 0…1.
    struct Cutoffs {
        /// The main scene (mountain, sunset, ocean…) has to be at least this confident.
        let primary: Float
        /// Outdoor context (sky, outdoor, landscape…) counted as "outdoors".
        let context: Float
        /// Final nature score needed to be shown.
        let minScore: Float
        /// Aesthetics overall score (-1…1, iOS 18+) below this = blurry/accidental.
        let minAesthetic: Float
        /// Largest face bigger than this share of the frame = a people photo.
        let maxFace: Float
        /// Recognised text covering more than this share of the frame = a sign, menu, document.
        let maxText: Float
        /// Pet, indoor, food, house-plant label confidences that exclude a photo.
        let pet: Float, indoor: Float, food: Float, housePlant: Float
        /// A backyard/hedge/lawn label this strong excludes the photo unless there's real landscape.
        let yard: Float
        /// Wild animal confidence needed for Wildlife.
        let wildlife: Float
        /// Close-up flower confidence needed without landscape around it.
        let closeFlower: Float
    }

    var cutoffs: Cutoffs {
        switch self {
        case .strict:
            return Cutoffs(primary: 0.5, context: 0.3, minScore: 0.5, minAesthetic: -0.25, maxFace: 0.08, maxText: 0.04,
                           pet: 0.35, indoor: 0.35, food: 0.4, housePlant: 0.25, yard: 0.3, wildlife: 0.6, closeFlower: 0.85)
        case .balanced:
            return Cutoffs(primary: 0.35, context: 0.2, minScore: 0.38, minAesthetic: -0.5, maxFace: 0.15, maxText: 0.08,
                           pet: 0.5, indoor: 0.5, food: 0.55, housePlant: 0.4, yard: 0.45, wildlife: 0.45, closeFlower: 0.65)
        case .everything:
            return Cutoffs(primary: 0.2, context: 0.1, minScore: 0.2, minAesthetic: -1.01, maxFace: 0.35, maxText: 0.2,
                           pet: 0.7, indoor: 0.7, food: 0.7, housePlant: 0.7, yard: 0.75, wildlife: 0.3, closeFlower: 0.4)
        }
    }
}

// MARK: - What the scan measured for one photo

/// Everything the scanner learned about a photo. Stored, so strictness and scoring changes apply without a rescan.
struct NatureSignals: Codable, Hashable {
    /// Vision classification label → confidence (0…1); only labels ≥ 0.1 are kept.
    var labels: [String: Float]
    /// Labels that also pass Vision's calibrated high-precision cutoff (`hasMinimumRecall(_:forPrecision:)`).
    var precise: Set<String> = []
    /// Largest detected face as a share of the frame (0…1), nil when not checked.
    var faceFraction: Float?
    /// Recognised text area as a share of the frame (0…1), nil when not checked.
    var textFraction: Float?
    /// Vision aesthetics overall score (-1…1), iOS 18+ only.
    var aesthetic: Float?
    /// Vision says it's a utility shot (receipt, whiteboard, screenshot-like), iOS 18+ only.
    var isUtility: Bool?
    /// Sun elevation in degrees where and when the photo was taken (needs GPS).
    var sunElevation: Double?
    /// Distance in km from the nearest place the person photographs most (home, work), when known.
    var kmFromHome: Double?

    init(labels: [String: Float], precise: Set<String> = [], faceFraction: Float? = nil, textFraction: Float? = nil,
         aesthetic: Float? = nil, isUtility: Bool? = nil, sunElevation: Double? = nil, kmFromHome: Double? = nil) {
        self.labels = labels; self.precise = precise; self.faceFraction = faceFraction; self.textFraction = textFraction
        self.aesthetic = aesthetic; self.isUtility = isUtility; self.sunElevation = sunElevation; self.kmFromHome = kmFromHome
    }

    /// Golden hour / blue hour: the sun is low (just below to a little above the horizon).
    var isGoldenHour: Bool? { sunElevation.map { $0 > -8 && $0 < 12 } }
}

struct NatureVerdict: Hashable {
    /// 0…1: how sure this is a genuine nature/outdoor shot.
    var score: Float
    /// Category → evidence (0…1).
    var categories: [NatureCategory: Float]
    /// Why it was left out (nil when included).
    var excluded: String?
    /// Score weighted by how good the photo looks; used for "Best of".
    var rank: Float

    var included: Bool { excluded == nil && !categories.isEmpty }

    static func out(_ why: String) -> NatureVerdict { NatureVerdict(score: 0, categories: [:], excluded: why, rank: 0) }
}

// MARK: - Scoring

enum NatureScore {
    // Vision labels (exact identifiers; ones a given OS doesn't produce simply never match).
    static let sunrises: Set<String> = ["sunset_sunrise", "sunset", "sunrise", "dusk", "dawn", "twilight", "golden_hour", "afterglow"]
    static let trailWords: Set<String> = ["trail", "hiking", "hike", "hiking_trail", "trailhead", "footpath", "backpacking",
                                          "national_park", "campground", "camping", "trekking", "mountain_trail"]
    /// "path" alone could be a sidewalk; it only counts with forest/mountain/open land around it.
    static let pathWords: Set<String> = ["path", "dirt_road", "boardwalk", "walkway"]
    static let mountains: Set<String> = ["mountain", "mountains", "hill", "hills", "cliff", "canyon", "volcano", "valley", "peak",
                                         "summit", "ridge", "glacier", "desert", "dune", "sand_dune", "mesa", "butte",
                                         "rock_formation", "alpine", "highland", "plateau", "mountain_range", "gorge", "crater"]
    static let forests: Set<String> = ["forest", "woodland", "jungle", "rainforest", "redwood", "sequoia", "woods", "grove",
                                       "old_growth", "bamboo_forest"]
    /// Water that is almost always nature.
    static let wildWater: Set<String> = ["ocean", "sea", "lake", "river", "waterfall", "beach", "shore", "coast", "coastline",
                                         "creek", "stream", "pond", "lagoon", "bay", "surf", "wave", "waves", "cove", "reef",
                                         "tide_pool", "rapids", "wetland", "marsh", "swamp", "estuary", "seashore", "hot_spring",
                                         "geyser", "fjord", "iceberg"]
    /// Water that could be a pool or a glass: only counts when strong and outdoors.
    static let anyWater: Set<String> = ["water", "water_body", "waterways", "waterway"]
    static let manMadeWater: Set<String> = ["swimming_pool", "pool", "fountain", "aquarium", "bathtub", "hot_tub", "glass", "sink"]
    static let starSky: Set<String> = ["night_sky", "star", "stars", "starry_sky", "milky_way", "aurora", "aurora_borealis",
                                       "northern_lights", "rainbow", "moon", "full_moon", "eclipse", "lightning", "galaxy"]
    static let clouds: Set<String> = ["clouds", "cloud", "cloudy", "cloudscape", "cumulus", "storm", "storm_cloud", "fog", "mist"]
    static let plainSky: Set<String> = ["sky", "blue_sky", "sun", "horizon", "overcast"]
    static let openLand: Set<String> = ["meadow", "field", "grassland", "prairie", "countryside", "landscape", "scenery",
                                        "wilderness", "tundra", "snow", "snowfield", "ice", "savanna", "badlands", "steppe",
                                        "nature", "natural_landscape", "panorama", "vista", "rock", "boulder", "cave"]
    static let outdoor: Set<String> = ["outdoor", "outdoors", "land", "grass", "foliage", "tree", "trees", "vegetation",
                                       "plant", "shrub"]
    static let wildlife: Set<String> = [
        "bird", "birds", "wildlife", "wild_animal", "deer", "squirrel", "owl", "hawk", "eagle", "falcon", "raptor", "duck",
        "goose", "swan", "heron", "egret", "crane", "seagull", "gull", "pelican", "hummingbird", "songbird", "woodpecker",
        "crow", "raven", "jay", "robin", "sparrow", "finch", "quail", "rabbit", "hare", "fox", "bear", "elk", "moose",
        "bison", "wolf", "coyote", "lizard", "reptile", "frog", "toad", "turtle", "tortoise", "snake", "seal", "sea_lion",
        "otter", "whale", "dolphin", "butterfly", "dragonfly", "bee", "ladybug", "crab", "starfish", "jellyfish",
        "salamander", "chipmunk", "marmot", "raccoon", "bobcat", "mountain_lion", "cougar", "antelope", "pronghorn",
        "mountain_goat", "bighorn_sheep", "giraffe", "zebra", "elephant", "lion", "tiger", "leopard", "cheetah", "hippo",
        "rhinoceros", "kangaroo", "koala", "penguin", "puffin", "flamingo", "vulture", "condor", "osprey", "kingfisher"]
    static let pets: Set<String> = ["dog", "cat", "puppy", "kitten", "pet", "canine", "feline", "hamster", "guinea_pig",
                                    "goldfish", "dog_bed", "leash", "pet_collar", "litter_box"]
    static let flowers: Set<String> = ["flower", "flowers", "blossom", "wildflower", "sunflower", "tulip", "rose", "daisy",
                                       "poppy", "lupine", "lavender", "orchid", "lily", "cherry_blossom", "magnolia",
                                       "dandelion", "cactus", "succulent", "fern", "moss", "mushroom", "fungus", "lichen",
                                       "bluebonnet", "iris", "hibiscus", "petal", "bloom", "flower_field"]
    static let housePlants: Set<String> = ["houseplant", "house_plant", "potted_plant", "flowerpot", "planter", "vase",
                                           "bouquet", "flower_arrangement", "terrarium", "pot", "windowsill"]
    static let indoor: Set<String> = ["indoor", "indoors", "interior_room", "interior", "room", "living_room", "bedroom",
                                      "kitchen", "bathroom", "office", "furniture", "couch", "sofa", "bed", "table", "desk",
                                      "chair", "shelf", "bookshelf", "carpet", "rug", "ceiling", "lamp", "television",
                                      "computer", "monitor", "interior_shop", "restaurant", "classroom", "hallway",
                                      "cushion", "pillow", "blanket", "countertop", "cabinet", "curtain"]
    static let yard: Set<String> = ["backyard", "yard", "lawn", "hedge", "shrub", "bush", "garden", "patio", "fence", "deck",
                                    "porch", "driveway", "flowerbed", "gardening", "front_yard", "lawn_mower", "sprinkler",
                                    "topiary", "hedgerow", "mulch"]
    static let urban: Set<String> = ["vehicle", "car", "truck", "automobile", "street", "road", "building", "house", "city",
                                     "cityscape", "skyscraper", "parking_lot", "traffic", "bus", "train", "sidewalk",
                                     "storefront", "shop", "urban", "downtown", "highway", "motorcycle", "architecture",
                                     "construction", "residential", "suburb", "apartment", "office_building", "streetlight"]
    static let text: Set<String> = ["document", "text", "screenshot", "paper", "receipt", "menu", "poster", "book",
                                    "handwriting", "printed_page", "whiteboard", "diagram", "chart", "letter", "envelope",
                                    "label", "ticket", "business_card", "barcode", "qr_code", "screen"]
    static let food: Set<String> = ["food", "meal", "dish", "dessert", "drink", "beverage", "baked_goods", "pizza", "sandwich",
                                    "burger", "salad", "soup", "sushi", "cake", "coffee", "plate", "bowl", "cup", "snack",
                                    "breakfast", "dinner", "lunch", "wine", "beer", "cocktail", "fast_food", "produce"]
    static let selfies: Set<String> = ["selfie", "portrait", "face", "headshot"]
    static let people: Set<String> = ["people", "person", "adult", "child", "baby", "crowd", "teen", "group", "wedding",
                                      "party", "concert"]

    /// Is this photo nature, and where does it go?
    static func evaluate(_ s: NatureSignals, strictness: NatureStrictness = .strict) -> NatureVerdict {
        let t = strictness.cutoffs
        // Vision's calibrated high-precision labels count as at least 0.6.
        func c(_ label: String) -> Float {
            let v = s.labels[label] ?? 0
            return s.precise.contains(label) ? max(v, 0.6) : v
        }
        func e(_ set: Set<String>) -> Float {
            var best: Float = 0
            for (label, _) in s.labels where set.contains(label) { best = max(best, c(label)) }
            return best
        }

        // 1. Things that are never nature.
        if s.isUtility == true && strictness != .everything { return .out("utility") }
        if let tf = s.textFraction, tf > t.maxText { return .out("text") }
        if e(text) >= max(0.5, t.indoor) { return .out("text") }
        if let f = s.faceFraction, f > t.maxFace { return .out("people") }
        // A "portrait"/"face" label only counts when faces weren't measured or one is clearly visible.
        if e(selfies) >= max(0.4, t.pet) && (s.faceFraction ?? 1) > 0.02 { return .out("people") }
        if e(pets) >= t.pet { return .out("pet") }
        if e(food) >= t.food { return .out("food") }
        if e(indoor) >= t.indoor { return .out("indoor") }

        // 2. Scene evidence.
        let sun = e(sunrises)
        let trailStrong = e(trailWords)
        let path = e(pathWords)
        let mtn = e(mountains)
        let forest = e(forests)
        let wildW = e(wildWater)
        let anyW = e(anyWater)
        let poolish = e(manMadeWater)
        let stars = e(starSky)
        let cloud = e(clouds)
        let sky = max(e(plainSky), cloud)
        let open = e(openLand)
        let wild = e(wildlife)
        let flower = e(flowers)
        let house = e(housePlants)
        let yardish = e(yard)
        let city = e(urban)
        let crowd = e(people)

        let landscape = max(sun, trailStrong, mtn, forest, wildW, stars, open)
        let context = max(e(outdoor), sky, landscape)
        let away = (s.kmFromHome ?? 0) > 5

        if house >= t.housePlant && landscape < 0.6 { return .out("houseplant") }
        // A bush, hedge or lawn with no real landscape or open sky around it.
        if yardish >= t.yard && landscape < max(t.primary, 0.5) && !(sky >= 0.6 && open >= t.primary) && !away {
            return .out("yard")
        }
        // Streets, buildings and cars that outweigh the scenery.
        if city >= max(0.5, t.indoor) && city > landscape + 0.1 { return .out("street") }
        // People-dominant (when faces weren't measured, e.g. backs turned in a group shot).
        if crowd >= 0.85 && landscape < t.primary && strictness == .strict { return .out("people") }

        // 3. Categories.
        var cats: [NatureCategory: Float] = [:]
        let golden = s.isGoldenHour
        let midday = (s.sunElevation ?? 0) > 25

        var sunset = sun
        // Golden hour confirms a borderline sunset; midday makes "sunset" mostly orange light, so ask for more.
        if golden == true && sun >= t.primary * 0.6 && sky >= 0.4 { sunset = max(sun, t.primary) }
        if midday && sun < 0.8 { sunset = 0 }
        if sunset >= t.primary { cats[.sunrises] = sunset }

        let wildContext = max(forest, mtn, open)
        if trailStrong >= t.primary { cats[.trails] = trailStrong }
        else if path >= t.primary && wildContext >= t.primary * 0.8 { cats[.trails] = min(path, wildContext) }

        if mtn >= t.primary { cats[.mountains] = mtn }

        if forest >= t.primary { cats[.forests] = forest }
        else if strictness != .strict, c("tree") >= 0.8, sky >= 0.3 || open >= t.primary, yardish < 0.3 {
            cats[.forests] = c("tree") * 0.7
        }

        if poolish < 0.3 {
            if wildW >= t.primary { cats[.water] = wildW }
            else if anyW >= max(0.7, t.primary) && (landscape >= t.primary || sky >= 0.5) { cats[.water] = anyW * 0.8 }
        }

        if stars >= t.primary { cats[.sky] = stars }
        else if cloud >= 0.7 && sky >= 0.85 && city < 0.3 { cats[.sky] = min(cloud, sky) * 0.85 }

        if wild >= t.wildlife && e(pets) < 0.3 { cats[.wildlife] = wild }

        if flower >= t.primary && house < 0.2 {
            let inLandscape = landscape >= t.primary
            let outdoorCloseUp = flower >= t.closeFlower && (context >= t.context || away) && yardish < 0.5
            if inLandscape || outdoorCloseUp { cats[.flowers] = flower }
        }

        guard let top = cats.values.max() else { return .out("no scene") }

        // 4. Score.
        var score = 0.6 * top + 0.2 * min(context, 1)
        if cats.count > 1 { score += 0.05 }
        if away { score += min(Float((s.kmFromHome ?? 0) / 100), 1) * 0.05 + 0.05 }
        if golden == true && cats[.sunrises] != nil { score += 0.1 }
        if s.precise.contains(where: { landscapeLabels.contains($0) }) { score += 0.05 }
        score -= 0.3 * yardish * (landscape < 0.7 ? 1 : 0.3)
        score -= 0.3 * city
        score -= 0.15 * max(crowd - 0.5, 0)
        if let f = s.faceFraction { score -= min(f * 2, 0.2) }
        score = min(max(score, 0), 1)
        if score < t.minScore { return .out("low score") }

        // 5. Aesthetics (iOS 18+): blurry or accidental shots drop; the rest is weighted.
        if let a = s.aesthetic, a < t.minAesthetic { return .out("blurry") }
        let looks = s.aesthetic.map { 0.55 + 0.45 * (min(max($0, -1), 1) + 1) / 2 } ?? 0.8
        return NatureVerdict(score: score, categories: cats, excluded: nil, rank: score * looks)
    }

    static let landscapeLabels: Set<String> = sunrises.union(trailWords).union(mountains).union(forests).union(wildWater)
        .union(starSky).union(openLand)
}

// MARK: - Sun position

enum SunPosition {
    /// Sun elevation above the horizon in degrees (low-precision solar formula, ±1°: plenty for golden hour).
    static func elevation(latitude: Double, longitude: Double, date: Date) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0   // days since J2000
        let meanLong = (280.460 + 0.985_647_4 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.985_600_3 * n).truncatingRemainder(dividingBy: 360) * rad
        let lambda = (meanLong + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.000_000_4 * n) * rad
        let decl = asin(sin(eps) * sin(lambda))
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda))
        let gmstHours = (18.697_374_558 + 24.065_709_824_419_08 * n).truncatingRemainder(dividingBy: 24)
        let hourAngle = (gmstHours * 15 + longitude) * rad - ra
        let lat = latitude * rad
        let s = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        return asin(max(-1, min(1, s))) / rad
    }
}

// MARK: - Frequent places (home cluster)

enum FrequentPlaces {
    struct Cell: Hashable { let lat: Int; let lng: Int }
    /// ~2 km grid cells.
    static let cellsPerDegree = 50.0

    static func cell(_ lat: Double, _ lng: Double) -> Cell {
        Cell(lat: Int((lat * cellsPerDegree).rounded(.down)), lng: Int((lng * cellsPerDegree).rounded(.down)))
    }

    /// The handful of places someone photographs most (home, work…), as cell centres.
    static func find(_ points: [(Double, Double)]) -> [(Double, Double)] {
        guard points.count >= 30 else { return [] }
        var counts: [Cell: Int] = [:]
        for (la, ln) in points { counts[cell(la, ln), default: 0] += 1 }
        let need = max(20, points.count / 25)
        return counts.filter { $0.value >= need }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ((Double($0.key.lat) + 0.5) / cellsPerDegree, (Double($0.key.lng) + 0.5) / cellsPerDegree) }
    }

    /// Great-circle distance in km to the nearest frequent place (nil when there are none).
    static func kmToNearest(_ lat: Double, _ lng: Double, places: [(Double, Double)]) -> Double? {
        places.map { km(lat, lng, $0.0, $0.1) }.min()
    }

    static func km(_ a1: Double, _ o1: Double, _ a2: Double, _ o2: Double) -> Double {
        let r = Double.pi / 180
        let dLat = (a2 - a1) * r, dLng = (o2 - o1) * r
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a1 * r) * cos(a2 * r) * sin(dLng / 2) * sin(dLng / 2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }
}
