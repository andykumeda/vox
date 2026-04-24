import XCTest
@testable import vox

final class ContextDetectorTests: XCTestCase {
    let d = ContextDetector()

    func testTerminalBundleYieldsCommand() {
        XCTAssertEqual(d.mode(forBundleID: "com.apple.Terminal"), .command)
        XCTAssertEqual(d.mode(forBundleID: "com.googlecode.iterm2"), .command)
        XCTAssertEqual(d.mode(forBundleID: "dev.warp.Warp-Stable"), .command)
        XCTAssertEqual(d.mode(forBundleID: "com.mitchellh.ghostty"), .command)
        XCTAssertEqual(d.mode(forBundleID: "dev.commandline.waveterm"), .command)
    }

    func testNonTerminalYieldsProse() {
        XCTAssertEqual(d.mode(forBundleID: "com.apple.TextEdit"), .prose)
        XCTAssertEqual(d.mode(forBundleID: "com.apple.Safari"), .prose)
        XCTAssertEqual(d.mode(forBundleID: "com.apple.dt.Xcode"), .prose)
    }

    func testNilBundleYieldsProse() {
        XCTAssertEqual(d.mode(forBundleID: nil), .prose)
    }

    func testCustomTerminalSet() {
        let custom = ContextDetector(terminalBundleIDs: ["com.example.myterm"])
        XCTAssertEqual(custom.mode(forBundleID: "com.example.myterm"), .command)
        XCTAssertEqual(custom.mode(forBundleID: "com.apple.Terminal"), .prose)
    }
}
