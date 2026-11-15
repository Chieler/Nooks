import AppKit
import XCTest
@testable import Nooks

final class IslandWakeTests: XCTestCase {
    func testWakeOrdersOutAnIslandThatStillReportsVisible() {
        assertWakeOrdersOutPanel(NSWorkspace.didWakeNotification)
    }

    func testScreenWakeOrdersOutAnIslandThatStillReportsVisible() {
        assertWakeOrdersOutPanel(NSWorkspace.screensDidWakeNotification)
    }

    func testWillSleepOrdersOutPanelAndCallsOnSleep() {
        let center = NotificationCenter()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)

        var sleepCalled = false
        let recovery = IslandWakeRecovery(panel: panel, notificationCenter: center, onSleep: {
            sleepCalled = true
        })
        withExtendedLifetime(recovery) {
            center.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
            XCTAssertFalse(panel.isVisible, "Panel should be ordered out when system prepares to sleep")
            XCTAssertTrue(sleepCalled, "onSleep callback must be invoked")
        }
    }

    func testScreenParametersChangedOrdersOutPanelAndCallsOnWake() {
        let appCenter = NotificationCenter()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)

        var wakeCalled = false
        let recovery = IslandWakeRecovery(panel: panel, appNotificationCenter: appCenter, onWake: {
            wakeCalled = true
        })
        withExtendedLifetime(recovery) {
            appCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApplication.shared)
            XCTAssertFalse(panel.isVisible, "Panel should be ordered out when screen parameters change")
            XCTAssertTrue(wakeCalled, "onWake callback must be invoked")
        }
    }

    func testHoverSwitcherResetsPresentationStateOnWake() {
        let model = SpaceModel()
        let mission = MissionControl()
        let switcher = HoverSwitcher(model: model, mission: mission)

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            switcher.show(on: screen)
            XCTAssertTrue(switcher.expanded)
            XCTAssertTrue(switcher.state.isPresented)
        }

        // Simulate wake notification
        switcher.handleWakeOrScreenChange()
        XCTAssertFalse(switcher.expanded, "Expanded state must be reset to false after wake")
        XCTAssertFalse(switcher.state.isPresented, "isPresented state must be reset to false after wake")
        XCTAssertTrue(switcher.panel.isVisible, "Panel must be ordered front in resting state after wake")

        switcher.stop()
    }

    private func assertWakeOrdersOutPanel(_ notification: Notification.Name) {
        let center = NotificationCenter()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)

        let recovery = IslandWakeRecovery(panel: panel, notificationCenter: center)
        withExtendedLifetime(recovery) {
            center.post(name: notification, object: NSWorkspace.shared)
            XCTAssertFalse(panel.isVisible, "A visible panel may be stranded on a different Space after wake")
        }
    }
}
