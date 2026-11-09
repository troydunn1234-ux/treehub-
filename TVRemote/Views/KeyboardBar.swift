import SwiftUI

/// "Type on TV": a glass bar with a real text field. The phone keyboard opens right away and
/// what you type shows up in the TV's search box (only the changes are sent, ~150 ms after you pause).
struct KeyboardBar: View {
    @Environment(TVStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Look.S.m) {
            HStack(spacing: Look.S.s) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Look.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("TYPE ON TV").font(Look.font(11, .black)).tracking(2.2).foregroundStyle(Look.dim)
                    Text(store.tv?.name ?? "Your TV").font(Look.font(15, .heavy)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer()
                Button { done() } label: {
                    Text("Done").font(Look.font(15, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Look.accentH, in: Capsule())
                }
                .accessibilityLabel("Close the keyboard")
            }

            if store.canType {
                HStack(spacing: Look.S.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Look.dim)
                    TextField("", text: $text, prompt: Text("Search or type…").foregroundStyle(Look.faint))
                        .font(Look.font(18, .bold))
                        .foregroundStyle(.white)
                        .tint(Look.cyan)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { store.submitTyping() }
                        .onChange(of: text) { _, new in store.typed(new) }
                        .accessibilityLabel("Text to type on the TV")
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Look.dim)
                        }
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? AnyShapeStyle(Look.accentH) : AnyShapeStyle(Look.line), lineWidth: focused ? 1.5 : 1))
                .shadow(color: focused ? Look.violet.opacity(0.45) : .clear, radius: 14)

                Text(store.tvWantsKeyboard ? "Your TV's text box is open. Type here and it shows up there."
                                           : "Pick a search box on the TV, then type here. Return searches.")
                    .font(Look.font(12, .semibold)).foregroundStyle(Look.dim)
            } else {
                // VIZIO SmartCast has no text-entry command on its local API.
                Text("VIZIO TVs don't accept typing from phones. Use your TV remote's voice button, or search inside the streaming app's own phone app, then use the arrows here to pick a result.")
                    .font(Look.font(14, .semibold)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Handy while typing: move through results without leaving the keyboard.
            HStack(spacing: Look.S.s) {
                key("arrow.uturn.backward", "Back", .back)
                key("chevron.left", "Left", .left)
                key("chevron.up", "Up", .up)
                key("chevron.down", "Down", .down)
                key("chevron.right", "Right", .right)
                key("checkmark", "OK", .ok)
            }
        }
        .padding(Look.S.l)
        .glass(26, glow: Look.violet, material: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear {
            text = ""
            if store.canType { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } }
        }
        .onChange(of: store.typing) { _, open in if !open { focused = false } }
    }

    private func key(_ symbol: String, _ label: String, _ k: RemoteKey) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.press(k)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .accessibilityLabel(label)
    }

    private func done() {
        focused = false
        store.closeKeyboard()
    }
}

/// Small round button that opens the keyboard bar.
struct KeyboardButton: View {
    @Environment(TVStore.self) private var store
    var size: CGFloat = 40

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.openKeyboard()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .glassCircle(glow: Look.cyan)
        }
        .accessibilityLabel("Type on TV")
    }
}

/// "Search" chip: opens the TV's search (where the brand allows it) and the phone keyboard.
struct SearchChip: View {
    @Environment(TVStore.self) private var store

    var body: some View {
        Button { store.searchOnTV() } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .black))
                Text("Search").font(Look.font(14, .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .glassCapsule(glow: Look.cyan)
        }
        .accessibilityLabel("Search on TV")
        .accessibilityHint("Opens search on the TV and the keyboard on your phone")
    }
}
