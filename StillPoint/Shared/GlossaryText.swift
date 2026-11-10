import SwiftUI

/// Prose with glossary terms dotted-underlined; tap a term for a short definition.
struct GlossaryText: View {
    let text: String
    var font: Font = SP.serif(16, .light)
    var color: Color = SP.ink
    var accent: Color = SP.amber
    @State private var term: GlossaryTerm? = nil

    var body: some View {
        Text(Glossary.shared.attributed(text, accent: accent))
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                if let t = Glossary.shared.term(for: url) {
                    term = t
                    return .handled
                }
                return .systemAction
            })
            .sheet(item: $term) { t in GlossarySheet(term: t) }
    }
}

struct GlossarySheet: View {
    let term: GlossaryTerm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        content.presentationDetents([.medium]).presentationBackground(.ultraThinMaterial)
        #else
        content
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("GLOSSARY").font(SP.rounded(10, .semibold)).tracking(1.6).foregroundStyle(SP.faint)
                Text(term.term).font(SP.serif(24, .light)).foregroundStyle(SP.ink)
                Rectangle().fill(SP.gold.opacity(0.6)).frame(width: 40, height: 1)
                Text(term.definition).font(SP.rounded(15)).foregroundStyle(SP.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if !term.aliases.isEmpty {
                    Text("Also: " + term.aliases.joined(separator: ", ")).font(SP.rounded(12)).foregroundStyle(SP.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(DuskBackground().ignoresSafeArea())
    }
}

/// Every term, alphabetically, for browsing.
struct GlossaryListView: View {
    var body: some View {
        List(Glossary.shared.terms) { t in
            VStack(alignment: .leading, spacing: 4) {
                Text(t.term).font(SP.serif(17)).foregroundStyle(SP.ink)
                Text(t.definition).font(SP.rounded(13)).foregroundStyle(SP.dim)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(DuskBackground())
        .navigationTitle("Glossary")
    }
}
