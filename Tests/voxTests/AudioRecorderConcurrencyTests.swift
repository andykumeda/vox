import AVFoundation
import XCTest
@testable import vox

final class AudioRecorderConcurrencyTests: XCTestCase {
    func testFailedStartDrainsCallbackWithoutHoldingItsLock() throws {
        let engine = CallbackDuringFailedStartEngine()
        let recorder = AudioRecorder(mode: "prose", engine: engine)

        XCTAssertThrowsError(try recorder.start())
        XCTAssertTrue(engine.callbackWasScheduled)
        XCTAssertTrue(engine.callbackFinishedDuringRemoval,
                      "Removing the tap must allow its in-flight callback to acquire the recorder lock")
        XCTAssertEqual(engine.callbackFinished.wait(timeout: .now() + 2), .success)
        XCTAssertNil(recorder.stop())
    }
}

private final class CallbackDuringFailedStartEngine: AudioEngineControlling {
    private enum Failure: Error { case startup }
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var handler: AVAudioNodeTapBlock?
    private let releaseCallback = DispatchSemaphore(value: 0)
    private let callbackEntered = DispatchSemaphore(value: 0)
    private let callbackDrained = DispatchSemaphore(value: 0)
    let callbackFinished = DispatchSemaphore(value: 0)
    private(set) var callbackWasScheduled = false
    private(set) var callbackFinishedDuringRemoval = false
    var isRunning: Bool { false }

    func inputFormat() -> AVAudioFormat { format }
    func selectInputDevice(_ deviceID: AudioDeviceID) throws {}
    func prepare() {}
    func stop() {}
    func reset() {}

    func installInputTap(bufferSize: AVAudioFrameCount, format: AVAudioFormat?,
                         handler: @escaping AVAudioNodeTapBlock) throws {
        self.handler = handler
    }

    func start() throws {
        let handler = self.handler!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        buffer.floatChannelData![0].initialize(repeating: 0, count: 4800)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            callbackEntered.signal()
            releaseCallback.wait()
            handler(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
            callbackDrained.signal()
            callbackFinished.signal()
        }
        callbackWasScheduled = callbackEntered.wait(timeout: .now() + 2) == .success
        throw Failure.startup
    }

    func removeInputTap() {
        guard handler != nil else { return }
        releaseCallback.signal()
        // Bound the fake drain so a lock regression fails instead of hanging the suite.
        callbackFinishedDuringRemoval = callbackDrained.wait(timeout: .now() + 2) == .success
        handler = nil
    }
}
