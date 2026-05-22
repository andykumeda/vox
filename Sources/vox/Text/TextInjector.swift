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
            dlog("paste remote fallback: VNC/Screen Sharing unicode typing \(text.count) chars")
            typeUnicodeText(text)
        case .rustDesk:
            dlog("paste remote fallback: RustDesk physical typing \(text.count) chars")
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

    static func usesPhysicalTypingFallback(for target: PasteTarget) -> Bool {
        switch target {
        case .rustDesk: true
        case .screenSharing, .standard: false
        }
    }

    static func usesUnicodeTypingFallback(for target: PasteTarget) -> Bool {
        switch target {
        case .screenSharing: true
        case .standard: false
        case .rustDesk: false
        }
    }

    enum PhysicalTypingMode {
        case withShiftModifiers
        case unmodifiedOnly
    }

    private func typePhysicalText(_ text: String, mode: PhysicalTypingMode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for stroke in Self.physicalKeystrokes(for: text, mode: mode) {
            postKeystroke(stroke, source: source)
            usleep(3_000)
        }
    }

    private func typeUnicodeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            postUnicodeScalar(scalar, source: source)
            usleep(3_000)
        }
    }

    private func postUnicodeScalar(_ scalar: Unicode.Scalar, source: CGEventSource?) {
        let string = String(scalar)
        let units = Array(string.utf16)
        units.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
            up?.post(tap: .cghidEventTap)
        }
    }

    static func physicalKeystrokes(
        for text: String,
        mode: PhysicalTypingMode
    ) -> [PhysicalKeystroke] {
        var strokes: [PhysicalKeystroke] = []
        for character in text {
            appendPhysicalKeystrokes(for: character, mode: mode, to: &strokes)
        }
        return strokes
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
            appendPhysicalKeystrokes(for: expanded, mode: mode, to: &strokes)
        }
    }

    private static func physicalKeystroke(
        for character: Character,
        mode: PhysicalTypingMode
    ) -> PhysicalKeystroke? {
        if mode == .withShiftModifiers, let stroke = shiftedPhysicalKeystroke(for: character) {
            return stroke
        }
        guard let code = unmodifiedPhysicalKeyCode(for: character) else {
            return nil
        }
        return PhysicalKeystroke(code: code, flags: [])
    }

    private static func shiftedPhysicalKeystroke(for character: Character) -> PhysicalKeystroke? {
        let shift: CGEventFlags = .maskShift
        switch character {
        case "A": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_A), flags: shift)
        case "B": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_B), flags: shift)
        case "C": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_C), flags: shift)
        case "D": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_D), flags: shift)
        case "E": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_E), flags: shift)
        case "F": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_F), flags: shift)
        case "G": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_G), flags: shift)
        case "H": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_H), flags: shift)
        case "I": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_I), flags: shift)
        case "J": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_J), flags: shift)
        case "K": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_K), flags: shift)
        case "L": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_L), flags: shift)
        case "M": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_M), flags: shift)
        case "N": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_N), flags: shift)
        case "O": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_O), flags: shift)
        case "P": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_P), flags: shift)
        case "Q": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Q), flags: shift)
        case "R": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_R), flags: shift)
        case "S": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_S), flags: shift)
        case "T": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_T), flags: shift)
        case "U": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_U), flags: shift)
        case "V": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_V), flags: shift)
        case "W": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_W), flags: shift)
        case "X": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_X), flags: shift)
        case "Y": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Y), flags: shift)
        case "Z": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Z), flags: shift)
        case "!": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_1), flags: shift)
        case "@": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_2), flags: shift)
        case "#": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_3), flags: shift)
        case "$": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_4), flags: shift)
        case "%": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_5), flags: shift)
        case "^": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_6), flags: shift)
        case "&": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_7), flags: shift)
        case "*": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_8), flags: shift)
        case "(": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_9), flags: shift)
        case ")": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_0), flags: shift)
        case "_": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Minus), flags: shift)
        case "+": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Equal), flags: shift)
        case "{": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_LeftBracket), flags: shift)
        case "}": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_RightBracket), flags: shift)
        case "|": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Backslash), flags: shift)
        case ":": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Semicolon), flags: shift)
        case "\"": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Quote), flags: shift)
        case "<": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Comma), flags: shift)
        case ">": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Period), flags: shift)
        case "?": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Slash), flags: shift)
        case "~": return PhysicalKeystroke(code: CGKeyCode(kVK_ANSI_Grave), flags: shift)
        default: return nil
        }
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
