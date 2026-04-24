import AppKit

/// If the app is running from a mounted DMG or ~/Downloads, offer to move
/// itself to /Applications, relaunch from there, and (for DMG) eject the volume.
/// Mirrors Chrome / VS Code / Andy Matuschak's LetsMove pattern.
enum Relocator {
    static func offerMoveToApplicationsIfNeeded() {
        let fm = FileManager.default
        let currentPath = Bundle.main.bundlePath

        // Already in /Applications — nothing to do.
        if currentPath.hasPrefix("/Applications/") { return }
        // User chose ~/Applications — respect.
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        if currentPath.hasPrefix(userApps + "/") { return }

        let isInDMG = currentPath.hasPrefix("/Volumes/")
        let downloadsPath = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        let isInDownloads = currentPath.hasPrefix(downloadsPath + "/")
        guard isInDMG || isInDownloads else { return }

        let appName = (currentPath as NSString).lastPathComponent
        let destPath = "/Applications/\(appName)"

        let alert = NSAlert()
        alert.messageText = "Move Vox to the Applications folder?"
        alert.informativeText = "Vox works best when it lives in /Applications. I can copy myself there and relaunch automatically."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Don't Move")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Replace any existing copy.
        if fm.fileExists(atPath: destPath) {
            do {
                try fm.removeItem(atPath: destPath)
            } catch {
                presentError(error, note: "Vox.app already exists in /Applications and couldn't be replaced.")
                return
            }
        }

        do {
            try fm.copyItem(atPath: currentPath, toPath: destPath)
        } catch {
            presentError(error, note: "Couldn't copy Vox.app into /Applications. Drag it there manually.")
            return
        }

        // Relaunch from new location.
        let destURL = URL(fileURLWithPath: destPath)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: destURL, configuration: cfg) { _, _ in
            if isInDMG, let volumeRoot = dmgMountPoint(forBundlePath: currentPath) {
                try? NSWorkspace.shared.unmountAndEjectDevice(atPath: volumeRoot)
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }

        // Stay in run loop briefly so openApplication callback can fire.
        RunLoop.main.run(until: Date().addingTimeInterval(5))
        exit(0)
    }

    private static func dmgMountPoint(forBundlePath path: String) -> String? {
        // "/Volumes/Vox/Vox.app" → "/Volumes/Vox"
        let parts = path.components(separatedBy: "/")
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        return "/Volumes/" + parts[2]
    }

    private static func presentError(_ error: Error, note: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't move Vox"
        alert.informativeText = "\(note)\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
