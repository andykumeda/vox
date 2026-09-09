import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

public enum AudioRecorderError: Error {
    case permissionDenied
    case engineStartFailed(Error)
    case noInputNode
    case formatConversionFailed
    case fileOpenFailed(Error)
    case inputDeviceUnavailable(String)
    case inputDeviceSelectionFailed(String, Error)
    case inputDeviceFormatUnavailable(String)
}

protocol AudioEngineControlling: AnyObject {
    var isRunning: Bool { get }

    func inputFormat() -> AVAudioFormat
    func selectInputDevice(_ deviceID: AudioDeviceID) throws
    func installInputTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        handler: @escaping AVAudioNodeTapBlock
    )
    func removeInputTap()
    func prepare()
    func start() throws
    func stop()
    func reset()
}

private final class SystemAudioEngine: AudioEngineControlling {
    private let engine = AVAudioEngine()

    var isRunning: Bool { engine.isRunning }

    func inputFormat() -> AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func selectInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(
                domain: "com.andykumeda.vox.audio-input",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioEngine input unit is unavailable"]
            )
        }
        var selectedID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Core Audio rejected input device \(deviceID)"]
            )
        }
    }

    func installInputTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        handler: @escaping AVAudioNodeTapBlock
    ) {
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: handler)
    }

    func removeInputTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    func prepare() { engine.prepare() }
    func start() throws { try engine.start() }
    func stop() { engine.stop() }
    func reset() { engine.reset() }
}

/// Records microphone input as 16kHz mono 16-bit PCM and streams the WAV to disk
/// while capture is in progress. The output URL lives under
/// `RecordingArchive.directory()` so the recording survives crashes, silence
/// gating, transcription failure, or replays. Header sizes are placeholders
/// until `stop()` patches them; see `RecordingArchive.repairOrphans` for the
/// crash-recovery path.
public final class AudioRecorder {
    /// Single long-lived engine, reused across recordings. The 0.6.0 build
    /// recreated this on every `start()` to clear post-meeting silent-buffer
    /// state, but that pattern deadlocked AVAudioEngine internally
    /// (IOUnitDispose vs IOUnitConfigurationChanged on a recursive_mutex)
    /// after a meeting + several dictations. The post-meeting silent-buffer
    /// case observed during testing turned out to be a hardware-level mic
    /// stall, not framework state, so this rolls back to the original
    /// single-engine pattern with explicit reset on each start.
    private let engine: AudioEngineControlling
    private let selectedInputDeviceUID: () -> String?
    private let resolveInputDevice: (String) -> AudioDeviceID?
    private let hardwareInputFormat: (AudioDeviceID) -> AVAudioFormat?
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    private let lock = NSLock()
    private var isRecording = false

    private var fileHandle: FileHandle?
    private var currentURL: URL?
    private var pcmBytesWritten: UInt32 = 0
    private let mode: String

    public convenience init(mode: String = "prose") {
        self.init(
            mode: mode,
            engine: SystemAudioEngine(),
            selectedInputDeviceUID: { AppSettings.audioInputDeviceUID },
            resolveInputDevice: { AudioInputDevices.deviceID(forUID: $0) },
            hardwareInputFormat: { AudioInputDevices.hardwareInputFormat(for: $0) }
        )
    }

    init(
        mode: String,
        engine: AudioEngineControlling,
        selectedInputDeviceUID: @escaping () -> String? = { nil },
        resolveInputDevice: @escaping (String) -> AudioDeviceID? = { _ in nil },
        hardwareInputFormat: @escaping (AudioDeviceID) -> AVAudioFormat? = { _ in nil }
    ) {
        self.mode = mode
        self.engine = engine
        self.selectedInputDeviceUID = selectedInputDeviceUID
        self.resolveInputDevice = resolveInputDevice
        self.hardwareInputFormat = hardwareInputFormat
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            case .denied, .restricted:
                cont.resume(returning: false)
            @unknown default:
                cont.resume(returning: false)
            }
        }
    }

    /// Begins capture and opens the on-disk WAV stream. The file is created
    /// immediately with a placeholder header so that even an instant crash
    /// leaves a recoverable file behind.
    public func start(mode modeOverride: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRecording else { return }

        let resolvedMode = modeOverride ?? mode
        let url: URL
        do {
            url = try RecordingArchive.newRecordingURL(mode: resolvedMode)
        } catch {
            throw AudioRecorderError.fileOpenFailed(error)
        }

        // Defensive cleanup of any prior recording's tap before reusing the
        // engine. Stop / reset clears in-flight render state without tearing
        // down the IO unit (which is what triggered the recursive_mutex
        // deadlock in 0.6.0).
        if engine.isRunning { engine.stop() }
        engine.removeInputTap()
        engine.reset()

        var pinnedFormat: AVAudioFormat?
        if let uid = selectedInputDeviceUID() {
            guard let deviceID = resolveInputDevice(uid) else {
                throw AudioRecorderError.inputDeviceUnavailable(uid)
            }
            do {
                try engine.selectInputDevice(deviceID)
                dlog("AudioRecorder.start pinned input uid=\(uid) deviceID=\(deviceID)")
            } catch {
                throw AudioRecorderError.inputDeviceSelectionFailed(uid, error)
            }
            guard let format = hardwareInputFormat(deviceID) else {
                throw AudioRecorderError.inputDeviceFormatUnavailable(uid)
            }
            pinnedFormat = format
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else { throw AudioRecorderError.formatConversionFailed }

        // Create the file with a 44-byte placeholder header (sizes = 0).
        let placeholder = wavHeader(
            sampleRate: Int(targetSampleRate),
            channels: 1,
            bitsPerSample: 16,
            pcmByteCount: 0
        )
        do {
            try placeholder.write(to: url, options: .atomic)
        } catch {
            throw AudioRecorderError.fileOpenFailed(error)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: url)
            try handle.seekToEnd()
        } catch {
            throw AudioRecorderError.fileOpenFailed(error)
        }
        self.fileHandle = handle
        self.currentURL = url
        self.pcmBytesWritten = 0

        // A pinned device's Core Audio hardware format is authoritative. The
        // AVAudioEngine input node may still expose the prior Bluetooth/output
        // route's cached format immediately after kAudioOutputUnitProperty_CurrentDevice.
        let initialInputFormat = pinnedFormat ?? engine.inputFormat()
        do {
            try configureAndStart(
                inputFormat: initialInputFormat,
                tapFormat: pinnedFormat,
                targetFormat: targetFormat
            )
        } catch let initialError {
            engine.removeInputTap()
            engine.stop()
            engine.reset()

            // A start cue can wake a Bluetooth output while the selected USB
            // microphone remains the input. During that route transition,
            // AVAudioEngine can first report the Bluetooth input's 8 kHz format
            // and then fail because the hardware input settles at 48 kHz. Once
            // the failed start returns, query the now-settled format and rebuild
            // the converter/tap exactly once.
            let settledInputFormat = engine.inputFormat()
            guard Self.inputFormatChanged(from: initialInputFormat, to: settledInputFormat) else {
                cleanUpFailedStart(handle: handle, url: url)
                throw AudioRecorderError.engineStartFailed(initialError)
            }

            dlog(
                "AudioRecorder.start recovering after input route change "
                    + "sampleRate=\(initialInputFormat.sampleRate)->\(settledInputFormat.sampleRate) "
                    + "channels=\(initialInputFormat.channelCount)->\(settledInputFormat.channelCount)"
            )
            do {
                try configureAndStart(
                    inputFormat: settledInputFormat,
                    tapFormat: nil,
                    targetFormat: targetFormat
                )
            } catch {
                engine.removeInputTap()
                engine.stop()
                engine.reset()
                cleanUpFailedStart(handle: handle, url: url)
                throw AudioRecorderError.engineStartFailed(error)
            }
        }
        isRecording = true
    }

    /// Stops capture, finalises the WAV header on disk, and returns the URL.
    /// Returns nil if no recording was in progress.
    @discardableResult
    public func stop() -> URL? {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            return nil
        }
        isRecording = false
        lock.unlock()

        // removeTap waits for any in-flight tap callback to finish. The tap
        // callback also takes `lock`, so holding it here can deadlock the main
        // thread while the audio callback waits for the same lock.
        engine.removeInputTap()
        engine.stop()

        lock.lock()
        defer { lock.unlock() }
        guard let handle = self.fileHandle, let url = self.currentURL else { return nil }
        finaliseHeader(handle: handle, pcmByteCount: pcmBytesWritten)
        try? handle.close()
        self.fileHandle = nil
        self.currentURL = nil
        self.converter = nil
        return url
    }

    private func configureAndStart(
        inputFormat: AVAudioFormat,
        tapFormat: AVAudioFormat?,
        targetFormat: AVAudioFormat
    ) throws {
        dlog(
            "AudioRecorder.start inputFormat sampleRate=\(inputFormat.sampleRate) "
                + "channels=\(inputFormat.channelCount)"
        )
        guard inputFormat.sampleRate > 0 else { throw AudioRecorderError.noInputNode }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatConversionFailed
        }
        self.converter = converter

        // Use the input node's native format. Supplying the earlier snapshot
        // here can raise an Objective-C exception if the route changes between
        // querying the node and installing the tap.
        engine.installInputTap(bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }
        engine.prepare()
        try engine.start()
    }

    private static func inputFormatChanged(
        from initial: AVAudioFormat,
        to settled: AVAudioFormat
    ) -> Bool {
        initial.sampleRate != settled.sampleRate
            || initial.channelCount != settled.channelCount
            || initial.commonFormat != settled.commonFormat
            || initial.isInterleaved != settled.isInterleaved
    }

    private func cleanUpFailedStart(handle: FileHandle, url: URL) {
        try? handle.close()
        fileHandle = nil
        currentURL = nil
        converter = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func handle(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate + 1024
        )
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let int16Channel = outBuf.int16ChannelData?[0]
        else { return }

        let bytes = Int(outBuf.frameLength) * 2
        let data = Data(bytes: int16Channel, count: bytes)
        lock.lock()
        // One-shot probe: log peak amplitude of the first decoded buffer so we
        // can tell the difference between "tap not firing" (no log) vs "tap
        // firing with silent samples" (log shows peak=0).
        if pcmBytesWritten == 0 {
            // Widen to Int before negating: `abs(Int16.min)` traps because
            // +32768 is not representable as Int16 (a clipped sample of
            // -32768 from a hot mic would crash the audio callback).
            var peak: Int = 0
            for f in 0..<Int(outBuf.frameLength) {
                let s = abs(Int(int16Channel[f]))
                if s > peak { peak = s }
            }
            dlog("AudioRecorder first buffer frames=\(outBuf.frameLength) peak=\(peak)")
        }
        if let handle = fileHandle {
            do {
                try handle.write(contentsOf: data)
                let nextTotal = UInt64(pcmBytesWritten) + UInt64(bytes)
                pcmBytesWritten = UInt32(min(nextTotal, UInt64(UInt32.max)))
            } catch {
                // Don't crash the audio thread; the next stop() will still
                // patch what we did write so far. Repair sweep handles header.
            }
        }
        lock.unlock()
    }

    // MARK: - WAV header

    private func wavHeader(
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int,
        pcmByteCount: UInt32
    ) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let chunkSize: UInt32 = pcmByteCount == 0 ? 36 : (36 + pcmByteCount)

        header.append(contentsOf: "RIFF".utf8)
        header.appendLE(chunkSize)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.appendLE(UInt32(16))
        header.appendLE(UInt16(1))
        header.appendLE(UInt16(channels))
        header.appendLE(UInt32(sampleRate))
        header.appendLE(UInt32(byteRate))
        header.appendLE(UInt16(blockAlign))
        header.appendLE(UInt16(bitsPerSample))
        header.append(contentsOf: "data".utf8)
        header.appendLE(pcmByteCount)
        return header
    }

    private func finaliseHeader(handle: FileHandle, pcmByteCount: UInt32) {
        let riffSize = UInt32(36) &+ pcmByteCount
        try? handle.seek(toOffset: 4)
        try? handle.write(contentsOf: RecordingArchive.littleEndianBytes(riffSize))
        try? handle.seek(toOffset: 40)
        try? handle.write(contentsOf: RecordingArchive.littleEndianBytes(pcmByteCount))
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
