import AppIntents
import SwiftUI
import WidgetKit

// Couch Remote on the iPhone: Control Center / Lock Screen / Action button controls for the TV (iOS 18+),
// plus a Lock Screen widget that opens the remote. The controls run TVControlKeyIntent
// (TVRemote/App/RemoteControlIntents.swift) in the app's process, so the TV gets the key without opening the app.

@main
struct ClickerWidgets: WidgetBundle {
    var body: some Widget {
        CouchRemoteLockWidget()
        if #available(iOS 18.0, *) {
            TVPowerControl()
            TVVolumeUpControl()
            TVVolumeDownControl()
            TVMuteControl()
        }
    }
}

// MARK: - Controls

@available(iOS 18.0, *)
struct TVPowerControl: ControlWidget {
    static let kind = "com.troydunn.clicker.control.power"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVControlKeyIntent(key: .power)) {
                Label("TV Power", systemImage: "power")
            }
        }
        .displayName("TV Power")
        .description("Turns your TV on or off.")
    }
}

@available(iOS 18.0, *)
struct TVVolumeUpControl: ControlWidget {
    static let kind = "com.troydunn.clicker.control.volup"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVControlKeyIntent(key: .volumeUp)) {
                Label("TV Volume Up", systemImage: "speaker.plus.fill")
            }
        }
        .displayName("TV Volume Up")
        .description("Turns the TV volume up one step.")
    }
}

@available(iOS 18.0, *)
struct TVVolumeDownControl: ControlWidget {
    static let kind = "com.troydunn.clicker.control.voldown"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVControlKeyIntent(key: .volumeDown)) {
                Label("TV Volume Down", systemImage: "speaker.minus.fill")
            }
        }
        .displayName("TV Volume Down")
        .description("Turns the TV volume down one step.")
    }
}

@available(iOS 18.0, *)
struct TVMuteControl: ControlWidget {
    static let kind = "com.troydunn.clicker.control.mute"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TVControlKeyIntent(key: .mute)) {
                Label("Mute TV", systemImage: "speaker.slash.fill")
            }
        }
        .displayName("Mute TV")
        .description("Mutes or unmutes the TV.")
    }
}

// MARK: - Lock Screen widget

private enum CRPhone {
    static let appGroup = "group.com.troydunn.clicker"
    static let deepLink = URL(string: "couchremote://remote")!
    static func tvName() -> String {
        (UserDefaults(suiteName: appGroup)?.string(forKey: "tvName") ?? "").trimmingCharacters(in: .whitespaces)
    }
}

struct CRLockEntry: TimelineEntry {
    let date: Date
    let tvName: String
}

struct CRLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> CRLockEntry { CRLockEntry(date: Date(), tvName: "Living Room TV") }
    func getSnapshot(in context: Context, completion: @escaping (CRLockEntry) -> Void) {
        completion(CRLockEntry(date: Date(), tvName: context.isPreview ? "Living Room TV" : CRPhone.tvName()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CRLockEntry>) -> Void) {
        // The app reloads timelines when the TV changes; refresh hourly as a backstop.
        let next = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [CRLockEntry(date: Date(), tvName: CRPhone.tvName())], policy: .after(next)))
    }
}

struct CouchRemoteLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CouchRemoteLock", provider: CRLockProvider()) { entry in
            CRLockView(entry: entry)
                .widgetURL(CRPhone.deepLink)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Couch Remote")
        .description("Open the remote for your TV.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CRLockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CRLockEntry
    private var title: String { entry.tvName.isEmpty ? "Couch Remote" : entry.tvName }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "tv.fill").font(.system(size: 24, weight: .black)).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1).widgetAccentable()
                    Text(entry.tvName.isEmpty ? "Pair a TV in the app" : "Tap for the remote")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label(title, systemImage: "tv.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "tv.fill").font(.system(size: 22, weight: .black)).widgetAccentable()
            }
        }
    }
}
