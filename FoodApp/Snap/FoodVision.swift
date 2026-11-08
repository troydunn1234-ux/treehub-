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
        "produce", "fruit", "vegetable", "dessert", "baked_goods", "snack", "beverage", "drink", "cookware", "utensil",
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
        "sweet_potato": "Sweet potato", "potato": "Baked potato", "mashed_potatoes": "Mashed potatoes",
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

    /// Runs the classifier and turns its labels into foods, strongest first.
    static func recognizeMeal(_ image: UIImage) async -> (guesses: [FoodGuess], topLabel: String?) {
        let labels = await classify(image)
        let foods = Dictionary(QuickFood.all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [FoodGuess] = []
        var seen = Set<String>()
        var top: String?
        for (label, _) in labels {
            let key = label.lowercased()
            guard !generic.contains(key) else { continue }
            var name = learned(key) ?? synonyms[key]
            if name == nil {
                // Loose match: "fried_chicken" → a food whose name contains "chicken".
                let words = key.split(separator: "_").map(String.init).filter { $0.count > 3 }
                name = QuickFood.all.first { q in words.contains { q.name.lowercased().contains($0) } }?.name
            }
            guard let n = name, let q = foods[n] else { continue }
            if top == nil { top = key }
            if seen.insert(n).inserted { out.append(FoodGuess(q)) }
            if out.count == 6 { break }
        }
        return (out, top)
    }

    private static func classify(_ image: UIImage) async -> [(String, Float)] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do { try handler.perform([req]) } catch { cont.resume(returning: []); return }
                let obs = (req.results ?? [])
                    .filter { $0.confidence > 0.08 }
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
