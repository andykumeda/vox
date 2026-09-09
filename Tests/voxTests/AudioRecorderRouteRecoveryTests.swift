import AVFoundation
import XCTest
@testable import vox

final class AudioRecorderRouteRecoveryTests: XCTestCase {
    func testStartRecoversWhenInputFormatChangesDuringEngineStartup() throws {
        let engine = RouteChangingAudioEngine(
            initialSampleRate: 8_000,
            settledSampleRate: 48_000,
            failFirstStart: true
        )
        let recorder = AudioRecorder(mode: "prose", engine: engine)

        try recorder.start()
        let recordingURL = try XCTUnwrap(recorder.stop())
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        XCTAssertEqual(engine.startAttempts, 2)
        XCTAssertEqual(engine.queriedSampleRates, [8_000, 48_000])
    }

    func testStartDoesNotRetryWhenInputFormatDidNotChange() {
        let engine = RouteChangingAudioEngine(
            initialSampleRate: 48_000,
            settledSampleRate: 48_000,
            failFirstStart: true
        )
        let recorder = AudioRecorder(mode: "prose", engine: engine)

        XCTAssertThrowsError(try recorder.start())
        XCTAssertEqual(engine.startAttempts, 1)
        XCTAssertNil(recorder.stop())
    }

    func testStartPinsConfiguredInputDeviceBeforeReadingItsFormat() throws {
        let engine = RouteChangingAudioEngine(
            initialSampleRate: 48_000,
            settledSampleRate: 48_000,
            failFirstStart: false
        )
        let recorder = AudioRecorder(
            mode: "prose",
            engine: engine,
            selectedInputDeviceUID: { "usb-mic-uid" },
            resolveInputDevice: { uid in uid == "usb-mic-uid" ? 42 : nil },
            hardwareInputFormat: { deviceID in
                deviceID == 42
                    ? AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
                    : nil
            }
        )

        try recorder.start()
        let recordingURL = try XCTUnwrap(recorder.stop())
        defer { try? FileManager.default.removeItem(at: recordingURL) }

        XCTAssertEqual(engine.selectedDeviceIDs, [42])
        XCTAssertEqual(engine.installedTapSampleRates, [48_000])
        XCTAssertEqual(engine.operations.prefix(2), ["select", "tap"])
        XCTAssertTrue(engine.queriedSampleRates.isEmpty)
    }

    func testStartFailsInsteadOfFallingBackWhenPinnedInputIsUnavailable() {
        let engine = RouteChangingAudioEngine(
            initialSampleRate: 48_000,
            settledSampleRate: 48_000,
            failFirstStart: false
        )
        let recorder = AudioRecorder(
            mode: "prose",
            engine: engine,
            selectedInputDeviceUID: { "missing-usb-mic" },
            resolveInputDevice: { _ in nil }
        )

        XCTAssertThrowsError(try recorder.start()) { error in
            guard case AudioRecorderError.inputDeviceUnavailable(let uid) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(uid, "missing-usb-mic")
        }
        XCTAssertTrue(engine.selectedDeviceIDs.isEmpty)
        XCTAssertEqual(engine.startAttempts, 0)
    }
}

private enum RouteChangingAudioEngineError: Error {
    case firstStartFailed
}

private final class RouteChangingAudioEngine: AudioEngineControlling {
    private let initialFormat: AVAudioFormat
    private let settledFormat: AVAudioFormat

    private(set) var startAttempts = 0
    private(set) var queriedSampleRates: [Double] = []
    private(set) var selectedDeviceIDs: [AudioDeviceID] = []
    private(set) var installedTapSampleRates: [Double] = []
    private(set) var operations: [String] = []
    private let failFirstStart: Bool
    var isRunning = false

    init(initialSampleRate: Double, settledSampleRate: Double, failFirstStart: Bool) {
        initialFormat = AVAudioFormat(
            standardFormatWithSampleRate: initialSampleRate,
            channels: 1
        )!
        settledFormat = AVAudioFormat(
            standardFormatWithSampleRate: settledSampleRate,
            channels: 1
        )!
        self.failFirstStart = failFirstStart
    }

    func inputFormat() -> AVAudioFormat {
        operations.append("format")
        let format = startAttempts == 0 ? initialFormat : settledFormat
        queriedSampleRates.append(format.sampleRate)
        return format
    }

    func selectInputDevice(_ deviceID: AudioDeviceID) throws {
        operations.append("select")
        selectedDeviceIDs.append(deviceID)
    }

    func installInputTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        handler: @escaping AVAudioNodeTapBlock
    ) {
        operations.append("tap")
        installedTapSampleRates.append(format?.sampleRate ?? 0)
    }

    func removeInputTap() {}
    func prepare() {}
    func reset() {}

    func start() throws {
        startAttempts += 1
        if failFirstStart && startAttempts == 1 {
            throw RouteChangingAudioEngineError.firstStartFailed
        }
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
