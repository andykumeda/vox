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
    ///     prior clipboard contents after ~400ms.
    public func paste(
        _ text: String,
        keepOnClipboard: Bool = false
    ) {
        let pb = NSPasteboard.general
        let previous = keepOnClipboard ? nil : pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        sendKeyCombo(keycode: UInt16(kVK_ANSI_V), modifiers: [.maskCommand])
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
