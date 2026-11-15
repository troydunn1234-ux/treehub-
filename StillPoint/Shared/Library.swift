import Foundation

// MARK: - Data model (tolerant: only `id` and `title` are required; everything else has a default)

struct Tradition: Decodable, Hashable, Identifiable {
    let id: String
    var name: String
    var region: String = ""
    var origin: String = ""
    var summary: String = ""
    var color: String = "#7C6CF0"
    /// One plain line for the library list ("Upright sitting, breath counting…").
    var short: String = ""

    init(id: String, name: String, region: String = "", origin: String = "", summary: String = "", color: String = "#7C6CF0", short: String = "") {
        self.id = id; self.name = name; self.region = region; self.origin = origin; self.summary = summary; self.color = color
        self.short = short
    }

    enum CodingKeys: String, CodingKey { case id, name, title, region, origin, summary, color, short }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? (try? c.decodeIfPresent(String.self, forKey: .title)) ?? id
        region = ((try? c.decodeIfPresent(String.self, forKey: .region)) ?? nil) ?? ""
        origin = ((try? c.decodeIfPresent(String.self, forKey: .origin)) ?? nil) ?? ""
        summary = ((try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil) ?? ""
        color = ((try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil) ?? "#7C6CF0"
        short = ((try? c.decodeIfPresent(String.self, forKey: .short)) ?? nil) ?? ""
    }

    /// The short line, or the first sentence of the summary.
    var blurb: String {
        if !short.isEmpty { return short }
        if let r = summary.range(of: ". ") { return String(summary[..<r.lowerBound]) + "." }
        return summary
    }
}

/// A goal tab in the library: Healing, Calm & Anxiety, Sleep… A practice can sit in several.
struct PracticeCategory: Decodable, Hashable, Identifiable {
    let id: String
    var name: String
    var summary: String = ""
    var symbol: String = "circle.hexagongrid.fill"
    var color: String = "#8FD3CC"
    /// Extra line under the header (e.g. "not medical advice" on Healing).
    var note: String? = nil

    init(id: String, name: String, summary: String, symbol: String, color: String, note: String? = nil) {
        self.id = id; self.name = name; self.summary = summary; self.symbol = symbol; self.color = color; self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, name, summary, symbol, color, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? id.capitalized
        summary = ((try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil) ?? ""
        symbol = ((try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? nil) ?? "circle.hexagongrid.fill"
        color = ((try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil) ?? "#8FD3CC"
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil
    }

    /// Name / summary / note in the person's language when the string catalog has them.
    var localizedName: String { NSLocalizedString(name, comment: "Library category") }
    var localizedSummary: String { NSLocalizedString(summary, comment: "Library category summary") }
    var localizedNote: String? { note.map { NSLocalizedString($0, comment: "Library category note") } }

    static let quickID = "quick"
    static let beginnerID = "beginner"

    static let fallback: [PracticeCategory] = [
        PracticeCategory(id: "healing", name: "Healing", summary: "Gentle practices for recovery, easing discomfort, grief and deep rest.", symbol: "cross.case.fill", color: "#E8A6A6",
                         note: "Supportive practices, not medical advice. Keep following your care team."),
        PracticeCategory(id: "calm", name: "Calm & Anxiety", summary: "Slow the heart and quiet worry, from a 1-minute SOS to longer sits.", symbol: "leaf.fill", color: "#8FD3CC"),
        PracticeCategory(id: "sleep", name: "Sleep", summary: "Unwind the body and mind at night so sleep comes more easily.", symbol: "moon.stars.fill", color: "#A99BE8"),
        PracticeCategory(id: "energy", name: "Energy", summary: "Wake up, warm up and lift a flat mood without caffeine.", symbol: "sun.max.fill", color: "#EBC88E"),
        PracticeCategory(id: "focus", name: "Focus", summary: "Steady, clear attention for work, study or a big moment.", symbol: "scope", color: "#7FB3D5"),
        PracticeCategory(id: "recovery", name: "Recovery", summary: "Before and after training, the cold plunge and the sauna.", symbol: "figure.cooldown", color: "#E07A5F"),
        PracticeCategory(id: "nature", name: "Nature & Grounding", summary: "Get out of your head and back into your body and the world around you.", symbol: "tree.fill", color: "#4F9D69"),
        PracticeCategory(id: "quick", name: "Quick", summary: "Three minutes or less. Good for a busy day.", symbol: "timer", color: "#F6DDA8"),
        PracticeCategory(id: "beginner", name: "Beginner", summary: "Simple to learn and easy to enjoy. Start here.", symbol: "sparkle", color: "#F4EFE6"),
    ]
}

struct BreathPattern: Codable, Hashable {
    var inhale: Double = 4
    var holdIn: Double = 0
    var exhale: Double = 4
    var holdOut: Double = 0
    var cycles: Int? = nil
    /// Alternate-nostril breathing (Nadi Shodhana): switch sides each breath.
    var nostril: Bool = false
    /// Hum on the exhale (Bhramari).
    var hum: Bool = false
    /// Physiological sigh: a second short "top-up" inhale.
    var sigh: Bool = false

    init(inhale: Double, holdIn: Double = 0, exhale: Double, holdOut: Double = 0, cycles: Int? = nil,
         nostril: Bool = false, hum: Bool = false, sigh: Bool = false) {
        self.inhale = inhale; self.holdIn = holdIn; self.exhale = exhale; self.holdOut = holdOut
        self.cycles = cycles; self.nostril = nostril; self.hum = hum; self.sigh = sigh
    }

    enum CodingKeys: String, CodingKey { case inhale, holdIn, exhale, holdOut, cycles, nostril, hum, sigh }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inhale = max(0.5, Self.num(c, .inhale) ?? 4)
        holdIn = max(0, Self.num(c, .holdIn) ?? 0)
        exhale = max(0.5, Self.num(c, .exhale) ?? 4)
        holdOut = max(0, Self.num(c, .holdOut) ?? 0)
        if let n = Self.num(c, .cycles), n > 0 { cycles = Int(n) }
        nostril = Self.flag(c, .nostril)
        hum = Self.flag(c, .hum)
        sigh = Self.flag(c, .sigh)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inhale, forKey: .inhale); try c.encode(holdIn, forKey: .holdIn)
        try c.encode(exhale, forKey: .exhale); try c.encode(holdOut, forKey: .holdOut)
        try c.encodeIfPresent(cycles, forKey: .cycles)
        try c.encode(nostril, forKey: .nostril); try c.encode(hum, forKey: .hum); try c.encode(sigh, forKey: .sigh)
    }

    private static func num(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }

    /// Accepts true/false, 1/0, or any non-empty string ("alternate", "left-right", ...) as on.
    private static func flag(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Bool {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: k) { return b }
        if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return d != 0 }
        if let s = try? c.decodeIfPresent(String.self, forKey: k) {
            let v = s.lowercased().trimmingCharacters(in: .whitespaces)
            return !(v.isEmpty || v == "false" || v == "no" || v == "none" || v == "off" || v == "0")
        }
        return false
    }

    var cycleLength: Double { inhale + holdIn + exhale + holdOut }
    var breathsPerMinute: Double { cycleLength > 0 ? 60 / cycleLength : 0 }

    /// "4 · 7 · 8" style summary.
       var shortLabel: String {
        var parts = [Self.fmt(inhale)]
        if holdIn > 0 { parts.append(Self.fmt(holdIn)) }
        parts.append(Self.fmt(exhale))
        if holdOut > 0 { parts.append(Self.fmt(holdOut)) }
        return parts.joined(separator: " · ")
    }

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct Cue: Decodable, Hashable {
    /// Seconds from the start of the session.
    var at: Double
    var text: String

    enum CodingKeys: String, CodingKey { case at, text }
    init(at: Double, text: String) { self.at = at; self.text = text }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let d = try? c.decode(Double.self, forKey: .at) { at = d }
        else if let s = try? c.decode(String.self, forKey: .at) { at = Cue.parseTime(s) }
        else { at = 0 }
        text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
    }

    /// "1:30" → 90, "90" → 90, "start" → 0, "minute:5" → 300. "end" / "everyCycle" have no fixed time: -1 (dropped).
    static func parseTime(_ s: String) -> Double {
        let low = s.lowercased().trimmingCharacters(in: .whitespaces)
        if low == "start" { return 0 }
        if low.hasPrefix("minute:"), let m = Double(low.dropFirst(7)) { return m * 60 }
        if low.first.map({ !$0.isNumber }) ?? true { return -1 }
        let parts = s.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts.first ?? 0
    }
}

/// One step of a movement / warm-up routine.
struct MoveStep: Decodable, Hashable {
    var name: String
    var seconds: Double = 30
    var how: String = ""
    /// "in", "out" or "natural"
    var breath: String = "natural"
    /// "left", "right", "both" or nil
    var side: String? = nil

    init(name: String, seconds: Double, how: String = "", breath: String = "natural", side: String? = nil) {
        self.name = name; self.seconds = seconds; self.how = how; self.breath = breath; self.side = side
    }

    enum CodingKeys: String, CodingKey { case name, title, seconds, how, breath, side }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Move"
        if let d = try? c.decode(Double.self, forKey: .seconds) { seconds = max(3, d) }
        else if let s = try? c.decode(String.self, forKey: .seconds), let d = Double(s) { seconds = max(3, d) }
        how = ((try? c.decodeIfPresent(String.self, forKey: .how)) ?? nil) ?? ""
        breath = (((try? c.decodeIfPresent(String.self, forKey: .breath)) ?? nil) ?? "natural").lowercased()
        let sd = ((try? c.decodeIfPresent(String.self, forKey: .side)) ?? nil)?.lowercased()
        side = (sd == nil || sd == "" || sd == "null" || sd == "none") ? nil : sd
    }

    var sideLetter: String? {
        switch side {
        case "left": return "L"
        case "right": return "R"
        case "both": return "L+R"
        default: return nil
        }
    }

    var breathCue: String {
        switch breath {
        case "in": return "Breathe in"
        case "out": return "Breathe out"
        default: return "Breathe naturally"
        }
    }
}

struct Practice: Decodable, Hashable, Identifiable {
    let id: String
    var title: String
    var traditionId: String = ""
    var kind: String = "breath"
    var minutes: [Int] = [5, 10]
    var level: String = "Beginner"
    var about: String = ""
    var why: String = ""
    var pattern: BreathPattern? = nil
    var cues: [Cue] = []
    var safety: String? = nil
    var sources: [String] = []
    var steps: [MoveStep] = []
    /// Optional "focus" tag from the library file: joint, lymph, stretch or breathe.
    var focusTag: String? = nil
    /// Plain-English labels: one line on what it does, who it's for, and 2–3 sentences on how it works.
    var whatItDoes: String = ""
    var goodFor: [String] = []
    var howItWorks: String = ""
    /// Goal tabs (healing, calm, sleep, energy, focus, recovery, nature, quick, beginner).
    var categoryIds: [String] = []
    /// Numbered steps for the detail page.
    var howTo: [String] = []
    /// Part of the free starter set (from the library file).
    var freeFlag: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, traditionId, kind, minutes, level, about, why, pattern, cues, safety, sources, steps
        case focusTag = "focus"
        case whatItDoes, goodFor, howItWorks, howTo
        case categoryIds = "categories"
        case freeFlag = "free"
    }

    init(id: String, title: String, traditionId: String, kind: String = "breath", minutes: [Int], level: String = "Beginner",
         about: String, why: String, pattern: BreathPattern?, cues: [Cue] = [], safety: String? = nil, sources: [String] = [],
         steps: [MoveStep] = [], focusTag: String? = nil) {
        self.id = id; self.title = title; self.traditionId = traditionId; self.kind = kind; self.minutes = minutes
        self.level = level; self.about = about; self.why = why; self.pattern = pattern; self.cues = cues
        self.safety = safety; self.sources = sources; self.steps = steps; self.focusTag = focusTag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        traditionId = ((try? c.decodeIfPresent(String.self, forKey: .traditionId)) ?? nil) ?? ""
        kind = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil) ?? "breath"
        if let m = try? c.decodeIfPresent([Int].self, forKey: .minutes), !m.isEmpty { minutes = m }
        else if let m = try? c.decodeIfPresent([Double].self, forKey: .minutes), !m.isEmpty { minutes = m.map { Int($0) } }
        else if let m = try? c.decodeIfPresent(Int.self, forKey: .minutes) { minutes = [m] }
        minutes = minutes.filter { $0 > 0 }
        if minutes.isEmpty { minutes = [5, 10] }
        level = ((try? c.decodeIfPresent(String.self, forKey: .level)) ?? nil) ?? "Beginner"
        about = ((try? c.decodeIfPresent(String.self, forKey: .about)) ?? nil) ?? ""
        why = ((try? c.decodeIfPresent(String.self, forKey: .why)) ?? nil) ?? ""
        pattern = (try? c.decodeIfPresent(BreathPattern.self, forKey: .pattern)) ?? nil
        cues = ((try? c.decodeIfPresent([Cue].self, forKey: .cues)) ?? nil)?.sorted { $0.at < $1.at } ?? []
        safety = (try? c.decodeIfPresent(String.self, forKey: .safety)) ?? nil
        if let s = try? c.decodeIfPresent([String].self, forKey: .sources) { sources = s }
        else if let s = try? c.decodeIfPresent(String.self, forKey: .sources) { sources = [s] }
        steps = ((try? c.decodeIfPresent([MoveStep].self, forKey: .steps)) ?? nil) ?? []
        focusTag = ((try? c.decodeIfPresent(String.self, forKey: .focusTag)) ?? nil)?.lowercased()
        whatItDoes = ((try? c.decodeIfPresent(String.self, forKey: .whatItDoes)) ?? nil) ?? ""
        goodFor = ((try? c.decodeIfPresent([String].self, forKey: .goodFor)) ?? nil) ?? []
        howItWorks = ((try? c.decodeIfPresent(String.self, forKey: .howItWorks)) ?? nil) ?? ""
        howTo = ((try? c.decodeIfPresent([String].self, forKey: .howTo)) ?? nil) ?? []
        categoryIds = (((try? c.decodeIfPresent([String].self, forKey: .categoryIds)) ?? nil) ?? []).map { $0.lowercased() }
        freeFlag = (try? c.decodeIfPresent(Bool.self, forKey: .freeFlag)) ?? nil
        cues = cues.filter { $0.at >= 0 }
        if isMovement { pattern = nil }
    }

    /// "Beginner", "Intermediate", "Advanced" (the file says easy / medium / deep).
    var levelLabel: String {
        switch level.lowercased() {
        case "easy", "beginner": return String(localized: "Beginner")
        case "medium", "intermediate": return String(localized: "Intermediate")
        case "deep", "advanced": return String(localized: "Advanced")
        default: return level.capitalized
        }
    }

    /// "1–3 min" or "5 min".
    var minutesLabel: String {
        let lo = minutes.min() ?? 5, hi = minutes.max() ?? lo
        return lo == hi ? "\(lo) min" : "\(lo)–\(hi) min"
    }

    /// The one-liner, falling back to the first sentence of the about text.
    var tagline: String {
        if !whatItDoes.isEmpty { return whatItDoes }
        if let r = about.range(of: ". ") { return String(about[..<r.lowerBound]) + "." }
        return about
    }

    /// In a goal tab: listed there, or (Quick) has a 3-minute-or-shorter option, or (Beginner) easy and tagged.
    func isIn(_ category: String) -> Bool {
        if categoryIds.contains(category) { return true }
        if category == PracticeCategory.quickID { return (minutes.min() ?? 99) <= 3 }
        return false
    }

    /// Does this practice match a search? Title, tradition, labels, goals and "good for" lines.
    func matches(_ query: String, tradition: Tradition?, categories: [PracticeCategory]) -> Bool {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return true }
        let cats = categories.filter { isIn($0.id) }.map { $0.name + " " + $0.localizedName }
        let hay = ([title, whatItDoes, howItWorks, kind, tradition?.name ?? "", levelLabel] + goodFor + cats)
            .joined(separator: " ").lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return words.allSatisfy { hay.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)) }
    }

    var isMovement: Bool { kind.lowercased() == "movement" || !steps.isEmpty }

    /// Which body section this belongs to. Untagged movement counts as stretch; paced breathing as breathe.
    var focus: BodyFocus? {
        if let t = focusTag, let f = BodyFocus(rawValue: t) { return f }
        if isMovement { return .stretch }
        if kind.lowercased() == "breath" || isBreathwork { return .breathe }
        return nil
    }

    /// Steps scaled so the routine fills `minutes`.
    func scaledSteps(minutes: Int) -> [MoveStep] {
        let base = steps.reduce(0) { $0 + $1.seconds }
        guard base > 0 else { return steps }
        let f = Double(max(1, minutes)) * 60 / base
        return steps.map { (old: MoveStep) -> MoveStep in
            var s = old
            s.seconds = max(3, (old.seconds * f).rounded())
            return s
        }
    }

    var defaultMinutes: Int { minutes.contains(5) ? 5 : (minutes.first ?? 5) }
    var isBreathwork: Bool { pattern != nil && !isMovement }

    /// Cue text to show at `elapsed` seconds (the latest cue that has started, shown for up to 20 s).
    func cue(at elapsed: Double) -> String? {
        guard let c = cues.last(where: { $0.at <= elapsed }), elapsed - c.at < 20, !c.text.isEmpty else { return nil }
        return c.text
    }
}

struct Intention: Decodable, Hashable, Identifiable {
    let id: String
    var name: String
    var practiceIds: [String] = []

    init(id: String, name: String, practiceIds: [String]) { self.id = id; self.name = name; self.practiceIds = practiceIds }

    enum CodingKeys: String, CodingKey { case id, name, title, practiceIds }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? (try? c.decodeIfPresent(String.self, forKey: .title)) ?? id
        practiceIds = ((try? c.decodeIfPresent([String].self, forKey: .practiceIds)) ?? nil) ?? []
    }

    /// SF Symbol for common intention names.
    var symbol: String {
        let n = (id + " " + name).lowercased()
        if n.contains("sleep") { return "moon.stars.fill" }
        if n.contains("calm") || n.contains("anx") || n.contains("stress") { return "leaf.fill" }
        if n.contains("focus") || n.contains("clar") { return "scope" }
        if n.contains("energy") || n.contains("wake") || n.contains("morning") { return "sun.max.fill" }
        if n.contains("heart") || n.contains("love") || n.contains("compassion") || n.contains("kind") { return "heart.fill" }
        if n.contains("grief") || n.contains("heal") { return "drop.fill" }
        if n.contains("pray") || n.contains("devot") || n.contains("spirit") || n.contains("sacred") { return "sparkles" }
        if n.contains("body") || n.contains("ground") { return "figure.mind.and.body" }
        return "circle.hexagongrid.fill"
    }
}

private struct LibraryFile: Decodable {
    var traditions: [Tradition]?
    var practices: [Practice]?
    var intentions: [Intention]?
    var categories: [PracticeCategory]?

    enum CodingKeys: String, CodingKey { case traditions, practices, intentions, categories }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        traditions = Self.lossy(c, .traditions)
        practices = Self.lossy(c, .practices)
        intentions = Self.lossy(c, .intentions)
        categories = Self.lossy(c, .categories)
    }

    /// Decode an array but skip any element that fails, instead of failing the whole file.
    private static func lossy<T: Decodable>(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> [T]? {
        guard var arr = try? c.nestedUnkeyedContainer(forKey: k) else { return nil }
        var out: [T] = []
        while !arr.isAtEnd {
            if let v = try? arr.decode(T.self) { out.append(v) }
            else { _ = try? arr.decode(Skip.self) }
        }
        return out
    }
    /// Accepts any JSON value so a bad element can be stepped over.
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
}

// MARK: - Library

final class PracticeLibrary {
    static let shared = PracticeLibrary()

    let traditions: [Tradition]
    let practices: [Practice]
    let intentions: [Intention]
    /// Goal tabs for the library (Healing, Calm & Anxiety, Sleep…).
    let categories: [PracticeCategory]
    /// source id → citation line (from SOURCES.md)
    let sourceNotes: [String: String]

    private init() {
        var t: [Tradition] = []
        var p: [Practice] = []
        var i: [Intention] = []
        var cats: [PracticeCategory] = []
        if let url = Bundle.main.url(forResource: "practices", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(LibraryFile.self, from: data) {
            t = file.traditions ?? []
            p = file.practices ?? []
            i = file.intentions ?? []
            cats = file.categories ?? []
        }
        if p.isEmpty {
            t = Fallback.traditions
            p = Fallback.practices
            i = Fallback.intentions
        }
        // Make sure every practice's tradition exists.
        let known = Set(t.map(\.id))
        for pr in p where !pr.traditionId.isEmpty && !known.contains(pr.traditionId) {
            if !t.contains(where: { $0.id == pr.traditionId }) {
                t.append(Tradition(id: pr.traditionId, name: pr.traditionId.replacingOccurrences(of: "-", with: " ").capitalized))
            }
        }
        // Dedupe by id, keep first.
        var seen = Set<String>()
        p = p.filter { seen.insert($0.id).inserted }
        if i.isEmpty { i = Fallback.intentions }
        let ids = Set(p.map(\.id))
        i = i.map { (old: Intention) -> Intention in
            var x = old
            x.practiceIds = x.practiceIds.filter { ids.contains($0) }
            return x
        }.filter { !$0.practiceIds.isEmpty }

        traditions = t
        practices = p
        intentions = i
        categories = cats.isEmpty ? PracticeCategory.fallback : cats
        sourceNotes = Self.loadSources()
    }

    func practice(_ id: String) -> Practice? { practices.first { $0.id == id } }

    /// The free starter set: the first practice of every tradition, plus the first two
    /// movement routines. Everything else is part of Still Point Pro.
    lazy var freeIDs: Set<String> = {
        var ids = Set<String>()
        // The library file marks its starter set with "free": true; older files fall back to the rule below.
        let flagged = practices.filter { $0.freeFlag == true }.map(\.id)
        if !flagged.isEmpty {
            ids.formUnion(flagged)
            for t in practices where t.focus == .trees { ids.insert(t.id) }
            return ids
        }
        for t in traditions { if let first = practices.first(where: { $0.traditionId == t.id && !$0.isMovement }) { ids.insert(first.id) } }
        for m in practices.filter(\.isMovement).prefix(2) { ids.insert(m.id) }
        // Tree Hugs are always free (Rootbound's "Breathe with this tree" opens them).
        for t in practices where t.focus == .trees { ids.insert(t.id) }
        return ids
    }()
    func isFree(_ p: Practice) -> Bool { freeIDs.contains(p.id) }
    /// Locked for this person right now (not free and not unlocked).
    func isLocked(_ p: Practice) -> Bool { !isFree(p) && !Prefs.shared.pro }
    func tradition(_ id: String) -> Tradition? { traditions.first { $0.id == id } }
    func category(_ id: String) -> PracticeCategory? { categories.first { $0.id == id } }
    func practices(inCategory id: String) -> [Practice] { practices.filter { $0.isIn(id) } }
    /// Goal tabs this practice belongs to, in tab order.
    func categories(for p: Practice) -> [PracticeCategory] { categories.filter { p.isIn($0.id) } }
    func search(_ query: String) -> [Practice] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return practices.filter { $0.matches(q, tradition: tradition($0.traditionId), categories: categories) }
    }
    var freeCount: Int { practices.filter { isFree($0) }.count }
    func practices(in tradition: Tradition) -> [Practice] { practices.filter { $0.traditionId == tradition.id } }
    func practices(for intention: Intention) -> [Practice] { intention.practiceIds.compactMap { practice($0) } }
    func note(for source: String) -> String { sourceNotes[source] ?? source }

    var warmUps: [Practice] { practices.filter(\.isMovement) }
    func practices(focus: BodyFocus) -> [Practice] { practices.filter { $0.focus == focus } }
    var meditations: [Practice] { practices.filter { !$0.isMovement } }

    /// A good default "breathe now" practice.
    var quickPractice: Practice {
        practice("resonance") ?? practices.first(where: { ($0.pattern?.breathsPerMinute ?? 0) > 4.5 && ($0.pattern?.breathsPerMinute ?? 0) < 7 })
            ?? practices.first(where: \.isBreathwork) ?? practices.first ?? Fallback.practices[2]
    }

    /// Parses lines like `- **id** — citation text`.
    private static func loadSources() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "SOURCES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- **") else { continue }
            let rest = line.dropFirst(4)
            guard let end = rest.range(of: "**") else { continue }
            let id = String(rest[rest.startIndex..<end.lowerBound])
            var note = String(rest[end.upperBound...]).trimmingCharacters(in: .whitespaces)
            for sep in ["—", "–", "-", ":"] where note.hasPrefix(sep) {
                note = String(note.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            note = note.replacingOccurrences(of: "*", with: "")
            if !id.isEmpty { out[id] = note }
        }
        return out
    }
}

// MARK: - Built-in fallback (used only if practices.json is missing or empty)

enum Fallback {
    static let traditions: [Tradition] = [
        Tradition(id: "yoga", name: "Yogic Prāṇāyāma", region: "South Asia", origin: "India",
                  summary: "Breath regulation from the yoga traditions of India, where the breath is the bridge between body and mind.",
                  color: "#E8A84E"),
        Tradition(id: "modern", name: "Breath Science", region: "Global", origin: "Modern research",
                  summary: "Simple patterns studied in labs for calming the nervous system and steadying heart rhythm.",
                  color: "#2EC4B6"),
    ]

    static let practices: [Practice] = [
        Practice(id: "box", title: "Box Breathing", traditionId: "modern", minutes: [3, 5, 10],
                 about: "Four equal sides: breathe in, hold, breathe out, hold, four counts each.",
                 why: "Even, slow breathing with gentle holds steadies attention and lowers arousal.",
                 pattern: BreathPattern(inhale: 4, holdIn: 4, exhale: 4, holdOut: 4),
                 cues: [Cue(at: 0, text: "Sit tall. Let the shoulders drop."), Cue(at: 60, text: "Keep each side even.")]),
        Practice(id: "four-seven-eight", title: "4-7-8 Breath", traditionId: "yoga", minutes: [2, 4, 6],
                 about: "In through the nose for 4, hold for 7, out through the mouth for 8.",
                 why: "A long exhale shifts the body toward rest. Adapted from prāṇāyāma.",
                 pattern: BreathPattern(inhale: 4, holdIn: 7, exhale: 8, cycles: 8),
                 safety: "Stop if you feel light-headed. Start with four rounds."),
        Practice(id: "resonance", title: "Resonance Breathing", traditionId: "modern", minutes: [5, 10, 20],
                 about: "About six breaths a minute: in for 5.5, out for 5.5.",
                 why: "Near this pace heart rate and breath fall into rhythm, which tends to raise heart rate variability.",
                 pattern: BreathPattern(inhale: 5.5, exhale: 5.5)),
        Practice(id: "physiological-sigh", title: "Physiological Sigh", traditionId: "modern", minutes: [1, 3, 5],
                 about: "Two inhales through the nose, the second a short top-up, then a long slow exhale.",
                 why: "The double inhale re-opens the lungs; the long exhale calms quickly.",
                 pattern: BreathPattern(inhale: 3, exhale: 6, sigh: true)),
        Practice(id: "so-hum", title: "So Hum", traditionId: "yoga", kind: "mantra", minutes: [5, 10, 20],
                 about: "Silently hear \"So\" on the in-breath and \"Hum\" on the out-breath.",
                 why: "Pairing a simple sound with the breath gives the mind a gentle anchor.",
                 pattern: BreathPattern(inhale: 5, exhale: 6),
                 cues: [Cue(at: 0, text: "In: So… Out: Hum…")]),
        Practice(id: "gentle-warmup", title: "Gentle Warm-up", traditionId: "modern", kind: "movement", minutes: [2, 5, 10],
                 about: "Loosen the neck, shoulders and spine before you sit.",
                 why: "A few minutes of easy movement makes sitting still more comfortable.",
                 pattern: nil, steps: [
                    MoveStep(name: "Neck rolls", seconds: 30, how: "Slow half circles, ear to shoulder.", breath: "natural", side: "both"),
                    MoveStep(name: "Side stretch", seconds: 20, how: "Reach the left arm up and over.", breath: "in", side: "left"),
                    MoveStep(name: "Side stretch", seconds: 20, how: "Reach the right arm up and over.", breath: "in", side: "right"),
                    MoveStep(name: "Shoulder rolls", seconds: 30, how: "Roll back and down, slowly.", breath: "natural"),
                    MoveStep(name: "Seated twist", seconds: 20, how: "Turn gently to the left.", breath: "out", side: "left"),
                    MoveStep(name: "Seated twist", seconds: 20, how: "Turn gently to the right.", breath: "out", side: "right"),
                 ]),
    ]

    static let intentions: [Intention] = [
        Intention(id: "calm", name: "Calm", practiceIds: ["resonance", "box", "physiological-sigh"]),
        Intention(id: "sleep", name: "Sleep", practiceIds: ["four-seven-eight", "so-hum"]),
        Intention(id: "focus", name: "Focus", practiceIds: ["box", "so-hum"]),
    ]
}

/// The four body sections on the Today screen.
enum BodyFocus: String, CaseIterable, Identifiable, Hashable {
    case joint, lymph, stretch, breathe, trees

    var id: String { rawValue }

    var title: String {
        switch self {
        case .joint: return "Joints"
        case .lymph: return "Lymph flow"
        case .stretch: return "Stretch"
        case .breathe: return "Breathe"
        case .trees: return "Tree Hugs"
        }
    }

    var symbol: String {
        switch self {
        case .joint: return "arrow.triangle.2.circlepath"
        case .lymph: return "drop.fill"
        case .stretch: return "figure.flexibility"
        case .breathe: return "wind"
        case .trees: return "tree"
        }
    }

    /// One line under the title on the tile.
    var tagline: String {
        switch self {
        case .joint: return "Circles & mobility"
        case .lymph: return "Pump, tap, drain"
        case .stretch: return "Long, slow lines"
        case .breathe: return "Paced breathing"
        case .trees: return "Ground yourself with a tree"
        }
    }

    /// A couple of sentences at the top of the section page.
    var about: String {
        switch self {
        case .joint: return "Slow circles through every joint, taking each to the edge of comfortable range. Movement is what feeds cartilage, so this is the fastest way to undo a stiff morning or a long day sitting."
        case .lymph: return "Lymph has no pump of its own; it moves when you breathe deeply and squeeze muscles. Light strokes, tapping and calf pumps get it flowing, which is good after sitting, flying or a sauna."
        case .stretch: return "Held shapes and flowing sequences that lengthen the big muscle chains: hamstrings, hips, spine and shoulders. Breathe out into each stretch; never bounce."
        case .breathe: return "Paced breathing patterns from yoga, Zen and modern research. Longer out-breaths calm you; even counts steady you; quick top-ups wake you up."
        case .trees: return "Short breaths for grounding yourself with nature: hands on the bark, arms around a trunk, feet on the ground. Open one from Rootbound's \"Breathe with this tree\" and it's saved under that tree."
        }
    }
}
