import AppKit
import Carbon.HIToolbox
import CoreGraphics

public struct TextInjector {
    public init() {}

    /// Writes `text` to the pasteboard and synthesizes Cmd+V.
    /// - Parameter keepOnClipboard: when true, leaves `text` on the clipboard so the user
    ///   can manually Cmd+V again if focus was lost. When false (default), restores the
    ///   prior clipboard contents after ~400ms.
    public func paste(_ text: String, keepOnClipboard: Bool = false) {
        let pasteboard = NSPasteboard.general
        let previous = keepOnClipboard ? nil : pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesizeCmdV()

        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
    }

    private func synthesizeCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
