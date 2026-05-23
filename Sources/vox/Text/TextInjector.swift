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

    struct PhysicalKeystroke: Equatable {
        let code: CGKeyCode
        let flags: CGEventFlags
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
        let target = pasteTargetForFrontmostApp()
        let pb = NSPasteboard.general
        let previous = Self.shouldRestorePasteboard(keepOnClipboard: keepOnClipboard, target: target)
            ? pb.string(forType: .string)
            : nil

        pb.clearContents()
        pb.setString(text, forType: .string)
        var expectedChangeCount = pb.changeCount

        switch target {
        case .standard:
            sendKeyCombo(keycode: UInt16(kVK_ANSI_V), modifiers: [.maskCommand])
        case .screenSharing:
            let delay = Self.prePasteDelay(for: target)
            dlog("paste remote fallback: VNC/Screen Sharing refreshing shared clipboard")
            guard refreshScreenSharingSharedClipboard() else {
                dlog("VNC/Screen Sharing exact paste unavailable; shared clipboard control is disabled")
                return
            }
            // Re-publish after the shared-clipboard refresh in case Screen Sharing
            // pulled the remote side's older clipboard while toggling sync.
            pb.clearContents()
            pb.setString(text, forType: .string)
            expectedChangeCount = pb.changeCount
            dlog("paste remote fallback: VNC/Screen Sharing waiting \(delay)s for shared clipboard sync")
            Thread.sleep(forTimeInterval: delay)
            dlog("paste remote fallback: VNC/Screen Sharing via remote Cmd+V")
            if !pasteWithSystemEventsKeyCode() {
                dlog("VNC/Screen Sharing exact paste failed")
            }
        case .rustDesk:
            dlog("paste remote fallback: RustDesk unmodified physical typing \(text.count) chars")
            typePhysicalText(text, mode: .unmodifiedOnly)
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
            || bundleID.contains("screensharing")
            || bundleID.contains("screen-sharing")
            || bundleID.contains("vnc")
            || name.contains("screen sharing")
            || name.contains("screensharing")
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
        // Remote-app pasteboard synchronization can lag
        // behind the local paste event. Restoring the prior clipboard causes
        // the remote side to paste that older value instead of the transcript.
        if target == .screenSharing || target == .rustDesk { return false }
        return true
    }

    static func usesPhysicalTypingFallback(for target: PasteTarget) -> Bool {
        switch target {
        case .rustDesk: true
        case .screenSharing, .standard: false
        }
    }

    static func requiresExactPaste(for target: PasteTarget) -> Bool {
        switch target {
        case .screenSharing: true
        case .rustDesk, .standard: false
        }
    }

    static func usesMenuPasteFallback(for target: PasteTarget) -> Bool {
        switch target {
        case .screenSharing: true
        case .rustDesk, .standard: false
        }
    }

    static func prePasteDelay(for target: PasteTarget) -> TimeInterval {
        switch target {
        case .screenSharing:
            return 1.5
        case .standard, .rustDesk:
            return 0
        }
    }

    static func refreshesRemoteClipboardAfterPasteboardWrite(for target: PasteTarget) -> Bool {
        switch target {
        case .screenSharing:
            return true
        case .standard, .rustDesk:
            return false
        }
    }

    private func refreshScreenSharingSharedClipboard() -> Bool {
        runAppleScript("""
        tell application "Screen Sharing" to activate
        delay 0.1
        tell application "System Events"
            tell process "Screen Sharing"
                set targetItem to menu item "Use Shared Clipboard" of menu "Edit" of menu bar 1
                if enabled of targetItem is false then error "Edit > Use Shared Clipboard is disabled"
                set isChecked to false
                try
                    set markChar to value of attribute "AXMenuItemMarkChar" of targetItem
                    if markChar is not missing value and markChar is not "" then set isChecked to true
                end try
                try
                    if selected of targetItem is true then set isChecked to true
                end try
                if isChecked is true then
                    click targetItem
                    delay 0.2
                end if
                click targetItem
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

    enum PhysicalTypingMode {
        case capsLockForUppercase
        case unmodifiedOnly
    }

    private func typePhysicalText(_ text: String, mode: PhysicalTypingMode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let initialCapsLockActive = CGEventSource
            .flagsState(.hidSystemState)
            .contains(.maskAlphaShift)
        for stroke in Self.physicalKeystrokes(
            for: text,
            mode: mode,
            initialCapsLockActive: initialCapsLockActive
        ) {
            postKeystroke(stroke, source: source)
            usleep(3_000)
        }
    }

    static func physicalKeystrokes(
        for text: String,
        mode: PhysicalTypingMode
    ) -> [PhysicalKeystroke] {
        physicalKeystrokes(
            for: text,
            mode: mode,
            initialCapsLockActive: false
        )
    }

    static func physicalKeystrokes(
        for text: String,
        mode: PhysicalTypingMode,
        initialCapsLockActive: Bool
    ) -> [PhysicalKeystroke] {
        if mode == .capsLockForUppercase {
            return capsLockPhysicalKeystrokes(
                for: text,
                initialCapsLockActive: initialCapsLockActive
            )
        }
        var strokes: [PhysicalKeystroke] = []
        for character in text {
            appendPhysicalKeystrokes(for: character, mode: mode, to: &strokes)
        }
        return strokes
    }

    private static func capsLockPhysicalKeystrokes(
        for text: String,
        initialCapsLockActive: Bool
    ) -> [PhysicalKeystroke] {
        var strokes: [PhysicalKeystroke] = []
        var capsLockActive = initialCapsLockActive
        for character in text {
            appendCapsLockPhysicalKeystrokes(
                for: character,
                initialCapsLockActive: initialCapsLockActive,
                capsLockActive: &capsLockActive,
                to: &strokes
            )
        }
        if capsLockActive != initialCapsLockActive {
            strokes.append(capsLockToggleStroke)
        }
        return strokes
    }

    private static let capsLockToggleStroke = PhysicalKeystroke(
        code: CGKeyCode(kVK_CapsLock),
        flags: []
    )

    private static func appendCapsLockPhysicalKeystrokes(
        for character: Character,
        initialCapsLockActive: Bool,
        capsLockActive: inout Bool,
        to strokes: inout [PhysicalKeystroke]
    ) {
        if let letter = letterKeyCodeAndCase(for: character) {
            if capsLockActive != letter.isUppercase {
                strokes.append(capsLockToggleStroke)
                capsLockActive.toggle()
            }
            strokes.append(PhysicalKeystroke(code: letter.code, flags: []))
            return
        }
        if let code = unmodifiedPhysicalKeyCode(for: character) {
            strokes.append(PhysicalKeystroke(code: code, flags: []))
            return
        }
        let expansion = physicalExpansion(for: character)
        guard expansion != String(character) else { return }
        for expanded in expansion {
            appendCapsLockPhysicalKeystrokes(
                for: expanded,
                initialCapsLockActive: initialCapsLockActive,
                capsLockActive: &capsLockActive,
                to: &strokes
            )
        }
    }

    private static func letterKeyCodeAndCase(for character: Character) -> (
        code: CGKeyCode,
        isUppercase: Bool
    )? {
        let string = String(character)
        guard string.lowercased() != string.uppercased(),
              let lower = string.lowercased().first else {
            return nil
        }
        guard let code = letterKeyCodes[lower] else { return nil }
        return (code, string == string.uppercased())
    }

    private static func appendPhysicalKeystrokes(
        for character: Character,
        mode: PhysicalTypingMode,
        to strokes: inout [PhysicalKeystroke]
    ) {
        if let stroke = physicalKeystroke(for: character, mode: mode) {
            strokes.append(stroke)
            return
        }
        let expansion = physicalExpansion(for: character)
        guard expansion != String(character) else { return }
        for expanded in expansion {
            appendPhysicalKeystrokes(for: expanded, mode: mode, to: &strokes)
        }
    }

    private static func physicalExpansion(for character: Character) -> String {
        switch character {
        case "?": "."
        case "!": "."
        case ":": ";"
        case "\"": "'"
        case "“", "”": "'"
        case "‘", "’": "'"
        case "(": " "
        case ")": " "
        case "@": " at "
        case "#": " number "
        case "$": " dollars "
        case "%": " percent "
        case "&": " and "
        case "*": " "
        case "_": "-"
        case "+": " plus "
        case "{": "["
        case "}": "]"
        case "|": "/"
        case "<": ","
        case ">": "."
        case "~": "-"
        case "—", "–": "-"
        case "…": "..."
        default: String(character).lowercased()
        }
    }

    private static func physicalKeystroke(
        for character: Character,
        mode: PhysicalTypingMode
    ) -> PhysicalKeystroke? {
        guard let code = unmodifiedPhysicalKeyCode(for: character) else {
            return nil
        }
        return PhysicalKeystroke(code: code, flags: [])
    }

    private static func unmodifiedPhysicalKeyCode(for character: Character) -> CGKeyCode? {
        switch character {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)
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

    private func postKeystroke(_ stroke: PhysicalKeystroke, source: CGEventSource?) {
        if stroke.code == CGKeyCode(kVK_CapsLock) {
            postKeycode(stroke.code, source: source)
            usleep(40_000)
            return
        }
        if stroke.flags.contains(.maskShift) {
            let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)
            shiftDown?.flags = .maskShift
            shiftDown?.post(tap: .cghidEventTap)
            usleep(1_000)
        }
        postKeycode(stroke.code, flags: stroke.flags, source: source)
        if stroke.flags.contains(.maskShift) {
            usleep(1_000)
            let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)
            shiftUp?.flags = []
            shiftUp?.post(tap: .cghidEventTap)
        }
    }

    private func postKeycode(_ code: CGKeyCode, flags: CGEventFlags = [], source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
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
