import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = MenuBarController()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `.accessory` keeps Vox out of the Dock — it's primarily a menu-bar
        // app. Windows that need to come to the front (e.g. the transcript
        // browser after a meeting ends) raise their `level` to .floating
        // rather than promoting the activation policy.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Relocator.offerMoveToApplicationsIfNeeded()
        AutoRelaunch.installAndHandOffIfNeeded()
        // Patch headers on any dictation WAVs left half-finished by a prior crash.
        RecordingArchive.repairOrphans()
        let transcriptStore = MeetingTranscriptStore()
        transcriptStore.recoverInFlightSessions()
        let dictDeleted = RecordingArchive.purgeOlderThan(.distantFuture)
        let meetingDeleted = transcriptStore.purgeAllAudioArtifacts()
        if dictDeleted > 0 || meetingDeleted > 0 {
            dlog("privacy audio sweep: dictation=\(dictDeleted) meeting=\(meetingDeleted)")
        }
        menuController.start()
        try? CleanupProfileStore.shared.ensureFileExists()
        DictionaryStore.shared.load()
        DictionaryStore.shared.startWatching()
        Task { @MainActor in
            MainWindowController.shared.showHome(source: .launch)
        }
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
