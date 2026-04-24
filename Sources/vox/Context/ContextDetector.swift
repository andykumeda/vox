import AppKit

public struct ContextDetector: Sendable {
    public static let defaultTerminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "dev.commandline.waveterm",
        "com.zeit.hyper",
        "com.tabby.tabby",
        "org.tabby.tabby",
    ]

    public let terminalBundleIDs: Set<String>

    public init(terminalBundleIDs: Set<String> = Self.defaultTerminalBundleIDs) {
        self.terminalBundleIDs = terminalBundleIDs
    }

    public func modeForFrontmost() -> TranscriptionMode {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return mode(forBundleID: bundleID)
    }

    public func mode(forBundleID bundleID: String?) -> TranscriptionMode {
        guard let bundleID else { return .prose }
        return terminalBundleIDs.contains(bundleID) ? .command : .prose
    }
}
