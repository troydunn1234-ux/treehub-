import SwiftUI
import UIKit

// Shared building blocks for the family design spec (Rootbound, Still Pointz, Roamr, Pulse Lab, Couch Remote).
// Every app keeps its own accent: pass it as `tint`. Everything uses system text styles, so it scales with
// Dynamic Type (wrapping instead of truncating), and works in light and dark mode.
//
//   FamilyEmptyState      SF symbol, title, one-line hint and a primary action for any empty list/screen
//   FamilyErrorRow        friendly error row with Retry
//   FamilyPrimaryButtonStyle / FamilySecondaryButtonStyle / FamilyDestructiveButtonStyle   50 pt buttons
//   .familyCard()         the one card style (radius 20, continuous; 1 pt stroke in dark mode; no heavy shadow)
//   FamilyAboutHeader     app icon + name + version for Settings / About
//   FamilyAboutLinks      privacy / terms / contact rows
//   MoreAppsList          "More apps by Troy" (MoreApps.swift)

enum FamilySpacing {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    /// Screen edge padding.
    static let screen: CGFloat = 18
    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 12
    static let buttonHeight: CGFloat = 50
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

// MARK: - Buttons

/// Filled accent capsule, 50 pt tall. Dims when disabled, springs on press.
struct FamilyPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: FamilySpacing.buttonHeight)
            .padding(.horizontal, FamilySpacing.l)
            .background(Capsule().fill(tint.opacity(enabled ? 1 : 0.4)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tinted capsule (accent at 15%), same size as the primary button.
struct FamilySecondaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: FamilySpacing.buttonHeight)
            .padding(.horizontal, FamilySpacing.l)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.24 : 0.15)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Red tinted capsule for destructive actions.
struct FamilyDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FamilySecondaryButtonStyle(tint: .red).makeBody(configuration: configuration)
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

    var body: some View {
        VStack(spacing: FamilySpacing.m) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(Circle().fill(tint.opacity(0.14)))
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
                    .padding(.top, FamilySpacing.xs)
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

/// A friendly error line with a Retry button, for data that failed to load.
struct FamilyErrorRow: View {
    let message: String
    var tint: Color = .accentColor
    var retry: (() -> Void)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FamilySpacing.m) { label; Spacer(minLength: FamilySpacing.s); retryButton }
            VStack(alignment: .leading, spacing: FamilySpacing.s) { label; retryButton }
        }
        .padding(FamilySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FamilySpacing.innerRadius, style: .continuous).fill(Color.orange.opacity(0.12)))
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
            Button("Retry", action: retry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(minWidth: 44, minHeight: 44)
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

    static let standardTerms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        if let privacy { row("Privacy Policy", "hand.raised.fill", privacy) }
        if let terms { row("Terms of Use", "doc.text.fill", terms) }
        if let support { row("Help & Contact", "envelope.fill", support) }
    }

    private func row(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: FamilySpacing.m) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 28).accessibilityHidden(true)
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: FamilySpacing.s)
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
}
