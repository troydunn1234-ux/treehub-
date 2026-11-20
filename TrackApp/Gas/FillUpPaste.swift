import Foundation

/// Reads fill-ups typed into a phone note, one tank per line, fields in any order:
///
///     tank 4 $61.20 18.3 gallons 402 miles 10/02 6:30pm
///
/// - "$61.20" is what you paid, "18.3 gallons" (or gal) what went in.
/// - "402 miles" (or mi) is how far you drove on that tank (trip miles, not the odometer).
/// - "10/02" is the month and day, in the most recent year that isn't in the future ("10/02/25" also works).
/// - "6:30pm" / "7pm" is the time (optional; noon when missing).
/// - "tank 4", "tank #4" is just a label.
/// Pure and deterministic: `now` and `calendar` are passed in, so tests don't depend on today.
enum FillUpPaste {

    enum Warning: Hashable {
        /// No date on the line: one was guessed from the lines around it (or today).
        case dateGuessed
        case missingTotal
        case missingGallons
        case missingMiles
        /// Miles ÷ gallons is outside 5–40 MPG: likely a typo (e.g. "3.3 miles").
        case unlikelyMPG(Double)
        /// Same day and same total as a fill-up already in the log (or earlier in the paste).
        case duplicate

        var text: String {
            switch self {
            case .dateGuessed: return String(localized: "No date: check it")
            case .missingTotal: return String(localized: "No $ total")
            case .missingGallons: return String(localized: "No gallons")
            case .missingMiles: return String(localized: "No miles")
            case .unlikelyMPG(let v): return String(localized: "\(String(format: "%.1f", v)) MPG looks off: typo?")
            case .duplicate: return String(localized: "Already in your log")
            }
        }
    }

    struct Line: Identifiable, Equatable {
        var id: Int { index }
        /// 0-based position among the lines that looked like fill-ups.
        var index: Int
        var raw: String
        var tank: Int?
        var date: Date
        var dateGuessed: Bool
        var total: Double?
        var gallons: Double?
        var miles: Double?

        var pricePerGallon: Double? {
            guard let total, let gallons, gallons > 0, total > 0 else { return nil }
            return total / gallons
        }

        var mpg: Double? {
            guard let miles, let gallons, gallons > 0, miles > 0 else { return nil }
            return miles / gallons
        }

        /// Gallons are the one thing a fill-up can't do without.
        var importable: Bool { (gallons ?? 0) > 0 }

        func warnings(existing: [(date: Date, total: Double)] = [], calendar: Calendar = .current) -> [Warning] {
            var w: [Warning] = []
            if dateGuessed { w.append(.dateGuessed) }
            if total == nil { w.append(.missingTotal) }
            if gallons == nil { w.append(.missingGallons) }
            if miles == nil { w.append(.missingMiles) }
            if let m = mpg, !FillUpPaste.plausibleMPG.contains(m) { w.append(.unlikelyMPG(m)) }
            if FillUpPaste.isDuplicate(date: date, total: total, in: existing, calendar: calendar) { w.append(.duplicate) }
            return w
        }
    }

    static let plausibleMPG: ClosedRange<Double> = 5...40

    /// Same calendar day and same total (to the cent). A line without a total is never a duplicate.
    static func isDuplicate(date: Date, total: Double?, in existing: [(date: Date, total: Double)], calendar: Calendar = .current) -> Bool {
        guard let total, total > 0 else { return false }
        return existing.contains { calendar.isDate($0.date, inSameDayAs: date) && abs($0.total - total) < 0.005 }
    }

    // MARK: Parsing

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> [Line] {
        struct Partial { var raw: String; var tank: Int?; var date: Date?; var total: Double?; var gallons: Double?; var miles: Double? }
        var partials: [Partial] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let raw = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let lower = raw.lowercased()
            let total = firstNumber(lower, #"\$\s*([0-9][0-9,]*(?:\.[0-9]+)?|\.[0-9]+)"#)
            let gallons = firstNumber(lower, #"([0-9]*\.?[0-9]+)\s*(?:gallons|gallon|gals|gal)\b"#)
            let miles = firstNumber(lower, #"([0-9][0-9,]*(?:\.[0-9]+)?|\.[0-9]+)\s*(?:miles|mile|mi)\b"#)
            // A line needs at least two of the three numbers to count as a fill-up (skips headings and chatter).
            guard [total, gallons, miles].compactMap({ $0 }).count >= 2 else { continue }
            let tank = firstNumber(lower, #"\btank\s*#?\s*([0-9]+)"#).map { Int($0) }
            partials.append(Partial(raw: raw, tank: tank, date: date(in: lower, now: now, calendar: calendar),
                                    total: total, gallons: gallons, miles: miles))
        }
        // Missing dates: halfway between the nearest dated lines around it (notes are in order), else a day after
        // the one before / before the one after, else today.
        var lines: [Line] = []
        for (i, p) in partials.enumerated() {
            var d = p.date
            if d == nil {
                let before = partials[..<i].last { $0.date != nil }?.date
                let after = partials[(i + 1)...].first { $0.date != nil }?.date
                switch (before, after) {
                case let (b?, a?) where a > b:
                    d = noon(b.addingTimeInterval(a.timeIntervalSince(b) / 2), calendar)
                case let (b?, _):
                    d = calendar.date(byAdding: .day, value: 1, to: b).map { min($0, now) }
                case let (nil, a?):
                    d = calendar.date(byAdding: .day, value: -1, to: a)
                default:
                    d = noon(now, calendar)
                }
            }
            lines.append(Line(index: i, raw: p.raw, tank: p.tank, date: d ?? now, dateGuessed: p.date == nil,
                              total: p.total, gallons: p.gallons, miles: p.miles))
        }
        return lines
    }

    /// "9/16", "09/16/25", "9/16/2025", plus an optional "7pm" / "7:15 pm" / "19:15" on the same line.
    static func date(in lower: String, now: Date, calendar: Calendar) -> Date? {
        guard let m = match(lower, #"(?<![0-9.$])([0-9]{1,2})/([0-9]{1,2})(?:/([0-9]{2,4}))?(?![0-9])"#),
              let month = Int(m[1]), let day = Int(m[2]), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var hour = 12, minute = 0
        if let t = match(lower, #"(?<![0-9/.$])([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])"#),
           var h = Int(t[1]), (1...12).contains(h) {
            let pm = t[3].hasPrefix("p")
            if h == 12 { h = 0 }
            hour = h + (pm ? 12 : 0)
            minute = Int(t[2]) ?? 0
        } else if let t = match(lower, #"(?<![0-9/.$])([0-9]{1,2}):([0-9]{2})(?![0-9])"#),
                  let h = Int(t[1]), let mm = Int(t[2]), h < 24, mm < 60 {
            hour = h; minute = mm
        }
        var comps = DateComponents(month: month, day: day, hour: hour, minute: minute)
        if let y = Int(m[3]), !m[3].isEmpty {
            comps.year = y < 100 ? 2000 + y : y
            return calendar.date(from: comps)
        }
        // The most recent such day that isn't in the future (a note written in January about 12/28 means last year).
        let thisYear = calendar.component(.year, from: now)
        for y in [thisYear, thisYear - 1] {
            comps.year = y
            if let d = calendar.date(from: comps), calendar.startOfDay(for: d) <= now { return d }
        }
        return nil
    }

    private static func noon(_ d: Date, _ cal: Calendar) -> Date {
        cal.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d
    }

    private static func firstNumber(_ s: String, _ pattern: String) -> Double? {
        guard let m = match(s, pattern) else { return nil }
        return Double(m[1].replacingOccurrences(of: ",", with: ""))
    }

    /// Capture groups of the first match (missing groups come back as "").
    private static func match(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }
}
