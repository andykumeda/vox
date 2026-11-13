import AppKit
import Foundation

/// Serializes automatic retries and rate-limits each meeting across UI events.
@MainActor
final class MeetingRecoveryScheduler {
    private let session: MeetingTranscriptionSession
    private let store: MeetingTranscriptStore
    private let interval: () throws -> Double
    private let now: () -> TimeInterval
    private var nextAttempt: [UUID: TimeInterval] = [:]
    private var running = false
    private var timer: Task<Void, Never>?

    init(session: MeetingTranscriptionSession, store: MeetingTranscriptStore,
         interval: @escaping () throws -> Double = { try ServiceConfiguration.number(.meetingRecoveryInterval) },
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.session = session
        self.store = store
        self.interval = interval
        self.now = now
    }

    func start() {
        guard timer == nil else { return }
        do { try Self.cleanStaleScratch(in: store.rootDirectory) }
        catch { Self.warnAboutScratch() }
        requestSweep()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let delay = try self.interval()
                    guard delay.isFinite, delay >= 60, delay <= Double(Int32.max) else { throw ServiceConfiguration.InvalidValue(key: .meetingRecoveryInterval) }
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    self.requestSweep()
                } catch { dlog("Meeting automatic recovery scheduler stopped: \(error)"); return }
            }
        }
    }

    func requestSweep() { Task { await sweep() } }

    func sweep() async {
        guard !running, !session.isActive else { return }
        running = true
        defer { running = false }
        guard let delay = try? interval(), delay.isFinite, delay >= 60, delay <= Double(Int32.max) else {
            dlog("Invalid meeting automatic recovery interval; automatic recovery is paused.")
            return
        }
        for item in store.list() where item.status == .failed ||
            (item.status == .completed && !MeetingTranscriptStore.hasConfirmedTranscript(item) && item.sourceAvailability != nil && item.sourceOffsets != nil) {
            if Task.isCancelled || session.isActive { return }
            let persistedNext = item.recoveryAttemptAt.map { $0.timeIntervalSince1970 + delay } ?? 0
            if max(nextAttempt[item.id] ?? 0, persistedNext) > now() { continue }
            let attemptTime = now()
            nextAttempt[item.id] = attemptTime + delay
            do { try await session.recoverMeeting(id: item.id, attemptedAt: Date(timeIntervalSince1970: attemptTime)) }
            catch MeetingTranscriptionSession.SessionError.alreadyActive { return }
            catch {
                let description = String(describing: error)
                _ = try? store.updateIfPresent(id: item.id,
                    matching: { $0.status == .failed || ($0.status == .completed && !MeetingTranscriptStore.hasConfirmedTranscript($0)) },
                    mutate: { $0.status = .failed; MeetingTranscriptionSession.setRecoveryNotice("Needs attention: " + description, in: &$0) })
            }
        }
    }

    static func cleanStaleScratch(in root: URL) throws {
        let directory = root.appendingPathComponent(".automatic-recovery", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where UUID(uuidString: item.lastPathComponent) != nil {
            try FileManager.default.removeItem(at: item)
        }
    }

    nonisolated static func warnAboutScratch() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Temporary meeting audio could not be removed"
            alert.informativeText = "Check disk access. Vox will retry cleanup at its next launch."
            alert.runModal()
        }
    }
}
