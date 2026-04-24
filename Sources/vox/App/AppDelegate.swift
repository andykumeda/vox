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
        menuController.start()
    }
}
