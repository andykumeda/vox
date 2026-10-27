import AVFoundation
import Foundation

public enum MeetingMicCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case recorderInitFailed(Error)
    case startFailed
    case notRecording
    case alreadyRecording

    public var description: String {
        switch self {
        case .permissionDenied:
            return "Microphone permission required (System Settings → Privacy & Security → Microphone)."
        case .recorderInitFailed(let e):
            return "Mic recorder init failed: \(e.localizedDescription)"
        case .startFailed:
            return "Mic recorder failed to start."
        case .alreadyRecording:
            return "Mic recording is already active."
        case .notRecording:
            return "Mic stop() called without a prior start()."
        }
    }
}

/// Captures the local microphone continuously alongside system audio.
/// Quiet audio is valid meeting content, not evidence that capture has stalled.
protocol MeetingMicrophoneRecording: AnyObject {
    var delegate: AVAudioRecorderDelegate? { get set }
    func record() -> Bool
    func stop()
}

extension AVAudioRecorder: MeetingMicrophoneRecording {}

public final class MeetingMicCapture: NSObject, MeetingAudioRecording, AVAudioRecorderDelegate {
    private var recorder: MeetingMicrophoneRecording?
    private var outputURL: URL?
    private var starting = false
    private let requestPermission: () async -> Bool
    private let makeRecorder: (URL) throws -> MeetingMicrophoneRecording
    private(set) public var lastFailureReason: String?
    private(set) public var captureWarnings: [String] = []
    private(set) public var audioStartedAt: Date?

    public override convenience init() {
        self.init(
            requestPermission: {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: return true
                case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
                default: return false
                }
            },
            makeRecorder: { url in
                try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64000,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ])
            }
        )
    }

    init(
        requestPermission: @escaping () async -> Bool,
        makeRecorder: @escaping (URL) throws -> MeetingMicrophoneRecording
    ) {
        self.requestPermission = requestPermission
        self.makeRecorder = makeRecorder
        super.init()
    }

    public func start(outputURL: URL) async throws {
        guard recorder == nil, !starting else { throw MeetingMicCaptureError.alreadyRecording }
        starting = true
        defer { starting = false }
        lastFailureReason = nil
        captureWarnings = []
        audioStartedAt = nil
        guard await requestPermission() else { throw MeetingMicCaptureError.permissionDenied }
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let r: MeetingMicrophoneRecording
        do {
            r = try makeRecorder(outputURL)
        } catch {
            throw MeetingMicCaptureError.recorderInitFailed(error)
        }
        r.delegate = self
        guard r.record() else {
            r.delegate = nil
            lastFailureReason = "AVAudioRecorder.record() returned false"
            throw MeetingMicCaptureError.startFailed
        }
        recorder = r
        self.outputURL = outputURL
        audioStartedAt = Date()
        dlog("MeetingMicCapture started → \(outputURL.path)")
    }

    public func stop() async throws -> URL {
        guard let outputURL, let recorder else { throw MeetingMicCaptureError.notRecording }
        // Detach before stop so its normal completion isn't reported as an interruption.
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        // Allow CoreAudio to release the input before a subsequent dictation tap.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        dlog("MeetingMicCapture stopped bytes=\(bytes)")
        if bytes < 4096, lastFailureReason == nil {
            lastFailureReason = "Mic recording empty (\(bytes) bytes). Mic may be muted or another app holds the input device."
        }
        return outputURL
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard let active = self.recorder, active === recorder else { return }
        let msg = error?.localizedDescription ?? "unknown encode error"
        dlog("MeetingMicCapture encode error: \(msg)")
        lastFailureReason = "Mic encode error: \(msg)"
    }

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        recorderDidFinish(recorder, successfully: flag)
    }

    func recorderDidFinish(_ recorder: MeetingMicrophoneRecording, successfully flag: Bool) {
        guard let active = self.recorder, active === recorder else { return }
        if flag {
            captureWarnings = ["Microphone recording ended early; audio captured before the interruption was preserved."]
        } else {
            lastFailureReason = "Microphone recording stopped unexpectedly with an encoding failure."
        }
        dlog("MeetingMicCapture unexpected stop successfully=\(flag)")
    }
}
