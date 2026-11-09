import Foundation
import UIKit
import Vision

/// One thing Food Book thinks you're eating, with macros for one serving.
struct FoodGuess: Identifiable, Hashable {
    enum Source: Hashable { case photo, barcode, label, recent }
    var id: String { name + "|" + serving }
    var name: String
    var serving: String
    var cal: Double
    var p: Double
    var c: Double
    var f: Double
    var caf: Double = 0
    var source: Source = .photo
    /// Estimated weight of `serving` in grams (from the photo estimate), with a plausible range.
    var grams: Double? = nil
    var gramsLow: Double? = nil
    var gramsHigh: Double? = nil
    /// Where the numbers came from, e.g. "USDA: Beef, top sirloin, steak, cooked, grilled".
    var sourceNote: String? = nil
    /// What the size was judged against, e.g. "sized from your meal-prep container".
    var sizedFrom: String? = nil
}

extension FoodGuess {
    init(_ q: QuickFood, source: Source = .photo) {
        self.init(name: q.name, serving: q.serving, cal: Double(q.cal), p: q.p, c: q.c, f: q.f, caf: Double(q.caf), source: source)
    }
}

enum SnapMode: String, CaseIterable, Identifiable {
    case meal = "MEAL", barcode = "BARCODE", label = "LABEL"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .meal: return "fork.knife"
        case .barcode: return "barcode.viewfinder"
        case .label: return "doc.text.viewfinder"
        }
    }
}

/// What came back from a snap, ready for the result sheet.
struct SnapResult: Identifiable {
    let id = UUID()
    var image: UIImage?
    var mode: SnapMode
    var guesses: [FoodGuess]
    /// The strongest image label, used to learn when you pick a different food.
    var topLabel: String?
    /// Items already on the plate when the sheet opens (several for a mixed meal).
    var plate: [FoodGuess] = []
    /// True when the Claude photo reader made the plate.
    var ai: Bool = false
    /// Small note under the photo, e.g. "AI unavailable, guessed on your phone".
    var note: String? = nil
}

/// Rough food groups, for the picker tabs and for building a plate (one protein, one side, one veggie).
enum FoodGroup: String, CaseIterable, Identifiable {
    case protein = "Protein", sides = "Carbs & sides", veggies = "Veggies & fruit", drinks = "Drinks", snacks = "Snacks", other = "Meals"
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .protein: return "🥩"
        case .sides: return "🥔"
        case .veggies: return "🥦"
        case .drinks: return "🥤"
        case .snacks: return "🍪"
        case .other: return "🍽️"
        }
    }

    static func of(_ q: QuickFood) -> FoodGroup { of(name: q.name, tags: q.tags) }

    static func of(name: String, tags: [String] = []) -> FoodGroup {
        let t = Set(tags.map { $0.lowercased() })
        let n = name.lowercased()
        // Whole words only ("steak" must not match "tea", "popcorn" must not match "pop").
        let words = Set(n.split { !$0.isLetter }.map { String($0) }.flatMap { [$0, $0.hasSuffix("s") ? String($0.dropLast()) : $0] })
        func has(_ list: [String]) -> Bool {
            list.contains { w in t.contains(w) || (w.contains(" ") ? n.contains(w) : words.contains(w)) }
        }
        // A few names the word rules would misfile.
        if words.contains("patty") { return .protein }
        if n.contains("tortilla chips") || n.contains("chips and salsa") { return .snacks }
        if n == "pasta" || n.hasSuffix("tortilla") { return .sides }
        if n.contains("plate") { return .other }
        if has(["coffee", "tea", "juice", "pop", "soda", "milk", "alcohol", "beer", "wine", "water", "latte", "smoothie", "shake",
                "energy drink", "kombucha", "espresso", "cold brew", "margarita", "liquor"]) && !has(["milk chocolate", "cereal"]) { return .drinks }
        if has(["sandwich", "burrito", "taco", "pizza", "burger", "bowl", "soup", "ramen", "pho", "sushi", "nachos", "quesadilla",
                "chili", "mein", "orange chicken", "ribs", "mac and cheese", "grilled cheese", "wrap", "spaghetti"]) { return .other }
        if has(["veggie", "vegetable", "greens", "salad", "broccoli", "asparagus", "beans", "carrot", "spinach", "zucchini",
                "cauliflower", "sprouts", "corn", "pepper", "cucumber", "tomato", "fruit", "berries"]) && !has(["chips"]) { return .veggies }
        if has(["beef", "steak", "chicken", "pork", "fish", "salmon", "shrimp", "tuna", "turkey", "eggs", "egg", "bacon", "sausage",
                "tofu", "ham", "jerky", "tilapia"]) { return .protein }
        if has(["potato", "rice", "pasta", "noodles", "bread", "tortilla", "toast", "bagel", "quinoa", "oatmeal", "fries", "tots",
                "muffin", "cereal", "pancake", "waffle"]) { return .sides }
        if has(["snack", "chips", "candy", "cookie", "dessert", "nuts", "bar", "chocolate", "popcorn", "pretzel", "cracker",
                "ice cream", "donut", "cake", "brownie", "trail mix"]) { return .snacks }
        return .other
    }
}

/// On-device food recognition (Vision), nutrition-label reading, and barcode lookups.
enum FoodVision {

    // MARK: Image prep

    /// Upright, max 1024 px, so Vision and thumbnails are fast.
    static func prepared(_ image: UIImage, maxSide: CGFloat = 1024) -> UIImage {
        let s = image.size
        let scale = min(1, maxSide / max(s.width, s.height, 1))
        let size = CGSize(width: max(1, s.width * scale), height: max(1, s.height * scale))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Square-cropped JPEG thumbnail for saving with an entry / sending to the watch.
    static func thumbnail(_ image: UIImage, side: CGFloat = 240, quality: CGFloat = 0.6) -> Data? {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return nil }
        let crop = min(s.width, s.height)
        let scale = side / crop
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            image.draw(in: CGRect(x: -(s.width - crop) / 2 * scale, y: -(s.height - crop) / 2 * scale,
                                  width: s.width * scale, height: s.height * scale))
        }
        return img.jpegData(compressionQuality: quality)
    }

    // MARK: Meal photos

    /// Vision labels that only say "there's food" and should never pick a food.
    private static let generic: Set<String> = ["food", "dish", "meal", "plate", "tableware", "bowl", "cup", "dining", "table",
        "produce", "fruit", "dessert", "baked_goods", "snack", "beverage", "drink", "cookware", "utensil",
        "fork", "spoon", "knife", "people", "adult", "container", "jar", "bottle", "glass", "drinking_glass", "mug"]

    /// Vision label → Food Book food name (exact names from foods.json).
    static let synonyms: [String: String] = [
        "banana": "Banana", "apple": "Apple", "orange": "Orange", "citrus_fruit": "Orange", "strawberry": "Strawberries",
        "blueberry": "Blueberries", "berry": "Strawberries", "grape": "Grapes", "watermelon": "Watermelon", "melon": "Watermelon",
        "pineapple": "Pineapple", "mango": "Mango", "avocado": "Avocado", "peach": "Peach", "pear": "Pear",
        "raspberry": "Raspberries", "cherry": "Cherries", "raisin": "Raisins",
        "broccoli": "Broccoli", "carrot": "Carrots", "spinach": "Spinach", "salad": "Side salad", "leafy_green": "Side salad",
        "lettuce": "Side salad", "caesar_salad": "Caesar salad", "cucumber": "Cucumber", "tomato": "Tomato",
        "bell_pepper": "Bell pepper", "pepper_veggie": "Bell pepper", "corn": "Corn", "green_beans": "Green beans",
        "sweet_potato": "Sweet potato", "potato": "Roasted potatoes", "roasted_potato": "Roasted potatoes", "baked_potato": "Baked potato",
        "asparagus": "Roasted asparagus", "brussels_sprouts": "Brussels sprouts", "zucchini": "Zucchini", "cauliflower": "Cauliflower",
        "vegetable": "Mixed veggies", "beans": "Black beans", "legume": "Black beans", "sirloin": "Sirloin steak", "ribeye": "Ribeye steak", "filet": "Steak", "mashed_potatoes": "Mashed potatoes",
        "egg": "Egg", "boiled_egg": "Egg", "fried_egg": "Fried egg", "scrambled_eggs": "Scrambled eggs", "omelet": "Scrambled eggs",
        "chicken": "Chicken breast", "poultry": "Chicken breast", "grilled_chicken": "Chicken breast", "fried_chicken": "Chicken tenders",
        "chicken_wings": "Chicken wings", "wings": "Chicken wings", "rotisserie": "Rotisserie chicken", "nugget": "Chicken tenders",
        "steak": "Steak", "beef": "Steak", "meat": "Steak", "red_meat": "Steak", "ground_beef": "Ground beef 80/20",
        "salmon": "Salmon", "fish": "Tilapia", "seafood": "Shrimp", "tuna": "Tuna", "shrimp": "Shrimp", "prawn": "Shrimp",
        "bacon": "Bacon", "sausage": "Sausage link", "ham": "Deli ham", "turkey_meat": "Turkey breast", "pork": "Pork chop",
        "hotdog": "Hot dog", "hot_dog": "Hot dog", "tofu": "Tofu",
        "rice": "White rice", "fried_rice": "Fried rice", "risotto": "White rice", "pasta": "Pasta", "spaghetti": "Spaghetti with meat sauce",
        "noodle": "Chow mein", "noodles": "Chow mein", "macaroni": "Mac and cheese", "mac_and_cheese": "Mac and cheese",
        "bread": "Bread", "toast": "Toast with butter", "tortilla": "Flour tortilla", "bagel": "Bagel", "english_muffin": "English muffin",
        "oatmeal": "Oatmeal", "porridge": "Oatmeal", "french_fries": "French fries", "fries": "French fries", "tater_tots": "Tater tots",
        "granola": "Granola", "quinoa": "Quinoa", "milk": "2% milk", "cheese": "Cheese slice", "yogurt": "Greek yogurt",
        "butter": "Butter", "cream_cheese": "Cream cheese", "peanut_butter": "Peanut butter",
        "chips": "Potato chips", "potato_chips": "Potato chips", "tortilla_chips": "Tortilla chips", "salsa": "Chips and salsa",
        "guacamole": "Guacamole", "almond": "Almonds", "nut": "Almonds", "peanut": "Peanuts", "cashew": "Cashews",
        "trail_mix": "Trail mix", "popcorn": "Popcorn", "cookie": "Chocolate chip cookie", "biscuit": "Chocolate chip cookie",
        "candy": "Candy bar", "chocolate": "Candy bar", "gummy": "Gummy candy", "cracker": "Crackers", "pretzel": "Pretzels",
        "jerky": "Beef jerky", "hummus": "Hummus",
        "burrito": "Burrito", "taco": "Tacos", "quesadilla": "Quesadilla", "nachos": "Nachos", "mexican_food": "Burrito bowl",
        "pizza": "Pizza", "pepperoni": "Pepperoni pizza", "hamburger": "Cheeseburger", "burger": "Cheeseburger",
        "cheeseburger": "Cheeseburger", "sandwich": "Sub sandwich", "sub_sandwich": "Sub sandwich", "wrap": "Burrito",
        "chicken_sandwich": "Chicken sandwich", "sushi": "Sushi roll", "sashimi": "Poke bowl", "poke": "Poke bowl",
        "ramen": "Ramen", "pho": "Pho", "dumpling": "Orange chicken", "chinese_food": "Orange chicken", "stir_fry": "Chow mein",
        "ribs": "BBQ ribs", "barbecue": "BBQ ribs", "pulled_pork": "Pulled pork sandwich", "chili": "Chili", "stew": "Chili",
        "soup": "Chicken noodle soup", "grilled_cheese": "Grilled cheese",
        "pancake": "Pancakes", "pancakes": "Pancakes", "waffle": "Waffle", "french_toast": "French toast", "crepe": "Pancakes",
        "breakfast_burrito": "Breakfast burrito", "cereal": "Cereal with milk", "avocado_toast": "Avocado toast", "hash_browns": "Hash browns",
        "ice_cream": "Ice cream", "frozen_dessert": "Ice cream", "gelato": "Ice cream", "donut": "Donut", "doughnut": "Donut",
        "brownie": "Brownie", "muffin": "Muffin", "cupcake": "Muffin", "cheesecake": "Cheesecake", "cake": "Cake", "pie": "Cake",
        "pastry": "Muffin", "croissant": "Muffin", "milkshake": "Milkshake",
        "water": "Water", "coffee": "Coffee", "latte": "Latte", "cappuccino": "Latte", "espresso": "Espresso", "iced_coffee": "Cold brew",
        "soda": "Soda", "cola": "Soda", "soft_drink": "Soda", "juice": "Orange juice", "orange_juice": "Orange juice",
        "apple_juice": "Apple juice", "smoothie": "Smoothie", "tea": "Green tea", "iced_tea": "Sweet tea", "kombucha": "Kombucha",
        "beer": "Beer", "wine": "Wine", "red_wine": "Wine", "white_wine": "Wine", "cocktail": "Margarita", "margarita": "Margarita",
        "liquor": "Shot of liquor", "energy_drink": "Energy drink",
    ]

    private static let learnKey = "snapLearned"

    /// Remember that this image label meant this food (you corrected a guess).
    static func learn(label: String, food: String) {
        var d = UserDefaults.standard.dictionary(forKey: learnKey) as? [String: String] ?? [:]
        d[label] = food
        UserDefaults.standard.set(d, forKey: learnKey)
    }

    private static func learned(_ label: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: learnKey) as? [String: String])?[label]
    }

    /// Labels that would turn a plate into a sandwich/burger. Only trusted when Vision is quite sure.
    private static let handheld = ["sandwich", "burger", "hamburger", "cheeseburger", "bread", "bun", "hotdog", "hot_dog", "wrap",
                                   "sub_sandwich", "chicken_sandwich", "pizza", "taco", "burrito"]

    /// Runs the classifier and builds a plate: up to one protein, one side and one veggie the photo most looks like,
    /// plus alternatives for the "Not it?" row. Never guesses a sandwich unless Vision is fairly sure.
    static func recognizeMeal(_ image: UIImage) async -> (plate: [FoodGuess], alternatives: [FoodGuess], topLabel: String?) {
        let labels = Array(await classify(image).prefix(12))
        let foods = Dictionary(QuickFood.all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var ranked: [(QuickFood, Float)] = []
        var seen = Set<String>()
        var top: String?
        for (label, conf) in labels {
            let key = label.lowercased()
            guard !generic.contains(key) else { continue }
            if handheld.contains(where: { key.contains($0) }) && conf < 0.3 { continue }
            guard let n = learned(key) ?? synonyms[key], let q = foods[n] else { continue }
            if top == nil { top = key }
            if seen.insert(n).inserted { ranked.append((q, conf)) }
        }
        // Plate: best item per group (protein, side, veggie); a full meal (e.g. burrito) stands alone.
        var plate: [FoodGuess] = []
        if let meal = ranked.first(where: { FoodGroup.of($0.0) == .other && $0.1 >= 0.3 }) {
            plate = [FoodGuess(meal.0)]
        } else {
            for g in [FoodGroup.protein, .sides, .veggies, .drinks, .snacks] {
                if let hit = ranked.first(where: { FoodGroup.of($0.0) == g }) { plate.append(FoodGuess(hit.0)) }
                if plate.count == 3 { break }
            }
        }
        // Alternatives: other matches, then close relatives of what's on the plate (same group).
        let onPlate = Set(plate.map(\.name))
        var alts = ranked.map { FoodGuess($0.0) }.filter { !onPlate.contains($0.name) }
        for item in plate {
            let g = FoodGroup.of(name: item.name, tags: foods[item.name]?.tags ?? [])
            let relatives = QuickFood.all.filter { FoodGroup.of($0) == g && !onPlate.contains($0.name) }
                .sorted { relatedScore($0.name, to: item.name) > relatedScore($1.name, to: item.name) }
                .prefix(3)
            for r in relatives where !alts.contains(where: { $0.name == r.name }) { alts.append(FoodGuess(r)) }
        }
        return (plate, Array(alts.prefix(8)), top)
    }

    /// Shares a word with the plate item (Steak → Ribeye steak, Sirloin steak) ranks first.
    private static func relatedScore(_ a: String, to b: String) -> Int {
        let wa = Set(a.lowercased().split(separator: " ")), wb = Set(b.lowercased().split(separator: " "))
        return wa.intersection(wb).count
    }

    private static func classify(_ image: UIImage) async -> [(String, Float)] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do { try handler.perform([req]) } catch { cont.resume(returning: []); return }
                let obs = (req.results ?? [])
                    .filter { $0.confidence > 0.05 }
                    .sorted { $0.confidence > $1.confidence }
                    .map { ($0.identifier, $0.confidence) }
                cont.resume(returning: obs)
            }
        }
    }

    // MARK: Nutrition labels

    struct LabelFacts {
        var name: String?
        var serving: String?
        var cal: Double
        var fat: Double
        var carbs: Double
        var protein: Double
    }

    /// Reads a Nutrition Facts panel. Needs at least the calories.
    static func readLabel(_ image: UIImage) async -> LabelFacts? {
        guard let cg = image.cgImage else { return nil }
        let lines: [String] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do { try handler.perform([req]) } catch { cont.resume(returning: []); return }
                let obs = (req.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }   // top to bottom
                cont.resume(returning: obs.compactMap { $0.topCandidates(1).first?.string })
            }
        }
        return parseLabel(lines)
    }

    static func parseLabel(_ raw: [String]) -> LabelFacts? {
        // OCR often reads 0 as O ("1Og"); fix letters O/o that follow a digit.
        let lines = raw.map { $0.replacingOccurrences(of: "(?<=\\d)[oO]", with: "0", options: .regularExpression) }
        let text = lines.joined(separator: "\n").lowercased()

        func number(_ pattern: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return Double(text[r].replacingOccurrences(of: ",", with: "."))
        }

        // Calories: "Calories 230", or the number on the next line. Skip "calories from fat".
        var cal = number("calories(?!\\s*from)[^0-9\\n]{0,6}(\\d{1,4})")
        if cal == nil, let i = lines.firstIndex(where: { $0.lowercased().contains("calories") }), i + 1 < lines.count {
            let next = lines[i + 1]
            if let r = next.range(of: "\\d{1,4}", options: .regularExpression) { cal = Double(next[r]) }
        }
        guard let calories = cal, calories > 0, calories < 3000 else { return nil }

        let fat = number("total\\s*fat[^0-9\\n]{0,4}(\\d+(?:[.,]\\d+)?)") ?? number("\\bfat[^0-9\\n]{0,4}(\\d+(?:[.,]\\d+)?)") ?? 0
        let carbs = number("carb[a-z.]*[^0-9\\n]{0,6}(\\d+(?:[.,]\\d+)?)") ?? 0
        let protein = number("prot[a-z]*[^0-9\\n]{0,4}(\\d+(?:[.,]\\d+)?)") ?? 0

        var serving: String?
        if let line = lines.first(where: { $0.lowercased().contains("serving size") }) {
            serving = line.replacingOccurrences(of: "(?i)serving size", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if serving?.isEmpty == true { serving = nil }
        }

        // Product name: first line that isn't panel text.
        let panelWords = ["nutrition", "facts", "serving", "calorie", "amount", "daily", "value", "fat", "%", "per container"]
        let name = lines.prefix(4).first { l in
            let low = l.lowercased()
            return l.count >= 3 && l.rangeOfCharacter(from: .letters) != nil && !panelWords.contains { low.contains($0) }
        }
        return LabelFacts(name: name, serving: serving, cal: calories, fat: fat, carbs: carbs, protein: protein)
    }

    // MARK: Barcodes (Open Food Facts)

    /// Finds a product barcode in a still photo (e.g. one picked from the library).
    static func barcode(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do { try handler.perform([req]) } catch { cont.resume(returning: nil); return }
                cont.resume(returning: (req.results ?? []).compactMap(\.payloadStringValue).first)
            }
        }
    }

    struct Product: Codable {
        let code: String
        let name: String
        let serving: String
        let cal: Double
        let p: Double
        let c: Double
        let f: Double
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scanned-products.json")
    }

    private static func loadCache() -> [String: Product] {
        guard let d = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Product].self, from: d)) ?? [:]
    }

    private static func save(_ p: Product) {
        var c = loadCache()
        c[p.code] = p
        if let d = try? JSONEncoder().encode(c) { try? d.write(to: cacheURL, options: .atomic) }
    }

    /// Looks a barcode up (cached forever once found). nil = not in the database or offline.
    static func product(barcode code: String) async -> Product? {
        if let hit = loadCache()[code] { return hit }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,serving_size,serving_quantity") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("FoodBook/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let response = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
              let prod = json["product"] as? [String: Any] else { return nil }

        func num(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        let n = prod["nutriments"] as? [String: Any] ?? [:]
        let servingText = (prod["serving_size"] as? String)?.trimmingCharacters(in: .whitespaces)
        var cal, p, c, f: Double?
        var serving: String
        if let k = num(n["energy-kcal_serving"]) {
            cal = k; p = num(n["proteins_serving"]); c = num(n["carbohydrates_serving"]); f = num(n["fat_serving"])
            serving = servingText ?? "1 serving"
        } else {
            let qty = num(prod["serving_quantity"]) ?? 100
            let scale = qty / 100
            cal = (num(n["energy-kcal_100g"]) ?? num(n["energy-kcal"])).map { $0 * scale }
            p = num(n["proteins_100g"]).map { $0 * scale }
            c = num(n["carbohydrates_100g"]).map { $0 * scale }
            f = num(n["fat_100g"]).map { $0 * scale }
            serving = servingText ?? "\(Int(qty)) g"
        }
        guard let kcal = cal else { return nil }
        let brand = (prod["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let pname = (prod["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        var title = [brand, pname].filter { !$0.isEmpty }.joined(separator: " ")
        if !brand.isEmpty, pname.lowercased().hasPrefix(brand.lowercased()) { title = pname }
        if title.isEmpty { title = "Scanned item" }
        let result = Product(code: code, name: title, serving: serving, cal: kcal.rounded(), p: p ?? 0, c: c ?? 0, f: f ?? 0)
        save(result)
        return result
    }
}
