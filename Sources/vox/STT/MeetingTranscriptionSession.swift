import AVFoundation
import Foundation

/// Coordinates a single end-to-end meeting capture: record system audio + local mic in
/// parallel, slice each into chunks, upload chunks to Whisper with infinite retry on
/// transport failures, persist segments tagged by source.
/// Singleton via `.shared` for the app; tests instantiate directly with mocks.
public final class MeetingTranscriptionSession {
    public typealias Chunker = (URL, URL) async throws -> [URL]
    public typealias Transcribe = (URL, Double, SegmentSource) async throws -> [TranscriptSegment]
    /// Mixed-audio diarized transcribe (Deepgram). Receives a single mixed
    /// m4a covering the whole meeting; returns segments tagged with speakerID.
    public typealias DeepgramTranscribe = (URL) async throws -> [TranscriptSegment]
    /// Optional post-completion summarizer. Returns the summary markdown
    /// or throws. Tests inject a mock; production injects the live OpenAI
    /// chat-completions client.
    public typealias Summarize = ([TranscriptSegment]) async throws -> String

    public static let shared = MeetingTranscriptionSession(
        store: MeetingTranscriptStore(),
        recorder: nil,
        micRecorder: nil,
        phoneRecorder: nil,
        captureMic: true,
        captureVoIPProcesses: true,
        chunker: { input, dir in
            try await MeetingChunker().split(input: input, outputDirectory: dir)
        },
        transcribe: { url, offset, source in
            let key = KeychainStore().read() ?? ""
            return try await OpenAITranscriber.transcribeMeetingChunk(
                fileURL: url, offsetSeconds: offset, apiKey: key, source: source
            )
        },
        deepgramTranscribe: { mixedURL in
            let key = KeychainStore(account: "deepgram-api-key").read() ?? ""
            return try await DeepgramTranscriber.transcribeMeeting(
                fileURL: mixedURL, apiKey: key
            )
        },
        provider: { AppSettings.meetingProvider },
        apiKey: { KeychainStore().read() },
        deepgramAPIKey: { KeychainStore(account: "deepgram-api-key").read() },
        retainAudio: { false },
        summarize: { segments in
            try await MeetingSummarizer(
                apiKeyProvider: { KeychainStore().read() }
            ).summarize(segments: segments)
        },
        summarizeEnabled: { AppSettings.meetingSummaryEnabled }
    )

    public let store: MeetingTranscriptStore
    private let systemRecorderFactory: () -> MeetingAudioRecording
    private let micRecorderFactory: () -> MeetingAudioRecording?
    private let phoneRecorderFactory: () -> MeetingAudioRecording?
    private let chunker: Chunker
    private let transcribe: Transcribe
    private let deepgramTranscribe: DeepgramTranscribe?
    private let providerProvider: () -> MeetingProvider
    private let retainAudioProvider: () -> Bool
    private let summarize: Summarize?
    private let summarizeEnabledProvider: () -> Bool
    private let saveSession: (TranscriptSession) throws -> Void
    /// Preflight gate. Default calls `MeetingPreflight.gate` with live
    /// AppSettings; tests pass `{ .success(()) }` to bypass.
    private let preflight: () -> Result<Void, MeetingGateError>
    private let backoffSchedule: [Double]
    private let chunkDuration: Double = 300

    private var systemRecorder: MeetingAudioRecording?
    private var micRecorder: MeetingAudioRecording?
    private var phoneRecorder: MeetingAudioRecording?
    private var uploadTask: Task<Void, Never>?
    private let lock = NSLock()
    private var session: TranscriptSession?

    public var activeSessionID: UUID? {
        withSessionLock { session?.id }
    }

    public var statusSnapshot: TranscriptSession.Status? {
        withSessionLock { session?.status }
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
        phoneRecorder: MeetingAudioRecording? = nil,
        captureMic: Bool = false,
        captureVoIPProcesses: Bool = false,
        chunker: @escaping Chunker,
        transcribe: @escaping Transcribe,
        deepgramTranscribe: DeepgramTranscribe? = nil,
        provider: @escaping () -> MeetingProvider = { .openai },
        apiKey: @escaping () -> String?,
        deepgramAPIKey: @escaping () -> String? = {
            KeychainStore(account: "deepgram-api-key").read()
        },
        retainAudio: @escaping () -> Bool,
        summarize: Summarize? = nil,
        summarizeEnabled: @escaping () -> Bool = { false },
        preflight: (() -> Result<Void, MeetingGateError>)? = nil,
        saveSession: ((TranscriptSession) throws -> Void)? = nil,
        backoffSchedule: [Double] = [1, 2, 4, 8, 16, 30],
        systemRecorderFactory: (() -> MeetingAudioRecording)? = nil
    ) {
        self.store = store
        if let systemRecorderFactory {
            self.systemRecorderFactory = systemRecorderFactory
        } else if let recorder {
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
        if let phoneRecorder = phoneRecorder {
            self.phoneRecorderFactory = { phoneRecorder }
        } else if captureVoIPProcesses {
            self.phoneRecorderFactory = {
                if #available(macOS 14.4, *) { return MeetingProcessTap() }
                return nil
            }
        } else {
            self.phoneRecorderFactory = { nil }
        }
        self.chunker = chunker
        self.transcribe = transcribe
        self.deepgramTranscribe = deepgramTranscribe
        self.providerProvider = provider
        self.retainAudioProvider = retainAudio
        self.summarize = summarize
        self.summarizeEnabledProvider = summarizeEnabled
        self.saveSession = saveSession ?? { try store.save($0) }
        if let preflight = preflight {
            self.preflight = preflight
        } else {
            // Resolve the selected provider at start time so the default gate
            // checks the same credential that transcription will use.
            let selectedProvider = provider
            let openAIKeyProvider = apiKey
            let deepgramKeyProvider = deepgramAPIKey
            self.preflight = {
                let key: String?
                switch selectedProvider() {
                case .deepgram:
                    key = deepgramKeyProvider()
                case .openai:
                    key = openAIKeyProvider()
                }
                let hasKey = (key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                return MeetingPreflight.gate(hasAPIKey: hasKey)
            }
        }
        self.backoffSchedule = backoffSchedule
    }

    public enum SessionError: Error, CustomStringConvertible {
        case alreadyActive
        case notRecording
        case preflight(MeetingGateError)
        case recorderStartFailed(String)

        public var description: String {
            switch self {
            case .alreadyActive: return "A meeting session is already active."
            case .notRecording: return "No active meeting session to stop."
            case .preflight(let g): return g.userMessage
            case .recorderStartFailed(let r): return "Could not start meeting recorder: \(r)"
            }
        }
    }

    public func start() async throws {
        // Preflight: enforce Meeting Mode + consent + API key + backend gate.
        // This guards against entry points that bypass the menu-bar wrapper
        // (the floating HUD's Record button calls start() directly).
        if case .failure(let err) = preflight() {
            throw SessionError.preflight(err)
        }

        let id = UUID()
        let now = Date()
        let title = "Meeting \(Self.titleFormatter.string(from: now))"
        let initial = TranscriptSession(
            id: id, title: title, startedAt: now, endedAt: nil,
            status: .recording, chunksTotal: 0, chunksCompleted: 0,
            segments: [], audioRetained: true
        )
        try withSessionLock {
            if let existing = session {
                switch existing.status {
                case .recording, .chunking, .transcribing:
                    throw SessionError.alreadyActive
                case .completed, .cancelled, .failed:
                    break
                }
            }
            session = initial
        }

        do {
            try saveSession(initial)
        } catch {
            clearSession(ifMatching: id)
            throw error
        }

        // Recorder lifecycle is wrapped so any failure clears the in-memory
        // session and persists the disk record as `.failed`. Without this
        // the next start() throws .alreadyActive until the app is relaunched.
        let system = systemRecorderFactory()
        let stillStarting = withSessionLock {
            session?.id == id && session?.status == .recording
        }
        guard stillStarting else {
            dlog("MeetingTranscriptionSession start aborted; session cleared during recorder create")
            throw SessionError.notRecording
        }
        self.systemRecorder = system
        do {
            try await system.start(outputURL: store.audioFile(id: id))
        } catch {
            dlog("MeetingTranscriptionSession start failed (system recorder): \(error)")
            self.systemRecorder = nil
            updateSession { s in
                s.status = .failed
                s.endedAt = Date()
                s.failureReason = "Recorder start failed: \(error)"
            }
            try? store.purgeAudio(for: id)
            clearSession(ifMatching: id)
            throw SessionError.recorderStartFailed(String(describing: error))
        }

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

        // VoIP process tap is best-effort: only succeeds on macOS 14.4+ when
        // Phone/FaceTime is already running. Common failure modes (no target
        // app, unsupported OS) are silently skipped — SCStream still covers
        // Teams/Zoom and the rest.
        if let phone = phoneRecorderFactory() {
            do {
                try await phone.start(outputURL: store.phoneFile(id: id))
                self.phoneRecorder = phone
            } catch {
                dlog("MeetingProcessTap start skipped: \(error)")
                self.phoneRecorder = nil
            }
        }
    }

    public func stop() async throws {
        let current: TranscriptSession = try withSessionLock {
            guard var current = session, current.status == .recording else {
                throw SessionError.notRecording
            }
            current.status = .chunking
            current.endedAt = Date()
            session = current
            return current
        }
        do {
            try saveSession(current)
        } catch {
            // The in-memory transition still prevents duplicate stop calls, but
            // persistence must never block shutdown of the live capture.
            dlog("Meeting chunking transition save failed; continuing recorder shutdown: \(error)")
        }

        guard let system = self.systemRecorder else {
            // Race: stop() arrived after status flipped to .recording but before
            // the recorder reference was assigned (or after a prior clear).
            // Persist .failed and clear in-memory state so .chunking cannot
            // permanently block start() via alreadyActive.
            dlog("MeetingTranscriptionSession stop with nil systemRecorder; failing session")
            updateSession { s in
                s.status = .failed
                s.failureReason = "Recorder missing during stop"
            }
            try? store.purgeAudio(for: current.id)
            clearSession(ifMatching: current.id)
            throw SessionError.notRecording
        }
        let systemURL: URL
        do {
            systemURL = try await system.stop()
        } catch {
            // Stop threw — record the failure and clear in-memory state so
            // subsequent start()s aren't permanently blocked by .alreadyActive.
            dlog("MeetingTranscriptionSession stop failed (system recorder): \(error)")
            self.systemRecorder = nil
            // Best-effort: also stop the mic so its recorder isn't left dangling.
            if let mic = self.micRecorder {
                _ = try? await mic.stop()
                self.micRecorder = nil
            }
            if let phone = self.phoneRecorder {
                _ = try? await phone.stop()
                self.phoneRecorder = nil
            }
            updateSession { s in
                s.status = .failed
                s.failureReason = "Recorder stop failed: \(error)"
            }
            try? store.purgeAudio(for: current.id)
            clearSession(ifMatching: current.id)
            throw error
        }
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

        var phoneURL: URL? = nil
        var phoneStartedAt: Date? = nil
        if let phone = self.phoneRecorder {
            do {
                let url = try await phone.stop()
                phoneStartedAt = phone.audioStartedAt
                if phone.lastFailureReason == nil {
                    phoneURL = url
                } else {
                    dlog("MeetingProcessTap produced no usable audio: \(phone.lastFailureReason ?? "")")
                }
            } catch {
                dlog("MeetingProcessTap stop failed (continuing without VoIP capture): \(error)")
            }
            self.phoneRecorder = nil
        }

        let sid = current.id
        // Hard-fail only if BOTH streams are unusable. If system captured nothing but mic
        // worked, proceed with mic-only transcript. Vice versa. Phone-tap is purely
        // additive so it doesn't participate in the hard-fail gate.
        if let sysReason = systemFailureReason, micURL == nil {
            updateSession { s in
                s.status = .failed
                s.failureReason = "System audio: \(sysReason)" +
                    (micFailureReason.map { " | Mic: \($0)" } ?? "")
            }
            try? store.purgeAudio(for: sid)
            return
        }
        if let micReason = micFailureReason {
            dlog("Mic capture failed (continuing with system audio only): \(micReason)")
        }

        let usableSystemURL: URL? = (systemFailureReason == nil) ? systemURL : nil

        // Compute per-stream wall-clock offset relative to a shared reference (the earliest
        // stream that produced its first audible content). Apply it to each segment's
        // startTime/endTime so segments from all streams share one timeline.
        let referenceTime: Date = {
            let candidates: [Date] = [systemStartedAt, micStartedAt, phoneStartedAt].compactMap { $0 }
            return candidates.min() ?? current.startedAt
        }()
        let systemShift = systemStartedAt.map { $0.timeIntervalSince(referenceTime) } ?? 0
        let micShift = micStartedAt.map { $0.timeIntervalSince(referenceTime) } ?? 0
        let phoneShift = phoneStartedAt.map { $0.timeIntervalSince(referenceTime) } ?? 0
        dlog("Meeting timeline shifts: system=\(systemShift)s mic=\(micShift)s phone=\(phoneShift)s")

        uploadTask = Task { [weak self] in
            await self?.runChunkAndUpload(
                systemURL: usableSystemURL,
                micURL: micURL,
                phoneURL: phoneURL,
                systemShift: systemShift,
                micShift: micShift,
                phoneShift: phoneShift,
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
        systemURL: URL?, micURL: URL?, phoneURL: URL? = nil,
        systemShift: Double, micShift: Double, phoneShift: Double = 0,
        sessionID: UUID
    ) async {
        defer {
            if let terminal = store.load(id: sessionID)?.status {
                switch terminal {
                case .completed, .cancelled, .failed:
                    do {
                        try store.purgeAudio(for: sessionID)
                    } catch {
                        dlog("Meeting terminal audio cleanup failed id=\(sessionID): \(error)")
                    }
                case .recording, .chunking, .transcribing:
                    break
                }
            }
        }
        // Deepgram path: mix mic+system (+ phone-tap) into one m4a, single batch
        // request, diarized speaker IDs across the whole meeting. Falls through
        // to the OpenAI per-source pipeline if Deepgram isn't wired or fails preflight.
        if providerProvider() == .deepgram, let dg = deepgramTranscribe {
            await runDeepgramPipeline(
                systemURL: systemURL, micURL: micURL, phoneURL: phoneURL,
                systemShift: systemShift, micShift: micShift, phoneShift: phoneShift,
                sessionID: sessionID, deepgram: dg
            )
            return
        }

        // (source, chunks, dir, shift, audibleDurationSec)
        var streams: [(SegmentSource, [URL], URL, Double, Double)] = []

        if let systemURL = systemURL {
            let dir = store.chunksDirectory(id: sessionID, source: .remote)
            let prepped = await prepareForChunking(streamURL: systemURL, baseShift: systemShift)
            do {
                let chunks = try await chunker(prepped.url, dir)
                streams.append((.remote, chunks, dir, prepped.shift, prepped.audibleDuration))
            } catch MeetingChunkerError.zeroDurationAsset {
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
            } catch MeetingChunkerError.zeroDurationAsset {
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

                // Collapse repetition cascades across consecutive segments
                // (e.g. 200× "I don't know." each on a 1-second grid). This
                // catches per-segment hallucinations that the per-segment
                // word-count gate misses.
                let deCascaded = MeetingTranscriptionSession.collapseRepetitionRuns(
                    segments, minRun: 4, source: source
                )
                updateSession { s in
                    s.rawSegments.append(contentsOf: segments.map { segment in
                        TranscriptSegment(
                            startTime: segment.startTime + shift,
                            endTime: segment.endTime + shift,
                            text: segment.text,
                            source: segment.source,
                            speakerID: segment.speakerID
                        )
                    })
                }

                // Drop Whisper hallucinations whose timestamps fall outside the actual
                // audible portion of the stream (Whisper sometimes invents segments past
                // the end of the file or right after a long silence).
                let hallucinationCap = audibleDuration > 0 ? audibleDuration + 1.5 : .greatestFiniteMagnitude
                let shifted: [TranscriptSegment] = deCascaded.compactMap { seg in
                    if seg.startTime > hallucinationCap { return nil }
                    if isHallucinated(seg) {
                        dlog(Self.redactedDropDiagnostic(
                            reason: .hallucination,
                            source: source,
                            startTime: seg.startTime,
                            endTime: seg.endTime,
                            runLength: 1,
                            text: seg.text
                        ))
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
        await runSummarizationIfEnabled(sessionID: sessionID)
    }

    /// Calls `summarize` on the completed session's segments and persists
    /// the result. Failures are logged and swallowed — a missing summary
    /// is non-fatal.
    private func runSummarizationIfEnabled(sessionID: UUID) async {
        guard summarizeEnabledProvider(), let summarize = summarize else { return }
        guard
            let s = store.load(id: sessionID),
            s.status == .completed,
            !s.segments.isEmpty
        else { return }
        let summarizedSegments = s.segments
        do {
            let summary = try await summarize(s.segments)
            let stillMatchesSnapshot: (TranscriptSession) -> Bool = {
                $0.status == .completed && $0.segments == summarizedSegments
            }
            if updatePersistedSessionIfPresent(
                id: sessionID,
                matching: stillMatchesSnapshot,
                { $0.summary = summary }
            ) {
                dlog("Meeting summary generated (\(summary.count) chars)")
            } else {
                dlog("Meeting summary discarded because session \(sessionID) changed or was deleted")
            }
        } catch {
            dlog("Meeting summary failed: \(error)")
        }
    }

    /// Returns the fraction of 100ms windows in `url` whose RMS is above the
    /// SilenceTrim threshold. Used as a pre-upload gate so we don't waste API
    /// calls (and don't ingest hallucinations) on chunks that are mostly silent.
    /// Returns 1.0 on read failure to fail open — better to send than drop real audio.
    static func audibleFraction(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 1.0 }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let totalFrames = file.length
        guard sampleRate > 0, channels > 0, totalFrames > 0 else { return 1.0 }
        let windowFrames = AVAudioFrameCount(max(1, Int(sampleRate * SilenceTrim.windowSec)))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else {
            return 1.0
        }
        var pos: Int64 = 0
        var windows = 0
        var audibleWindows = 0
        while pos < totalFrames {
            do {
                try file.read(into: buf, frameCount: windowFrames)
            } catch { break }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            windows += 1
            guard let data = buf.floatChannelData else { pos += Int64(n); continue }
            var sumSq: Float = 0
            for f in 0..<n {
                for c in 0..<channels {
                    let s = data[c][f]
                    sumSq += s * s
                }
            }
            let rms = sqrt(sumSq / Float(n * channels))
            if rms > SilenceTrim.rmsThreshold { audibleWindows += 1 }
            pos += Int64(n)
        }
        return windows > 0 ? Double(audibleWindows) / Double(windows) : 0
    }

    /// Drops runs of `minRun` or more consecutive segments whose normalised text
    /// matches. This is Whisper's hallucination signature on uniform/silent
    /// audio: identical short text repeated on a fixed time grid (e.g. one
    /// "I don't know." per second for an entire 5-minute mic chunk).
    static func collapseRepetitionRuns(
        _ segments: [TranscriptSegment],
        minRun: Int,
        source: SegmentSource
    ) -> [TranscriptSegment] {
        guard segments.count >= minRun else { return segments }
        var result: [TranscriptSegment] = []
        result.reserveCapacity(segments.count)
        var i = 0
        while i < segments.count {
            let start = i
            let key = normaliseForRunDetection(segments[i].text)
            var j = i + 1
            while j < segments.count, normaliseForRunDetection(segments[j].text) == key { j += 1 }
            let runLength = j - start
            if runLength >= minRun, !key.isEmpty {
                dlog(redactedDropDiagnostic(
                    reason: .cascade,
                    source: source,
                    startTime: segments[start].startTime,
                    endTime: segments[j - 1].endTime,
                    runLength: runLength,
                    text: segments[start].text
                ))
            } else {
                result.append(contentsOf: segments[start..<j])
            }
            i = j
        }
        return result
    }

    enum TranscriptDropReason: String {
        case hallucination
        case cascade
    }

    /// Formats drop diagnostics without placing transcript content in logs.
    static func redactedDropDiagnostic(
        reason: TranscriptDropReason,
        source: SegmentSource,
        startTime: Double,
        endTime: Double,
        runLength: Int,
        text: String
    ) -> String {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        return "Meeting \(reason.rawValue) dropped [\(source.rawValue)] "
            + "\(startTime)-\(endTime)s run=\(runLength) "
            + "chars=\(text.count) words=\(wordCount)"
    }

    private static func normaliseForRunDetection(_ s: String) -> String {
        return s
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\p{P}\\p{S}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Known Whisper hallucinations on silent / very low-energy audio. These
    /// strings are the model's standard fillers when given nothing useful to
    /// transcribe (especially around leading/trailing silence). Match after
    /// case-insensitive, punctuation-stripped, whitespace-collapsed normalisation.
    private static let whisperFillerPhrases: Set<String> = [
        "you", "thank you", "thanks", "thank you for watching",
        "thanks for watching", "subscribe", "please subscribe",
        "bye", "goodbye", "see you next time"
    ]

    /// Detect Whisper hallucination patterns on near-silent audio: known
    /// filler phrases ("you", "thanks for watching"), long monotonous
    /// repetitions ("yeah, yeah, yeah, ..." for 30+ seconds), single-word
    /// loops, and very low unique-word ratios over multi-second windows.
    /// Returns true if the segment should be dropped.
    private func isHallucinated(_ seg: TranscriptSegment) -> Bool {
        let stripped = seg.text
            .lowercased()
            .replacingOccurrences(of: "[\\p{P}\\p{S}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if Self.whisperFillerPhrases.contains(stripped) { return true }

        let words = stripped.split(separator: " ").map(String.init).filter { !$0.isEmpty }
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

    /// Deepgram path: silence-trim each stream, mix into one composition with
    /// per-stream wall-clock alignment, send the mixed m4a to Deepgram in a
    /// single request so speaker IDs are stable across the whole meeting.
    private func runDeepgramPipeline(
        systemURL: URL?, micURL: URL?, phoneURL: URL? = nil,
        systemShift: Double, micShift: Double, phoneShift: Double = 0,
        sessionID: UUID,
        deepgram: @escaping DeepgramTranscribe
    ) async {
        // Per-source Deepgram requests. Each input file is one speaker class
        // (your mic vs caller-side audio) so we tag segments from the file
        // boundary instead of relying on Deepgram's mix-based diarization,
        // which collapses distinct speakers to a single ID when their voices
        // share similar characteristics in the downmixed file. Within-source
        // diarization (multiple callers on phone tap) is still preserved.
        struct Job {
            let url: URL
            let source: SegmentSource
            let shift: Double
            let speakerOffset: Int
        }
        var jobs: [Job] = []
        if let url = systemURL {
            let prepped = await prepareForChunking(streamURL: url, baseShift: systemShift)
            if prepped.audibleDuration > 0 || systemShift == 0 {
                jobs.append(Job(url: prepped.url, source: .remote, shift: prepped.shift, speakerOffset: 0))
            }
        }
        if let url = phoneURL {
            let prepped = await prepareForChunking(streamURL: url, baseShift: phoneShift)
            if prepped.audibleDuration > 0 || phoneShift == 0 {
                jobs.append(Job(url: prepped.url, source: .remote, shift: prepped.shift, speakerOffset: 100))
            }
        }
        if let url = micURL {
            let prepped = await prepareForChunking(streamURL: url, baseShift: micShift)
            if prepped.audibleDuration > 0 || micShift == 0 {
                // Mic = you; collapse Deepgram's within-mic speakers to nil so
                // the renderer shows "You" rather than "Speaker N".
                jobs.append(Job(url: prepped.url, source: .local, shift: prepped.shift, speakerOffset: -1))
            }
        }
        guard !jobs.isEmpty else {
            updateSession { s in
                s.status = .failed
                s.failureReason = "No audio captured. Check that audio was actually playing through the system during the recording, that the microphone is not muted, and that Screen Recording + Microphone permissions are granted to Vox."
            }
            return
        }

        updateSession { s in
            s.status = .transcribing
            s.chunksTotal = jobs.count
            s.chunksCompleted = 0
        }

        var allSegments: [TranscriptSegment] = []
        for job in jobs {
            if Task.isCancelled {
                updateSession { $0.status = .cancelled }
                return
            }
            let raw: [TranscriptSegment]
            do {
                raw = try await deepgram(job.url)
            } catch {
                updateSession { s in
                    s.status = .failed
                    s.failureReason = "Deepgram transcription failed (\(job.source.rawValue)): \(error)"
                }
                return
            }
            let tagged = raw.map { seg -> TranscriptSegment in
                let speakerID: Int? = {
                    if job.speakerOffset < 0 { return nil }
                    guard let sid = seg.speakerID else { return job.speakerOffset }
                    return job.speakerOffset + sid
                }()
                return TranscriptSegment(
                    startTime: seg.startTime + job.shift,
                    endTime: seg.endTime + job.shift,
                    text: seg.text,
                    source: job.source,
                    speakerID: speakerID
                )
            }
            allSegments.append(contentsOf: tagged)
            updateSession { s in
                s.rawSegments.append(contentsOf: tagged)
                s.chunksCompleted += 1
            }
        }

        updateSession { s in
            s.segments = allSegments.sorted(by: TranscriptSegment.byStartTime)
            s.summary = nil
            s.status = .completed
        }

        await runSummarizationIfEnabled(sessionID: sessionID)
    }

    /// Re-run an existing meeting through the Deepgram pipeline using the
    /// retained audio on disk. Replaces the session's segments + summary.
    /// No-op if audio has already been purged.
    public func reTranscribeWithDeepgram(sessionID: UUID) async {
        guard let dg = deepgramTranscribe else {
            dlog("reTranscribeWithDeepgram: deepgram closure not configured")
            return
        }
        guard var s = store.load(id: sessionID) else {
            dlog("reTranscribeWithDeepgram: no session \(sessionID)")
            return
        }
        let systemURL = store.audioFile(id: sessionID)
        let micURL = store.micFile(id: sessionID)
        let phoneURL = store.phoneFile(id: sessionID)
        let fm = FileManager.default
        let systemExists = fm.fileExists(atPath: systemURL.path)
        let micExists = fm.fileExists(atPath: micURL.path)
        let phoneExists = fm.fileExists(atPath: phoneURL.path)
        guard systemExists || micExists || phoneExists else {
            dlog("reTranscribeWithDeepgram: no audio retained for \(sessionID)")
            return
        }

        // Fail loudly if another session is mid-run; we'd otherwise fight
        // over the lock-managed `session` field.
        let claimedSession = withSessionLock { () -> Bool in
            if let existing = session, existing.id != sessionID,
               [TranscriptSession.Status.recording, .chunking, .transcribing]
                .contains(existing.status) {
                return false
            }
            // Keep the existing transcript and summary durable until every
            // Deepgram job succeeds and the pipeline commits their replacement.
            s.status = .transcribing
            s.failureReason = nil
            s.chunksTotal = 1
            s.chunksCompleted = 0
            session = s
            return true
        }
        guard claimedSession else {
            dlog("reTranscribeWithDeepgram: another session is active")
            return
        }
        do {
            try saveSession(s)
        } catch {
            dlog("reTranscribeWithDeepgram: session save failed: \(error)")
            clearSession(ifMatching: sessionID)
            return
        }

        await runDeepgramPipeline(
            systemURL: systemExists ? systemURL : nil,
            micURL: micExists ? micURL : nil,
            phoneURL: phoneExists ? phoneURL : nil,
            systemShift: 0, micShift: 0, phoneShift: 0,
            sessionID: sessionID, deepgram: dg
        )
    }

    /// Caps transport retries so a prolonged outage cannot block new meetings
    /// via `.alreadyActive` forever. Matches the last backoff step (30s) for
    /// roughly twenty minutes of attempts before failing the chunk.
    private static let maxTransportRetryDuration: TimeInterval = 20 * 60

    private func transcribeWithInfiniteRetry(
        url: URL, offset: Double, source: SegmentSource
    ) async throws -> [TranscriptSegment] {
        var attempt = 0
        let deadline = Date().addingTimeInterval(Self.maxTransportRetryDuration)
        while true {
            try Task.checkCancellation()
            do {
                return try await transcribe(url, offset, source)
            } catch TranscriptionError.transportError(let underlying) {
                if Date() >= deadline {
                    dlog("Meeting transport retry budget exhausted after \(attempt) attempts")
                    throw TranscriptionError.transportError(underlying)
                }
                let delay = backoffSchedule[min(attempt, backoffSchedule.count - 1)]
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            } catch {
                throw error
            }
        }
    }

    private func updateSession(_ mutate: (inout TranscriptSession) -> Void) {
        guard let s: TranscriptSession = withSessionLock({
            guard var current = session else { return nil }
            mutate(&current)
            session = current
            return current
        }) else { return }
        do {
            try saveSession(s)
        } catch {
            dlog("Meeting session save failed id=\(s.id) status=\(s.status): \(error)")
        }
    }

    private func clearSession(ifMatching id: UUID) {
        withSessionLock {
            if session?.id == id {
                session = nil
            }
        }
    }

    /// Applies a post-processing result to the session that produced it, rather
    /// than whichever session happens to be active when the async work returns.
    /// The store checks existence and transcript identity under one lock so a
    /// deleted or re-transcribed session cannot receive a stale result.
    @discardableResult
    private func updatePersistedSessionIfPresent(
        id: UUID,
        matching predicate: (TranscriptSession) -> Bool,
        _ mutate: (inout TranscriptSession) -> Void
    ) -> Bool {
        let persisted: TranscriptSession
        do {
            guard let updated = try store.updateIfPresent(
                id: id,
                matching: predicate,
                mutate: mutate
            ) else { return false }
            persisted = updated
        } catch {
            dlog("Meeting session \(id) update failed: \(error)")
            return false
        }

        withSessionLock {
            if let current = session, current.id == id, predicate(current) {
                session = persisted
            }
        }
        return true
    }

    private func withSessionLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
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
