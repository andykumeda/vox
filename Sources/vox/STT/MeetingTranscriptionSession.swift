import Foundation

/// Coordinates a single end-to-end meeting capture: record system audio + local mic in
/// parallel, slice each into chunks, upload chunks to Whisper with infinite retry on
/// transport failures, persist segments tagged by source.
/// Singleton via `.shared` for the app; tests instantiate directly with mocks.
public final class MeetingTranscriptionSession {
    public typealias Chunker = (URL, URL) async throws -> [URL]
    public typealias Transcribe = (URL, Double, SegmentSource) async throws -> [TranscriptSegment]

    public static let shared = MeetingTranscriptionSession(
        store: MeetingTranscriptStore(),
        recorder: nil,
        micRecorder: nil,
        captureMic: true,
        chunker: { input, dir in
            try await MeetingChunker().split(input: input, outputDirectory: dir)
        },
        transcribe: { url, offset, source in
            let key = KeychainStore().read() ?? ""
            return try await OpenAITranscriber.transcribeMeetingChunk(
                fileURL: url, offsetSeconds: offset, apiKey: key, source: source
            )
        },
        apiKey: { KeychainStore().read() },
        retainAudio: { AppSettings.meetingRetainAudio }
    )

    public let store: MeetingTranscriptStore
    private let systemRecorderFactory: () -> MeetingAudioRecording
    private let micRecorderFactory: () -> MeetingAudioRecording?
    private let chunker: Chunker
    private let transcribe: Transcribe
    private let apiKeyProvider: () -> String?
    private let retainAudioProvider: () -> Bool
    private let backoffSchedule: [Double]
    private let chunkDuration: Double = 300

    private var systemRecorder: MeetingAudioRecording?
    private var micRecorder: MeetingAudioRecording?
    private var uploadTask: Task<Void, Never>?
    private let lock = NSLock()
    private var session: TranscriptSession?

    public var activeSessionID: UUID? {
        lock.lock(); defer { lock.unlock() }
        return session?.id
    }

    public var statusSnapshot: TranscriptSession.Status? {
        lock.lock(); defer { lock.unlock() }
        return session?.status
    }

    public var isRecording: Bool {
        statusSnapshot == .recording
    }

    public var isActive: Bool {
        switch statusSnapshot {
        case .recording, .chunking, .transcribing: return true
        default: return false
        }
    }

    public init(
        store: MeetingTranscriptStore,
        recorder: MeetingAudioRecording?,
        micRecorder: MeetingAudioRecording? = nil,
        captureMic: Bool = false,
        chunker: @escaping Chunker,
        transcribe: @escaping Transcribe,
        apiKey: @escaping () -> String?,
        retainAudio: @escaping () -> Bool,
        backoffSchedule: [Double] = [1, 2, 4, 8, 16, 30]
    ) {
        self.store = store
        if let recorder = recorder {
            self.systemRecorderFactory = { recorder }
        } else {
            self.systemRecorderFactory = {
                if #available(macOS 13.0, *) { return MeetingAudioCapture() }
                fatalError("ScreenCaptureKit requires macOS 13+")
            }
        }
        if let micRecorder = micRecorder {
            self.micRecorderFactory = { micRecorder }
        } else if captureMic {
            self.micRecorderFactory = { MeetingMicCapture() }
        } else {
            self.micRecorderFactory = { nil }
        }
        self.chunker = chunker
        self.transcribe = transcribe
        self.apiKeyProvider = apiKey
        self.retainAudioProvider = retainAudio
        self.backoffSchedule = backoffSchedule
    }

    public enum SessionError: Error, CustomStringConvertible {
        case alreadyActive
        case notRecording
        case missingAPIKey

        public var description: String {
            switch self {
            case .alreadyActive: return "A meeting session is already active."
            case .notRecording: return "No active meeting session to stop."
            case .missingAPIKey: return "OpenAI API key missing."
            }
        }
    }

    public func start() async throws {
        lock.lock()
        if let existing = session {
            switch existing.status {
            case .recording, .chunking, .transcribing:
                lock.unlock(); throw SessionError.alreadyActive
            case .completed, .cancelled, .failed:
                session = nil
            }
        }
        let id = UUID()
        let now = Date()
        let title = "Meeting \(Self.titleFormatter.string(from: now))"
        let initial = TranscriptSession(
            id: id, title: title, startedAt: now, endedAt: nil,
            status: .recording, chunksTotal: 0, chunksCompleted: 0,
            segments: [], audioRetained: retainAudioProvider()
        )
        self.session = initial
        lock.unlock()

        try store.save(initial)

        let system = systemRecorderFactory()
        self.systemRecorder = system
        try await system.start(outputURL: store.audioFile(id: id))

        // Mic is best-effort: if it fails (denied/init error) we still want the system-audio
        // recording to proceed. Log the failure and continue with mic disabled for this session.
        if let mic = micRecorderFactory() {
            do {
                try await mic.start(outputURL: store.micFile(id: id))
                self.micRecorder = mic
            } catch {
                dlog("MeetingMicCapture start failed (continuing without mic): \(error)")
                self.micRecorder = nil
            }
        }
    }

    public func stop() async throws {
        lock.lock()
        guard var current = session, current.status == .recording else {
            lock.unlock(); throw SessionError.notRecording
        }
        current.status = .chunking
        current.endedAt = Date()
        self.session = current
        lock.unlock()
        try store.save(current)

        guard let system = self.systemRecorder else { throw SessionError.notRecording }
        let systemURL = try await system.stop()
        let systemFailureReason = system.lastFailureReason
        let systemStartedAt = system.audioStartedAt
        self.systemRecorder = nil

        var micURL: URL? = nil
        var micFailureReason: String? = nil
        var micStartedAt: Date? = nil
        if let mic = self.micRecorder {
            do {
                let url = try await mic.stop()
                micFailureReason = mic.lastFailureReason
                micStartedAt = mic.audioStartedAt
                if micFailureReason == nil {
                    micURL = url
                }
            } catch {
                micFailureReason = "Mic stop failed: \(error)"
            }
            self.micRecorder = nil
        }

        let sid = current.id
        // Hard-fail only if BOTH streams are unusable. If system captured nothing but mic
        // worked, proceed with mic-only transcript. Vice versa.
        if let sysReason = systemFailureReason, micURL == nil {
            updateSession { s in
                s.status = .failed
                s.failureReason = "System audio: \(sysReason)" +
                    (micFailureReason.map { " | Mic: \($0)" } ?? "")
            }
            return
        }
        if let micReason = micFailureReason {
            dlog("Mic capture failed (continuing with system audio only): \(micReason)")
        }

        let usableSystemURL: URL? = (systemFailureReason == nil) ? systemURL : nil

        // Compute per-stream wall-clock offset relative to a shared reference (the earliest
        // stream that produced its first audible content). Apply it to each segment's
        // startTime/endTime so segments from both streams share one timeline.
        let referenceTime: Date = {
            switch (systemStartedAt, micStartedAt) {
            case let (s?, m?): return min(s, m)
            case let (s?, nil): return s
            case let (nil, m?): return m
            default: return current.startedAt
            }
        }()
        let systemShift = systemStartedAt.map { $0.timeIntervalSince(referenceTime) } ?? 0
        let micShift = micStartedAt.map { $0.timeIntervalSince(referenceTime) } ?? 0
        dlog("Meeting timeline shifts: system=\(systemShift)s mic=\(micShift)s")

        uploadTask = Task { [weak self] in
            await self?.runChunkAndUpload(
                systemURL: usableSystemURL,
                micURL: micURL,
                systemShift: systemShift,
                micShift: micShift,
                sessionID: sid
            )
        }
    }

    public func cancel() {
        uploadTask?.cancel()
    }

    /// Block the caller until the upload task finishes (used by tests; production fires-and-forgets).
    public func waitForCompletion() async {
        await uploadTask?.value
    }

    private func runChunkAndUpload(
        systemURL: URL?, micURL: URL?,
        systemShift: Double, micShift: Double,
        sessionID: UUID
    ) async {
        // (source, chunks, dir, shift, audibleDurationSec)
        var streams: [(SegmentSource, [URL], URL, Double, Double)] = []

        if let systemURL = systemURL {
            let dir = store.chunksDirectory(id: sessionID, source: .remote)
            let prepped = await prepareForChunking(streamURL: systemURL, baseShift: systemShift)
            do {
                let chunks = try await chunker(prepped.url, dir)
                streams.append((.remote, chunks, dir, prepped.shift, prepped.audibleDuration))
            } catch let MeetingChunkerError.zeroDurationAsset {
                dlog("System audio chunking: zero-duration asset")
            } catch {
                dlog("System audio chunking failed: \(error)")
            }
        }
        if let micURL = micURL {
            let dir = store.chunksDirectory(id: sessionID, source: .local)
            let prepped = await prepareForChunking(streamURL: micURL, baseShift: micShift)
            do {
                let chunks = try await chunker(prepped.url, dir)
                streams.append((.local, chunks, dir, prepped.shift, prepped.audibleDuration))
            } catch let MeetingChunkerError.zeroDurationAsset {
                dlog("Mic chunking: zero-duration asset")
            } catch {
                dlog("Mic chunking failed: \(error)")
            }
        }

        guard !streams.isEmpty else {
            updateSession { s in
                s.status = .failed
                s.failureReason = "No audio captured. Check that audio was actually playing through the system during the recording, that the microphone is not muted, and that Screen Recording + Microphone permissions are granted to Vox."
            }
            return
        }

        let totalChunks = streams.reduce(0) { $0 + $1.1.count }
        updateSession { s in
            s.chunksTotal = totalChunks
            s.status = .transcribing
        }

        var completed = 0
        for (source, chunks, _, shift, audibleDuration) in streams {
            for (i, chunkURL) in chunks.enumerated() {
                if Task.isCancelled { break }
                let offset = Double(i) * chunkDuration
                let segments: [TranscriptSegment]
                do {
                    segments = try await transcribeWithInfiniteRetry(
                        url: chunkURL, offset: offset, source: source
                    )
                } catch is CancellationError {
                    break
                } catch {
                    updateSession { s in
                        s.status = .failed
                        s.failureReason = "Transcription failed (\(source.rawValue)): \(error)"
                    }
                    return
                }
                // Drop Whisper hallucinations whose timestamps fall outside the actual
                // audible portion of the stream (Whisper sometimes invents segments past
                // the end of the file or right after a long silence).
                let hallucinationCap = audibleDuration > 0 ? audibleDuration + 1.5 : .greatestFiniteMagnitude
                let shifted: [TranscriptSegment] = segments.compactMap { seg in
                    if seg.startTime > hallucinationCap { return nil }
                    if isHallucinated(seg) {
                        dlog("Meeting hallucination dropped [\(source.rawValue)] \(seg.startTime)-\(seg.endTime)s: \(seg.text.prefix(80))")
                        return nil
                    }
                    return TranscriptSegment(
                        startTime: seg.startTime + shift,
                        endTime: min(seg.endTime, hallucinationCap) + shift,
                        text: seg.text,
                        source: seg.source
                    )
                }
                updateSession { s in
                    s.segments.append(contentsOf: shifted)
                    completed += 1
                    s.chunksCompleted = completed
                }
            }
            if Task.isCancelled { break }
        }

        if Task.isCancelled {
            updateSession { s in
                s.segments.sort(by: TranscriptSegment.byStartTime)
                s.status = .cancelled
            }
            return
        }

        updateSession { s in
            s.segments.sort(by: TranscriptSegment.byStartTime)
            s.status = .completed
        }
        for (_, _, dir, _, _) in streams {
            try? FileManager.default.removeItem(at: dir)
        }
        if !retainAudioProvider() {
            try? store.purgeAudio(for: sessionID)
        }
    }

    /// Detect Whisper hallucination patterns on near-silent audio: long monotonous
    /// repetitions ("yeah, yeah, yeah, ..." for 30+ seconds), single-word loops, and
    /// very low unique-word ratios over multi-second windows. Returns true if the
    /// segment should be dropped.
    private func isHallucinated(_ seg: TranscriptSegment) -> Bool {
        let normalized = seg.text
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "!", with: " ")
            .replacingOccurrences(of: "?", with: " ")
        let words = normalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let total = words.count
        let duration = seg.endTime - seg.startTime
        guard total >= 6 else { return false }

        let uniqueRatio = Double(Set(words).count) / Double(total)
        if uniqueRatio < 0.20 && duration > 3 { return true }

        // Same word repeating in a long run (e.g. "yeah, yeah, yeah, ..." × 30+).
        if let head = words.first {
            var run = 1
            for w in words.dropFirst() {
                if w == head { run += 1 } else { break }
            }
            if run >= 8 { return true }
        }
        return false
    }

    /// Trim leading/trailing silence from a stream before chunking. If detection or trim
    /// fails (e.g. unit-test fixture file isn't valid audio), fall back to the original URL
    /// with no shift adjustment. Returns the URL to feed to the chunker, the cumulative
    /// shift to apply to that stream's segments, and the audible duration (used to cap
    /// Whisper hallucination segments).
    private func prepareForChunking(
        streamURL: URL, baseShift: Double
    ) async -> (url: URL, shift: Double, audibleDuration: Double) {
        let bounds: AudibleBounds
        do {
            bounds = try SilenceTrim.detectBounds(url: streamURL)
        } catch {
            dlog("SilenceTrim.detectBounds failed (\(streamURL.lastPathComponent)): \(error) — using original")
            return (streamURL, baseShift, 0)
        }
        guard bounds.hasAudibleContent else {
            dlog("SilenceTrim: no audible content in \(streamURL.lastPathComponent) (total=\(bounds.totalDurationSec)s)")
            return (streamURL, baseShift, 0)
        }
        // Skip the trim step entirely if leading silence is short — re-encoding for
        // <0.5s saves no useful API cost.
        let padding = 0.25
        let trimmedDuration = (bounds.lastAudibleSec + padding) - max(0, bounds.firstAudibleSec - padding)
        if bounds.firstAudibleSec < 0.5 && bounds.totalDurationSec - bounds.lastAudibleSec < 0.5 {
            dlog("SilenceTrim: \(streamURL.lastPathComponent) firstAudible=\(bounds.firstAudibleSec)s lastAudible=\(bounds.lastAudibleSec)s — skipping trim")
            return (streamURL, baseShift, trimmedDuration)
        }
        let trimmedURL = streamURL
            .deletingLastPathComponent()
            .appendingPathComponent(streamURL.deletingPathExtension().lastPathComponent + "-trimmed.m4a")
        do {
            try await SilenceTrim.trim(input: streamURL, output: trimmedURL, bounds: bounds, padding: padding)
        } catch {
            dlog("SilenceTrim.trim failed (\(streamURL.lastPathComponent)): \(error) — using original")
            return (streamURL, baseShift, trimmedDuration)
        }
        let leadingTrim = max(0, bounds.firstAudibleSec - padding)
        dlog("SilenceTrim: \(streamURL.lastPathComponent) trimmed leading=\(leadingTrim)s audible=\(trimmedDuration)s")
        return (trimmedURL, baseShift + leadingTrim, trimmedDuration)
    }

    private func transcribeWithInfiniteRetry(
        url: URL, offset: Double, source: SegmentSource
    ) async throws -> [TranscriptSegment] {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await transcribe(url, offset, source)
            } catch let TranscriptionError.transportError(_) {
                let delay = backoffSchedule[min(attempt, backoffSchedule.count - 1)]
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            } catch {
                throw error
            }
        }
    }

    private func updateSession(_ mutate: (inout TranscriptSession) -> Void) {
        lock.lock()
        guard var s = session else { lock.unlock(); return }
        mutate(&s)
        session = s
        lock.unlock()
        try? store.save(s)
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

private extension TranscriptSegment {
    /// Stable interleaving order: by startTime ascending; ties broken so local appears
    /// before remote (the user's own utterance usually triggers the response).
    static func byStartTime(_ a: TranscriptSegment, _ b: TranscriptSegment) -> Bool {
        if a.startTime != b.startTime { return a.startTime < b.startTime }
        if a.source != b.source { return a.source == .local }
        return a.endTime < b.endTime
    }
}
