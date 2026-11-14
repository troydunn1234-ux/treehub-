import SwiftUI
import UIKit
import MessageUI
import Contacts
import ContactsUI
import UserNotifications

// MARK: - Window above everything (sheets, the Go Together map, the paywall)

@MainActor
final class HardStopWindow: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = HardStopWindow()
    private var window: UIWindow?

    func show() {
        if let window { window.isHidden = false; return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = UIHostingController(rootView: HardStopAlertView())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }

    /// Opens a pre-filled text. The person still has to tap Send: iOS never lets apps text silently.
    func composeText(to phone: String?, body: String) {
        if MFMessageComposeViewController.canSendText(), let presenter = topController() {
            let vc = MFMessageComposeViewController()
            if let phone { vc.recipients = [phone] }
            vc.body = body
            vc.messageComposeDelegate = self
            presenter.present(vc, animated: true)
        } else {
            var comps = URLComponents()
            comps.scheme = "sms"
            comps.path = phone?.filter { $0.isNumber || $0 == "+" } ?? ""
            comps.queryItems = [URLQueryItem(name: "body", value: body)]
            if let url = comps.url { UIApplication.shared.open(url) }
        }
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                  didFinishWith result: MessageComposeResult) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }

    private func topController() -> UIViewController? {
        var vc = window?.rootViewController ?? Self.keyRoot()
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }

    static func keyRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    }
}

// MARK: - Emergency contact picker (no Contacts permission needed: the picker runs out of process)

@MainActor
final class EmergencyContactPicker: NSObject, CNContactPickerDelegate {
    static let shared = EmergencyContactPicker()
    private var done: ((String, String) -> Void)?

    func present(_ done: @escaping (_ name: String, _ phone: String) -> Void) {
        self.done = done
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        var vc = HardStopWindow.keyRoot()
        while let next = vc?.presentedViewController { vc = next }
        vc?.present(picker, animated: true)
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
        Task { @MainActor in self.finish(name, phone) }
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? ""
        let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
        Task { @MainActor in self.finish(name, phone) }
    }

    private func finish(_ name: String, _ phone: String) {
        guard !phone.isEmpty else { return }
        done?(name.isEmpty ? phone : name, phone)
        done = nil
    }
}

// MARK: - "Are you OK?" full-screen countdown

struct HardStopAlertView: View {
    @State private var monitor = HardStopMonitor.shared
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private let red = Color(red: 0.78, green: 0.10, blue: 0.12)

    var body: some View {
        ZStack {
            LinearGradient(colors: [red, Color(red: 0.35, green: 0.02, blue: 0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    if monitor.phase == .help { helpContent } else { askContent }
                    disclaimer
                }
                .padding(24)
                .padding(.top, 30)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: String(localized: "Hard stop detected. Are you OK?"))
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var askContent: some View {
        VStack(spacing: 22) {
            Image(systemName: "car.side.rear.and.collision.and.car.side.front")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Are you OK?")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Roamr noticed a hard stop during your drive.")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(monitor.secondsLeft) / CGFloat(HardStopMonitor.countdownSeconds))
                    .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: monitor.secondsLeft)
                Text("\(monitor.secondsLeft)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 170, height: 170)
            .scaleEffect(pulse ? 1.04 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(monitor.secondsLeft) seconds left"))

            Button { monitor.imOK() } label: {
                Text("I'm OK")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(red)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Cancels the alert"))

            Button { monitor.getHelp() } label: {
                Text("Get help")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Text(noAnswerText)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var noAnswerText: String {
        if let name = monitor.contactName {
            return String(localized: "If you don't answer, Roamr opens a text to \(name) with your location. iOS doesn't let apps send texts on their own, so someone has to tap Send.")
        }
        return String(localized: "If you don't answer, Roamr opens a text with your location. iOS doesn't let apps send texts on their own, so someone has to tap Send.")
    }

    private var helpContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "sos.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Get help")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("If anyone is hurt, call 911 first.")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: "tel://911") { openURL(url) }
            } label: {
                Label("Call 911", systemImage: "phone.fill")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(red)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { monitor.composeMessage() } label: {
                Label(monitor.contactName.map { String(localized: "Text \($0) my location") }
                      ?? String(localized: "Text my location"), systemImage: "message.fill")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Text("The message is filled in for you. iOS doesn't let apps send texts on their own, so tap Send.")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            Button { monitor.close() } label: {
                Text("I'm OK, close")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
        }
    }

    private var disclaimer: some View {
        Text("Roamr's hard-stop alert is not a replacement for your iPhone's built-in Crash Detection or for calling 911. It can miss crashes and can go off when there wasn't one.")
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}

// MARK: - Settings card

struct HardStopSettingsCard: View {
    @AppStorage(HardStopMonitor.enabledKey) private var enabled = false
    @AppStorage(HardStopMonitor.contactNameKey) private var contactName = ""
    @Environment(RouteTracker.self) private var tracker

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    icon("car.side.rear.and.collision.and.car.side.front", Color(red: 1, green: 0.4, blue: 0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hard-stop alert").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        Text(enabled ? LocalizedStringKey("On during drives") : LocalizedStringKey("Off"))
                            .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 8)
                    Toggle("Hard-stop alert", isOn: $enabled).labelsHidden().tint(Theme.glow)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 66)

                Button {
                    EmergencyContactPicker.shared.present { name, phone in
                        HardStopMonitor.shared.setContact(name: name, phone: phone)
                        contactName = name
                    }
                } label: {
                    HStack(spacing: 14) {
                        icon("person.crop.circle.badge.exclamationmark", Theme.sky)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Emergency contact").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                            Text(contactName.isEmpty ? String(localized: "Choose someone to text") : contactName)
                                .font(Theme.rounded(12, .medium)).foregroundStyle(Theme.textDim)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textDim)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 66)

                Button { HardStopMonitor.shared.trigger(test: true) } label: {
                    HStack(spacing: 14) {
                        icon("bell.and.waves.left.and.right.fill", Theme.gold)
                        Text("Test the alert").font(Theme.rounded(15, .bold)).foregroundStyle(.white)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: enabled) { _, on in
            if on {
                // Asked here, when it's needed: notifications reach you if the phone is locked.
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
            HardStopMonitor.shared.update(tracker: tracker)
        }
    }

    private func icon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}
