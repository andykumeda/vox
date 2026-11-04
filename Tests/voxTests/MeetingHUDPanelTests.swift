import AppKit
import XCTest
@testable import vox

final class MeetingHUDPanelTests: XCTestCase {
    private let main = NSRect(x: 0, y: 24, width: 1440, height: 850)

    func testKeepsRememberedPositionOnItsDisplay() {
        let second = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = NSRect(x: -1200, y: 500, width: 270, height: 95)
        XCTAssertEqual(MeetingHUDPanel.visibleOrigin(for: frame, screens: [main, second]), frame.origin)
    }

    func testDisconnectedDisplayPositionReturnsToAvailableScreen() {
        let frame = NSRect(x: -1200, y: 500, width: 270, height: 95)
        XCTAssertEqual(MeetingHUDPanel.visibleOrigin(for: frame, screens: [main]), NSPoint(x: 0, y: 500))
    }

    func testClampsAllEdgesInsideVisibleArea() {
        let frame = NSRect(x: 1400, y: 900, width: 270, height: 95)
        XCTAssertEqual(MeetingHUDPanel.visibleOrigin(for: frame, screens: [main]), NSPoint(x: 1170, y: 779))
        let below = NSRect(x: -20, y: -100, width: 270, height: 95)
        XCTAssertEqual(MeetingHUDPanel.visibleOrigin(for: below, screens: [main]), main.origin)
    }

    func testNoScreensPreservesPositionAndTinyDisplayDoesNotInvertBounds() {
        let frame = NSRect(x: 400, y: 400, width: 270, height: 95)
        XCTAssertEqual(MeetingHUDPanel.visibleOrigin(for: frame, screens: []), frame.origin)
        let tiny = NSRect(x: 0, y: 0, width: 100, height: 80)
        XCTAssertEqual(MeetingHUDPanel.visibleOrigin(for: frame, screens: [tiny]), .zero)
    }
}
