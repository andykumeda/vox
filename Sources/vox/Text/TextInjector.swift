import AppKit
import Carbon.HIToolbox
import CoreGraphics

public enum SuffixKey: Sendable, Equatable {
    case tab
    case `return`
    case escape
    case space
    case control(Character)
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
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Writes `text` to the pasteboard and synthesizes the configured paste shortcut.
    /// - Parameters:
    ///   - text: the string to paste
    ///   - keepOnClipboard: when true, leaves `text` on the clipboard so the user
    ///     can manually paste again if focus was lost. When false (default), restores the
    ///     prior clipboard contents after ~400ms.
    ///   - shortcut: the hotkey combination to synthesize. When nil (default), uses `AppSettings.pasteHotkey`.
    public func paste(
        _ text: String,
        keepOnClipboard: Bool = false,
        shortcut: Hotkey? = nil
    ) {
        let pb = NSPasteboard.general
        let previous = keepOnClipboard ? nil : pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        let hk = shortcut ?? AppSettings.pasteHotkey
        guard hk.enabled, case .keycode(let kc) = hk.key else {
            // Fn or invalid binding — fall back to ⌘V (defensive).
            sendKeyCombo(keycode: UInt16(kVK_ANSI_V), modifiers: [.maskCommand])
            if !keepOnClipboard { schedulePasteboardClear(previous: previous) }
            return
        }

        var mods: CGEventFlags = []
        if hk.modifiers.contains(.command) { mods.insert(.maskCommand) }
        if hk.modifiers.contains(.control) { mods.insert(.maskControl) }
        if hk.modifiers.contains(.option)  { mods.insert(.maskAlternate) }
        if hk.modifiers.contains(.shift)   { mods.insert(.maskShift) }

        sendKeyCombo(keycode: kc, modifiers: mods)
        if !keepOnClipboard { schedulePasteboardClear(previous: previous) }
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

    private func schedulePasteboardClear(previous: String?) {
        guard let previous else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
    }
}
