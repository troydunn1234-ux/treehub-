import CarPlay
import UIKit
import SwiftUI

// CarPlay dashboard for drives (driving-task category).
//
// CarPlay only ever connects this scene once Apple grants the app the
// com.apple.developer.carplay-driving-task entitlement. Until then the scene configuration in
// Info.plist is simply never used, so the app builds and runs exactly the same without it.
// See store/roamr/CARPLAY_REQUEST.md.
//
// Templates: a tab bar with
//   • Drive — an information template: current speed, trip time, trip distance, Start/Stop drive.
//   • Go Together — a list of the friends in your group with their speed and how far away they are.

@objc(RoamrCarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var timer: Timer?
    private var driveTemplate: CPInformationTemplate?
    private var friendsTemplate: CPListTemplate?
    private var lastKey = ""

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            self.interfaceController = interfaceController
            let drive = CPInformationTemplate(title: "Roamr", layout: .twoColumn, items: [], actions: [])
            drive.tabTitle = String(localized: "Drive")
            drive.tabImage = UIImage(systemName: "car.fill")
            let friends = CPListTemplate(title: String(localized: "Go Together"), sections: [])
            friends.tabTitle = String(localized: "Go Together")
            friends.tabImage = UIImage(systemName: "person.2.fill")
            friends.emptyViewTitleVariants = [String(localized: "No group yet")]
            friends.emptyViewSubtitleVariants = [String(localized: "Start or join a Go Together trip on your iPhone.")]
            driveTemplate = drive
            friendsTemplate = friends
            let tabs = CPTabBarTemplate(templates: [drive, friends])
            interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
            refresh(force: true)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(force: false) }
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            timer?.invalidate()
            timer = nil
            self.interfaceController = nil
            driveTemplate = nil
            friendsTemplate = nil
        }
    }

    @MainActor
    private func refresh(force: Bool) {
        guard let driveTemplate, let friendsTemplate else { return }
        let tracker = RoamrContext.tracker
        let active = tracker?.isActive ?? false
        let speed = Format.speed(max(0, tracker?.currentSpeed ?? 0))
        let time = Format.duration(active ? (tracker?.elapsed ?? 0) : 0)
        let dist = Format.distance(active ? (tracker?.distance ?? 0) : 0)

        let group = GroupSession.shared
        let riders = group.riders.filter { !$0.isStale() }
        let riderKey = riders.map { "\($0.id)|\(Int($0.speed))|\(group.relation(to: $0))" }.joined(separator: ",")
        let key = "\(active)|\(speed)|\(time)|\(dist)|\(riderKey)"
        guard force || key != lastKey else { return }
        lastKey = key

        var items = [
            CPInformationItem(title: String(localized: "Speed"), detail: speed),
            CPInformationItem(title: String(localized: "Time"), detail: time),
            CPInformationItem(title: String(localized: "Distance"), detail: dist),
        ]
        if !riders.isEmpty {
            items.append(CPInformationItem(title: String(localized: "Go Together"),
                                           detail: String(localized: "\(riders.count) friends")))
        }
        driveTemplate.items = items

        let button: CPTextButton
        if active {
            button = CPTextButton(title: String(localized: "Stop drive"), textStyle: .cancel) { _ in
                MainActor.assumeIsolated { _ = RoamrContext.finishAndSave() }
            }
        } else {
            button = CPTextButton(title: String(localized: "Start drive"), textStyle: .confirm) { [weak self] _ in
                MainActor.assumeIsolated {
                    if !RoamrContext.start(.drive) { self?.showNeedsPhone() }
                }
            }
        }
        driveTemplate.actions = [button]

        let rows: [CPListItem] = riders.map { r in
            let detail = "\(Format.speed(max(0, r.speed))) · \(group.relation(to: r))"
            let item = CPListItem(text: r.name, detailText: detail,
                                  image: UIImage(systemName: r.kind.symbol)?.withTintColor(UIColor(r.color), renderingMode: .alwaysOriginal))
            item.handler = { _, completion in completion() }
            return item
        }
        friendsTemplate.updateSections(rows.isEmpty ? [] : [CPListSection(items: rows)])
    }

    @MainActor
    private func showNeedsPhone() {
        let ok = CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [String(localized: "Open Roamr on your iPhone and allow location first.")],
                                    actions: [ok])
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }
}
