import Foundation
import SwiftUI
import UIKit

/// One step of a scene (macro). Enum cases with associated values are Codable automatically.
enum RemoteSceneStep: Codable, Hashable {
    /// Turn the TV on or off.
    case tvPower(on: Bool)
    /// Open a streaming app by its catalog name.
    case launchApp(name: String)
    /// Press volume up (positive) or volume down (negative) this many times.
    case volume(presses: Int)
    /// Wake the paired PC's display.
    case pcWake
    /// Put the paired PC to sleep.
    case pcSleep
    /// Make another saved TV the active one (by its saved id; the name is kept for display).
    case switchTV(id: String, name: String)

    var title: String {
        switch self {
        case .tvPower(let on): return on ? "TV on" : "TV off"
        case .launchApp(let name): return "Open \(name)"
        case .volume(let n): return n >= 0 ? "Volume up ×\(n)" : "Volume down ×\(-n)"
        case .pcWake: return "Wake PC"
        case .pcSleep: return "Sleep PC"
        case .switchTV(_, let name): return "Switch to \(name)"
        }
    }

    var symbol: String {
        switch self {
        case .tvPower(let on): return on ? "power.circle.fill" : "power.circle"
        case .launchApp: return "play.rectangle.fill"
        case .volume(let n): return n >= 0 ? "speaker.wave.3.fill" : "speaker.wave.1.fill"
        case .pcWake: return "desktopcomputer"
        case .pcSleep: return "moon.zzz.fill"
        case .switchTV: return "tv.and.mediabox"
        }
    }
}

/// A user-made macro: a name, an emoji and an ordered list of steps.
struct RemoteScene: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var emoji: String
    var steps: [RemoteSceneStep]

    static let movieNight = RemoteScene(name: "Movie night", emoji: "🍿", steps: [.tvPower(on: true), .launchApp(name: "Netflix")])
    /// "PC sleep if a PC is paired": the step is skipped at run time when no PC is saved.
    static let lightsOut = RemoteScene(name: "Lights out", emoji: "🌙", steps: [.tvPower(on: false), .pcSleep])
}

/// Scenes live in UserDefaults as JSON. Free: the first 2 scenes; more are Pro.
@MainActor
@Observable
final class SceneStore {
    static let shared = SceneStore()
    static let freeLimit = 2
    private static let key = "scenes"
    private static let seededKey = "scenes.seeded"

    private(set) var scenes: [RemoteScene] = [] { didSet { save() } }
    /// The scene currently running (the row shows a spinner on it).
    private(set) var running: UUID?

    @ObservationIgnored private weak var store: TVStore?
    @ObservationIgnored private weak var pc: PCClient?

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.key), let list = try? JSONDecoder().decode([RemoteScene].self, from: data) {
            scenes = list
        }
        // Ship two starter scenes on first launch (once: deleting them should stick).
        if !d.bool(forKey: Self.seededKey) && scenes.isEmpty {
            scenes = [RemoteScene.movieNight, RemoteScene.lightsOut]
            d.set(true, forKey: Self.seededKey)
            save()
        }
    }

    func attach(store: TVStore, pc: PCClient) {
        self.store = store
        self.pc = pc
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(scenes) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        // Siri learns the scene names ("Run Movie night in Couch Remote").
        CouchRemoteShortcuts.updateAppShortcutParameters()
    }

    // MARK: Editing

    /// Adding a third scene is Pro. Returns false when the paywall was shown instead.
    func canAdd() -> Bool {
        scenes.count < Self.freeLimit || Unlock.shared.gate("More scenes")
    }

    @discardableResult
    func add(_ scene: RemoteScene) -> Bool {
        guard canAdd() else { return false }
        scenes.append(scene)
        return true
    }

    func update(_ scene: RemoteScene) {
        if let i = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[i] = scene } else { scenes.append(scene) }
    }

    func remove(_ scene: RemoteScene) {
        scenes.removeAll { $0.id == scene.id }
    }

    func move(from: IndexSet, to: Int) {
        scenes.move(fromOffsets: from, toOffset: to)
    }

    // MARK: Running

    /// Run the steps in order with a short pause between them (TVs need a beat after power on).
    func run(_ scene: RemoteScene) async {
        guard running == nil, let store else { return }
        running = scene.id
        defer { running = nil }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.show("\(scene.emoji) \(scene.name)")
        for (i, step) in scene.steps.enumerated() {
            if i > 0 { try? await Task.sleep(nanoseconds: 700_000_000) }
            await perform(step)
        }
    }

    func perform(_ step: RemoteSceneStep) async {
        guard let store else { return }
        switch step {
        case .tvPower(let on):
            store.press(on ? .powerOn : .powerOff)
            // Give the set time to come up before the next step talks to it.
            if on { try? await Task.sleep(nanoseconds: 2_500_000_000) }
        case .launchApp(let name):
            let app = store.catalog.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? StreamingApp(name: name)
            await store.launch(app)
        case .volume(let n):
            let key: RemoteKey = n >= 0 ? .volumeUp : .volumeDown
            for _ in 0..<min(abs(n), 30) {
                store.press(key)
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        case .pcWake:
            pc?.wake()
        case .pcSleep:
            // Only when a PC is paired; otherwise the step is a no-op.
            pc?.sleep()
        case .switchTV(let id, _):
            if let t = store.tvs.first(where: { $0.id == id }) { store.switchTo(t) }
        }
    }
}
