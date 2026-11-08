import SwiftUI
import SwiftData

@MainActor
struct TrackSettingsView: View {
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage(TrackPrefs.announceSplitsKey) private var announceSplits = TrackPrefs.defaultOn
    @AppStorage(TrackPrefs.autoPauseKey) private var autoPause = TrackPrefs.defaultOn
    @Query(sort: \Activity.start) private var activities: [Activity]
    @State private var healthStatus = ""
    @State private var healthConnecting = false
    @State private var healthConnected = false
    @State private var exportURL: URL?

    private static let spring = Animation.spring(response: 0.4, dampingFraction: 0.82)

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildString: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    private var tripCountText: String {
        "\(activities.count) \(activities.count == 1 ? "trip" : "trips")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    header

                    sectionLabel("Units")
                    unitsCard.cardAppear()

                    sectionLabel("Recording")
                    recordingCard.cardAppear()
                    footnote("Auto-pause never kicks in while driving. A pause you tap yourself always waits for you.")

                    sectionLabel("Garmin · Whoop")
                    healthCard.cardAppear()
                    footnote("In Garmin Connect: More → Settings → Connected Apps → Apple Health. \(AppInfo.name) then lists those workouts so you can add them with one tap.")

                    sectionLabel("Your data")
                    dataCard.cardAppear()
                    footnote("Stored on your iPhone and your private iCloud only. \(tripCountText).")

                    sectionLabel("About")
                    aboutCard.cardAppear()

                    versionFooter
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 8)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .forestScreen()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { exportURL = Self.export(activities) }
            .onChange(of: activities.count) { _, _ in exportURL = Self.export(activities) }
            .sensoryFeedback(.selection, trigger: useMetric)
            .sensoryFeedback(.selection, trigger: announceSplits)
            .sensoryFeedback(.selection, trigger: autoPause)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(Theme.title(34))
                .foregroundStyle(.white)
            Text("\(AppInfo.name) · \(tripCountText) saved")
                .font(Theme.rounded(14, .semibold))
                .foregroundStyle(Theme.textDim)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Units

    private var unitsCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                row(symbol: "ruler.fill", tint: Theme.glow,
                    title: "Metric units",
                    subtitle: useMetric ? "Kilometers and meters" : "Miles and feet") {
                    Toggle("Metric units", isOn: $useMetric.animation(Self.spring))
                        .labelsHidden()
                        .tint(Theme.glow)
                }
                divider
                row(symbol: "speedometer", tint: Theme.sky,
                    title: "Example",
                    subtitle: "How distances and speeds look") {
                    Text("\(Format.distance(5000)) · \(Format.speed(4))")
                        .font(Theme.rounded(13, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.glow)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    // MARK: Recording

    private var recordingCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                row(symbol: "speaker.wave.2.fill", tint: Theme.glow,
                    title: "Announce splits",
                    subtitle: announceSplits ? "Voice + tap every \(useMetric ? "kilometer" : "mile")" : "Off") {
                    Toggle("Announce splits", isOn: $announceSplits.animation(Self.spring))
                        .labelsHidden()
                        .tint(Theme.glow)
                }
                divider
                row(symbol: "pause.circle.fill", tint: Theme.gold,
                    title: "Auto-pause",
                    subtitle: autoPause ? "Pauses when you stop, resumes when you move" : "Off") {
                    Toggle("Auto-pause", isOn: $autoPause.animation(Self.spring))
                        .labelsHidden()
                        .tint(Theme.glow)
                }
            }
        }
    }

    // MARK: Apple Health

    private var healthCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    connectHealth()
                } label: {
                    healthRowLabel
                }
                .pressable()
                .disabled(healthConnecting)
                .accessibilityLabel("Connect Apple Health")

                if !healthStatus.isEmpty {
                    divider
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: healthConnected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(healthConnected ? Theme.glow : Theme.gold)
                        Text(healthStatus)
                            .font(Theme.rounded(13, .medium))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var healthRowLabel: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.48), Color(red: 0.93, green: 0.18, blue: 0.33)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Color(red: 0.93, green: 0.18, blue: 0.33).opacity(0.45), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Apple Health")
                    .font(Theme.rounded(16, .bold))
                    .foregroundStyle(.white)
                Text("Bring in Garmin and Whoop workouts")
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 8)
            healthTrailing
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var healthTrailing: some View {
        if healthConnecting {
            ProgressView()
                .tint(Theme.glow)
        } else if healthConnected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.glow)
                .transition(.scale.combined(with: .opacity))
        } else {
            Text("Connect")
                .font(Theme.rounded(13, .bold))
                .foregroundStyle(Theme.forestDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.leafGradient, in: Capsule())
                .shadow(color: Theme.glow.opacity(0.35), radius: 6, y: 2)
        }
    }

    private func connectHealth() {
        healthConnecting = true
        Task {
            let ok = await HealthService.shared.requestAccess()
            withAnimation(Self.spring) {
                healthConnecting = false
                healthConnected = ok
                healthStatus = ok ? "Done. Your Garmin and Whoop workouts show up on the Track tab." : "Apple Health isn't available on this device."
            }
        }
    }

    // MARK: Data

    private var dataCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                exportRow
                divider
                row(symbol: "icloud.fill", tint: Theme.sky,
                    title: "Storage",
                    subtitle: "iPhone + private iCloud") {
                    Text(tripCountText)
                        .font(Theme.rounded(13, .bold))
                        .foregroundStyle(Theme.textDim)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    @ViewBuilder
    private var exportRow: some View {
        if let exportURL {
            ShareLink(item: exportURL) {
                row(symbol: "square.and.arrow.up", tint: Theme.leaf,
                    title: "Export my trips",
                    subtitle: "JSON file with routes and stats") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                .contentShape(Rectangle())
            }
            .pressable()
        } else {
            row(symbol: "square.and.arrow.up", tint: Theme.leaf,
                title: "Export my trips",
                subtitle: "Preparing your file…") {
                ProgressView().tint(Theme.glow)
            }
            .opacity(0.7)
        }
    }

    // MARK: About

    private var aboutCard: some View {
        GlassCard(padding: 0) {
            row(symbol: "info.circle.fill", tint: Theme.glow,
                title: "Version",
                subtitle: nil) {
                Text(versionString)
                    .font(Theme.rounded(14, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.leafGradient)
            Text(footerText)
                .font(Theme.rounded(12, .semibold))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
    }

    private var footerText: String {
        if let build = buildString, build != versionString {
            return "\(AppInfo.name) \(versionString) (\(build))"
        }
        return "\(AppInfo.name) \(versionString)"
    }

    // MARK: Building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.rounded(12, .bold))
            .tracking(1.4)
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 4)
            .padding(.top, 10)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Theme.rounded(12, .medium))
            .foregroundStyle(Theme.textDim.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 66)
    }

    private func row<Trailing: View>(symbol: String, tint: Color, title: String, subtitle: String?,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rounded(15, .bold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.rounded(12, .medium))
                        .foregroundStyle(Theme.textDim)
                        .contentTransition(.interpolate)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Export

    static func export(_ activities: [Activity]) -> URL? {
        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = activities.map { a in
            [
                "id": a.id.uuidString, "kind": a.kindRaw, "title": a.displayTitle,
                "start": iso.string(from: a.start), "end": iso.string(from: a.end),
                "distanceM": a.distanceM, "movingSec": a.movingSec, "elevGainM": a.elevGainM, "maxSpeedMps": a.maxSpeed,
                "startPlace": a.startPlace, "endPlace": a.endPlace, "notes": a.notes,
                "route": a.route.map { [$0.lat, $0.lng] },
            ]
        }
        let root: [String: Any] = ["exported": iso.string(from: Date()), "activities": rows]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Roamr-export.json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
