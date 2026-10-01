import AppKit

struct Desktop: Identifiable {
    let id: UInt64
    let uuid: String
    let display: String
    let displayIdentifier: String
    let displayID: CGDirectDisplayID
    let index: Int
    let number: Int
    let isCurrent: Bool
    let isFullscreen: Bool
    var fallbackName: String { isFullscreen ? "Full screen \(number)" : "Desktop \(number)" }
}

enum SpaceTint {
    private static let colors = [
        NSColor(red: 0.58, green: 0.43, blue: 0.78, alpha: 1),
        NSColor(red: 0.43, green: 0.61, blue: 0.85, alpha: 1),
        NSColor(red: 0.38, green: 0.69, blue: 0.67, alpha: 1),
        NSColor(red: 0.43, green: 0.67, blue: 0.46, alpha: 1),
        NSColor(red: 0.76, green: 0.64, blue: 0.34, alpha: 1),
        NSColor(red: 0.75, green: 0.49, blue: 0.32, alpha: 1)
    ]

    static func color(for number: Int) -> NSColor {
        colors[(max(number, 1) - 1) % colors.count]
    }
}

struct WindowIdentity: Codable, Hashable {
    let pid: pid_t
    let id: UInt32
    let launched: Date
    var key: String { "\(pid):\(id):\(launched.timeIntervalSince1970)" }
}

struct ManagedWindow: Identifiable {
    let identity: WindowIdentity
    let element: AXUIElement
    let app: String
    let title: String
    let frame: CGRect
    let spaces: [UInt64]
    let isFullscreen: Bool
    var id: String { identity.key }
}

struct ParkedWindow: Codable {
    let identity: WindowIdentity
    let frame: CGRect
}

enum Parking {
    /// Accessibility uses an origin at the top left of the primary display.
    static func axFrame(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func origin(for window: CGRect, screens: [CGRect]) -> CGPoint? {
        guard let screen = screens.max(by: { intersectionArea(window, $0) < intersectionArea(window, $1) }),
              intersectionArea(window, screen) > 0 else { return nil }
        // ponytail: park at an exposed bottom corner; reject crowded layouts instead of relocating displays.
        let candidates = [
            CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),
            CGPoint(x: screen.minX - window.width + 1, y: screen.maxY - 1)
        ]
        return candidates.first { point in
            let parked = CGRect(origin: point, size: window.size)
            return screens.allSatisfy { $0 == screen || intersectionArea(parked, $0) <= 1 }
        }
    }

    static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }

    static func recoveredFrame(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let screen = screens.max(by: { intersectionArea(frame, $0) < intersectionArea(frame, $1) }) else { return frame }
        let size = CGSize(width: min(frame.width, screen.width), height: min(frame.height, screen.height))
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - size.height), width: size.width, height: size.height)
    }
}
