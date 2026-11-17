import SwiftUI

extension BodyFocus {
    var tint: Color {
        switch self {
        case .joint: return SP.gold
        case .lymph: return SP.teal
        case .stretch: return SP.rose
        case .breathe: return SP.violet
        case .trees: return Color(spHex: "#8CCB7E")
        }
    }
    var tint2: Color {
        switch self {
        case .joint: return SP.amber
        case .lymph: return Color(spHex: "#5B9BD6")
        case .stretch: return SP.plum
        case .breathe: return SP.indigo
        case .trees: return Color(spHex: "#3F7D4E")
        }
    }

    /// Title, tagline and intro in the person's language (the shared enum keeps plain English for the Watch).
    var localizedTitle: String { NSLocalizedString(title, comment: "Body focus section") }
    var localizedTagline: String { NSLocalizedString(tagline, comment: "Body focus tile line") }
    var localizedAbout: String { NSLocalizedString(about, comment: "Body focus section intro") }
}

/// Today screen: Joints / Lymph flow / Stretch / Breathe as four clear tiles (one column at the largest text sizes),
/// then Tree Hugs across the full width.
struct FocusGrid: View {
    private let lib = PracticeLibrary.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    private var cols: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: SP.s3, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(spacing: SP.s3) {
            LazyVGrid(columns: cols, spacing: SP.s3) {
                ForEach(BodyFocus.allCases.filter { $0 != .trees }) { f in
                    NavigationLink(value: f) { FocusTile(focus: f, count: lib.practices(focus: f).count) }
                        .buttonStyle(SoftPress())
                }
            }
            // Tree Hugs: its own full-width tile under the four body sections.
            let trees = lib.practices(focus: .trees).count
            if trees > 0 {
                NavigationLink(value: BodyFocus.trees) { FocusTile(focus: .trees, count: trees, wide: true) }
                    .buttonStyle(SoftPress())
            }
        }
    }
}

struct FocusTile: View {
    let focus: BodyFocus
    let count: Int
    /// Full-width row layout (Tree Hugs).
    var wide = false
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 132

    private var countText: String {
        count == 1 ? String(localized: "1 practice") : String(localized: "\(count) practices")
    }

    var body: some View {
        Group {
            if wide {
                HStack(spacing: SP.s3) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(focus.localizedTitle).font(.headline).foregroundStyle(SP.ink)
                        Text(focus.localizedTagline).font(.footnote).foregroundStyle(SP.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(countText).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(focus.tint)
                    }
                    Spacer(minLength: SP.s2)
                    chevron
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: SP.s1) {
                    HStack(alignment: .top) {
                        icon
                        Spacer(minLength: SP.s2)
                        chevron
                    }
                    Spacer(minLength: SP.s3)
                    Text(focus.localizedTitle).font(.headline).foregroundStyle(SP.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(focus.localizedTagline).font(.footnote).foregroundStyle(SP.dim)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(countText).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(focus.tint)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, minHeight: tileHeight, alignment: .topLeading)
            }
        }
        .padding(SP.s3 + 2)
        .background(
            RoundedRectangle(cornerRadius: SP.radius, style: .continuous)
                .fill(LinearGradient(colors: [focus.tint.opacity(0.16), SP.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: SP.radius, style: .continuous).stroke(SP.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: SP.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(focus.localizedTitle), \(countText)"))
        .accessibilityHint(Text(focus.localizedTagline))
    }

    private var icon: some View {
        Image(systemName: focus.symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(focus.tint)
            .frame(width: 40, height: 40)
            .background(Circle().fill(focus.tint.opacity(0.16)))
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SP.faint)
            .accessibilityHidden(true)
    }
}

/// One section page: what it's for, a quick start, then every practice in it.
struct FocusView: View {
    let focus: BodyFocus
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Prefs
    @State private var starts = 0
    private let lib = PracticeLibrary.shared

    var body: some View {
        let list = lib.practices(focus: focus)
        let open = list.filter { !lib.isLocked($0) }
        let locked = list.filter { lib.isLocked($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: SP.s6) {
                hero

                if let first = open.first {
                    quickStart(first)
                }

                if list.isEmpty {
                    SPEmptyState(symbol: focus.symbol,
                                 title: String(localized: "Nothing here yet"),
                                 hint: String(localized: "New practices for this area arrive with updates. The library has plenty meanwhile."),
                                 actionTitle: String(localized: "Open the library")) { router.tab = 1 }
                        .spCard()
                }

                if !open.isEmpty {
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader(locked.isEmpty ? String(localized: "All \(list.count)") : String(localized: "Ready now"))
                        PracticeStack(practices: open)
                    }
                }
                if !locked.isEmpty {
                    VStack(alignment: .leading, spacing: SP.s3) {
                        SectionHeader(String(localized: "With Pro"), detail: String(localized: "\(locked.count) more"))
                        PracticeStack(practices: locked)
                    }
                }
            }
            .padding(.horizontal, SP.screenPadding)
            .padding(.bottom, SP.s8)
        }
        .background(DuskBackground(glow: focus.tint))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: starts)
    }

    /// Big quiet symbol, the section name and what it's for.
    private var hero: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            Image(systemName: focus.symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(focus.tint)
                .frame(width: 56, height: 56)
                .background(Circle().fill(focus.tint.opacity(0.14)))
                .overlay(Circle().stroke(focus.tint.opacity(0.25), lineWidth: 1))
                .accessibilityHidden(true)
            Text(focus.localizedTitle).font(SP.serif(36, .light)).foregroundStyle(SP.ink)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(focus.localizedAbout).font(.body).foregroundStyle(SP.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, SP.s4)
        .background(alignment: .topTrailing) {
            Image(systemName: focus.symbol)
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(focus.tint.opacity(0.12))
                .offset(x: 16, y: -6)
                .accessibilityHidden(true)
        }
    }

    /// The first open practice at the usual length, in one tap.
    private func quickStart(_ first: Practice) -> some View {
        let usual = prefs.settings.defaultMinutes
        let mins = first.minutes.contains(usual) ? usual : first.defaultMinutes
        return Button {
            starts += 1
            router.run(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: first, minutes: mins))
        } label: {
            Label { Text("Quick start · \(first.title)") } icon: { Image(systemName: "play.fill") }
        }
        .buttonStyle(SPPrimaryButtonStyle())
        .accessibilityLabel(Text("Start \(first.title), \(mins) minutes"))
    }
}
