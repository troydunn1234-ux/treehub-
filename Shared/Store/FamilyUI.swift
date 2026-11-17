import SwiftUI
import UIKit

// Shared building blocks for the family design spec (Rootbound, Still Pointz, Roamr, Pulse Lab, Couch Remote).
// Every app keeps its own accent: pass it as `tint`. Everything uses system text styles, so it scales with
// Dynamic Type (wrapping instead of truncating), and works in light and dark mode.
//
//   FamilyEmptyState      SF symbol, title, one-line hint and a primary action for any empty list/screen
//   FamilyErrorRow        friendly error row with "Try again"
//   FamilyPrimaryButtonStyle / FamilySecondaryButtonStyle / FamilyDestructiveButtonStyle   50 pt buttons
//   FamilyGradientButtonStyle   the paywall / onboarding call to action (accent gradient, dark label)
//   .familyCard()         the one card style (radius 20, continuous; 1 pt stroke in dark mode; no heavy shadow)
//   FamilyAboutHeader     app icon + name + version for Settings / About
//   FamilyAboutLinks      privacy / terms / contact rows
//   MoreAppsList          "More apps by Troy" (MoreApps.swift)
//   FamilyContrast        keeps an accent readable on buttons (WCAG contrast) in light and dark mode

enum FamilySpacing {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    /// Screen edge padding.
    static let screen: CGFloat = 18
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 12
    static let buttonHeight: CGFloat = 50
    /// Button corners: a capsule at the standard 50 pt height, and a soft rounded rectangle (not a tall pill)
    /// when a large Dynamic Type label wraps onto a second line.
    static let buttonRadius: CGFloat = buttonHeight / 2
}

// MARK: - Card

private struct FamilyCardModifier: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FamilySpacing.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.10 : 0), lineWidth: 1))
    }
}

extension View {
    /// The family card: secondary grouped background, radius 20 (continuous), a hairline stroke in dark mode.
    func familyCard(padding: CGFloat = FamilySpacing.l) -> some View { modifier(FamilyCardModifier(padding: padding)) }
}

// MARK: - Contrast

/// WCAG 2 contrast helpers, so each app's accent stays readable on the family buttons in light and dark mode.
enum FamilyContrast {
    /// Relative luminance (0 black ... 1 white) of `color` as it renders in `scheme`.
    static func luminance(_ color: Color, in scheme: ColorScheme) -> CGFloat {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
        func linear(_ c: CGFloat) -> CGFloat {
            let c = min(max(c, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Contrast ratio between two luminances (1 ... 21).
    static func ratio(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    /// Label color on a filled button: white, or near-black where white would fall under 3:1
    /// (AA for the 17 pt semibold button label), e.g. on orange, lime, cyan or periwinkle accents.
    static func label(on fill: Color, in scheme: ColorScheme) -> Color {
        ratio(1, luminance(fill, in: scheme)) >= 3 ? .white : Color.black.opacity(0.88)
    }

    /// Label color on an accent gradient: near-black (the paywall look) unless the gradient is too dark for it.
    static func label(on a: Color, _ b: Color, in scheme: ColorScheme) -> Color {
        let black = min(ratio(0, luminance(a, in: scheme)), ratio(0, luminance(b, in: scheme)))
        return black >= 3 ? Color.black.opacity(0.88) : .white
    }

    /// `tint` used as text on a light background: in light mode it is darkened just enough to reach 4.5:1
    /// (an orange or lime accent would otherwise be hard to read). Dark mode keeps the accent as it is.
    static func readable(_ tint: Color, in scheme: ColorScheme) -> Color {
        guard scheme == .light, ratio(1, luminance(tint, in: .light)) < 4.5 else { return tint }
        let ui = UIColor(tint).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a) else { return tint }
        var candidate = tint
        while v > 0.2, ratio(1, luminance(candidate, in: .light)) < 4.5 {
            v -= 0.06
            candidate = Color(UIColor(hue: h, saturation: s, brightness: v, alpha: a))
        }
        return candidate
    }
}

// MARK: - Buttons

/// Filled accent button, 50 pt tall. The label is white, or near-black on light accents where white would be
/// hard to read. Dims when disabled, springs on press (not with Reduce Motion).
struct FamilyPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        FamilyButtonBody(label: configuration.label, pressed: configuration.isPressed, kind: .filled(tint))
    }
}

/// Tinted button (accent at 15%), same size as the primary button.
struct FamilySecondaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        FamilyButtonBody(label: configuration.label, pressed: configuration.isPressed, kind: .tinted(tint))
    }
}

/// Red tinted button for destructive actions.
struct FamilyDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FamilyButtonBody(label: configuration.label, pressed: configuration.isPressed, kind: .tinted(.red))
    }
}

/// The paywall and onboarding call to action: the app's two accents as a gradient with a dark label.
struct FamilyGradientButtonStyle: ButtonStyle {
    var tint: Color
    var tint2: Color

    func makeBody(configuration: Configuration) -> some View {
        FamilyButtonBody(label: configuration.label, pressed: configuration.isPressed, kind: .gradient(tint, tint2))
    }
}

/// One body for every family button. A view of its own (not a style calling another style's makeBody), so the
/// enabled state, Reduce Motion and the color scheme come from the environment it's actually shown in.
private struct FamilyButtonBody<Content: View>: View {
    enum Kind { case filled(Color), tinted(Color), gradient(Color, Color) }

    let label: Content
    let pressed: Bool
    let kind: Kind
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FamilySpacing.buttonRadius, style: .continuous)
        label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, FamilySpacing.l)
            .padding(.vertical, FamilySpacing.s)
            .frame(maxWidth: .infinity, minHeight: FamilySpacing.buttonHeight)
            .background(fill, in: shape)
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: pressed)
    }

    private var foreground: Color {
        switch kind {
        case .filled(let tint): return FamilyContrast.label(on: tint, in: scheme)
        case .tinted(let tint): return FamilyContrast.readable(tint, in: scheme)
        case .gradient(let a, let b): return FamilyContrast.label(on: a, b, in: scheme)
        }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .filled(let tint):
            return AnyShapeStyle(tint.opacity(pressed ? 0.85 : 1))
        case .tinted(let tint):
            return AnyShapeStyle(tint.opacity(pressed ? 0.24 : 0.15))
        case .gradient(let a, let b):
            let o = pressed ? 0.85 : 1
            return AnyShapeStyle(LinearGradient(colors: [a.opacity(o), b.opacity(o)], startPoint: .leading, endPoint: .trailing))
        }
    }
}

// MARK: - Empty state

/// The designed empty state: symbol, title, one-line hint, optional primary action.
struct FamilyEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var tint: Color = .accentColor
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var badge: CGFloat = 72

    var body: some View {
        VStack(spacing: FamilySpacing.m) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: badge, height: badge)
                .background(Circle().fill(tint.opacity(0.14)))
                .symbolEffect(.bounce, value: appeared)
                .padding(.bottom, FamilySpacing.xs)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(FamilyPrimaryButtonStyle(tint: tint))
                    .frame(maxWidth: 320)
                    .padding(.top, FamilySpacing.s)
            }
        }
        .padding(.vertical, FamilySpacing.xl)
        .padding(.horizontal, FamilySpacing.l)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear { if !reduceMotion { appeared = true } }
    }
}

// MARK: - Error row

/// A friendly error line with a "Try again" button, for data that failed to load.
struct FamilyErrorRow: View {
    let message: String
    var tint: Color = .accentColor
    var retry: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FamilySpacing.m) { label; Spacer(minLength: FamilySpacing.s); retryButton }
            VStack(alignment: .leading, spacing: FamilySpacing.xs) { label; retryButton }
        }
        .padding(.horizontal, FamilySpacing.m)
        .padding(.vertical, FamilySpacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FamilySpacing.innerRadius, style: .continuous).fill(Color.orange.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        Label {
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var retryButton: some View {
        if let retry {
            Button(action: retry) {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(FamilyContrast.readable(tint, in: scheme))
        }
    }
}

// MARK: - About

enum FamilyAppInfo {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""
    }
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "Version \(v) (\($0))" } ?? "Version \(v)"
    }
    /// This app's own icon (the primary icon set), if the system will hand it over.
    static var icon: UIImage? {
        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last, let img = UIImage(named: last) {
            return img
        }
        if let key = Bundle.main.bundleIdentifier?.split(separator: ".").last,
           let img = UIImage(named: "moreapps-\(key)") { return img }
        return UIImage(named: "AppIcon")
    }
}

/// App icon, name and version, centered. Top of every Settings / About screen.
struct FamilyAboutHeader: View {
    var name: String = FamilyAppInfo.name
    var tagline: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: FamilySpacing.s) {
            Group {
                if let icon = FamilyAppInfo.icon {
                    Image(uiImage: icon).resizable().scaledToFill()
                } else {
                    Image(systemName: "app.fill").font(.system(size: 40)).foregroundStyle(tint)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
            Text(name).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let tagline {
                Text(tagline).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(FamilyAppInfo.version).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FamilySpacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Privacy, terms and contact rows (each only if given). Works inside a List/Form section or a card.
struct FamilyAboutLinks: View {
    var privacy: URL? = nil
    var terms: URL? = nil
    var support: URL? = nil
    var tint: Color = .accentColor
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    /// Apple's standard license agreement (EULA), the Terms of Use for every family app.
    static let standardTerms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        if let privacy { row("Privacy Policy", "hand.raised.fill", privacy) }
        if let terms { row("Terms of Use", "doc.text.fill", terms) }
        if let support { row("Help & Contact", "envelope.fill", support) }
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: FamilySpacing.m) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: iconWidth).accessibilityHidden(true)
                Text(title).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: FamilySpacing.s)
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
}
