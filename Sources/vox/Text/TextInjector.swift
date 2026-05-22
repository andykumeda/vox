import AppKit
import Carbon.HIToolbox
import CoreGraphics

public enum ArrowDirection: Sendable, Equatable, Hashable {
    case left, right, up, down
}

public enum KeyModifier: Sendable, Equatable, Hashable {
    case control, command, option, shift
}

public enum SuffixKey: Sendable, Equatable {
    case tab
    case `return`
    case escape
    case space
    case control(Character)
    case arrow(ArrowDirection, modifiers: Set<KeyModifier>)
}

private let letterKeyCodes: [Character: CGKeyCode] = [
    "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B),
    "c": CGKeyCode(kVK_ANSI_C), "d": CGKeyCode(kVK_ANSI_D),
    "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
    "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H),
    "i": CGKeyCode(kVK_ANSI_I), "j": CGKeyCode(kVK_ANSI_J),
    "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
    "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N),
    "o": CGKeyCode(kVK_ANSI_O), "p": CGKeyCode(kVK_ANSI_P),
    "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
    "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T),
    "u": CGKeyCode(kVK_ANSI_U), "v": CGKeyCode(kVK_ANSI_V),
    "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
    "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
]

public struct TextInjector {
    public init() {}

    enum PasteTarget: Equatable {
        case standard
        case screenSharing
        case rustDesk
    }

    public func sendKey(_ key: SuffixKey) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let code: CGKeyCode
        var flags: CGEventFlags = []
        switch key {
        case .tab: code = CGKeyCode(kVK_Tab)
        case .return: code = CGKeyCode(kVK_Return)
        case .escape: code = CGKeyCode(kVK_Escape)
        case .space: code = CGKeyCode(kVK_Space)
        case .control(let ch):
            guard let mapped = letterKeyCodes[Character(ch.lowercased())] else { return }
            code = mapped
            flags = .maskControl
        case .arrow(let dir, let mods):
            switch dir {
            case .left:  code = CGKeyCode(kVK_LeftArrow)
            case .right: code = CGKeyCode(kVK_RightArrow)
            case .up:    code = CGKeyCode(kVK_UpArrow)
            case .down:  code = CGKeyCode(kVK_DownArrow)
            }
            if mods.contains(.control) { flags.insert(.maskControl) }
            if mods.contains(.command) { flags.insert(.maskCommand) }
            if mods.contains(.option)  { flags.insert(.maskAlternate) }
            if mods.contains(.shift)   { flags.insert(.maskShift) }
        }
        // For arrow keystrokes with modifiers, synthesize explicit modifier
        // press / release events around the arrow key with a hardware-like
        // event source. Mission Control's space switcher and similar system
        // shortcuts filter events that come from `.combinedSessionState`;
        // `.hidSystemState` emulates the path real hardware events take.
        if case .arrow = key, !flags.isEmpty {
            let hwSource = CGEventSource(stateID: .hidSystemState)
            postFullKeystrokeWithModifiers(source: hwSource, code: code, flags: flags)
            return
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func postFullKeystrokeWithModifiers(
        source: CGEventSource?,
        code: CGKeyCode,
        flags: CGEventFlags
    ) {
        let modKeys: [(CGEventFlags, Int)] = [
            (.maskControl,   kVK_Control),
            (.maskCommand,   kVK_Command),
            (.maskAlternate, kVK_Option),
            (.maskShift,     kVK_Shift),
        ]
        // HID-level tap with a hardware-like source. Mission Control's
        // space-switcher listens at WindowServer level; HID events from a
        // hidSystemState source propagate up the same way a real key would.
        let tap: CGEventTapLocation = .cghidEventTap
        var current: CGEventFlags = []
        for (flag, vk) in modKeys where flags.contains(flag) {
            current.insert(flag)
            let evt = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vk), keyDown: true)
            evt?.flags = current
            evt?.post(tap: tap)
        }
        // Small delay so WindowServer registers the modifier flag-change
        // before the arrow event arrives.
        usleep(15_000)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: tap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: tap)
        usleep(15_000)
        for (flag, vk) in modKeys.reversed() where flags.contains(flag) {
            current.remove(flag)
            let evt = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vk), keyDown: false)
            evt?.flags = current
            evt?.post(tap: tap)
        }
    }

    /// Writes `text` to the pasteboard and synthesizes ⌘V into the focused app.
    /// ⌘V is hardcoded because virtually every macOS responder chain binds Paste
    /// to it; user-configurable outbound shortcuts silently broke paste in apps
    /// that didn't honor the rebind.
    /// - Parameters:
    ///   - text: the string to paste
    ///   - keepOnClipboard: when true, leaves `text` on the clipboard so the user
    ///     can manually paste again if focus was lost. When false (default), restores the
    ///     prior clipboard contents after ~1.5s — long enough that even slow
    ///     apps (Slack, Electron, web inputs) read the transcript before the
    ///     restore lands.
    public func paste(
        _ text: String,
        keepOnClipboard: Bool = false
    ) {
        let pb = NSPasteboard.general
        let previous = keepOnClipboard ? nil : pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let expectedChangeCount = pb.changeCount

        let target = pasteTargetForFrontmostApp()
        switch target {
        case .standard:
            sendKeyCombo(keycode: UInt16(kVK_ANSI_V), modifiers: [.maskCommand])
        case .screenSharing:
            let delay = Self.prePasteDelay(for: target)
            dlog("paste remote fallback: VNC/Screen Sharing waiting \(delay)s for clipboard sync")
            Thread.sleep(forTimeInterval: delay)
            dlog("paste remote fallback: VNC/Screen Sharing via Edit > Paste menu")
            if !pasteWithFrontmostEditMenu() {
                dlog("VNC/Screen Sharing Edit > Paste failed; falling back to System Events Cmd+V")
                if !pasteWithSystemEventsKeyCode() {
                    dlog("VNC/Screen Sharing paste fallback failed")
                }
            }
        case .rustDesk:
            dlog("paste remote fallback: RustDesk physical typing \(text.count) chars")
            typePhysicalTextForRustDesk(text)
        }
        if Self.shouldRestorePasteboard(keepOnClipboard: keepOnClipboard, target: target) {
            schedulePasteboardClear(previous: previous, expectedChangeCount: expectedChangeCount)
        }
    }

    private func pasteTargetForFrontmostApp() -> PasteTarget {
        let app = NSWorkspace.shared.frontmostApplication
        let target = Self.pasteTarget(
            bundleIdentifier: app?.bundleIdentifier,
            localizedName: app?.localizedName
        )
        dlog("paste target: \(target) bundle=\(app?.bundleIdentifier ?? "nil") name=\(app?.localizedName ?? "nil")")
        return target
    }

    static func pasteTarget(
        bundleIdentifier: String?,
        localizedName: String?
    ) -> PasteTarget {
        let bundleID = bundleIdentifier?.lowercased() ?? ""
        let name = localizedName?.lowercased() ?? ""
        if bundleID == "com.carriez.rustdesk" {
            return .rustDesk
        }
        if bundleID == "com.apple.screensharing"
            || bundleID.contains("vnc")
            || name.contains("vnc") {
            return .screenSharing
        }
        return .standard
    }

    static func shouldRestorePasteboard(
        keepOnClipboard: Bool,
        target: PasteTarget
    ) -> Bool {
        if keepOnClipboard { return false }
        // VNC/Screen Sharing paste and clipboard synchronization can lag
        // behind the local paste event. Restoring the prior clipboard causes
        // the remote side to paste that older value instead of the transcript.
        if target == .screenSharing { return false }
        return true
    }

    static func prePasteDelay(for target: PasteTarget) -> TimeInterval {
        switch target {
        case .screenSharing:
            // VNC clients sync the local pasteboard to the remote host out of
            // band. If we send Paste immediately, the remote host can paste its
            // previous clipboard before it has received Vox's transcript.
            return 1.5
        case .standard, .rustDesk:
            return 0
        }
    }

    private func pasteWithFrontmostEditMenu() -> Bool {
        runAppleScript("""
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            tell frontApp
                click menu item "Paste" of menu "Edit" of menu bar 1
            end tell
        end tell
        """)
    }

    private func pasteWithSystemEventsKeyCode() -> Bool {
        runAppleScript("""
        tell application "System Events"
            key code 9 using command down
        end tell
        """)
    }

    private func typePhysicalTextForRustDesk(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for code in physicalKeyCodes(for: text) {
            postKeycode(code, source: source)
            usleep(4_000)
        }
    }

    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            dlog("AppleScript failed: \(error)")
            return false
        }
        return true
    }

    private func physicalKeyCodes(for text: String) -> [CGKeyCode] {
        var codes: [CGKeyCode] = []
        for character in text {
            appendPhysicalKeyCodes(for: character, to: &codes)
        }
        return codes
    }

    private func appendPhysicalKeyCodes(for character: Character, to codes: inout [CGKeyCode]) {
        if let code = unmodifiedPhysicalKeyCode(for: character) {
            codes.append(code)
            return
        }
        let expansion: String
        switch character {
        case "?": expansion = "."
        case "!": expansion = "."
        case ":": expansion = ";"
        case "\"": expansion = "'"
        case "“", "”": expansion = "'"
        case "‘", "’": expansion = "'"
        case "(": expansion = " "
        case ")": expansion = " "
        case "@": expansion = " at "
        case "#": expansion = " number "
        case "$": expansion = " dollars "
        case "%": expansion = " percent "
        case "&": expansion = " and "
        case "*": expansion = " "
        case "_": expansion = "-"
        case "+": expansion = " plus "
        case "{": expansion = "["
        case "}": expansion = "]"
        case "|": expansion = "/"
        case "<": expansion = ","
        case ">": expansion = "."
        case "~": expansion = "-"
        case "—", "–": expansion = "-"
        case "…": expansion = "..."
        default: expansion = String(character).lowercased()
        }
        guard expansion != String(character) else { return }
        for expanded in expansion {
            appendPhysicalKeyCodes(for: expanded, to: &codes)
        }
    }

    private func unmodifiedPhysicalKeyCode(for character: Character) -> CGKeyCode? {
        switch character {
        case "a", "A": return CGKeyCode(kVK_ANSI_A)
        case "b", "B": return CGKeyCode(kVK_ANSI_B)
        case "c", "C": return CGKeyCode(kVK_ANSI_C)
        case "d", "D": return CGKeyCode(kVK_ANSI_D)
        case "e", "E": return CGKeyCode(kVK_ANSI_E)
        case "f", "F": return CGKeyCode(kVK_ANSI_F)
        case "g", "G": return CGKeyCode(kVK_ANSI_G)
        case "h", "H": return CGKeyCode(kVK_ANSI_H)
        case "i", "I": return CGKeyCode(kVK_ANSI_I)
        case "j", "J": return CGKeyCode(kVK_ANSI_J)
        case "k", "K": return CGKeyCode(kVK_ANSI_K)
        case "l", "L": return CGKeyCode(kVK_ANSI_L)
        case "m", "M": return CGKeyCode(kVK_ANSI_M)
        case "n", "N": return CGKeyCode(kVK_ANSI_N)
        case "o", "O": return CGKeyCode(kVK_ANSI_O)
        case "p", "P": return CGKeyCode(kVK_ANSI_P)
        case "q", "Q": return CGKeyCode(kVK_ANSI_Q)
        case "r", "R": return CGKeyCode(kVK_ANSI_R)
        case "s", "S": return CGKeyCode(kVK_ANSI_S)
        case "t", "T": return CGKeyCode(kVK_ANSI_T)
        case "u", "U": return CGKeyCode(kVK_ANSI_U)
        case "v", "V": return CGKeyCode(kVK_ANSI_V)
        case "w", "W": return CGKeyCode(kVK_ANSI_W)
        case "x", "X": return CGKeyCode(kVK_ANSI_X)
        case "y", "Y": return CGKeyCode(kVK_ANSI_Y)
        case "z", "Z": return CGKeyCode(kVK_ANSI_Z)
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        case " ": return CGKeyCode(kVK_Space)
        case "\n": return CGKeyCode(kVK_Return)
        case "\t": return CGKeyCode(kVK_Tab)
        case "-": return CGKeyCode(kVK_ANSI_Minus)
        case "=": return CGKeyCode(kVK_ANSI_Equal)
        case "[": return CGKeyCode(kVK_ANSI_LeftBracket)
        case "]": return CGKeyCode(kVK_ANSI_RightBracket)
        case "\\": return CGKeyCode(kVK_ANSI_Backslash)
        case ";": return CGKeyCode(kVK_ANSI_Semicolon)
        case "'": return CGKeyCode(kVK_ANSI_Quote)
        case ",": return CGKeyCode(kVK_ANSI_Comma)
        case ".": return CGKeyCode(kVK_ANSI_Period)
        case "/": return CGKeyCode(kVK_ANSI_Slash)
        case "`": return CGKeyCode(kVK_ANSI_Grave)
        default: return nil
        }
    }

    private func postKeycode(_ code: CGKeyCode, source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func sendKeyCombo(keycode: UInt16, modifiers: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: false)
        down?.flags = modifiers
        up?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func schedulePasteboardClear(previous: String?, expectedChangeCount: Int) {
        // 1.5s lets even slow paste handlers (Slack, Electron, browser inputs)
        // read the transcript before we overwrite the clipboard. Earlier
        // restores raced the target app's paste and inserted the prior
        // clipboard contents instead of the transcript.
        //
        // Guard against clobbering: if changeCount moved, the user (or
        // another app) wrote new clipboard content in the meantime — leave
        // it alone rather than overwriting their work.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let pb = NSPasteboard.general
            guard pb.changeCount == expectedChangeCount else { return }
            pb.clearContents()
            if let previous {
                pb.setString(previous, forType: .string)
            }
        }
    }
}
