import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Test-substitutable interface for the meeting capture backend. Production wires
/// `MeetingAudioCapture`; tests inject a mock that writes a fixture m4a file.
public protocol MeetingAudioRecording: AnyObject {
    /// Begins recording system audio to `outputURL`. Throws on permission denial or
    /// stream start failure. Idempotent: calling start twice in a row is an error.
    func start(outputURL: URL) async throws

    /// Stops the in-flight recording, flushes the writer, and returns the file URL.
    /// Throws if recording was never started.
    func stop() async throws -> URL

    /// Set when capture finished but produced no usable audio (no sample buffers, writer
    /// failure, etc). Read by MeetingTranscriptionSession after stop to surface a clean
    /// failure rather than handing an empty file to the chunker.
    var lastFailureReason: String? { get }
}

public extension MeetingAudioRecording {
    var lastFailureReason: String? { nil }
}

public enum MeetingAudioCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case noShareableContent(Error)
    case streamStartFailed(Error)
    case writerFailed(Error)
    case notRecording

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission required (System Settings → Privacy & Security → Screen Recording)."
        case .noShareableContent(let e):
            return "Could not enumerate shareable content: \(e.localizedDescription)"
        case .streamStartFailed(let e):
            return "SCStream failed to start: \(e.localizedDescription)"
        case .writerFailed(let e):
            return "Audio writer failed: \(e.localizedDescription)"
        case .notRecording:
            return "stop() called without a prior start()."
        }
    }
}

@available(macOS 13.0, *)
public final class MeetingAudioCapture: NSObject, MeetingAudioRecording, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private let queue = DispatchQueue(label: "vox.meeting.capture", qos: .userInitiated)
    private var sessionStarted = false
    private var sampleBufferCount = 0
    private(set) public var lastFailureReason: String?

    public override init() { super.init() }

    public func start(outputURL: URL) async throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw MeetingAudioCaptureError.permissionDenied
        }
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.outputURL = outputURL

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
        } catch {
            throw MeetingAudioCaptureError.noShareableContent(error)
        }
        guard let display = content.displays.first else {
            throw MeetingAudioCaptureError.noShareableContent(
                NSError(domain: "vox.meeting", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "no displays"])
            )
        }
        let excluded = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excluded,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        // SCStream requires non-zero video dimensions even for audio-only capture
        // (otherwise stream silently emits no buffers). 2x2 keeps overhead negligible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps video — discarded
        config.capturesAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true
        sampleBufferCount = 0
        lastFailureReason = nil
        NSLog("[vox] MeetingAudioCapture starting → \(outputURL.path)")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        self.writer = writer
        self.writerInput = input

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            // We discard video; still need a registered output or the stream rejects start.
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            NSLog("[vox] MeetingAudioCapture stream.startCapture failed: \(error)")
            throw MeetingAudioCaptureError.streamStartFailed(error)
        }
        self.stream = stream
        NSLog("[vox] MeetingAudioCapture stream started")
    }

    public func stop() async throws -> URL {
        guard let stream = stream, let writer = writer,
              let input = writerInput, let outputURL = outputURL else {
            throw MeetingAudioCaptureError.notRecording
        }
        try? await stream.stopCapture()
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            let reason = "writer status=\(writer.status.rawValue) error=\(writer.error?.localizedDescription ?? "nil") sampleBuffers=\(sampleBufferCount)"
            NSLog("[vox] MeetingAudioCapture finishWriting failed: \(reason)")
            lastFailureReason = reason
        } else {
            NSLog("[vox] MeetingAudioCapture finishWriting ok sampleBuffers=\(sampleBufferCount)")
        }
        if sampleBufferCount == 0 {
            lastFailureReason = "No system audio captured (\(sampleBufferCount) sample buffers received). Check that audio was actually playing during recording and Screen Recording permission is granted."
        }
        let url = outputURL
        self.stream = nil
        self.writer = nil
        self.writerInput = nil
        self.outputURL = nil
        self.sessionStarted = false
        return url
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[vox] MeetingAudioCapture SCStream didStopWithError: \(error)")
        lastFailureReason = "SCStream stopped: \(error.localizedDescription)"
    }

    // MARK: - SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              let writer = writer,
              let input = writerInput,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        sampleBufferCount += 1
        if !sessionStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let started = writer.startWriting()
            if !started {
                NSLog("[vox] MeetingAudioCapture writer.startWriting returned false: \(writer.error?.localizedDescription ?? "nil")")
                return
            }
            writer.startSession(atSourceTime: startTime)
            sessionStarted = true
            NSLog("[vox] MeetingAudioCapture session started at PTS \(startTime.seconds)")
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
