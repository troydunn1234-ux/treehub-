import SwiftUI

// Shared by the iPhone and Watch apps: what a sauna / steam session is, and what to do in one.

/// Sauna or steam room.
enum HeatKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case sauna, steam

    var id: String { rawValue }
    var title: String { self == .sauna ? "Sauna" : "Steam room" }
    var short: String { self == .sauna ? "Sauna" : "Steam" }
    var symbol: String { self == .sauna ? "flame.fill" : "cloud.fog.fill" }
    var tint: Color { self == .sauna ? Color(spHex: "#F29A5B") : Color(spHex: "#7FC8D9") }
    var tint2: Color { self == .sauna ? Color(spHex: "#C2474A") : Color(spHex: "#5B7FD6") }
    /// When to send the "time to step out?" nudge.
    var checkInMinutes: Int { self == .sauna ? 20 : 15 }
}

/// Breathing that suits high heat: slow, through the nose, no holds, no fast breathing.
struct HeatBreath: Identifiable, Hashable {
    let id: String
    let title: String
    let pattern: String
    let why: String
    /// Phases in seconds: (label, seconds, isInhale)
    let phases: [Phase]
    struct Phase: Hashable { let label: String; let seconds: Double; let grow: Bool }

    var cycle: Double { phases.reduce(0) { $0 + $1.seconds } }

    static let all: [HeatBreath] = [
        HeatBreath(id: "cool", title: "Cool nose breath", pattern: "In 4 · Out 6",
                   why: "Slow breathing through the nose cools and moistens the air and keeps your heart rate from racing. Best way to settle in.",
                   phases: [.init(label: "In through the nose", seconds: 4, grow: true), .init(label: "Out slowly", seconds: 6, grow: false)]),
        HeatBreath(id: "long", title: "Long exhale", pattern: "In 4 · Out 8",
                   why: "For when the heat feels intense. A long out-breath switches on the body's calming side, so the heat feels easier to sit with.",
                   phases: [.init(label: "In through the nose", seconds: 4, grow: true), .init(label: "Long slow out", seconds: 8, grow: false)]),
        HeatBreath(id: "sigh", title: "Sigh it out", pattern: "In 2 · top-up 1 · Out 6",
                   why: "A double breath in through the nose, then one long sigh out. The quickest way to let tension go. A few rounds, then breathe normally.",
                   phases: [.init(label: "In", seconds: 2, grow: true), .init(label: "Top it up", seconds: 1, grow: true), .init(label: "Sigh it all out", seconds: 6, grow: false)]),
        HeatBreath(id: "even", title: "Even rhythm", pattern: "In 5 · Out 5",
                   why: "About 6 breaths a minute, smooth and even. A good rhythm to hold for the rest of the round while you just sit.",
                   phases: [.init(label: "In", seconds: 5, grow: true), .init(label: "Out", seconds: 5, grow: false)]),
    ]
    static func find(_ id: String) -> HeatBreath { all.first { $0.id == id } ?? all[0] }
}

/// Gentle moves you can do sitting or lying on the bench. `pose` picks the animated figure.
struct HeatMove: Identifiable, Hashable {
    let id: String
    let title: String
    let pose: String
    let how: String
    let seconds: Double

    var step: MoveStep { MoveStep(name: pose, seconds: seconds, how: how) }

    static let all: [HeatMove] = [
        HeatMove(id: "neck", title: "Neck release", pose: "neck stretch",
                 how: "Ear toward shoulder, three slow breaths, then the other side. Never roll the head back.", seconds: 45),
        HeatMove(id: "shoulders", title: "Shoulder rolls", pose: "neck & shoulders",
                 how: "Big, slow rolls back and down, then forward. Let the heat loosen the upper back.", seconds: 40),
        HeatMove(id: "twist", title: "Seated twist", pose: "twisting hermit",
                 how: "Sit tall, hand to the opposite knee, turn on the out-breath. Hold, then switch sides.", seconds: 60),
        HeatMove(id: "fold", title: "Hamstring fold", pose: "straight-leg bow",
                 how: "Legs long on the bench, fold toward the toes. Warm muscles give a little more, but don't force it.", seconds: 60),
        HeatMove(id: "butterfly", title: "Butterfly", pose: "butterfly bow",
                 how: "Soles together, knees drop open, lean forward gently. Breathe into the hips.", seconds: 50),
        HeatMove(id: "jaw", title: "Jaw & face", pose: "face & eye massage",
                 how: "Small circles at the jaw hinge and temples. Unclench your teeth; soften the forehead.", seconds: 40),
        HeatMove(id: "lymph", title: "Lymph strokes", pose: "legs & feet",
                 how: "Light strokes from the ankles up to the knees, then from the knees up toward the hips. Feather-light.", seconds: 60),
        HeatMove(id: "ankles", title: "Ankle & wrist circles", pose: "arms",
                 how: "Circle the ankles and wrists both ways. Keeps blood moving in the extremities while you sit still.", seconds: 40),
    ]
    static func find(_ id: String) -> HeatMove { all.first { $0.id == id } ?? all[0] }
}

