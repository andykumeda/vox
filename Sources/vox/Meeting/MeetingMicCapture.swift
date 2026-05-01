import AVFoundation
import Foundation

public enum MeetingMicCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case recorderInitFailed(Error)
    case startFailed
    case notRecording

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Microphone permission required (System Settings → Privacy & Security → Microphone)."
        case .recorderInitFailed(let e):
            return "Mic recorder init failed: \(e.localizedDescription)"
        case .startFailed:
            return "Mic recorder failed to start."
        case .notRecording:
            return "Mic stop() called without a prior start()."
        }
    }
}

/// Captures the local microphone to AAC m4a in parallel with `MeetingAudioCapture`'s
/// SCStream system-audio capture. Together they cover every voice in a meeting:
/// SCStream picks up remote participants (mixed by Zoom/etc → speakers), this picks up
/// the local user.
public final class MeetingMicCapture: NSObject, MeetingAudioRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private(set) public var lastFailureReason: String?
    private(set) public var audioStartedAt: Date?

    public override init() { super.init() }

    public func start(outputURL: URL) async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw MeetingMicCaptureError.permissionDenied }
        case .denied, .restricted:
            throw MeetingMicCaptureError.permissionDenied
        @unknown default:
            throw MeetingMicCaptureError.permissionDenied
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r: AVAudioRecorder
        do {
            r = try AVAudioRecorder(url: outputURL, settings: settings)
        } catch {
            throw MeetingMicCaptureError.recorderInitFailed(error)
        }
        r.delegate = self
        audioStartedAt = nil
        guard r.record() else {
            lastFailureReason = "AVAudioRecorder.record() returned false"
            throw MeetingMicCaptureError.startFailed
        }
        audioStartedAt = Date()
        self.recorder = r
        self.outputURL = outputURL
        dlog("MeetingMicCapture started → \(outputURL.path)")
    }

    public func stop() async throws -> URL {
        guard let recorder = recorder, let outputURL = outputURL else {
            throw MeetingMicCaptureError.notRecording
        }
        recorder.stop()
        // Drop delegate before releasing so AVAudioRecorder fully tears down
        // its CoreAudio input handle. Without this, dictation taken from
        // AVAudioEngine immediately after the meeting produced all-zero
        // buffers — the HAL device was still flagged in-use by the prior
        // recorder.
        recorder.delegate = nil
        self.recorder = nil
        self.outputURL = nil
        // Yield so CoreAudio finalises the release before any subsequent
        // dictation tap installs on the same input.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        dlog("MeetingMicCapture stopped bytes=\(bytes)")
        if bytes < 4096 {
            lastFailureReason = "Mic recording empty (\(bytes) bytes). Mic may be muted or another app holds the input device."
        }
        return outputURL
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown encode error"
        dlog("MeetingMicCapture encode error: \(msg)")
        lastFailureReason = "Mic encode error: \(msg)"
    }
}
