import AVFoundation
import Foundation

public enum AudioRecorderError: Error {
    case permissionDenied
    case engineStartFailed(Error)
    case noInputNode
    case formatConversionFailed
}

/// Records microphone input and produces a 16kHz mono 16-bit PCM WAV blob on stop.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var outputBuffer = Data()
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    private let lock = NSLock()
    private var isRecording = false

    public init() {}

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

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRecording else { return }

        outputBuffer.removeAll(keepingCapacity: true)

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

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error)
        }
    }

    /// Stops recording and returns a complete WAV file as Data.
    public func stop() -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let pcm = outputBuffer
        outputBuffer = Data()
        return wavWrap(pcm: pcm, sampleRate: Int(targetSampleRate), channels: 1, bitsPerSample: 16)
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
        outputBuffer.append(data)
        lock.unlock()
    }

    // MARK: - WAV header

    private func wavWrap(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize

        header.append(contentsOf: "RIFF".utf8)
        header.appendLE(UInt32(chunkSize))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.appendLE(UInt32(16))           // fmt chunk size
        header.appendLE(UInt16(1))            // PCM format
        header.appendLE(UInt16(channels))
        header.appendLE(UInt32(sampleRate))
        header.appendLE(UInt32(byteRate))
        header.appendLE(UInt16(blockAlign))
        header.appendLE(UInt16(bitsPerSample))
        header.append(contentsOf: "data".utf8)
        header.appendLE(dataSize)

        header.append(pcm)
        return header
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
