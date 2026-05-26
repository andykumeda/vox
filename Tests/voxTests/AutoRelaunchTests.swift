import XCTest
@testable import vox

final class AutoRelaunchTests: XCTestCase {
    func testLaunchAgentRunsVoxExecutableWithSupervisorArgument() throws {
        let plist = AutoRelaunch.launchAgentPlist(
            executablePath: "/Applications/Vox.app/Contents/MacOS/vox",
            logDirectoryPath: "/Users/test/Library/Logs"
        )

        XCTAssertEqual(plist["Label"] as? String, "com.andykumeda.vox")
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/Applications/Vox.app/Contents/MacOS/vox", "--vox-launch-agent"]
        )
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["ProcessType"] as? String, "Interactive")
        XCTAssertEqual(plist["LimitLoadToSessionType"] as? String, "Aqua")
    }

    func testLaunchAgentRestartsOnlyUnsuccessfulExits() throws {
        let plist = AutoRelaunch.launchAgentPlist(
            executablePath: "/Applications/Vox.app/Contents/MacOS/vox",
            logDirectoryPath: "/Users/test/Library/Logs"
        )
        let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Bool])

        XCTAssertEqual(keepAlive["Crashed"], true)
        XCTAssertEqual(keepAlive["SuccessfulExit"], false)
        XCTAssertEqual(plist["ThrottleInterval"] as? Int, 5)
    }

    func testLaunchAgentWritesLaunchdLogsToUserLogsDirectory() throws {
        let plist = AutoRelaunch.launchAgentPlist(
            executablePath: "/Applications/Vox.app/Contents/MacOS/vox",
            logDirectoryPath: "/Users/test/Library/Logs"
        )

        XCTAssertEqual(
            plist["StandardOutPath"] as? String,
            "/Users/test/Library/Logs/vox.launchd.out.log"
        )
        XCTAssertEqual(
            plist["StandardErrorPath"] as? String,
            "/Users/test/Library/Logs/vox.launchd.err.log"
        )
    }
}
