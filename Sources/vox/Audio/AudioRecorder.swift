import AVFoundation
import Foundation

public enum AudioRecorderError: Error {
    case permissionDenied
    case engineStartFailed(Error)
    case noInputNode
    case formatConversionFailed
    case fileOpenFailed(Error)
}

/// Records microphone input as 16kHz mono 16-bit PCM and streams the WAV to disk
/// while capture is in progress. The output URL lives under
/// `RecordingArchive.directory()` so the recording survives crashes, silence
/// gating, transcription failure, or replays. Header sizes are placeholders
/// until `stop()` patches them; see `RecordingArchive.repairOrphans` for the
/// crash-recovery path.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    private let lock = NSLock()
    private var isRecording = false

    private var fileHandle: FileHandle?
    private var currentURL: URL?
    private var pcmBytesWritten: UInt32 = 0
    private let mode: String

    public init(mode: String = "prose") {
        self.mode = mode
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

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw AudioRecorderError.noInputNode }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else { throw AudioRecorderError.formatConversionFailed }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatConversionFailed
        }
        self.converter = conv

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

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            input.removeTap(onBus: 0)
            try? handle.close()
            self.fileHandle = nil
            throw AudioRecorderError.engineStartFailed(error)
        }
    }

    /// Stops capture, finalises the WAV header on disk, and returns the URL.
    /// Returns nil if no recording was in progress.
    @discardableResult
    public func stop() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        guard let handle = self.fileHandle, let url = self.currentURL else { return nil }
        finaliseHeader(handle: handle, pcmByteCount: pcmBytesWritten)
        try? handle.close()
        self.fileHandle = nil
        self.currentURL = nil
        return url
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
