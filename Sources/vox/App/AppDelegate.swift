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
