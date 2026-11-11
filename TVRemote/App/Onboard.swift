import SwiftUI

enum CouchRemoteOnboard {
    static let spec = OnboardingSpec(
        appName: "Couch Remote", tint: Look.cyan, tint2: Look.magenta,
        pages: [
            .init(icon: "tv.fill", title: "One remote.\nEvery TV.", text: "Vizio, Roku, Samsung, LG and Google TV over Wi-Fi. Couch Remote finds them on your network — no IR, no hub."),
            .init(icon: "keyboard", title: "Type, don't peck.", text: "Tap search on the TV and your phone's keyboard pops up. Launch apps straight from the picker."),
            .init(icon: "desktopcomputer", title: "Your PC too.", text: "Install the free companion on Windows and get a trackpad, media keys, volume and sleep from the couch — or from anywhere with Tailscale."),
        ],
        freeLine: "The full remote and app launcher for one TV, free forever.",
        proLine: "Pro adds unlimited TVs, typing on the TV and the PC remote for"
    )
}
