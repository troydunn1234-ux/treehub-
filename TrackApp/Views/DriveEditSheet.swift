import SwiftUI
import MapKit

@MainActor
struct DriveEditSheet: View {
    @Bindable var activity: Activity
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    @State private var saveError: String?

    private var trimmed: TrimmedDrive? { DriveCorrection.trim(activity.route, start: start, end: end) }
    private var hasTimestampedGPS: Bool {
        let route = activity.route
        return route.count >= 2 && route.allSatisfy { $0.t.isFinite && $0.t > 0 }
    }
    private var valid: Bool { end > start }

    var body: some View {
        NavigationStack {
            Form {
                Section("Correct the drive times") {
                    DatePicker("Started", selection: $start)
                    DatePicker("Ended", selection: $end)
                    LabeledContent("Corrected duration", value: valid ? Format.duration(end.timeIntervalSince(start)) : "End must be after start")
                }

                Section("Route preview") {
                    if let trimmed, trimmed.route.count > 1 {
                        Map {
                            MapPolyline(coordinates: trimmed.route.map(\.coordinate))
                                .stroke(.blue, lineWidth: 5)
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        LabeledContent("Kept distance", value: Format.distance(trimmed.distanceM))
                        LabeledContent("Average speed", value: Format.speed(trimmed.averageSpeedMPS))
                        Text("The map and distance preview use GPS points between the corrected times, including interpolated points at the cut boundaries when available.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if hasTimestampedGPS {
                        Text("GPS points have timestamps, but fewer than two fall within these times. Saving will correct only the times; the existing route and distance will stay as recorded.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Label("This drive has no usable timestamped GPS points. You can correct its times, but the saved route and distance cannot be trimmed from this data.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!valid)
                }
            }
            .onAppear { start = activity.start; end = activity.end }
        }
    }

    private func save() {
        guard valid else { return }
        let old = (activity.start, activity.end, activity.routeData, activity.distanceM,
                   activity.movingSec, activity.elevGainM, activity.maxSpeed, activity.laneChangesData)
        activity.start = start
        activity.end = end
        activity.movingSec = end.timeIntervalSince(start)
        if let trimmed {
            activity.route = trimmed.route
            activity.distanceM = trimmed.distanceM
            activity.elevGainM = trimmed.elevationGainM
            activity.maxSpeed = trimmed.maxSpeedMPS
            activity.laneChanges = activity.laneChanges.filter { $0.t >= start.timeIntervalSince1970 && $0.t <= end.timeIntervalSince1970 }
        }
        do {
            try context.save()
            dismiss()
        } catch {
            activity.start = old.0; activity.end = old.1; activity.routeData = old.2
            activity.distanceM = old.3; activity.movingSec = old.4
            activity.elevGainM = old.5; activity.maxSpeed = old.6
            activity.laneChangesData = old.7
            saveError = "The drive could not be saved. Your original trip details have been restored. Please try again."
        }
    }
}
