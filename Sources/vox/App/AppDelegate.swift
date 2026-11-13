import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = MenuBarController()
    private var meetingRecovery: MeetingRecoveryScheduler?

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
        let transcriptStore = MeetingTranscriptStore()
        transcriptStore.recoverInFlightSessions()
        let dictDeleted = RecordingArchive.purgeOlderThan(.distantFuture)
        Task.detached(priority: .utility) { transcriptStore.applyAudioRetention() }
        if dictDeleted > 0 { dlog("privacy audio sweep: dictation=\(dictDeleted)") }
        for name in [Notification.Name.NSCalendarDayChanged, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task.detached(priority: .utility) { MeetingTranscriptStore().applyAudioRetention() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task.detached(priority: .utility) { MeetingTranscriptStore().applyAudioRetention() }
        }
        let recovery = MeetingRecoveryScheduler(session: .shared, store: transcriptStore)
        meetingRecovery = recovery
        recovery.start()
        NotificationCenter.default.addObserver(forName: .meetingTranscriptStoreDidChange, object: nil, queue: .main) { [weak recovery] _ in
            Task { @MainActor in recovery?.requestSweep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak recovery] _ in
            Task { @MainActor in recovery?.requestSweep() }
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
