import Foundation
import SwiftData

/// Brings a stack over from Food Book. Food Book opens
/// pulselab://stack-import?d=<base64url JSON> with a list of
/// {"n": name, "d": dose, "e": emoji, "t": time ("Morning"…), "o": order, "f": withFood}.
enum StackImport {
    struct Item: Codable { let n: String; let d: String; let e: String; let t: String; let o: Int; let f: Bool? }

    /// Returns how many supplements were added (ones already in the stack by name are skipped).
    @MainActor
    static func run(_ url: URL, into context: ModelContext) -> Int? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = comps.queryItems?.first(where: { $0.name == "d" })?.value else { return nil }
        var b64 = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let items = try? JSONDecoder().decode([Item].self, from: data) else { return nil }
        let existing = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let have = Set(existing.map { $0.name.lowercased() })
        var order = (existing.map(\.order).max() ?? -1) + 1
        var added = 0
        for i in items.sorted(by: { $0.o < $1.o }) where !have.contains(i.n.lowercased()) {
            let s = Supplement(name: i.n, dose: i.d, emoji: i.e.isEmpty ? "💊" : i.e,
                               time: SuppTime(rawValue: i.t) ?? .anytime, order: order)
            s.withFood = i.f ?? false
            context.insert(s)
            order += 1
            added += 1
        }
        try? context.save()
        return added
    }
}
