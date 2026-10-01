import AppKit
import SwiftUI
import SpaceBridge

@main
enum NooksApp {
    static func main() {
        if CommandLine.arguments.contains("--test-windows") {
            runTemporaryWindows()
            return
        }
        if CommandLine.arguments.contains("--self-check") {
            exit(runDesktopCheck())
        }
        if CommandLine.arguments.contains("--mission-check") {
            exit(runMissionControlCheck())
        }
        if CommandLine.arguments.contains("--diagnose") {
            let output: [String: Any] = [
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "accessibility": AX.trusted,
                "managedDisplays": SSCopyDisplays()
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: SpaceModel!
    private let mission = MissionControl()
    private var item: NSStatusItem!
    private var window: NSWindow!
    private var hoverSwitcher: HoverSwitcher!
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.nooks.app").count > 1 {
            NSApplication.shared.terminate(nil)
            return
        }
        model = SpaceModel()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = NSMenu()
        item.menu?.delegate = self
        model.menuChanged = { [weak self] in self?.updateTitle() }
        updateTitle()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Nooks"
        window.minSize = NSSize(width: 620, height: 360)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(srgbRed: 0.031, green: 0.024, blue: 0.071, alpha: 1)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.managed)
        window.contentView = NSHostingView(rootView: ContentView(model: model, mission: mission))
        window.center()
        hoverSwitcher = HoverSwitcher(model: model, mission: mission)
        hoverSwitcher.start()
        installMainMenu()
        showWindow()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Changing native Spaces ends the emulation trial so hidden windows remain recoverable.
            if !self.model.parked.isEmpty { _ = self.model.revealAll() }
            self.model.refreshSpaces()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
            self.model.refresh()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !self.model.parked.isEmpty { _ = self.model.revealAll() }
            self.model.refresh()
        })
    }

    private func updateTitle() {
        let title = model.activeWorkspace.map { "◫ \($0)" }
            ?? model.desktops.filter(\.isCurrent).map { model.name($0) }.joined(separator: " · ")
        item.button?.title = String((title.isEmpty ? "Nooks" : title).prefix(44))
        item.button?.toolTip = "Nooks — \(title)"
        // Color bar for the current desktop, next to the name. Hidden while a workspace is active.
        if model.activeWorkspace == nil, let current = model.desktops.first(where: \.isCurrent) {
            item.button?.image = barImage(number: current.number)
            item.button?.imagePosition = .imageLeading
        } else {
            item.button?.image = nil
        }
    }

    private func barImage(number: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 6, height: 13), flipped: false) { rect in
            SpaceTint.color(for: number).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard model != nil else { return }
        menu.removeAllItems()
        menu.minimumWidth = 180
        for desktop in model.desktops {
            let entry = add(model.name(desktop), action: #selector(switchSpace(_:)), to: menu)
            entry.image = badgeImage(number: desktop.number)
            entry.representedObject = NSNumber(value: desktop.id)
            entry.state = desktop.isCurrent ? .on : .off
            entry.isEnabled = !model.busy
        }
        if !model.workspaces.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for workspace in model.workspaces {
            let entry = add(workspace, action: #selector(switchWorkspace(_:)), to: menu)
            entry.representedObject = workspace
            entry.state = model.activeWorkspace == workspace ? .on : .off
            entry.isEnabled = !model.busy
        }
        menu.addItem(.separator())
        add("Open Nooks…", action: #selector(showWindow), to: menu)
        add("Quit Nooks", action: #selector(quit), to: menu)
    }

    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    private func badgeImage(number: Int) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            SpaceTint.color(for: number).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            return true
        }
    }

    private func installMainMenu() {
        let bar = NSMenu()
        let app = NSMenuItem()
        bar.addItem(app)
        app.submenu = NSMenu()
        add("Open Nooks", action: #selector(showWindow), to: app.submenu!)
        let restore = add("Restore all parked windows", action: #selector(restoreAll), to: app.submenu!)
        restore.keyEquivalent = "r"
        restore.keyEquivalentModifierMask = [.command, .shift]
        add("Quit Nooks", action: #selector(quit), to: app.submenu!).keyEquivalent = "q"
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "Edit")
        bar.addItem(edit)
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApplication.shared.mainMenu = bar
    }

    @objc private func showWindow() {
        guard window != nil else { return }
        model.refresh()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func restoreAll() { _ = model.revealAll() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func switchSpace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSNumber, let desktop = model.desktops.first(where: { $0.id == id.uint64Value }) else { return }
        mission.switchTo(desktop, model: model)
    }
    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        model.toggleWorkspace(name)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        guard model.revealAll() else {
            let alert = NSAlert()
            alert.messageText = "Some windows still need restoring"
            alert.informativeText = model.message + " Nooks will stay open so you can retry Restore all."
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}

final class IslandState: ObservableObject {
    @Published var isPresented = false
}

private final class HoverSwitcher {
    private let model: SpaceModel
    private let panel: NSPanel
    private var timer: Timer?
    private var hideAfter: Date?
    private var animationID = 0
    private var expanded = false
    private let state = IslandState()

    init(model: SpaceModel, mission: MissionControl) {
        self.model = model
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: IslandSwitcher(model: model, state: state, mission: mission) { [weak self] in
            self?.hide()
        })
    }

    func start() {
        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func update() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            point.x >= $0.frame.minX && point.x <= $0.frame.maxX &&
            point.y >= $0.frame.minY && point.y <= $0.frame.maxY + 10
        }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let islandWidth = max(160, (screen.auxiliaryTopRightArea?.minX ?? 0) - (screen.auxiliaryTopLeftArea?.maxX ?? 0))
        let islandHeight = max(32, screen.safeAreaInsets.top)
        let hotspotWidth = max(210, islandWidth + 26)
        let hotspotHeight = islandHeight + 2
        let hotspot = NSRect(x: screen.frame.midX - hotspotWidth / 2,
                             y: screen.frame.maxY - hotspotHeight,
                             width: hotspotWidth,
                             height: hotspotHeight + 25)

        if hotspot.contains(point) {
            show(on: screen)
            hideAfter = nil
        } else if panel.isVisible && panel.frame.insetBy(dx: -10, dy: -6).contains(point) {
            hideAfter = nil
        } else if panel.isVisible {
            if hideAfter == nil { hideAfter = Date().addingTimeInterval(0.05) }
            if hideAfter! <= Date() {
                hide()
                hideAfter = nil
            }
        }
    }

    private func show(on screen: NSScreen) {
        guard !expanded else { return }
        expanded = true
        let islandWidth = max(160, (screen.auxiliaryTopRightArea?.minX ?? 0) - (screen.auxiliaryTopLeftArea?.maxX ?? 0))
        let islandHeight = max(32, screen.safeAreaInsets.top)
        let width = max(islandWidth + 36, CGFloat(model.desktops.count) * 47 + 26)
        let height = islandHeight + 55
        let targetX = screen.frame.midX - width / 2
        let frame = NSRect(x: targetX, y: screen.frame.maxY - height, width: width, height: height + 3)
        animationID += 1
        panel.setFrame(frame, display: false)
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            state.isPresented = true
        }
    }

    private func hide() {
        guard panel.isVisible, expanded else { return }
        expanded = false
        animationID += 1
        let id = animationID
        withAnimation(.easeOut(duration: 0.12)) {
            state.isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, self.animationID == id, !self.expanded else { return }
            self.panel.orderOut(nil)
        }
    }
}

private struct IslandSwitcher: View {
    @ObservedObject var model: SpaceModel
    @ObservedObject var state: IslandState
    let mission: MissionControl
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            HStack(spacing: 5) {
                ForEach(model.desktops) { desktop in
                    Button {
                        dismiss()
                        mission.switchTo(desktop, model: model)
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(desktop.number)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(width: 34, height: 34)
                                .background(Color(nsColor: SpaceTint.color(for: desktop.number)).opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                                .overlay {
                                    if desktop.isCurrent {
                                        RoundedRectangle(cornerRadius: 9).stroke(.white, lineWidth: 2)
                                    }
                                }
                            Text(model.name(desktop))
                                .font(.system(size: 10, weight: desktop.isCurrent ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(width: 42)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy || desktop.isFullscreen)
                    .accessibilityLabel("Switch to \(model.name(desktop))")
                }
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            IslandCardShape(bottomRadius: 18)
                .fill(Color.black.opacity(0.92))
                .shadow(color: .black.opacity(state.isPresented ? 0.35 : 0), radius: 10, x: 0, y: 6)
        )
        .offset(y: state.isPresented ? 0 : -95)
        .opacity(state.isPresented ? 1 : 0)
        .preferredColorScheme(.dark)
    }
}

private struct IslandCardShape: Shape {
    var bottomRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(bottomRadius, min(rect.width / 2, rect.height))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r,
                    startAngle: .degrees(0),
                    endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                    radius: r,
                    startAngle: .degrees(90),
                    endAngle: .degrees(180),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

private enum Palette {
    static let ink = Color(red: 0.043, green: 0.039, blue: 0.094)
    static let accent = Color(red: 0.58, green: 0.55, blue: 1.0)
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.6)
    static let surface = Color.white.opacity(0.055)
    static let line = Color.white.opacity(0.09)
}

private let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

struct ContentView: View {
    @ObservedObject var model: SpaceModel
    let mission: MissionControl
    @State private var tab = 0

    var body: some View {
        Group {
            if model.hasAccess { main } else { AccessGate() }
        }
        .frame(minWidth: 620, minHeight: 360)
        .background(
            Palette.ink.ignoresSafeArea()
        )
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        // Poll while waiting for the grant so the gate closes the moment it is switched on.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if !model.hasAccess { model.refresh() }
        }
        .onChange(of: model.hasAccess) { granted in
            if granted { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
    }

    private var main: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1).ignoresSafeArea()
            Group { if tab == 0 { spacesView } else { workspacesView } }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .bottomLeading) { status }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nooks").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10).padding(.bottom, 14)
            navItem("Spaces", icon: "square.grid.2x2", tag: 0)
            navItem("Workspaces", icon: "macwindow.on.rectangle", tag: 1)
            Spacer()
            Button(action: model.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise").font(.system(size: 12))
                    .foregroundStyle(Palette.muted).padding(.horizontal, 10).padding(.vertical, 6)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 14)
        .frame(width: 168).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.18).ignoresSafeArea())
    }

    private func navItem(_ title: String, icon: String, tag: Int) -> some View {
        Button {
            guard tab != tag else { return }
            _ = model.revealAll()
            tab = tag
        } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: tab == tag ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(tab == tag ? Palette.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(tab == tag ? Palette.text : Palette.muted)
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var status: some View {
        if model.busy || !model.message.isEmpty {
            HStack(spacing: 6) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.message).font(.caption).foregroundStyle(Palette.muted).lineLimit(2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(14)
        }
    }

    private var spacesView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                ForEach(model.desktops) { desktop in
                    HStack(spacing: 10) {
                        SpaceBadge(number: desktop.number)
                        TextField(desktop.fallbackName, text: Binding(get: { model.names[desktop.uuid] ?? "" }, set: { model.rename(desktop, to: $0) }))
                            .textFieldStyle(.plain).font(.system(size: 13))
                            .accessibilityLabel("Name for \(desktop.fallbackName)")
                            .disabled(desktop.uuid.isEmpty)
                        if desktop.isCurrent {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent).accessibilityLabel("Current desktop")
                        } else {
                            Button("Switch") { mission.switchTo(desktop, model: model) }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                                .disabled(model.busy)
                        }
                    }
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(desktop.isCurrent ? Palette.accent.opacity(0.6) : Palette.line, lineWidth: 1))
                }
            }
            if model.desktops.isEmpty { Text("Desktops unavailable on this macOS build.").foregroundStyle(Palette.muted).padding() }
        }
    }

    private var workspacesView: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                WorkspaceField(model: model)
                if model.workspaces.isEmpty {
                    Text("No workspaces yet. Name one, then pick it for the windows you want in it.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 4) { ForEach(model.workspaces, id: \.self) { WorkspaceRow(name: $0, model: model) } }
                    }
                }
                Spacer(minLength: 0)
            }.frame(width: 190)
            windowList
        }
    }

    private var windowList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.windows) { window in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.app).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(window.title.isEmpty ? "Untitled" : String(window.title.prefix(28)) + (window.title.count > 28 ? "…" : ""))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).help(window.title)
                        }
                        Spacer(minLength: 8)
                        if model.parked[window.id] != nil { Image(systemName: "eye.slash").foregroundStyle(Palette.muted).help("Hidden") }
                        Picker("Workspace for \(window.app): \(window.title)", selection: Binding(get: { model.assignments[window.id] ?? "" }, set: { model.assign(window, to: $0.isEmpty ? nil : $0) })) {
                            Text("None").tag("")
                            ForEach(model.workspaces, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 104).disabled(window.isFullscreen || model.busy || model.workspaces.isEmpty)
                    }.padding(.vertical, 8)
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                if model.windows.isEmpty { Text("No windows found.").foregroundStyle(Palette.muted).padding(.vertical, 24) }
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct AccessGate: View {
    var body: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "hand.raised.fill").font(.system(size: 26)).foregroundStyle(Palette.accent)
                Text("Allow Accessibility").font(.system(size: 24, weight: .semibold))
                Text("Nooks needs it to read window titles and switch desktops.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Button {
                    AX.requestAccess()
                    NSWorkspace.shared.open(accessibilityPane)
                } label: {
                    Text("Open Accessibility Settings").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.top, 6)
            }.frame(maxWidth: 270, alignment: .leading)
            VStack(alignment: .leading, spacing: 16) {
                step(1, "Open Accessibility Settings with the button.")
                step(2, "Switch on Nooks in the list.")
                step(3, "Come back. This screen closes by itself.")
                Text("Already listed but still asking? Select Nooks, click −, then add it again.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            .padding(20).frame(maxWidth: 270, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Palette.accent)
                .frame(width: 20, height: 20).background(Palette.accent.opacity(0.18), in: Circle())
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WorkspaceField: View {
    @ObservedObject var model: SpaceModel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
            TextField("New workspace", text: $text).textFieldStyle(.plain).font(.system(size: 13))
                .onSubmit { model.addWorkspace(text); text = "" }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
    }
}

private struct WorkspaceRow: View {
    let name: String
    @ObservedObject var model: SpaceModel
    @State private var hovering = false

    var body: some View {
        let active = model.activeWorkspace == name
        HStack(spacing: 8) {
            Button { model.toggleWorkspace(name) } label: {
                HStack(spacing: 8) {
                    Image(systemName: active ? "checkmark.circle.fill" : "circle").foregroundStyle(active ? Palette.accent : Palette.muted)
                    Text(name).font(.system(size: 13, weight: active ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy)
            if hovering {
                Button { model.deleteWorkspace(name) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Delete \(name)").accessibilityLabel("Delete \(name)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(active ? Palette.accent.opacity(0.18) : (hovering ? Palette.surface : .clear), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .contextMenu { Button("Delete", role: .destructive) { model.deleteWorkspace(name) } }
        .accessibilityElement(children: .combine).accessibilityValue(active ? "selected" : "")
    }
}

private struct SpaceBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color(nsColor: SpaceTint.color(for: number)), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("Desktop \(number)")
    }
}
