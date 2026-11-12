import SwiftUI

extension BodyFocus {
    var tint: Color {
        switch self {
        case .joint: return SP.gold
        case .lymph: return SP.teal
        case .stretch: return SP.rose
        case .breathe: return SP.violet
        }
    }
    var tint2: Color {
        switch self {
        case .joint: return SP.amber
        case .lymph: return Color(spHex: "#5B9BD6")
        case .stretch: return SP.plum
        case .breathe: return SP.indigo
        }
    }
}

/// Today screen: Joints / Lymph flow / Stretch / Breathe as four clear tiles.
struct FocusGrid: View {
    private let lib = PracticeLibrary.shared
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(BodyFocus.allCases) { f in
                NavigationLink(value: f) { FocusTile(focus: f, count: lib.practices(focus: f).count) }
                    .buttonStyle(SoftPress())
            }
        }
    }
}

struct FocusTile: View {
    let focus: BodyFocus
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: focus.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [focus.tint, focus.tint2], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(focus.tint.opacity(0.16)))
                    .overlay(Circle().stroke(focus.tint.opacity(0.25), lineWidth: 1))
                Spacer()
                Text("\(count)").font(SP.numbers(15)).foregroundStyle(focus.tint.opacity(0.9))
            }
            Spacer(minLength: 14)
            Text(focus.title).font(SP.serif(21)).foregroundStyle(SP.ink)
            Text(focus.tagline).font(SP.rounded(12)).foregroundStyle(SP.dim).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SP.card)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [focus.tint.opacity(0.22), focus.tint2.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(focus.tint.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(focus.title), \(count) practices")
    }
}

/// One section page: what it's for, a quick start, then every practice in it.
struct FocusView: View {
    let focus: BodyFocus
    @EnvironmentObject var router: Router
    @EnvironmentObject var prefs: Prefs
    private let lib = PracticeLibrary.shared

    var body: some View {
        let list = lib.practices(focus: focus)
        let open = list.filter { !lib.isLocked($0) }
        let locked = list.filter { lib.isLocked($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomLeading) {
                    RadialGradient(colors: [focus.tint.opacity(0.35), .clear], center: .topTrailing, startRadius: 4, endRadius: 260)
                    Image(systemName: focus.symbol)
                        .font(.system(size: 120, weight: .ultraLight))
                        .foregroundStyle(focus.tint.opacity(0.18))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: 16, y: -10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(focus.title).font(SP.serif(38, .light)).foregroundStyle(SP.ink)
                        Text(focus.about).font(SP.rounded(15)).foregroundStyle(SP.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: 200)

                if let first = open.first {
                    Button {
                        let usual = prefs.settings.defaultMinutes
                        let mins = first.minutes.contains(usual) ? usual : first.defaultMinutes
                        router.run(SessionPlan(warmUp: nil, warmUpMinutes: 0, practice: first, minutes: mins))
                    } label: {
                        Label("Quick start · \(first.title)", systemImage: "play.fill")
                            .font(SP.rounded(15, .medium)).lineLimit(1)
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(Capsule().fill(LinearGradient(colors: [focus.tint, focus.tint2], startPoint: .leading, endPoint: .trailing)))
                            .shadow(color: focus.tint.opacity(0.4), radius: 12, y: 4)
                    }
                    .buttonStyle(SoftPress())
                }

                if !open.isEmpty {
                    SectionHeader(locked.isEmpty ? "All \(list.count)" : "Ready now")
                    PracticeStack(practices: open)
                }
                if !locked.isEmpty {
                    SectionHeader("With Pro", detail: "\(locked.count) more")
                    PracticeStack(practices: locked)
                }
            }
            .padding(22)
        }
        .background(DuskBackground())
        .navigationBarTitleDisplayMode(.inline)
    }
}
