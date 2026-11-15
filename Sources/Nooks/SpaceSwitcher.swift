import AppKit
import SpaceBridge

/// Custom borderless window subclass that permits becoming the key window.
/// In macOS AppKit, standard NSWindowStyleMaskBorderless windows return `canBecomeKey = false`.
/// Without `canBecomeKey = true`, WindowServer ignores `makeKeyAndOrderFront` and refuses
/// to switch Spaces when the application is activated.
final class SpaceSwitcherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Manages Space switching using SpaceJump's dual-engine architecture:
/// 1. Instant Engine: Synthetic multi-touch trackpad swipe events posted directly to
///    `kCGHIDEventTap` for adjacent desktop spaces (distance == 1).
/// 2. Verified Window Focus Engine: Lightweight hairline helper windows bound strictly
///    to specific space IDs (with `.fullScreenAuxiliary` collection behavior and pre-switch
///    auto-fixing) for long jumps, fullscreen spaces, or instant switch fallbacks.
final class SpaceSwitcher {
    static let shared = SpaceSwitcher()

    private var helperWindows: [UInt64: SpaceSwitcherWindow] = [:]
    private var dismissTasks: [UInt64: DispatchWorkItem] = [:]

    init() {}

    deinit {
        cleanup()
    }

    func cleanup() {
        for (_, task) in dismissTasks { task.cancel() }
        dismissTasks.removeAll()
        for (_, window) in helperWindows { window.close() }
        helperWindows.removeAll()
    }

    /// Synchronizes helper windows with the current list of desktops.
    func sync(with desktops: [Desktop]) {
        let validIDs = Set(desktops.filter { !$0.isFullscreen }.map(\.id))

        // Remove helper windows for spaces that no longer exist
        for (id, window) in helperWindows where !validIDs.contains(id) {
            dismissTasks[id]?.cancel()
            dismissTasks.removeValue(forKey: id)
            window.close()
            helperWindows.removeValue(forKey: id)
        }

        // Ensure each regular desktop space has a helper window bound to it
        for spaceID in validIDs {
            _ = ensureHelperWindow(for: spaceID)
        }
    }

    /// Ensures a 1x29 hairline helper window exists and is bound to `spaceID`.
    @discardableResult
    func ensureHelperWindow(for spaceID: UInt64) -> SpaceSwitcherWindow? {
        if let existing = helperWindows[spaceID] {
            fixPlacement(window: existing, expectedSpaceID: spaceID)
            return existing
        }

        // Window properties verified against SpaceJump (v3.0.3) disassembly:
        // - Frame: (80, 262, 1, 29) hairline within screen bounds so WindowServer treats it as active
        // - alphaValue: 0.01 (0.0 causes WindowServer to ignore activation transitions)
        // - collectionBehavior: .fullScreenAuxiliary (rawValue 256; NOT .transient which resets to active space)
        // - ignoresMouseEvents: true
        let window = SpaceSwitcherWindow(
            contentRect: NSRect(x: 80, y: 262, width: 1, height: 29),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenAuxiliary]

        let wid = UInt32(window.windowNumber)
        guard wid > 0 else {
            window.close()
            return nil
        }

        // Order back initially to establish SkyLight connection, bind to space, then order out
        window.orderBack(nil)
        helperWindows[spaceID] = window
        fixPlacement(window: window, expectedSpaceID: spaceID)
        window.orderOut(nil)
        return window
    }

    /// Verifies and enforces that the window belongs strictly and only to `expectedSpaceID`.
    func fixPlacement(window: SpaceSwitcherWindow, expectedSpaceID: UInt64) {
        let wid = UInt32(window.windowNumber)
        guard wid > 0 else { return }

        let currentSpaces = SSCopyWindowSpaces(wid)
        let spaceNums = currentSpaces.map(\.uint64Value)

        if spaceNums != [expectedSpaceID] {
            if !currentSpaces.isEmpty {
                SSRemoveWindowFromSpaces(wid, currentSpaces)
            }
            SSAddWindowToSpace(wid, expectedSpaceID)
        }
    }

    /// Switches directly to the given desktop.
    /// Uses synthetic trackpad swipes for distance == 1, and helper window focus for distance > 1 or fallback.
    @discardableResult
    func switchTo(desktop: Desktop, allDesktops: [Desktop] = []) -> Bool {
        // Fullscreen spaces: activate the owning application directly
        if desktop.isFullscreen {
            if let pid = desktop.pid, let app = NSRunningApplication(processIdentifier: pid) {
                return app.activate(options: .activateIgnoringOtherApps)
            }
            if let targetWindow = AX.windows().first(where: { $0.spaces.contains(desktop.id) }),
               let app = NSRunningApplication(processIdentifier: targetWindow.identity.pid) {
                return app.activate(options: .activateIgnoringOtherApps)
            }
            return false
        }

        // Query live display spaces to get the true, current physical order
        let displays = SSCopyDisplays()
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let cur = display["Current Space"] as? [String: Any]
            guard let curID = (cur?["id64"] as? NSNumber)?.uint64Value ?? (cur?["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }

            var curIndex: Int?
            var targetIndex: Int?
            for (idx, s) in spaces.enumerated() {
                guard let sid = (s["id64"] as? NSNumber)?.uint64Value ?? (s["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
                if sid == curID { curIndex = idx }
                if sid == desktop.id { targetIndex = idx }
            }

            if let curIdx = curIndex, let tgtIdx = targetIndex {
                let stepCount = abs(tgtIdx - curIdx)
                // For adjacent spaces (stepCount == 1), synthetic swipe triggers the native slide animation cleanly.
                if stepCount == 1 {
                    let isRight = tgtIdx > curIdx
                    _ = SSPostSyntheticSwipe(isRight)

                    // Scheduled verification check matching SpaceJump:
                    // If synthetic swipe didn't reach target within 0.35s, fall back to window focus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        let liveDisplays = SSCopyDisplays()
                        for d in liveDisplays {
                            let liveCur = d["Current Space"] as? [String: Any]
                            let liveCurID = (liveCur?["id64"] as? NSNumber)?.uint64Value ?? (liveCur?["ManagedSpaceID"] as? NSNumber)?.uint64Value
                            if liveCurID != desktop.id {
                                self?.performWindowFocusSwitch(to: desktop.id)
                            }
                        }
                    }
                    return true
                }
            }
        }

        // Window Focus Engine for distance > 1 or when instant swipe is not applicable
        return performWindowFocusSwitch(to: desktop.id)
    }

    /// Focuses the helper window for `spaceID` to trigger WindowServer transition.
    @discardableResult
    func performWindowFocusSwitch(to spaceID: UInt64) -> Bool {
        guard let window = ensureHelperWindow(for: spaceID) else {
            return false
        }

        dismissTasks[spaceID]?.cancel()

        // Strict pre-switch validation and placement fix
        fixPlacement(window: window, expectedSpaceID: spaceID)

        // Make window key and order front, and activate app to trigger space transition
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        NSApp.activate(ignoringOtherApps: true)

        // Dismiss helper window after transition engages
        let task = DispatchWorkItem { [weak window] in
            window?.orderOut(nil)
        }
        dismissTasks[spaceID] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)

        return true
    }

    /// Switches to the space containing `window` and brings that window to the front.
    @discardableResult
    func switchTo(window: ManagedWindow, desktops: [Desktop] = []) -> Bool {
        // If window is on a known space that isn't current, switch to that space first
        if let targetSpaceID = window.spaces.first {
            if let targetDesktop = desktops.first(where: { $0.id == targetSpaceID }), !targetDesktop.isCurrent {
                switchTo(desktop: targetDesktop, allDesktops: desktops)
            }
        }

        // Raise window via Accessibility
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)

        // Activate the application
        if let app = NSRunningApplication(processIdentifier: window.identity.pid) {
            return app.activate(options: .activateIgnoringOtherApps)
        }
        return true
    }
}
