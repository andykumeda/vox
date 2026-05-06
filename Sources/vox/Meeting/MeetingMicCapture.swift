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
///
/// Dead-mic resilience: a watchdog polls AVAudioRecorder's peak meter once per second.
/// macOS occasionally lets the input device's HAL go silent mid-session — Teams renegotiates
/// sample rate / format, USB power management kicks in, or another app grabs exclusive
/// access. AVAudioRecorder doesn't notice and keeps encoding zero PCM samples for the rest
/// of the meeting. When the watchdog sees `silenceRestartThresholdSec` of consecutive
/// floor-level peak power while we expect speech, it tears down the current recorder and
/// starts a new one writing to a fresh part file. At stop(), parts are concatenated via
/// AVMutableComposition into a single output m4a that the chunking pipeline consumes
/// unchanged.
public final class MeetingMicCapture: NSObject, MeetingAudioRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    /// Files written by recorders that have already been torn down by the
    /// watchdog. Concatenated with the final recorder's output at stop().
    private var partURLs: [URL] = []
    private var watchdog: Task<Void, Never>?
    /// Wall-clock seconds of consecutive floor-level peak observed by the
    /// watchdog. Reset whenever a non-floor sample arrives.
    private var consecutiveSilentSec: Int = 0
    /// Set true when stop() begins so the watchdog stops trying to restart.
    private var stopping: Bool = false
    private(set) public var lastFailureReason: String?
    private(set) public var audioStartedAt: Date?

    /// Peak power threshold (dB). AVAudioRecorder reports -160 for true
    /// digital silence and around -50 for a quiet mic floor with no
    /// speech. Anything quieter than this for the full window is treated
    /// as a stalled input.
    static let silenceFloorDB: Float = -50.0
    /// Seconds of consecutive floor-level peak before the watchdog
    /// declares the mic stalled and restarts the recorder.
    static let silenceRestartThresholdSec: Int = 30
    /// Watchdog poll interval (seconds).
    static let watchdogIntervalSec: Double = 1.0

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

        partURLs = []
        consecutiveSilentSec = 0
        stopping = false

        try startRecorder(at: outputURL)
        self.outputURL = outputURL
        audioStartedAt = Date()

        // Spawn the watchdog. Using a Task instead of a timer so the work
        // stays off the main runloop and can be cancelled cleanly on stop.
        watchdog = Task { [weak self] in
            await self?.runWatchdog()
        }
        dlog("MeetingMicCapture started → \(outputURL.path)")
    }

    public func stop() async throws -> URL {
        stopping = true
        watchdog?.cancel()
        watchdog = nil

        guard let outputURL = outputURL else {
            throw MeetingMicCaptureError.notRecording
        }

        // Tear down the active recorder (always exists when outputURL is set).
        let lastURL = teardownActiveRecorder()
        self.outputURL = nil

        // Yield so CoreAudio finalises the release before any subsequent
        // dictation tap installs on the same input.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Concatenate any parts produced by mid-session restarts. If there
        // were none, lastURL is the final file and we're done.
        let finalURL = try await concatenateParts(parts: partURLs, last: lastURL, outputURL: outputURL)

        let bytes = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int) ?? 0
        dlog("MeetingMicCapture stopped bytes=\(bytes) restarts=\(partURLs.count)")
        if bytes < 4096 {
            lastFailureReason = "Mic recording empty (\(bytes) bytes). Mic may be muted or another app holds the input device."
        }
        partURLs = []
        return finalURL
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown encode error"
        dlog("MeetingMicCapture encode error: \(msg)")
        lastFailureReason = "Mic encode error: \(msg)"
    }

    // MARK: - Internal recorder management

    private func startRecorder(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r: AVAudioRecorder
        do {
            r = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            throw MeetingMicCaptureError.recorderInitFailed(error)
        }
        r.delegate = self
        r.isMeteringEnabled = true
        guard r.record() else {
            lastFailureReason = "AVAudioRecorder.record() returned false"
            throw MeetingMicCaptureError.startFailed
        }
        self.recorder = r
    }

    /// Stops the active recorder and returns the URL it was writing to.
    /// Drops the delegate before nilling so AVAudioRecorder fully tears
    /// down its CoreAudio input handle (without this dictation immediately
    /// after a meeting received all-zero buffers).
    @discardableResult
    private func teardownActiveRecorder() -> URL {
        let url = recorder?.url ?? outputURL!
        recorder?.stop()
        recorder?.delegate = nil
        recorder = nil
        return url
    }

    // MARK: - Watchdog

    private func runWatchdog() async {
        while !Task.isCancelled, !stopping {
            try? await Task.sleep(nanoseconds: UInt64(Self.watchdogIntervalSec * 1_000_000_000))
            if Task.isCancelled || stopping { return }
            tickWatchdog()
        }
    }

    private func tickWatchdog() {
        guard let r = recorder else { return }
        r.updateMeters()
        let peak = r.peakPower(forChannel: 0)
        if peak <= Self.silenceFloorDB {
            consecutiveSilentSec += 1
            if consecutiveSilentSec >= Self.silenceRestartThresholdSec {
                attemptRestart()
                consecutiveSilentSec = 0
            }
        } else {
            consecutiveSilentSec = 0
        }
    }

    /// Tears down the active recorder, archives its output as a part file,
    /// and starts a fresh recorder writing to `<basename>-partN.m4a`. The
    /// running output URL becomes the new part. At stop() all parts plus
    /// the final recorder's file are concatenated.
    private func attemptRestart() {
        guard let baseURL = outputURL else { return }
        dlog("MeetingMicCapture: \(Self.silenceRestartThresholdSec)s of silence → restarting recorder")
        // Move the current file aside so it survives until concat.
        let partIndex = partURLs.count
        let partURL = baseURL.deletingPathExtension()
            .appendingPathExtension("part\(partIndex).m4a")
        let finishedURL = teardownActiveRecorder()
        // Re-locate the just-finished file under a part-specific name so
        // the next recorder can claim the original output URL.
        do {
            try? FileManager.default.removeItem(at: partURL)
            try FileManager.default.moveItem(at: finishedURL, to: partURL)
            partURLs.append(partURL)
        } catch {
            dlog("MeetingMicCapture restart: could not archive part — \(error). Using in-place restart instead.")
        }
        // Brief yield so CoreAudio releases the input cleanly before re-acquiring.
        Thread.sleep(forTimeInterval: 0.2)
        do {
            try startRecorder(at: baseURL)
            audioStartedAt = audioStartedAt ?? Date()
        } catch {
            dlog("MeetingMicCapture restart failed: \(error)")
            lastFailureReason = "Mic stalled and could not be restarted: \(error)"
        }
    }

    // MARK: - Concat

    /// Builds a single AAC m4a from `parts + last` using AVMutableComposition.
    /// Returns `last` directly when there are no parts (no restarts happened).
    private func concatenateParts(parts: [URL], last: URL, outputURL: URL) async throws -> URL {
        guard !parts.isEmpty else { return last }
        // Last file may have just been written; give the OS a beat.
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            dlog("MeetingMicCapture concat: addMutableTrack failed; falling back to last part")
            return last
        }
        var cursor = CMTime.zero
        for url in parts + [last] {
            let asset = AVURLAsset(url: url)
            let dur = try await asset.load(.duration)
            guard dur.seconds > 0 else { continue }
            let assetTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let assetTrack = assetTracks.first else { continue }
            let range = CMTimeRange(start: .zero, duration: dur)
            try track.insertTimeRange(range, of: assetTrack, at: cursor)
            cursor = cursor + dur
        }
        // Write to a sibling so we can atomically swap to outputURL at the end.
        let tmp = outputURL.deletingPathExtension().appendingPathExtension("concat.m4a")
        try? FileManager.default.removeItem(at: tmp)
        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetAppleM4A
        ) else {
            dlog("MeetingMicCapture concat: AVAssetExportSession init failed; falling back to last part")
            return last
        }
        export.outputURL = tmp
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else {
            dlog("MeetingMicCapture concat export failed: \(export.error?.localizedDescription ?? "unknown")")
            return last
        }
        // Move concat result into outputURL and clean up parts + last.
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: tmp, to: outputURL)
        for u in parts + [last] where u != outputURL {
            try? FileManager.default.removeItem(at: u)
        }
        return outputURL
    }
}
