import SwiftUI

@main
struct RoamrWatchApp: App {
    @State private var link = PhoneLink.shared

    var body: some Scene {
        WindowGroup {
            RoamrWatchRoot()
                .environment(link)
                .onAppear { link.activate() }
        }
    }
}

enum RW {
    static let navy = Color(red: 0.03, green: 0.05, blue: 0.10)
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.20)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.32)
    static let green = Color(red: 0.30, green: 0.90, blue: 0.55)
    static let red = Color(red: 1.0, green: 0.25, blue: 0.30)
    static let fire = LinearGradient(colors: [amber, orange], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "drive": return "car.fill"
        case "bike": return "bicycle"
        case "run": return "figure.run"
        case "hike": return "figure.hiking"
        default: return "figure.walk"
        }
    }

    static func title(_ kind: String) -> String {
        switch kind {
        case "drive": return "Drive"
        case "bike": return "Ride"
        case "run": return "Run"
        case "hike": return "Hike"
        default: return "Walk"
        }
    }

    static func clock(_ s: Double) -> String {
        let t = Int(max(0, s))
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

struct RoamrWatchRoot: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        NavigationStack {
            TabView {
                Group {
                    if link.state.tracking { LiveView() } else { StartView() }
                }
                .containerBackground(RW.navy.gradient, for: .tabView)
                TripsView()
                    .containerBackground(RW.navy.gradient, for: .tabView)
            }
            .tabViewStyle(.verticalPage)
        }
        .alert("Roamr", isPresented: Binding(get: { link.error != nil }, set: { if !$0 { link.error = nil } })) {
            Button("OK", role: .cancel) { link.error = nil }
        } message: {
            Text(link.error ?? "")
        }
    }
}
