import AppKit
import SpaceBridge

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func find(_ element: AXUIElement, identifier: String, depth: Int = 8) -> AXUIElement? {
        if value(element, "AXIdentifier") as? String == identifier { return element }
        guard depth > 0 else { return nil }
        for child in children(element) {
            if let result = find(child, identifier: identifier, depth: depth - 1) { return result }
        }
        return nil
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult static func move(_ element: AXUIElement, to point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    static func restore(_ element: AXUIElement, frame: CGRect) -> Bool {
        var size = frame.size
        if let value = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
        guard move(element, to: frame.origin), let actual = self.frame(element) else { return false }
        return abs(actual.minX - frame.minX) < 5 && abs(actual.minY - frame.minY) < 5
    }

    static func windows() -> [ManagedWindow] {
        guard trusted else { return [] }
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.flatMap { app -> [ManagedWindow] in
            guard let launched = app.launchDate else { return [] }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.2)
            let windows = value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
            return windows.compactMap { window in
                let id = SSWindowID(window)
                guard id != 0, let frame = frame(window), frame.width > 60, frame.height > 40,
                      value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      value(window, kAXMinimizedAttribute) as? Bool != true else { return nil }
                return ManagedWindow(identity: WindowIdentity(pid: app.processIdentifier, id: id, launched: launched),
                                     element: window, app: app.localizedName ?? "App",
                                     title: value(window, kAXTitleAttribute) as? String ?? "Untitled",
                                     frame: frame, spaces: SSCopyWindowSpaces(id).map(\.uint64Value),
                                     isFullscreen: value(window, "AXFullScreen") as? Bool == true)
            }
        }.sorted { ($0.app, $0.title) < ($1.app, $1.title) }
    }

    static var screens: [CGRect] {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { Parking.axFrame($0.visibleFrame, primaryHeight: height) }
    }
}
