import AppKit
import SwiftUI
import SpaceBridge

final class MissionControlOverlayState: ObservableObject {
    @Published var items: [MissionControlLabelItem] = []
}

struct MissionControlLabelItem: Identifiable {
    let id: String
    let name: String
    let color: NSColor
    let position: CGPoint
}

final class MissionControlOverlay {
    private let model: SpaceModel
    private let mission: MissionControl
    private let panel: NSPanel
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private let state = MissionControlOverlayState()

    init(model: SpaceModel, mission: MissionControl) {
        self.model = model
        self.mission = mission
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: MissionControlOverlayView(state: state))
    }

    func start() {
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hideImmediately()
        })

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return }
            if event.keyCode == 53 {
                self.hideImmediately()
            }
        }
    }

    func hideImmediately() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
        if !state.items.isEmpty {
            state.items = []
        }
    }

    private func update() {
        guard AX.trusted else {
            hideImmediately()
            return
        }
        let lists = mission.lists()
        guard !lists.isEmpty else {
            hideImmediately()
            return
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let unionFrame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        var newItems: [MissionControlLabelItem] = []

        for (displayID, buttons) in lists {
            let displayDesktops = model.desktops.filter { $0.displayID == displayID }
            for (index, button) in buttons.enumerated() {
                var axRect: CGRect?
                if let val = AX.value(button, "AXFrame") {
                    var r = CGRect.zero
                    if CFGetTypeID(val) == AXValueGetTypeID(), AXValueGetValue(val as! AXValue, .cgRect, &r) {
                        axRect = r
                    }
                }
                if axRect == nil { axRect = AX.frame(button) }
                guard let axRect, axRect.width > 20, axRect.height > 10 else { continue }
                let appKitFrame = Parking.axFrame(axRect, primaryHeight: primaryHeight)

                let desktop = displayDesktops.first(where: { $0.index == index })
                    ?? model.desktops.first(where: { $0.index == index })
                let desktopNumber = desktop?.number ?? (index + 1)
                let name = desktop.map { model.name($0) } ?? "Desktop \(desktopNumber)"
                let color = SpaceTint.color(for: desktopNumber)

                let centerX = appKitFrame.midX
                let centerY = appKitFrame.height >= 45 ? (appKitFrame.minY - 14) : appKitFrame.midY

                // macOS draws the desktop name centered above each thumbnail. Place the color bar just left of that native caption.
                let captionWidth = CGFloat(name.count) * 7.2 + 16
                let barX = centerX - captionWidth / 2 - 8

                // Convert AppKit coordinates to SwiftUI ZStack position relative to unionFrame
                let swiftUiX = barX - unionFrame.minX
                let swiftUiY = (unionFrame.origin.y + unionFrame.height) - centerY

                newItems.append(MissionControlLabelItem(
                    id: "\(displayID):\(index)",
                    name: name,
                    color: color,
                    position: CGPoint(x: swiftUiX, y: swiftUiY)
                ))
            }
        }

        guard !newItems.isEmpty else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

        if panel.frame != unionFrame {
            panel.setFrame(unionFrame, display: false)
        }
        state.items = newItems
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}

private struct MissionControlOverlayView: View {
    @ObservedObject var state: MissionControlOverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(state.items) { item in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: item.color))
                    .frame(width: 6, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .position(item.position)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
