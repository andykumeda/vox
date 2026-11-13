import XCTest
@testable import vox

final class MeetingRecordingRetentionTests: XCTestCase {
    private let key = Data(repeating: 0x71, count: 32)
    private let endedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private var root: URL!
    private var policy = MeetingRecordingRetention(enabled: true, days: .thirty)
    private var keyUnavailable = false
    private var keyCalls = 0
    private var failKeyCall: Int?
    private var store: MeetingTranscriptStore!

    private struct KeyFailure: Error {}

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vox-retention-\(UUID().uuidString)")
        store = MeetingTranscriptStore(rootDirectory: root, keyProvider: {
            self.keyCalls += 1
            if self.keyUnavailable || self.keyCalls == self.failKeyCall { throw KeyFailure() }
            return self.key
        }, retention: { self.policy })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        store = nil
        super.tearDown()
    }

    private func session(status: TranscriptSession.Status = .completed) throws -> TranscriptSession {
        let session = TranscriptSession(
            id: UUID(), title: "Retention test", startedAt: endedAt.addingTimeInterval(-7200),
            endedAt: endedAt, status: status, chunksTotal: 1, chunksCompleted: 1,
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "complete")], audioRetained: false,
            sourceOffsets: .init(system: 0, microphone: 0, phone: 0), sourceAvailability: [true, false, false]
        )
        try store.save(session)
        return session
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func archive(_ source: URL) -> URL { source.appendingPathExtension("enc") }

    func testSettingsDefaultValidationAndRoundTripPreserveUserPreferences() {
        let defaults = UserDefaults.standard
        let keys = ["retainMeetingRecordings", "meetingRecordingRetentionDays"]
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        XCTAssertFalse(AppSettings.retainMeetingRecordings)
        XCTAssertEqual(AppSettings.meetingRecordingRetentionDays, .thirty)
        defaults.set(365, forKey: keys[1])
        XCTAssertEqual(AppSettings.meetingRecordingRetentionDays, .thirty)
        AppSettings.retainMeetingRecordings = true
        for days in MeetingRecordingRetentionDays.allCases {
            AppSettings.meetingRecordingRetentionDays = days
            XCTAssertEqual(AppSettings.meetingRecordingRetention, .init(enabled: true, days: days))
        }
        AppSettings.retainMeetingRecordings = false
        XCTAssertFalse(AppSettings.meetingRecordingRetention.enabled)
    }

    func testRetainsEncryptedOriginalSourcesWithoutDuplicateChunks() throws {
        let meeting = try session()
        let sources = [store.audioFile(id: meeting.id), store.micFile(id: meeting.id), store.phoneFile(id: meeting.id)]
        let fixture = Data("recording fixture with private speech".utf8)
        for source in sources { try write(fixture, to: source) }
        let chunk = store.chunksDirectory(id: meeting.id, source: .local).appendingPathComponent("part.m4a")
        try write(fixture, to: chunk)
        try write(fixture, to: store.sessionDirectory(id: meeting.id).appendingPathComponent("conversion.wav"))
        let interruptedArchive = store.sessionDirectory(id: meeting.id).appendingPathComponent(".audio-crash.candidate")
        try write(fixture, to: interruptedArchive)
        XCTAssertEqual(store.audioDiskBytes(), UInt64(fixture.count * 6))

        try store.finishAudio(for: meeting.id, now: endedAt)

        for source in sources {
            XCTAssertFalse(exists(source))
            let retained = archive(source)
            XCTAssertTrue(exists(retained))
            try MeetingAudioArchive.verify(archive: retained, key: key)
            XCTAssertEqual(try firstBlockPayload(at: retained), fixture)
            XCTAssertNil(try Data(contentsOf: retained).range(of: fixture))
        }
        XCTAssertFalse(exists(chunk.deletingLastPathComponent()))
        XCTAssertFalse(exists(interruptedArchive))
        XCTAssertFalse(exists(store.sessionDirectory(id: meeting.id).appendingPathComponent("conversion.wav")))
        XCTAssertTrue(store.load(id: meeting.id)?.audioRetained == true)
        let expectedBytes = try sources.reduce(UInt64(0)) { total, source in
            total + UInt64(try Data(contentsOf: archive(source)).count)
        }
        XCTAssertEqual(store.audioDiskBytes(), expectedBytes)
    }

    func testDefaultDisabledPolicyPurgesAudioAndChunks() throws {
        let defaultStore = MeetingTranscriptStore(rootDirectory: root, keyProvider: { self.key })
        let meeting = try session()
        try write(Data([1, 2]), to: store.audioFile(id: meeting.id))
        let chunk = store.chunksDirectory(id: meeting.id).appendingPathComponent("part.wav")
        try write(Data([3]), to: chunk)
        try defaultStore.finishAudio(for: meeting.id, now: endedAt)
        XCTAssertFalse(exists(store.audioFile(id: meeting.id)))
        XCTAssertFalse(exists(chunk.deletingLastPathComponent()))
        XCTAssertEqual(defaultStore.audioDiskBytes(), 0)
        XCTAssertFalse(defaultStore.load(id: meeting.id)?.audioRetained ?? true)
    }

    func testExpiryUsesMeetingEndAndIncludesExactBoundaryForEveryDuration() throws {
        for days in MeetingRecordingRetentionDays.allCases {
            policy.days = days
            let meeting = try session()
            let source = store.audioFile(id: meeting.id)
            try write(Data([1, 2, 3]), to: source)
            let expiry = endedAt.addingTimeInterval(Double(days.rawValue) * 86400)
            try store.finishAudio(for: meeting.id, now: expiry.addingTimeInterval(-1))
            XCTAssertTrue(exists(archive(source)), "\(days)")
            XCTAssertEqual(store.applyAudioRetention(now: expiry), 0)
            XCTAssertFalse(exists(archive(source)), "\(days)")
            XCTAssertFalse(store.load(id: meeting.id)?.audioRetained ?? true)
        }
    }

    func testPolicyChangesApplyToPreviouslyRetainedArchives() throws {
        policy.days = .ninety
        let shortened = try session()
        let shortSource = store.micFile(id: shortened.id)
        try write(Data([4]), to: shortSource)
        try store.finishAudio(for: shortened.id, now: endedAt)
        policy.days = .seven
        XCTAssertEqual(store.applyAudioRetention(now: endedAt.addingTimeInterval(8 * 86400)), 0)
        XCTAssertFalse(exists(archive(shortSource)))

        let disabled = try session()
        let disabledSource = store.phoneFile(id: disabled.id)
        try write(Data([5]), to: disabledSource)
        try store.finishAudio(for: disabled.id, now: endedAt)
        policy.enabled = false
        XCTAssertEqual(store.applyAudioRetention(now: endedAt), 0)
        XCTAssertFalse(exists(archive(disabledSource)))
    }

    func testActiveSessionsAreNeitherMaintainedNorDeleted() throws {
        policy.enabled = false
        for status in [TranscriptSession.Status.recording, .chunking, .transcribing] {
            let meeting = try session(status: status)
            let source = store.audioFile(id: meeting.id)
            try write(Data([1, 2]), to: source)
            try store.finishAudio(for: meeting.id, now: endedAt.addingTimeInterval(100 * 86400))
            XCTAssertEqual(store.applyAudioRetention(now: .distantFuture), 0)
            XCTAssertThrowsError(try store.delete(id: meeting.id))
            XCTAssertThrowsError(try store.purgeAudio(for: meeting.id))
            XCTAssertTrue(exists(source))
            XCTAssertEqual(store.load(id: meeting.id)?.status, status)
        }
    }

    func testFailedAndCancelledSessionsKeepUsableSources() throws {
        for status in [TranscriptSession.Status.failed, .cancelled] {
            let meeting = try session(status: status)
            let source = store.audioFile(id: meeting.id)
            try write(Data([6, 7]), to: source)
            try store.finishAudio(for: meeting.id, now: endedAt)
            XCTAssertTrue(exists(archive(source)))
            XCTAssertFalse(exists(source))
            XCTAssertEqual(store.load(id: meeting.id)?.status, status)
        }
    }

    func testUnreadableMetadataAndUnavailableKeyPreserveAudio() throws {
        let corrupt = try session()
        let corruptSource = store.audioFile(id: corrupt.id)
        try write(Data([8, 9]), to: corruptSource)
        let corruptTranscript = Data("invalid encrypted transcript".utf8)
        try corruptTranscript.write(to: store.transcriptFile(id: corrupt.id))
        XCTAssertEqual(store.applyAudioRetention(now: .distantFuture), 1)
        XCTAssertTrue(exists(corruptSource))
        XCTAssertThrowsError(try store.finishAudio(for: corrupt.id, now: endedAt))
        XCTAssertThrowsError(try store.purgeAudio(for: corrupt.id))
        XCTAssertThrowsError(try store.delete(id: corrupt.id))
        XCTAssertEqual(try Data(contentsOf: store.transcriptFile(id: corrupt.id)), corruptTranscript)

        let locked = try session()
        let lockedSource = store.micFile(id: locked.id)
        try write(Data([10]), to: lockedSource)
        let originalTranscript = try Data(contentsOf: store.transcriptFile(id: locked.id))
        keyUnavailable = true
        XCTAssertEqual(store.applyAudioRetention(now: .distantFuture), 2)
        XCTAssertThrowsError(try store.finishAudio(for: locked.id, now: endedAt))
        XCTAssertThrowsError(try store.purgeAudio(for: locked.id))
        XCTAssertThrowsError(try store.delete(id: locked.id))
        XCTAssertTrue(exists(lockedSource))
        XCTAssertEqual(try Data(contentsOf: store.transcriptFile(id: locked.id)), originalTranscript)
    }

    func testEncryptionFailurePreservesRawAudioAndPersistsGenericWarningThenRetries() throws {
        let meeting = try session()
        let source = store.audioFile(id: meeting.id)
        let fixture = Data("private content must not enter warnings".utf8)
        try write(fixture, to: source)
        keyCalls = 0
        failKeyCall = 2 // Metadata decrypts; encrypting the first source fails.
        XCTAssertFalse(store.finalizeAudio(for: meeting.id, now: endedAt))
        XCTAssertEqual(try Data(contentsOf: source), fixture)
        let warnings = try XCTUnwrap(store.load(id: meeting.id)).captureWarnings
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("Recording storage cleanup failed"))
        XCTAssertFalse(warnings[0].contains(String(decoding: fixture, as: UTF8.self)))
        XCTAssertFalse(warnings[0].contains(root.path))
        failKeyCall = nil
        XCTAssertTrue(store.finalizeAudio(for: meeting.id, now: endedAt))
        XCTAssertTrue(exists(archive(source)))
        XCTAssertFalse(exists(source))
        XCTAssertTrue(try XCTUnwrap(store.load(id: meeting.id)).captureWarnings.isEmpty)
    }

    func testFailureInLaterSourceDoesNotDeleteEarlierPlaintext() throws {
        let meeting = try session()
        let system = store.audioFile(id: meeting.id)
        let mic = store.micFile(id: meeting.id)
        try write(Data([12]), to: system)
        try write(Data([13]), to: mic)
        keyCalls = 0
        failKeyCall = 3 // First archive succeeds, then the second source fails.
        XCTAssertFalse(store.finalizeAudio(for: meeting.id, now: endedAt))
        XCTAssertTrue(exists(system))
        XCTAssertTrue(exists(mic))
        XCTAssertTrue(exists(archive(system)))
        XCTAssertFalse(exists(archive(mic)))
        failKeyCall = nil
        XCTAssertTrue(store.finalizeAudio(for: meeting.id, now: endedAt))
        XCTAssertFalse(exists(system))
        XCTAssertFalse(exists(mic))
        XCTAssertEqual(try firstBlockPayload(at: archive(system)), Data([12]))
        XCTAssertEqual(try firstBlockPayload(at: archive(mic)), Data([13]))
    }

    func testLegacyCompleteWithoutManifestRemainsProtected() throws {
        policy.enabled = false
        var meeting = try session()
        meeting.sourceAvailability = nil
        meeting.sourceOffsets = nil
        try store.save(meeting)
        let source = store.audioFile(id: meeting.id)
        try write(Data([1, 2]), to: source)
        XCTAssertEqual(store.applyAudioRetention(now: .distantFuture), 0)
        XCTAssertTrue(exists(archive(source)))
        try MeetingAudioArchive.verify(archive: archive(source), key: key)
    }

    func testIncompleteSessionsRemainEncryptedEvenAfterRestartAndOptOutExpiry() throws {
        policy = .init(enabled: false, days: .seven)
        var cases: [TranscriptSession] = []
        for status in [TranscriptSession.Status.failed, .cancelled, .transcribing] {
            cases.append(try session(status: status))
        }
        var empty = try session()
        empty.segments = []
        try store.save(empty)
        cases.append(empty)
        var blank = try session()
        blank.segments = [TranscriptSegment(startTime: 0, endTime: 1, text: "   ")]
        try store.save(blank)
        cases.append(blank)
        var noChunks = try session()
        noChunks.chunksTotal = 0
        noChunks.chunksCompleted = 0
        try store.save(noChunks)
        cases.append(noChunks)
        var warning = try session()
        warning.chunksTotal = 1
        warning.chunksCompleted = 1
        warning.segments = [TranscriptSegment(startTime: 0, endTime: 1, text: "partial")]
        warning.captureWarnings = ["Missing microphone"]
        try store.save(warning)
        cases.append(warning)
        var partial = try session()
        partial.chunksTotal = 2
        partial.chunksCompleted = 1
        partial.segments = [TranscriptSegment(startTime: 0, endTime: 1, text: "partial")]
        try store.save(partial)
        cases.append(partial)
        for meeting in cases {
            try write(Data([14, 15]), to: store.audioFile(id: meeting.id))
        }
        let restarted = MeetingTranscriptStore(rootDirectory: root, keyProvider: { self.key }, retention: { self.policy })
        restarted.recoverInFlightSessions()
        XCTAssertEqual(restarted.applyAudioRetention(now: endedAt.addingTimeInterval(365 * 86400)), 0)
        for meeting in cases {
            let source = store.audioFile(id: meeting.id)
            XCTAssertFalse(exists(source))
            XCTAssertTrue(exists(archive(source)), "\(meeting.status)")
            try MeetingAudioArchive.verify(archive: archive(source), key: key)
        }
    }

    func testIncompleteMeetingPreservesDerivedAudioWhenOriginalIsMissing() throws {
        policy.enabled = false
        let meeting = try session(status: .failed)
        let chunk = store.chunksDirectory(id: meeting.id).appendingPathComponent("part.wav")
        let derived = store.sessionDirectory(id: meeting.id).appendingPathComponent("converted.m4a")
        try write(Data("only chunk".utf8), to: chunk)
        try write(Data("derived".utf8), to: derived)
        XCTAssertEqual(store.applyAudioRetention(now: .distantFuture), 0)
        XCTAssertFalse(exists(chunk))
        XCTAssertTrue(exists(archive(chunk)))
        XCTAssertTrue(exists(archive(derived)))
        XCTAssertEqual(try firstBlockPayload(at: archive(chunk)), Data("only chunk".utf8))
        XCTAssertEqual(store.applyAudioRetention(now: .distantFuture), 0)
        XCTAssertTrue(exists(archive(chunk)))
        try store.delete(id: meeting.id)
        XCTAssertFalse(exists(store.sessionDirectory(id: meeting.id)))
    }

    func testIncompleteAudioEncryptionFailureLeavesEverySourceInPlace() throws {
        policy.enabled = false
        let meeting = try session(status: .failed)
        let source = store.audioFile(id: meeting.id)
        let chunk = store.chunksDirectory(id: meeting.id).appendingPathComponent("part.wav")
        let candidate = store.sessionDirectory(id: meeting.id).appendingPathComponent(".audio-interrupted.candidate")
        let empty = store.sessionDirectory(id: meeting.id).appendingPathComponent("empty.wav")
        try write(Data(), to: empty)
        try write(Data([1]), to: source)
        try write(Data([2]), to: chunk)
        try write(Data([3]), to: candidate)
        keyCalls = 0
        failKeyCall = 3
        XCTAssertFalse(store.finalizeAudio(for: meeting.id, now: .distantFuture))
        XCTAssertTrue(exists(source))
        XCTAssertTrue(exists(chunk))
        XCTAssertTrue(exists(candidate))
        failKeyCall = nil
        XCTAssertTrue(store.finalizeAudio(for: meeting.id, now: .distantFuture))
        XCTAssertTrue(exists(archive(source)))
        XCTAssertTrue(exists(archive(chunk)))
        XCTAssertTrue(exists(candidate))
        XCTAssertTrue(exists(empty))
    }

    func testStartupRecoveryAllowsInterruptedCaptureToBeEncrypted() throws {
        let meeting = try session(status: .recording)
        let source = store.audioFile(id: meeting.id)
        try write(Data([14]), to: source)
        store.recoverInFlightSessions()
        XCTAssertEqual(store.load(id: meeting.id)?.status, .failed)
        XCTAssertEqual(store.applyAudioRetention(now: endedAt), 0)
        XCTAssertTrue(exists(archive(source)))
        XCTAssertFalse(exists(source))
    }

    func testMeetingLifecycleEncryptsOriginalAudioAfterSuccessfulTranscription() async throws {
        let recorder = MeetingTranscriptionSessionTests.MockRecorder()
        let meeting = MeetingTranscriptionSession(
            store: store, recorder: recorder,
            chunker: { source, _ in [source] },
            transcribe: { _, offset, _ in
                [TranscriptSegment(startTime: offset, endTime: offset + 1, text: "Retained meeting")]
            },
            apiKey: { "test-key" }, preflight: { .success(()) }
        )
        try await meeting.start()
        let id = try XCTUnwrap(meeting.activeSessionID)
        let source = store.audioFile(id: id)
        XCTAssertTrue(exists(source))
        try await meeting.stop()
        await meeting.waitForCompletion()

        let saved = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(saved.status, .completed)
        XCTAssertEqual(saved.segments.first?.text, "Retained meeting")
        XCTAssertNotNil(saved.endedAt)
        XCTAssertTrue(saved.audioRetained)
        XCTAssertTrue(exists(store.transcriptFile(id: id)))
        XCTAssertFalse(exists(source))
        XCTAssertTrue(exists(archive(source)))
        try MeetingAudioArchive.verify(archive: archive(source), key: key)
        XCTAssertEqual(try firstBlockPayload(at: archive(source)), Data([0xFA, 0xCE]))
        XCTAssertEqual(recorder.startCallCount, 1)
        XCTAssertEqual(recorder.stopCallCount, 1)
    }

    func testDeletingMeetingDeletesRetainedAudio() throws {
        let meeting = try session()
        let source = store.phoneFile(id: meeting.id)
        try write(Data([11]), to: source)
        try store.finishAudio(for: meeting.id, now: endedAt)
        XCTAssertTrue(exists(archive(source)))
        try store.delete(id: meeting.id)
        XCTAssertFalse(exists(store.sessionDirectory(id: meeting.id)))
        XCTAssertNil(store.load(id: meeting.id))
    }

    // Decode a small fixture's authenticated first block to verify retained bytes.
    private func firstBlockPayload(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        var offset = 0
        func frame() throws -> Data {
            let size = data[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            offset += 8
            defer { offset += Int(size) }
            return try TranscriptCipher(keyData: key).open(data.subdata(in: offset..<(offset + Int(size))))
        }
        let context = try frame()
        return try frame().dropFirst(context.count + 8)
    }
}
