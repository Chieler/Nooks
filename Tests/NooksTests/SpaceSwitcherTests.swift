import XCTest
import AppKit
import SpaceBridge
@testable import Nooks

final class SpaceSwitcherTests: XCTestCase {
    func testHelperWindowCreationAndAttributes() {
        let switcher = SpaceSwitcher()
        defer { switcher.cleanup() }

        let testSpaceID: UInt64 = 99999
        let window = switcher.ensureHelperWindow(for: testSpaceID)

        XCTAssertNotNil(window, "Helper window should be successfully created")
        guard let win = window else { return }

        XCTAssertEqual(win.frame.width, 1.0)
        XCTAssertEqual(win.frame.height, 29.0)
        XCTAssertFalse(win.isOpaque)
        XCTAssertEqual(win.backgroundColor, .clear)
        XCTAssertEqual(win.alphaValue, 0.01)
        XCTAssertTrue(win.canBecomeKey, "Helper window must allow becoming key to trigger space transitions")
        XCTAssertFalse(win.canBecomeMain)
        XCTAssertTrue(win.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(win.collectionBehavior.contains(.transient))

        // Same space ID returns identical cached window
        let secondWindow = switcher.ensureHelperWindow(for: testSpaceID)
        XCTAssertEqual(win, secondWindow, "ensureHelperWindow should reuse the existing window for the space")
    }

    func testDesktopSync() {
        let switcher = SpaceSwitcher()
        defer { switcher.cleanup() }

        let desktops = [
            Desktop(id: 101, uuid: "u-101", display: "Main", displayIdentifier: "Main", displayID: 1, index: 0, number: 1, isCurrent: true, isFullscreen: false),
            Desktop(id: 102, uuid: "u-102", display: "Main", displayIdentifier: "Main", displayID: 1, index: 1, number: 2, isCurrent: false, isFullscreen: false),
            Desktop(id: 103, uuid: "u-103", display: "Main", displayIdentifier: "Main", displayID: 1, index: 2, number: 3, isCurrent: false, isFullscreen: true, pid: 42)
        ]

        switcher.sync(with: desktops)

        // Helper windows should exist for desktop 101 and 102, but NOT for fullscreen 103
        let win101 = switcher.ensureHelperWindow(for: 101)
        let win102 = switcher.ensureHelperWindow(for: 102)
        XCTAssertNotNil(win101)
        XCTAssertNotNil(win102)

        // Now sync with only desktop 101; desktop 102 should be pruned
        let prunedDesktops = [desktops[0]]
        switcher.sync(with: prunedDesktops)

        // Calling ensureHelperWindow for 102 now creates a new window because previous was closed
        let newWin102 = switcher.ensureHelperWindow(for: 102)
        XCTAssertNotEqual(win102, newWin102)
    }

    func testSpaceBridgeAddAndRemoveWindowFromSpace() {
        let window = SpaceSwitcherWindow(
            contentRect: NSRect(x: 80, y: 262, width: 1, height: 29),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        defer { window.close() }

        let wid = UInt32(window.windowNumber)
        XCTAssertGreaterThan(wid, 0)

        // Get live displays and spaces from system
        let displays = SSCopyDisplays()
        guard let firstDisplay = displays.first,
              let spaces = firstDisplay["Spaces"] as? [[String: Any]],
              let firstSpace = spaces.first,
              let spaceID = (firstSpace["id64"] as? NSNumber)?.uint64Value else {
            return
        }

        let added = SSAddWindowToSpace(wid, spaceID)
        XCTAssertTrue(added, "SSAddWindowToSpace should succeed for our own window")

        let currentSpaces = SSCopyWindowSpaces(wid)
        XCTAssertTrue(currentSpaces.contains(NSNumber(value: spaceID)), "Window should now belong to space \(spaceID)")

        let removed = SSRemoveWindowFromSpaces(wid, [NSNumber(value: spaceID)])
        XCTAssertTrue(removed, "SSRemoveWindowFromSpaces should succeed")

        let spacesAfterRemove = SSCopyWindowSpaces(wid)
        XCTAssertFalse(spacesAfterRemove.contains(NSNumber(value: spaceID)), "Window should no longer belong to space \(spaceID)")
    }

    func testSyntheticSwipeGeneration() {
        // Posting synthetic swipe events to kCGHIDEventTap should return true
        let postedRight = SSPostSyntheticSwipe(true)
        XCTAssertTrue(postedRight)

        let postedLeft = SSPostSyntheticSwipe(false)
        XCTAssertTrue(postedLeft)
    }
}
