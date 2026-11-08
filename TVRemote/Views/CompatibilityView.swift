import SwiftUI

/// "Which TVs work?" — shown from Setup and About so people know before they rely on it.
struct CompatibilityView: View {
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let brand: TVBrand
        let title: String
        let detail: String
        let pairing: String
        var id: String { brand.rawValue }
    }

    static let rows: [Row] = [
        Row(brand: .vizio, title: "VIZIO SmartCast TVs", detail: "2016 and newer (SmartCast / VIZIO Home).",
            pairing: "Type the 4-digit code the TV shows."),
        Row(brand: .roku, title: "Roku TVs & Roku players", detail: "Roku TVs from TCL, Hisense, onn., Sharp, Insignia and others, plus every Roku stick and box.",
            pairing: "No code needed. Turn on Settings › System › Advanced › Control by mobile apps if it's off."),
        Row(brand: .samsung, title: "Samsung Smart TVs", detail: "Tizen models, 2016 and newer.",
            pairing: "Choose Allow on the TV the first time."),
        Row(brand: .lg, title: "LG Smart TVs", detail: "webOS models, 2014 and newer.",
            pairing: "Choose Allow on the TV the first time."),
        Row(brand: .googleTV, title: "Google TV & Android TV", detail: "Sony, TCL and Hisense Google TV sets, Philips Android TVs, Chromecast with Google TV, Nvidia Shield.",
            pairing: "Type the 6-character code the TV shows."),
    ]

    static let notSupported = "Amazon Fire TV, Apple TV, game consoles (Xbox, PlayStation) and older TVs without built-in smart features."

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.09).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Look.S.l) {
                    HStack {
                        CapsLabel("Works with", color: Look.cyan)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).glassCircle()
                        }
                        .accessibilityLabel("Close")
                    }
                    Text("Which TVs\nwork?").font(Look.display(38)).tracking(-1).foregroundStyle(.white)
                    Label("Your phone and TV must be on the same Wi-Fi.", systemImage: "wifi")
                        .font(Look.font(14, .bold)).foregroundStyle(Look.dim)

                    ForEach(Self.rows) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: Look.S.s) {
                                BrandChip(brand: r.brand)
                                Text(r.title).font(Look.font(17, .heavy)).foregroundStyle(.white)
                            }
                            Text(r.detail).font(Look.font(14, .medium)).foregroundStyle(Look.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            Label(r.pairing, systemImage: "lock.open.fill")
                                .font(Look.font(13, .semibold)).foregroundStyle(Look.cyan)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Look.S.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(18)
                        .accessibilityElement(children: .combine)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Doesn't work with", systemImage: "xmark.circle.fill")
                            .font(Look.font(15, .heavy)).foregroundStyle(.orange)
                        Text(Self.notSupported).font(Look.font(14, .medium)).foregroundStyle(Look.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Look.S.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(18, tint: .orange)

                    Text("Couch Remote is an independent app and isn't affiliated with or endorsed by VIZIO, Roku, Samsung, LG or Google. Brand names are used only to say which TVs work.")
                        .font(Look.font(12, .medium)).foregroundStyle(Look.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Look.S.xl)
            }
        }
    }
}
