import XCTest
@testable import Nooks

final class ParkingTests: XCTestCase {
    func testParkingRecoveryAndCoordinateConversion() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        let right = Parking.origin(for: window, screens: [screen])!
        XCTAssertEqual(right, CGPoint(x: 1439, y: 899))
        XCTAssertEqual(Parking.intersectionArea(CGRect(origin: right, size: window.size), screen), 1)

        let belowRight = CGRect(x: 1440, y: 500, width: 1440, height: 900)
        let left = Parking.origin(for: window, screens: [screen, belowRight])!
        XCTAssertEqual(left, CGPoint(x: -799, y: 899))
        let belowLeft = CGRect(x: -1440, y: 500, width: 1440, height: 900)
        XCTAssertNil(Parking.origin(for: window, screens: [screen, belowRight, belowLeft]))

        XCTAssertEqual(Parking.axFrame(CGRect(x: -1440, y: 100, width: 1440, height: 900), primaryHeight: 900),
                       CGRect(x: -1440, y: -100, width: 1440, height: 900))
        let recovered = Parking.recoveredFrame(CGRect(x: 2200, y: 100, width: 800, height: 600), screens: [screen])
        XCTAssertTrue(screen.contains(recovered), "A disconnected display must not strand a recovered window")
        XCTAssertEqual(Parking.recoveredFrame(window, screens: [screen]), window)

        let identity = WindowIdentity(pid: 1, id: 3, launched: Date(timeIntervalSince1970: 100))
        let reusedID = WindowIdentity(pid: 1, id: 3, launched: Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(identity.key, reusedID.key, "Recovery must not target a reused process/window ID")
        let record = ParkedWindow(identity: identity, frame: window)
        let decoded = try! JSONDecoder().decode(ParkedWindow.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.frame, window)
        XCTAssertEqual(decoded.identity, identity)
    }
}
