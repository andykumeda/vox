import XCTest
@testable import vox

final class MenuBarControllerTests: XCTestCase {
    func testPasteLastWaitsForMenuAndModifierFocusToSettle() {
        XCTAssertGreaterThanOrEqual(MenuBarController.pasteLastFocusSettleDelay, 0.15)
    }
}
