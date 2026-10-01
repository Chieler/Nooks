import AppKit
import SpaceBridge

/// Runs in a child process so Accessibility can control these windows like real app windows.
func runTemporaryWindows() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let origin = NSScreen.screens.first?.frame.origin ?? .zero
    let windows = (0..<2).map { index -> NSWindow in
        let window = NSWindow(contentRect: CGRect(x: origin.x + 150 + CGFloat(index * 100), y: origin.y + 180 + CGFloat(index * 70), width: 420, height: 260),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Nooks temporary check \(index + 1)"
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }
    DispatchQueue.main.async {
        if let data = try? JSONEncoder().encode(windows.map { UInt32($0.windowNumber) }) {
            FileHandle.standardOutput.write(data + Data([10]))
        }
    }
    withExtendedLifetime(windows) { app.run() }
}

/// Moves only a child process's temporary windows, never the user's app windows.
func runDesktopCheck() -> Int32 {
    _ = NSApplication.shared
    guard AX.trusted else { print("FAIL: Accessibility permission is required for the desktop check."); return 1 }
    guard let executable = Bundle.main.executableURL, let screen = NSScreen.screens.first else {
        print("FAIL: No executable or display session."); return 1
    }
    let child = Process()
    child.executableURL = executable
    child.arguments = ["--test-windows"]
    let pipe = Pipe()
    child.standardOutput = pipe
    do { try child.run() } catch { print("FAIL: \(error.localizedDescription)"); return 1 }
    defer {
        if child.isRunning { child.terminate() }
        child.waitUntilExit()
    }
    let ready = pipe.fileHandleForReading.availableData
    guard let ids = try? JSONDecoder().decode([UInt32].self, from: ready), ids.count == 2 else {
        print("FAIL: Temporary-window helper did not start."); return 1
    }
    let root = AXUIElementCreateApplication(child.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 2)
    guard let elements = AX.value(root, kAXWindowsAttribute) as? [AXUIElement],
          let axA = elements.first(where: { SSWindowID($0) == ids[0] }),
          let axB = elements.first(where: { SSWindowID($0) == ids[1] }),
          let originalA = AX.frame(axA), let originalB = AX.frame(axB) else {
        print("FAIL: Could not identify the two temporary windows through Accessibility.")
        return 1
    }
    defer { _ = AX.restore(axA, frame: originalA); _ = AX.restore(axB, frame: originalB) }
    let screens = NSScreen.screens.map { Parking.axFrame($0.frame, primaryHeight: screen.frame.height) }
    guard let point = Parking.origin(for: originalA, screens: screens), AX.move(axA, to: point) else {
        print("FAIL: Temporary window did not accept the parking request."); return 1
    }
    guard let parked = AX.frame(axA), screens.allSatisfy({ Parking.intersectionArea(parked, $0) <= max(parked.width, parked.height) * 2 }),
          AX.frame(axB) == originalB else {
        print("FAIL: Parking did not hide one window independently of the other."); return 1
    }
    guard AX.restore(axA, frame: originalA), AX.frame(axB) == originalB else {
        print("FAIL: Temporary window did not return to its original position."); return 1
    }
    let spaces = SSCopyWindowSpaces(ids[0])
    guard !spaces.isEmpty, !SSCopyDisplays().isEmpty else { print("FAIL: Native Space discovery is unavailable."); return 1 }
    print("PASS: Window IDs, Space membership, independent offscreen parking, and original-position restoration.")
    return 0
}

func runMissionControlCheck() -> Int32 {
    _ = NSApplication.shared
    guard AX.trusted else { print("FAIL: Accessibility permission is required."); return 1 }
    func snapshot() -> [(UInt32, [AXUIElement])] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let mission = AX.find(root, identifier: "mc", depth: 3) else { return [] }
        return AX.children(mission).compactMap { display in
            guard let id = AX.value(display, "AXDisplayID") as? NSNumber,
                  let list = AX.find(display, identifier: "mc.spaces.list", depth: 3) else { return nil }
            return (id.uint32Value, AX.children(list))
        }
    }
    func waitForButtons() -> Int {
        for _ in 0..<15 {
            let count = snapshot().reduce(0) { $0 + $1.1.count }
            if count > 0 { return count }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return 0
    }
    func waitForClose() -> Bool {
        for _ in 0..<25 {
            if snapshot().isEmpty { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
    let mission = MissionControl()
    guard mission.open() else { print("FAIL: Mission Control's Dock notification is unavailable."); return 1 }
    let launched = waitForButtons()
    if launched > 0 {
        for (id, buttons) in snapshot() {
            let screenName = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }?.localizedName ?? "unmatched"
            print("AX display \(id) (\(screenName)): \(buttons.count) buttons")
            for (index, button) in buttons.enumerated() {
                var actions: CFArray?
                AXUIElementCopyActionNames(button, &actions)
                print("  \(index): \(AX.value(button, kAXDescriptionAttribute) as? String ?? "no description") · \((actions as? [String])?.joined(separator: ",") ?? "no actions")")
            }
        }
        guard let display = SSCopyDisplays().first(where: { (($0["Spaces"] as? [[String: Any]])?.count ?? 0) > 1 }),
              let identifier = display["Display Identifier"] as? String,
              let spaces = display["Spaces"] as? [[String: Any]],
              let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber,
              let originalIndex = spaces.firstIndex(where: { ($0["id64"] as? NSNumber) == current }),
              let targetIndex = spaces.indices.first(where: { $0 != originalIndex && (spaces[$0]["type"] as? NSNumber)?.intValue == 0 }),
              let target = spaces[targetIndex]["id64"] as? NSNumber,
              let displayID = displayID(for: identifier) else {
            _ = SSToggleMissionControl()
            print("PASS: Dock notification exposed \(launched) desktop buttons; switch check skipped (one usable Space).")
            return 0
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        guard mission.press(displayID: displayID, index: targetIndex) == .success,
              waitForSpace(target.uint64Value, display: identifier) else {
            if waitForButtons() > 0 { _ = SSToggleMissionControl() }
            print("FAIL: Desktop button press did not change the active Space.")
            return 1
        }
        guard waitForClose(), mission.open(), waitForButtons() > 0 else {
            print("FAIL: Could not reopen Mission Control to return to the original Space.")
            return 1
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        guard
              mission.press(displayID: displayID, index: originalIndex) == .success,
              waitForSpace(current.uint64Value, display: identifier) else {
            if waitForButtons() > 0 { _ = SSToggleMissionControl() }
            print("FAIL: Switched Spaces but could not return to the original Space.")
            return 1
        }
        print("PASS: Dock notification exposed \(launched) buttons, switched Spaces, and returned to the original Space.")
        return 0
    }
    print("FAIL: Dock notification exposed 0 desktop buttons.")
    return 1
}

private func displayID(for identifier: String) -> CGDirectDisplayID? {
    if identifier == "Main" { return CGMainDisplayID() }
    return NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String == identifier ? id : nil
    }.first
}

private func waitForSpace(_ target: UInt64, display identifier: String) -> Bool {
    for _ in 0..<25 {
        let current = SSCopyDisplays().first(where: { ($0["Display Identifier"] as? String) == identifier })?["Current Space"] as? [String: Any]
        if (current?["id64"] as? NSNumber)?.uint64Value == target { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return false
}
