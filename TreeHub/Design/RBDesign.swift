import SwiftUI
import UIKit

// Rootbound's design system (family spec): one card, one section title, one primary + one secondary button,
// stat tiles, empty states and loading skeletons. Everything in Rootbound uses these so screens line up.
// Prefixed "RB" so nothing collides with the shared design files.

enum RB {
    // Spacing scale 4 / 8 / 12 / 16 / 24 / 32.
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Screen edge padding.
    static let screen: CGFloat = 20
    /// Card + inner corner radii.
    static let radius: CGFloat = 20
    static let inner: CGFloat = 12

    /// Card fill and its 1pt hairline (Rootbound is always dark).
    static let cardFill = Color.white.opacity(0.07)
    static let innerFill = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)

    /// Big numbers: rounded, tabular.
    static func number(_ style: Font.TextStyle = .title2, _ weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
    static func text(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

// MARK: - Card

/// The one card style: soft fill, 20pt continuous corners, 1pt hairline, no heavy shadow.
struct RBCard<Content: View>: View {
    var padding: CGFloat = RB.l
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: RB.radius, style: .continuous)
                shape.fill(RB.cardFill)
                if let tint {
                    shape.fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: RB.radius, style: .continuous).strokeBorder(tint?.opacity(0.35) ?? RB.stroke, lineWidth: 1))
    }
}

extension View {
    /// Inner tile / field background (12pt radius).
    func rbInner(_ fill: Color = RB.innerFill) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: RB.inner, style: .continuous))
    }
}

// MARK: - Section title

/// Section header: .headline, an accent symbol, optional trailing accessory.
struct RBSectionTitle<Trailing: View>: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.glow
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: RB.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(RB.text(.headline, .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: RB.s)
            trailing
        }
    }
}

extension RBSectionTitle where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, tint: Color = Theme.glow) {
        self.title = title; self.symbol = symbol; self.tint = tint
        self.trailing = EmptyView()
    }
}

/// Small uppercase label above a group of fields.
struct RBGroupLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(RB.text(.caption, .bold)).tracking(0.6)
            .foregroundStyle(Theme.textDim)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

/// Primary: filled accent, 50pt tall, 14pt corners.
struct RBPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.glow
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RB.text(.body, .bold))
            .foregroundStyle(Theme.forestDeep)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, RB.l)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary: tinted fill + tinted label, same size as primary (or compact).
struct RBSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.glow
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RB.text(compact ? .subheadline : .body, .bold))
            .foregroundStyle(tint)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, RB.m)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 50)
            .background(tint.opacity(configuration.isPressed ? 0.24 : 0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Destructive: red label on a faint red fill.
struct RBDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RB.text(.body, .semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.red.opacity(configuration.isPressed ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Round 44pt icon button on material (toolbar-style buttons over photos).
struct RBIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(RB.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Stats

/// One number with its label. A missing value ("--" or "") shows a calm "No data yet" instead of raw dashes.
struct RBStatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil
    var tint: Color = Theme.glow

    private var missing: Bool { value == "--" || value == "––" || value.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: RB.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if missing {
                    Text("No data yet")
                        .font(RB.text(.subheadline, .semibold))
                        .foregroundStyle(Theme.textDim)
                } else {
                    Text(value)
                        .font(RB.number(.title3))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(label)
                    .font(RB.text(.caption, .semibold))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RB.m)
        .rbInner()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(missing ? "no data yet" : value)")
    }
}

/// A small metric inside a stat block: value over label.
struct RBMetric: View {
    let value: String
    let label: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(RB.number(.headline))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(RB.text(.caption2, .semibold))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Adaptive grid that drops columns at large text sizes.
struct RBGrid<Content: View>: View {
    var minimum: CGFloat = 96
    var spacing: CGFloat = RB.s
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size.isAccessibilitySize ? minimum * 1.9 : minimum), spacing: spacing)],
                  alignment: .leading, spacing: spacing) {
            content
        }
    }
}

/// Fixed-count grid that falls back to fewer columns for accessibility sizes.
func rbColumns(_ count: Int, _ size: DynamicTypeSize, spacing: CGFloat = RB.s) -> [GridItem] {
    let n = size.isAccessibilitySize ? max(1, count - 1 - (count > 2 ? 1 : 0)) : count
    return Array(repeating: GridItem(.flexible(), spacing: spacing), count: n)
}

// MARK: - Chips

/// Small info chip ("12 min breathwork", "1.2 mi walk").
struct RBInfoChip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.glow

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            Text(text).lineLimit(1)
        }
        .font(RB.text(.caption, .bold))
        .foregroundStyle(tint)
        .padding(.horizontal, RB.s).padding(.vertical, 5)
        .background(tint.opacity(0.16), in: Capsule())
    }
}

/// Selectable chip (tags, weather, categories): a quiet capsule that fills with the accent when on.
/// No glow, 40 pt tall, wraps its label at big text sizes instead of truncating.
struct RBChip: View {
    let label: String
    var symbol: String? = nil
    var selected = false
    var count: Int? = nil
    var tint: Color = Theme.glow

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.footnote.weight(.bold)).accessibilityHidden(true) }
            Text(label).font(RB.text(.subheadline, .semibold)).multilineTextAlignment(.leading)
            if let count {
                Text("\(count)")
                    .font(RB.text(.caption, .bold)).monospacedDigit()
                    .opacity(0.75)
            }
            if selected {
                Image(systemName: "checkmark").font(.caption2.weight(.heavy)).accessibilityHidden(true)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, RB.m)
        .frame(minHeight: 40)
        .foregroundStyle(selected ? Theme.forestDeep : .white)
        .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Color.clear : RB.stroke, lineWidth: 1))
        .contentShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Screen header

/// Top of a main screen: big title (Rootbound's serif), a dim one-line subtitle and an optional trailing accessory.
struct RBScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: RB.m) { titles; Spacer(minLength: RB.s); trailing }
            VStack(alignment: .leading, spacing: RB.m) { titles; trailing }
        }
        .padding(.top, RB.s)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.title(34))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RB.text(.subheadline, .semibold))
                    .foregroundStyle(Theme.textDim)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension RBScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title; self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

// MARK: - Rows

/// A tappable row inside a card: icon in a tinted circle, title, one-line detail, chevron.
struct RBNavRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = Theme.glow
    var trailingSymbol = "chevron.right"

    var body: some View {
        HStack(spacing: RB.m) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RB.text(.headline, .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(RB.text(.footnote)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: RB.s)
            Image(systemName: trailingSymbol)
                .font(.footnote.weight(.bold)).foregroundStyle(Theme.textDim)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state

/// Designed empty state: symbol, title, one-line hint, optional primary action.
struct RBEmptyState: View {
    let symbol: String
    let title: String
    let hint: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: RB.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.leafGradient)
                .frame(width: 84, height: 84)
                .background(Theme.glow.opacity(0.10), in: Circle())
                .symbolEffect(.bounce, value: appeared)
                .onAppear { if !reduceMotion { appeared = true } }
                .accessibilityHidden(true)
            Text(title)
                .font(RB.text(.title3, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(hint)
                .font(RB.text(.subheadline))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(RBPrimaryButtonStyle())
                    .padding(.top, RB.xs)
            }
        }
        .padding(RB.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Skeletons

/// Loading placeholder: redacted with a soft shimmer (still when Reduce Motion is on).
struct RBShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width * 1.4)
                    }
                    .allowsHitTesting(false)
                    .mask(content.redacted(reason: .placeholder))
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityLabel("Loading")
    }
}

extension View {
    func rbSkeleton() -> some View { modifier(RBShimmer()) }
}

/// A grey block the size of a row, for skeleton lists.
struct RBSkeletonRow: View {
    var height: CGFloat = 64
    var body: some View {
        HStack(spacing: RB.m) {
            Circle().fill(Color.white.opacity(0.10)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text("Breath session placeholder").font(RB.text(.subheadline, .bold))
                Text("00:00 – 00:00 · 10 min").font(RB.text(.caption))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: height)
        .padding(.horizontal, RB.m)
        .rbInner()
        .rbSkeleton()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A soft, slowly shimmering block (photo thumbnails while they load).
struct RBSkeletonBlock: View {
    var cornerRadius: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(lit ? 0.10 : 0.05))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lit = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Photo with gradient scrim

/// Photo (or a calm placeholder) cropped to fill, with a bottom scrim for text.
struct RBPhotoFill: View {
    let data: Data?
    var placeholderSymbol = "tree.fill"
    /// Longest side on screen, in points: the photo is decoded at that size, once (RBPhotoCache.swift).
    var points: CGFloat = 440

    var body: some View {
        RBCachedPhoto(data: data, points: points) {
            ZStack {
                LinearGradient(colors: [Theme.moss, Theme.forest], startPoint: .top, endPoint: .bottom)
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.glow.opacity(0.35))
            }
        }
        .accessibilityHidden(true)
    }
}
