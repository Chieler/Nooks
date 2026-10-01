import AppKit
import SpaceBridge

final class MissionControl {
    func lists() -> [(CGDirectDisplayID, [AXUIElement])] {
        guard AX.trusted, let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let mission = AX.find(root, identifier: "mc", depth: 3) else { return [] }
        return AX.children(mission).compactMap { display in
            guard AX.value(display, "AXIdentifier") as? String == "mc.display",
                  let id = AX.value(display, "AXDisplayID") as? NSNumber,
                  let list = AX.find(display, identifier: "mc.spaces.list", depth: 3) else { return nil }
            return (id.uint32Value, AX.children(list))
        }
    }

    @discardableResult func open() -> Bool {
        guard lists().isEmpty else { return true }
        return SSToggleMissionControl()
    }

    func press(displayID: CGDirectDisplayID, index: Int) -> AXError? {
        guard let (_, buttons) = lists().first(where: { $0.0 == displayID }), buttons.indices.contains(index) else { return nil }
        return AXUIElementPerformAction(buttons[index], kAXPressAction as CFString)
    }

    func switchTo(_ desktop: Desktop, model: SpaceModel) {
        guard !model.busy else { return }
        guard AX.trusted else { model.message = "Enable Accessibility to switch Spaces."; return }
        guard model.revealAll() else { return }
        if desktop.isCurrent { model.message = "Already on \(model.name(desktop))."; return }
        model.busy = true
        guard open() else {
            model.busy = false
            model.message = "Mission Control's Dock notification is unavailable on this macOS build."
            return
        }
        attemptSwitch(desktop, model: model, remaining: 12)
    }

    private func attemptSwitch(_ desktop: Desktop, model: SpaceModel, remaining: Int) {
        // Mission Control exposes buttons before it accepts AXPress; Hammerspoon observes the same settling period.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak model] in
            guard let self, let model else { return }
            model.refreshSpaces()
            guard let live = model.desktops.first(where: { $0.id == desktop.id }) else {
                model.busy = false; model.message = "That Space no longer exists."; return
            }
            if self.press(displayID: live.displayID, index: live.index) == .success {
                // Button accepted the press; release the cooldown now and confirm only to update the status message.
                model.busy = false
                self.confirmSwitch(live, model: model, remaining: 12)
                return
            }
            if remaining > 1 { self.attemptSwitch(desktop, model: model, remaining: remaining - 1) }
            else {
                model.busy = false
                model.message = "Mission Control did not expose its desktop buttons. Select the Space manually."
            }
        }
    }

    private func confirmSwitch(_ desktop: Desktop, model: SpaceModel, remaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak model] in
            guard let self, let model else { return }
            model.refreshSpaces()
            if model.desktops.contains(where: { $0.id == desktop.id && $0.isCurrent }) {
                model.busy = false; model.message = "Switched to \(model.name(desktop))."
            } else if remaining > 1 {
                self.confirmSwitch(desktop, model: model, remaining: remaining - 1)
            } else {
                model.busy = false; model.message = "macOS did not confirm the Space switch."
            }
        }
    }

}
