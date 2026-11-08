import SwiftUI

/// One fun, well-established fact per common species. Matched loosely, so
/// "Coast Live Oak" and "Valley Oak" both find the oak fact.
enum TreeFacts {
    private static let facts: [(key: String, fact: String)] = [
        ("sequoia", "Giant sequoias are the largest trees on Earth by volume, and some are more than 3,000 years old."),
        ("redwood", "Coast redwoods are the tallest trees on Earth. The record holder, Hyperion, stands over 115 m (380 ft)."),
        ("oak", "A single mature oak can support hundreds of species of insects, birds and fungi."),
        ("sycamore", "California sycamores shed their bark in patches, leaving that ghostly white-and-tan camouflage trunk."),
        ("maple", "Maple seeds spin like helicopters, which can carry them well away from the parent tree."),
        ("eucalyptus", "Eucalyptus came to California from Australia in the 1800s. Their leaves are full of fragrant oils."),
        ("palm", "Palms aren't true trees botanically. They're closer to grasses and never grow rings."),
        ("pine", "Bristlecone pines in California's White Mountains are among the oldest living things, near 5,000 years old."),
        ("cypress", "Monterey cypress grow wild in only two spots on the Monterey coast, yet they're planted worldwide."),
        ("fir", "Douglas firs aren't true firs at all. They're their own genus, named for botanist David Douglas."),
        ("spruce", "Spruce wood is a favorite for guitar and violin tops because it carries sound so well."),
        ("cedar", "Cedar wood naturally resists rot and insects, thanks to its aromatic oils."),
        ("birch", "Birch bark is waterproof enough that people have made canoes from it for thousands of years."),
        ("willow", "Willow bark contains salicin, the natural compound that inspired aspirin."),
        ("ginkgo", "Ginkgo is a living fossil. Its family dates back over 200 million years, before the dinosaurs died out."),
        ("magnolia", "Magnolias evolved before bees existed, so they were first pollinated by beetles."),
        ("cherry", "Cherry blossom season in Japan is so loved that its forecasts are national news."),
        ("olive", "Some olive trees around the Mediterranean are thought to be over 2,000 years old and still bear fruit."),
        ("elm", "Elms were once the classic American street tree until Dutch elm disease swept through in the 1900s."),
        ("ash", "Ash wood is tough and springy, which is why baseball bats and tool handles are made from it."),
        ("fig", "Every fig depends on a tiny wasp to pollinate it, a partnership tens of millions of years old."),
        ("jacaranda", "Jacarandas turn whole streets purple in late spring. They're originally from South America."),
        ("bay laurel", "California bay leaves are stronger than the Mediterranean bay in your spice rack, so use fewer."),
        ("buckeye", "California buckeyes drop their leaves in summer to survive the dry season, then bloom early."),
        ("madrone", "Madrones peel their red bark every year, revealing smooth green-gold wood underneath."),
        ("pepper", "California pepper trees came from Peru with the Spanish missions. Their pink berries are sold as pink peppercorns."),
        ("baobab", "Baobabs store thousands of liters of water in their trunks to get through the dry season."),
        ("bamboo", "Some bamboo can grow almost a meter in a single day. It's technically a grass."),
        ("citrus", "Every sweet orange tree is thought to descend from an ancient cross of pomelo and mandarin."),
        ("aspen", "A grove of aspens can be one single organism. Utah's Pando shares one root system across 40+ hectares."),
        ("juniper", "Those 'berries' on a juniper are really tiny, fleshy cones. They flavor gin."),
        ("chestnut", "American chestnuts once made up about a quarter of eastern forests before a blight in the 1900s."),
        ("walnut", "Black walnuts release a chemical called juglone that keeps many plants from growing beneath them."),
        ("joshua", "Joshua trees are actually a kind of yucca and depend on one moth species to pollinate them."),
    ]

    static func fact(for species: String) -> String? {
        let s = species.lowercased()
        guard !s.isEmpty else { return nil }
        return facts.first { s.contains($0.key) }?.fact
    }
}

struct TreeFactCard: View {
    let species: String
    var body: some View {
        if let fact = TreeFacts.fact(for: species) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.glow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Did you know?").font(Theme.rounded(13, .bold)).foregroundStyle(Theme.glow)
                    Text(fact).font(Theme.rounded(15, .medium)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.leaf.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.glow.opacity(0.25), lineWidth: 1))
        }
    }
}
