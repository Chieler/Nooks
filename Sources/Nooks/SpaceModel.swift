import AppKit
import SpaceBridge

final class SpaceModel: ObservableObject {
    @Published var desktops: [Desktop] = []
    @Published var windows: [ManagedWindow] = []
    @Published var names = UserDefaults.standard.dictionary(forKey: "spaceNames") as? [String: String] ?? [:]
    @Published var workspaces = UserDefaults.standard.stringArray(forKey: "workspaces") ?? []
    @Published var assignments: [String: String] = [:]
    @Published var activeWorkspace: String?
    @Published var message = ""
    @Published var hasAccess = AX.trusted
    @Published var busy = false
    @Published var parked: [String: ParkedWindow] = [:]
    private let journal: URL
    private var recoveryReadable = true
    var menuChanged: (() -> Void)?

    init() {
        journal = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nooks/recovery.json")
        if FileManager.default.fileExists(atPath: journal.path) {
            do { parked = try JSONDecoder().decode([String: ParkedWindow].self, from: Data(contentsOf: journal)) }
            catch { recoveryReadable = false; message = "Cannot read recovery positions: \(error.localizedDescription)" }
        }
        refresh()
        if !parked.isEmpty { _ = revealAll() }
    }

    func name(_ desktop: Desktop) -> String { names[desktop.uuid] ?? desktop.fallbackName }

    func rename(_ desktop: Desktop, to text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desktop.uuid.isEmpty else { message = "This Space has no persistent UUID; naming is unavailable."; return }
        names[desktop.uuid] = name.isEmpty ? nil : String(name.prefix(80))
        UserDefaults.standard.set(names, forKey: "spaceNames")
        menuChanged?()
    }

    func refresh() {
        hasAccess = AX.trusted
        refreshSpaces()
        windows = AX.windows()
    }

    func refreshSpaces() {
        var result: [Desktop] = []
        var number = 0
        for display in SSCopyDisplays() {
            let identifier = display["Display Identifier"] as? String ?? "Main"
            let screen = NSScreen.screens.first { screen in
                if identifier == "Main" { return screen == NSScreen.screens.first }
                let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
                return CFUUIDCreateString(nil, uuid) as String == identifier
            }
            let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            // CGSManagedDisplaySetCurrentSpace needs a real display UUID string; resolve the "Main" fallback from the display ID.
            var resolvedIdentifier = identifier
            if identifier == "Main", displayID != 0, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                resolvedIdentifier = CFUUIDCreateString(nil, uuid) as String
            }
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            for (index, space) in ((display["Spaces"] as? [[String: Any]]) ?? []).enumerated() {
                guard let id = space["id64"] as? NSNumber else { continue }
                number += 1
                result.append(Desktop(id: id.uint64Value, uuid: space["uuid"] as? String ?? "", display: screen?.localizedName ?? identifier,
                                      displayIdentifier: resolvedIdentifier,
                                      displayID: displayID, index: index, number: number, isCurrent: current == id,
                                      isFullscreen: (space["type"] as? NSNumber)?.intValue != 0))
            }
        }
        desktops = result
        menuChanged?()
    }

    func addWorkspace(_ text: String) {
        let name = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty, !workspaces.contains(name) else { return }
        workspaces.append(name)
        UserDefaults.standard.set(workspaces, forKey: "workspaces")
        menuChanged?()
    }

    func deleteWorkspace(_ name: String) {
        guard !busy, workspaces.contains(name) else { return }
        if activeWorkspace == name || parked.keys.contains(where: { assignments[$0] == name }) { guard revealAll() else { return } }
        workspaces.removeAll { $0 == name }
        assignments = assignments.filter { $0.value != name }
        UserDefaults.standard.set(workspaces, forKey: "workspaces")
        message = ""
        menuChanged?()
    }

    func assign(_ window: ManagedWindow, to workspace: String?) {
        guard !busy else { return }
        if parked[window.id] != nil, !restoreOne(window.id) { return }
        assignments[window.id] = workspace
        if let activeWorkspace { activateWorkspace(activeWorkspace) }
    }

    private func saveRecovery() -> Bool {
        guard recoveryReadable else { message = "Resolve the unreadable recovery file before parking windows: \(journal.path)"; return false }
        do {
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(parked).write(to: journal, options: .atomic)
            return true
        } catch {
            message = "Could not save recovery positions. \(error.localizedDescription)"
            return false
        }
    }

    private func restoreOne(_ key: String) -> Bool {
        guard let record = parked[key] else { return true }
        guard AX.trusted else { message = "Enable Accessibility to restore parked windows."; return false }
        let app = NSRunningApplication(processIdentifier: record.identity.pid)
        if app == nil || app?.launchDate != record.identity.launched {
            parked.removeValue(forKey: key)
            return saveRecovery()
        }
        // Look up even minimized windows: closing/minimizing a parked window must not strand recovery.
        let root = AXUIElementCreateApplication(record.identity.pid)
        AXUIElementSetMessagingTimeout(root, 0.3)
        guard let raw = AX.value(root, kAXWindowsAttribute) as? [AXUIElement] else {
            message = "An app is not responding. Recovery positions are retained; try Restore all again."
            return false
        }
        if let element = raw.first(where: { SSWindowID($0) == record.identity.id }) {
            let frame = Parking.recoveredFrame(record.frame, screens: AX.screens)
            guard AX.restore(element, frame: frame) else {
                message = "A window could not be restored. Its recovery position is retained; try Restore all again."
                return false
            }
        }
        parked.removeValue(forKey: key)
        return saveRecovery()
    }

    @discardableResult func revealAll() -> Bool {
        var success = true
        for key in Array(parked.keys) { if !restoreOne(key) { success = false } }
        if success {
            activeWorkspace = nil
            message = ""
        }
        refresh()
        return success
    }

    func activateWorkspace(_ name: String) {
        guard !busy, workspaces.contains(name) else { return }
        guard AX.trusted else { message = "Enable Accessibility first."; return }
        guard recoveryReadable else { message = "The recovery file is unreadable. Window parking is disabled."; return }
        refresh()
        let currentSpaces = Set(desktops.filter(\.isCurrent).map(\.id))
        // Only windows on the current desktop can be parked; others are left alone.
        let onScreen = windows.filter { !$0.isFullscreen && $0.spaces.count == 1 && currentSpaces.isSuperset(of: $0.spaces) }
        for key in Array(parked.keys) where assignments[key] == name {
            guard restoreOne(key) else { return }
        }
        let physicalScreens = NSScreen.screens.map { Parking.axFrame($0.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0) }
        let toHide = onScreen.filter { assignments[$0.id] != name && parked[$0.id] == nil }
        var plans: [(ManagedWindow, CGPoint)] = []
        for window in toHide {
            guard let point = Parking.origin(for: window.frame, screens: physicalScreens) else {
                message = "No exposed screen corner for \(window.app). Restore all or rearrange displays before switching."
                return
            }
            plans.append((window, point))
        }
        let previousRecords = parked
        for (window, _) in plans { parked[window.id] = ParkedWindow(identity: window.identity, frame: window.frame) }
        guard saveRecovery() else { parked = previousRecords; return }
        for (window, point) in plans {
            let moved = AX.move(window.element, to: point)
            let actual = AX.frame(window.element)
            let hidden = actual.map { frame in
                physicalScreens.allSatisfy { Parking.intersectionArea(frame, $0) <= max(frame.width, frame.height) * 2 }
            } ?? false
            guard moved && hidden else {
                let restored = revealAll()
                message = "\(window.app) refused offscreen parking. \(restored ? "Windows restored." : "Use Restore all to retry recovery.")"
                return
            }
        }
        activeWorkspace = name
        message = ""
        refresh()
    }

    func toggleWorkspace(_ name: String) {
        if activeWorkspace == name { revealAll() } else { activateWorkspace(name) }
    }

    func clearAssignments() {
        guard revealAll() else { return }
        assignments.removeAll()
        message = "Assignments cleared."
    }

}
