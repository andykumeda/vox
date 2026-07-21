import XCTest
@testable import vox

final class RelocatorTests: XCTestCase {
    func testEscalatedCopyQuotesUntrustedPathsBeforeTheyReachTheShell() throws {
        let source = #"/Volumes/Vox $(touch /tmp/owned) `id` \"quoted\"/Vox.app"#
        let destination = #"/Applications/Vox $(touch /tmp/owned).app"#

        let script = try XCTUnwrap(
            Relocator.escalatedCopyScript(from: source, to: destination)
        )
        let shellLine = try XCTUnwrap(
            script.split(separator: "\n").first { $0.contains("do shell script") }
        )

        XCTAssertTrue(shellLine.contains("quoted form of sourcePath"))
        XCTAssertTrue(shellLine.contains("quoted form of destinationPath"))
        XCTAssertFalse(shellLine.contains("$("))
        XCTAssertFalse(shellLine.contains("`"))

        var compileError: NSDictionary?
        let appleScript = try XCTUnwrap(NSAppleScript(source: script))
        XCTAssertTrue(
            appleScript.compileAndReturnError(&compileError),
            "Generated AppleScript did not compile: \(String(describing: compileError))"
        )
    }

    func testEscalatedCopyRejectsControlCharactersInPaths() {
        XCTAssertNil(Relocator.escalatedCopyScript(
            from: "/Volumes/Vox\nInjected/Vox.app",
            to: "/Applications/Vox.app"
        ))
    }
}
