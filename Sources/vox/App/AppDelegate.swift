import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = MenuBarController()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Relocator.offerMoveToApplicationsIfNeeded()
        // Patch headers on any dictation WAVs left half-finished by a prior crash.
        RecordingArchive.repairOrphans()
        // Purge audio older than the configured retention. Transcript text is
        // kept indefinitely; only heavy WAV/m4a files are deleted.
        if let cutoff = AppSettings.audioRetention.cutoffDate() {
            let dictDeleted = RecordingArchive.purgeOlderThan(cutoff)
            let meetingDeleted = MeetingTranscriptStore().purgeAudioOlderThan(cutoff)
            if dictDeleted > 0 || meetingDeleted > 0 {
                dlog("audio retention sweep: dictation=\(dictDeleted) meeting=\(meetingDeleted) cutoff=\(cutoff)")
            }
        }
        menuController.start()
        MeetingTranscriptStore().recoverInFlightSessions()
        DictionaryStore.shared.load()
        DictionaryStore.shared.startWatching()
        Task { @MainActor in MainWindowController.shared.showWindow() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Cheap belt-and-suspenders: reload on focus in case the watcher
            // missed an event or never started.
            Task { @MainActor in
                DictionaryStore.shared.load()
            }
        }
    }
}
