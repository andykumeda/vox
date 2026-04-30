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
public final class MeetingAudioCapture: NSObject, MeetingAudioRecording, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private let queue = DispatchQueue(label: "vox.meeting.capture", qos: .userInitiated)
    private var sessionStarted = false

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
        config.capturesAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true

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

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw MeetingAudioCaptureError.streamStartFailed(error)
        }
        self.stream = stream
    }

    public func stop() async throws -> URL {
        guard let stream = stream, let writer = writer,
              let input = writerInput, let outputURL = outputURL else {
            throw MeetingAudioCaptureError.notRecording
        }
        try? await stream.stopCapture()
        input.markAsFinished()
        await writer.finishWriting()
        let url = outputURL
        self.stream = nil
        self.writer = nil
        self.writerInput = nil
        self.outputURL = nil
        self.sessionStarted = false
        return url
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
        if !sessionStarted {
            let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: startTime)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
