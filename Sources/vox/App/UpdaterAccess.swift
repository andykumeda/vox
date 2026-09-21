import Sparkle

/// Process-wide handle to the Sparkle updater so SwiftUI views (Settings, Help, etc)
/// can trigger "Check for Updates…" without owning the controller themselves.
/// Set when `MenuBarController` configures its menu at launch.
public enum UpdaterAccess {
    nonisolated(unsafe) public static var controller: SPUStandardUpdaterController?

    @MainActor
    public static func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
