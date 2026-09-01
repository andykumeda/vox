import XCTest
@testable import vox
@testable import VoxCore

final class LogTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-log-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testTextLogMetricsReportsCountsWithoutContent() {
        let sensitiveText = "Project Falcon launches tomorrow"

        let metrics = textLogMetrics(label: "raw", text: sensitiveText)

        XCTAssertEqual(metrics, "raw_chars=32 raw_words=4")
        XCTAssertFalse(metrics.contains("Falcon"))
        XCTAssertFalse(metrics.contains(sensitiveText))
    }

    func testTextLogMetricsCountsWordsAcrossWhitespace() {
        let metrics = textLogMetrics(label: "cleaned", text: "one\n two\tthree")

        XCTAssertEqual(metrics, "cleaned_chars=14 cleaned_words=3")
    }

    func testFormatDLogLineUsesFractionalISOTimestamp() {
        let line = formatDLogLine(
            message: "ready",
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(line, "1970-01-01T00:00:00.000Z [vox] ready\n")
    }

    func testLaunchAgentLogWriteSkipsStandardErrorMirror() throws {
        let logURL = tempDirectory.appendingPathComponent("vox.log")
        let standardErrorURL = tempDirectory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        defer {
            try? logHandle.close()
            try? standardErrorHandle.close()
        }

        writeDLogData(
            Data("launch-agent line\n".utf8),
            to: logHandle,
            standardError: standardErrorHandle,
            mirrorToStandardError: shouldMirrorDLogToStandardError(
                isLaunchAgentInstance: true
            )
        )

        XCTAssertEqual(
            try String(contentsOf: logURL, encoding: .utf8),
            "launch-agent line\n"
        )
        XCTAssertEqual(try Data(contentsOf: standardErrorURL), Data())
    }

    func testInteractiveLogWriteKeepsStandardErrorMirror() throws {
        let logURL = tempDirectory.appendingPathComponent("vox.log")
        let standardErrorURL = tempDirectory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        defer {
            try? logHandle.close()
            try? standardErrorHandle.close()
        }
        let data = Data("interactive line\n".utf8)

        writeDLogData(
            data,
            to: logHandle,
            standardError: standardErrorHandle,
            mirrorToStandardError: shouldMirrorDLogToStandardError(
                isLaunchAgentInstance: false
            )
        )

        XCTAssertEqual(try Data(contentsOf: logURL), data)
        XCTAssertEqual(try Data(contentsOf: standardErrorURL), data)
    }

    func testPrepareLogFileRotatesOversizedLogAndKeepsOnePreviousGeneration() throws {
        let logURL = tempDirectory.appendingPathComponent("vox.log")
        let previousURL = tempDirectory.appendingPathComponent("vox.log.previous")
        try Data("first generation".utf8).write(to: logURL)
        try Data("obsolete generation".utf8).write(to: previousURL)

        try prepareLogFile(at: logURL, maximumBytes: 8)

        XCTAssertEqual(try Data(contentsOf: logURL), Data())
        XCTAssertEqual(
            try String(contentsOf: previousURL, encoding: .utf8),
            "first generation"
        )

        try Data("second generation".utf8).write(to: logURL)
        try prepareLogFile(at: logURL, maximumBytes: 8)

        XCTAssertEqual(try Data(contentsOf: logURL), Data())
        XCTAssertEqual(
            try String(contentsOf: previousURL, encoding: .utf8),
            "second generation"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDirectory.appendingPathComponent("vox.log.previous.1").path
            )
        )
    }

    func testPrepareLogFileLeavesSmallExistingLogUntouched() throws {
        let logURL = tempDirectory.appendingPathComponent("vox.log")
        let previousURL = tempDirectory.appendingPathComponent("vox.log.previous")
        try Data("current".utf8).write(to: logURL)
        try Data("previous".utf8).write(to: previousURL)

        try prepareLogFile(at: logURL, maximumBytes: 64)

        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "current")
        XCTAssertEqual(try String(contentsOf: previousURL, encoding: .utf8), "previous")
    }
}
