import Foundation
import Vision
import CoreGraphics
import ImageIO

/// On-device guess at what kind of tree is in a photo, using Apple's built-in
/// image classifier. Nothing leaves the phone.
struct SpeciesGuess: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let confidence: Double   // 0...1
}

enum SpeciesGuesser {
    /// Classifier label words → the species name we show. Labels are matched
    /// word-by-word ("palm_tree" → ["palm", "tree"]) so "ash" never matches "cashew".
    private static let map: [(words: [String], name: String)] = [
        (["redwood"], "Coast Redwood"),
        (["sequoia"], "Giant Sequoia"),
        (["oak"], "Oak"),
        (["acorn"], "Oak"),
        (["maple"], "Maple"),
        (["palm"], "Palm"),
        (["coconut"], "Palm"),
        (["eucalyptus"], "Eucalyptus"),
        (["pine"], "Pine"),
        (["pinecone"], "Pine"),
        (["conifer"], "Pine"),
        (["christmas", "tree"], "Fir"),
        (["fir"], "Fir"),
        (["spruce"], "Spruce"),
        (["cypress"], "Cypress"),
        (["cedar"], "Cedar"),
        (["birch"], "Birch"),
        (["willow"], "Willow"),
        (["ginkgo"], "Ginkgo"),
        (["magnolia"], "Magnolia"),
        (["cherry", "blossom"], "Cherry"),
        (["cherry"], "Cherry"),
        (["sakura"], "Cherry"),
        (["olive"], "Olive"),
        (["sycamore"], "California Sycamore"),
        (["elm"], "Elm"),
        (["ash"], "Ash"),
        (["fig"], "Fig"),
        (["jacaranda"], "Jacaranda"),
        (["baobab"], "Baobab"),
        (["bamboo"], "Bamboo"),
        (["bonsai"], "Bonsai"),
        (["citrus"], "Citrus"),
        (["lemon"], "Citrus"),
        (["orange"], "Citrus"),
        (["apple", "tree"], "Apple"),
        (["juniper"], "Juniper"),
        (["poplar"], "Poplar"),
        (["aspen"], "Aspen"),
        (["beech"], "Beech"),
        (["chestnut"], "Chestnut"),
        (["walnut"], "Walnut"),
        (["dogwood"], "Dogwood"),
        (["linden"], "Linden"),
        (["hemlock"], "Hemlock"),
        (["larch"], "Larch"),
        (["yew"], "Yew"),
        (["sumac"], "Sumac"),
        (["holly"], "Holly"),
        (["acacia"], "Acacia"),
        (["mangrove"], "Mangrove"),
        (["joshua"], "Joshua Tree"),
        (["cactus"], "Cactus"),
    ]

    /// Words that mean "it's a tree" without saying which.
    private static let treeWords: Set<String> = ["tree", "trees", "forest", "woodland", "trunk", "bark", "foliage", "branch", "canopy", "leaf", "leaves", "plant"]

    struct Result {
        var guesses: [SpeciesGuess]
        var looksLikeTree: Bool
    }

    static func guess(from data: Data) async -> Result {
        await Task.detached(priority: .userInitiated) { () -> Result in
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary)
            else { return Result(guesses: [], looksLikeTree: false) }
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { return Result(guesses: [], looksLikeTree: false) }
            let labels = (request.results ?? []).map { ($0.identifier, Double($0.confidence)) }
            return interpret(labels)
        }.value
    }

    /// Pure mapping step, kept separate so it can be unit tested.
    static func interpret(_ labels: [(String, Double)]) -> Result {
        var best: [String: Double] = [:]
        var treeScore = 0.0
        for (label, conf) in labels where conf > 0.03 {
            let words = label.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
            let set = Set(words)
            if !set.isDisjoint(with: treeWords) { treeScore = max(treeScore, conf) }
            for entry in map where Set(entry.words).isSubset(of: set) {
                best[entry.name] = max(best[entry.name] ?? 0, conf)
                treeScore = max(treeScore, conf)
            }
        }
        let guesses = best
            .map { SpeciesGuess(name: $0.key, confidence: min(1, $0.value)) }
            .sorted { $0.confidence > $1.confidence }
        return Result(guesses: Array(guesses.prefix(3)), looksLikeTree: treeScore > 0.1)
    }

    /// Every label the on-device classifier knows; used by CI to check the map.
    static func supportedLabels() -> [String] {
        (try? VNClassifyImageRequest().supportedIdentifiers()) ?? []
    }
}
