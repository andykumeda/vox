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

        // Try plain copy first; if /Applications isn't writable, escalate via AppleScript.
        if !attemptCopy(from: currentPath, to: destPath) {
            guard escalatedCopy(from: currentPath, to: destPath) else {
                return  // user cancelled or copy errored — alert already shown
            }
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

    /// Plain user-level copy. Returns true on success. Cleans dest first if present.
    private static func attemptCopy(from src: String, to dst: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst) {
            do { try fm.removeItem(atPath: dst) }
            catch { return false }
        }
        do {
            try fm.copyItem(atPath: src, toPath: dst)
            return true
        } catch {
            return false
        }
    }

    /// AppleScript-based copy with admin privileges. Triggers Touch ID / password prompt.
    /// Returns false if the user cancelled or the copy errored (alert is shown).
    private static func escalatedCopy(from src: String, to dst: String) -> Bool {
        let escSrc = src.replacingOccurrences(of: "\"", with: "\\\"")
        let escDst = dst.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "rm -rf \\"\(escDst)\\" && /bin/cp -R \\"\(escSrc)\\" \\"\(escDst)\\"" with administrator privileges
        """
        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        _ = appleScript?.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            // -128 = user cancelled. Don't show an error in that case — they decided.
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { return false }
            let message = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown error."
            let alert = NSAlert()
            alert.messageText = "Couldn't move Vox to /Applications"
            alert.informativeText = message + "\n\nDrag Vox.app into /Applications manually."
            alert.runModal()
            return false
        }
        return true
    }

    private static func dmgMountPoint(forBundlePath path: String) -> String? {
        // "/Volumes/Vox/Vox.app" → "/Volumes/Vox"
        let parts = path.components(separatedBy: "/")
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        return "/Volumes/" + parts[2]
    }
}
