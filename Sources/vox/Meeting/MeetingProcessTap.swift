import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

/// Captures audio from specific bundle-ID processes via the macOS 14.4+
/// CoreAudio process-tap API. Used to record VoIP apps whose audio path
/// (Continuity Call, FaceTime) is invisible to SCStream's display tap.
@available(macOS 14.4, *)
public enum MeetingProcessTapError: Error, CustomStringConvertible {
    case unsupportedOS
    case noTargetProcess
    case translatePIDFailed(OSStatus, pid_t)
    case tapCreationFailed(OSStatus)
    case tapPropertyFailed(OSStatus, String)
    case aggregateCreationFailed(OSStatus)
    case ioProcInstallFailed(OSStatus)
    case ioProcStartFailed(OSStatus)
    case writerInit(Error?)
    case notRecording

    public var description: String {
        switch self {
        case .unsupportedOS:
            return "Process tap requires macOS 14.4 or newer."
        case .noTargetProcess:
            return "No target VoIP app (Phone/FaceTime) running."
        case .translatePIDFailed(let s, let pid):
            return "PID→AudioObject translate failed (status=\(s) pid=\(pid))."
        case .tapCreationFailed(let s):
            return "AudioHardwareCreateProcessTap failed (status=\(s))."
        case .tapPropertyFailed(let s, let k):
            return "Tap property \(k) fetch failed (status=\(s))."
        case .aggregateCreationFailed(let s):
            return "AudioHardwareCreateAggregateDevice failed (status=\(s))."
        case .ioProcInstallFailed(let s):
            return "AudioDeviceCreateIOProcIDWithBlock failed (status=\(s))."
        case .ioProcStartFailed(let s):
            return "AudioDeviceStart failed (status=\(s))."
        case .writerInit(let e):
            return "Phone-tap AVAssetWriter init failed: \(e?.localizedDescription ?? "nil")"
        case .notRecording:
            return "stop() called without a prior start()."
        }
    }
}

@available(macOS 14.4, *)
public final class MeetingProcessTap: NSObject, MeetingAudioRecording {
    public private(set) var lastFailureReason: String?
    public private(set) var audioStartedAt: Date?

    /// Default VoIP apps SCStream misses. Phone.app routes Continuity calls
    /// through a private CoreAudio path; FaceTime audio is similarly cloaked
    /// from screen-capture taps.
    public static let defaultVoIPBundleIDs: Set<String> = [
        "com.apple.mobilephone",
        "com.apple.FaceTime"
    ]

    /// System daemons that actually render call audio (Phone.app / FaceTime.app
    /// only host UI). `callservicesd` brokers Continuity Calls; `avconferenced`
    /// handles FaceTime audio/video. Tap these directly because their audio
    /// path bypasses both SCStream and process-tapping the UI app.
    public static let defaultVoIPDaemonNames: Set<String> = [
        "callservicesd",
        "avconferenced",
        "imagent",
        "identityservicesd"
    ]

    private let bundleIDs: Set<String>
    private let daemonNames: Set<String>
    private let queue = DispatchQueue(label: "vox.meeting.phonetap", qos: .userInitiated)

    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var formatDescription: CMAudioFormatDescription?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var sampleBufferCount = 0

    public init(
        bundleIDs: Set<String> = MeetingProcessTap.defaultVoIPBundleIDs,
        daemonNames: Set<String> = MeetingProcessTap.defaultVoIPDaemonNames
    ) {
        self.bundleIDs = bundleIDs
        self.daemonNames = daemonNames
        super.init()
    }

    public func start(outputURL: URL) async throws {
        // 1) Resolve PIDs of running target processes (apps via bundle ID,
        //    daemons via process name lookup).
        var targetPIDs: [(pid_t, String)] = []
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, bundleIDs.contains(id) {
                targetPIDs.append((app.processIdentifier, id))
            }
        }
        for (pid, name) in Self.daemonPIDs(matching: daemonNames) {
            targetPIDs.append((pid, name))
        }
        guard !targetPIDs.isEmpty else { throw MeetingProcessTapError.noTargetProcess }

        // 2) PID → process AudioObjectID
        var processObjects: [AudioObjectID] = []
        for (pid, name) in targetPIDs {
            var pidVar: pid_t = pid
            var process: AudioObjectID = 0
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &addr,
                UInt32(MemoryLayout<pid_t>.size), &pidVar,
                &size, &process
            )
            if status == noErr, process != 0 {
                processObjects.append(process)
                dlog("MeetingProcessTap: targeting \(name) pid=\(pid) audioObj=\(process)")
            } else {
                dlog("MeetingProcessTap: PID translate failed name=\(name) pid=\(pid) status=\(status)")
            }
        }
        guard !processObjects.isEmpty else { throw MeetingProcessTapError.noTargetProcess }

        // 3) Build CATapDescription (stereo mixdown of targeted processes)
        let desc = CATapDescription(stereoMixdownOfProcesses: processObjects)
        desc.isPrivate = true
        desc.isExclusive = false
        desc.name = "Vox Phone Tap"

        // 4) Create the tap
        var tap: AudioObjectID = 0
        var status = AudioHardwareCreateProcessTap(desc, &tap)
        guard status == noErr else { throw MeetingProcessTapError.tapCreationFailed(status) }
        self.tapID = tap

        // 5) Fetch tap UID and stream format
        let tapUID: String
        do {
            tapUID = try Self.getCFStringProperty(tap, selector: kAudioTapPropertyUID) as String
        } catch {
            cleanupTap()
            throw error
        }
        let asbd: AudioStreamBasicDescription
        do {
            asbd = try Self.getProperty(tap, selector: kAudioTapPropertyFormat)
        } catch {
            cleanupTap()
            throw error
        }
        var fmtASBD = asbd
        var formatDesc: CMFormatDescription?
        let fmtStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &fmtASBD,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard fmtStatus == noErr, let formatDesc = formatDesc else {
            cleanupTap()
            throw MeetingProcessTapError.tapPropertyFailed(fmtStatus, "CMAudioFormatDescriptionCreate")
        }
        self.formatDescription = formatDesc

        // 6) Private aggregate device wrapping the tap
        let aggUID = "vox-phone-tap-\(UUID().uuidString)"
        let aggConfig: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Vox Phone Tap",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUID,
                    kAudioSubTapDriftCompensationKey as String: false
                ]
            ],
            kAudioAggregateDeviceSubDeviceListKey as String: [] as [Any]
        ]
        var agg: AudioObjectID = 0
        status = AudioHardwareCreateAggregateDevice(aggConfig as CFDictionary, &agg)
        guard status == noErr else {
            cleanupTap()
            throw MeetingProcessTapError.aggregateCreationFailed(status)
        }
        self.aggregateID = agg

        // 7) AVAssetWriter — AAC m4a
        try? FileManager.default.removeItem(at: outputURL)
        let assetWriter: AVAssetWriter
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            cleanupAll()
            throw MeetingProcessTapError.writerInit(error)
        }
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: asbd.mSampleRate,
            AVNumberOfChannelsKey: Int(asbd.mChannelsPerFrame)
        ]
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: aacSettings,
            sourceFormatHint: formatDesc
        )
        input.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(input) else {
            cleanupAll()
            throw MeetingProcessTapError.writerInit(nil)
        }
        assetWriter.add(input)
        guard assetWriter.startWriting() else {
            cleanupAll()
            throw MeetingProcessTapError.writerInit(assetWriter.error)
        }
        self.writer = assetWriter
        self.writerInput = input
        self.outputURL = outputURL
        self.sessionStarted = false
        self.sampleBufferCount = 0
        self.lastFailureReason = nil
        self.audioStartedAt = nil

        // 8) Install IO proc and start
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, queue) { [weak self] _, inputData, inputTime, _, _ in
            self?.handle(inputData: inputData, time: inputTime.pointee)
        }
        guard status == noErr, let procID = procID else {
            cleanupAll()
            throw MeetingProcessTapError.ioProcInstallFailed(status)
        }
        self.ioProcID = procID
        status = AudioDeviceStart(agg, procID)
        guard status == noErr else {
            cleanupAll()
            throw MeetingProcessTapError.ioProcStartFailed(status)
        }
        dlog("MeetingProcessTap started → \(outputURL.path) processes=\(processObjects.count) sr=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame)")
    }

    public func stop() async throws -> URL {
        guard let outputURL = outputURL, let writer = writer, let input = writerInput else {
            throw MeetingProcessTapError.notRecording
        }
        if let procID = ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            lastFailureReason = "writer status=\(writer.status.rawValue) error=\(writer.error?.localizedDescription ?? "nil") sampleBuffers=\(sampleBufferCount)"
            dlog("MeetingProcessTap finishWriting failed: \(lastFailureReason ?? "")")
        } else if sampleBufferCount == 0 {
            lastFailureReason = "No audio buffers from VoIP process tap. Phone/FaceTime not playing call audio during recording."
            dlog("MeetingProcessTap finishWriting ok but 0 sample buffers")
        } else {
            dlog("MeetingProcessTap finishWriting ok sampleBuffers=\(sampleBufferCount)")
        }
        self.writer = nil
        self.writerInput = nil
        self.outputURL = nil
        self.formatDescription = nil
        return outputURL
    }

    // MARK: - IO callback

    private func handle(inputData: UnsafePointer<AudioBufferList>, time: AudioTimeStamp) {
        guard let formatDesc = formatDescription,
              let input = writerInput,
              let writer = writer else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)!.pointee
        let bytesPerFrame = max(1, Int(asbd.mBytesPerFrame))

        let buf = inputData.pointee.mBuffers
        let dataSize = Int(buf.mDataByteSize)
        let frameCount = dataSize / bytesPerFrame
        guard frameCount > 0, let dataPtr = buf.mData else { return }

        let nanos = AudioConvertHostTimeToNanos(time.mHostTime)
        let pts = CMTime(value: CMTimeValue(nanos), timescale: CMTimeScale(NSEC_PER_SEC))

        if !sessionStarted {
            audioStartedAt = Date()
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        var blockBuffer: CMBlockBuffer?
        var bbStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard bbStatus == noErr, let blockBuffer = blockBuffer else { return }
        bbStatus = CMBlockBufferReplaceDataBytes(
            with: dataPtr, blockBuffer: blockBuffer,
            offsetIntoDestination: 0, dataLength: dataSize
        )
        guard bbStatus == noErr else { return }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        let sbStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let sampleBuffer = sampleBuffer else { return }

        if input.isReadyForMoreMediaData, input.append(sampleBuffer) {
            sampleBufferCount += 1
        }
    }

    // MARK: - Cleanup helpers

    private func cleanupTap() {
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func cleanupAll() {
        if let procID = ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        cleanupTap()
        if let w = writer { w.cancelWriting() }
        writer = nil
        writerInput = nil
        outputURL = nil
        formatDescription = nil
    }

    // MARK: - CoreAudio property helpers

    private static func getProperty<T>(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> T {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size)
        guard status == noErr else {
            throw MeetingProcessTapError.tapPropertyFailed(status, "\(selector)")
        }
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer { ptr.deallocate() }
        status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, ptr)
        guard status == noErr else {
            throw MeetingProcessTapError.tapPropertyFailed(status, "\(selector)")
        }
        return ptr.assumingMemoryBound(to: T.self).pointee
    }

    /// Enumerate all running processes; return (pid, name) pairs whose
    /// executable name matches `names`. Uses libproc (stable since macOS 10.5).
    private static func daemonPIDs(matching names: Set<String>) -> [(pid_t, String)] {
        guard !names.isEmpty else { return [] }
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let count = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * count))
        guard written > 0 else { return [] }
        let actual = Int(written) / MemoryLayout<pid_t>.size

        var matches: [(pid_t, String)] = []
        var nameBuf = [CChar](repeating: 0, count: 1024)
        for idx in 0..<actual {
            let pid = pids[idx]
            guard pid > 0 else { continue }
            nameBuf.withUnsafeMutableBufferPointer { ptr in
                _ = proc_name(pid, ptr.baseAddress, UInt32(ptr.count))
            }
            let pname = String(cString: nameBuf)
            if !pname.isEmpty, names.contains(pname) {
                matches.append((pid, pname))
            }
        }
        return matches
    }

    private static func getCFStringProperty(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> CFString {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        guard status == noErr, let value = value else {
            throw MeetingProcessTapError.tapPropertyFailed(status, "\(selector)")
        }
        return value.takeRetainedValue()
    }
}
