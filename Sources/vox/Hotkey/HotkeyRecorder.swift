import AppKit
import Carbon.HIToolbox

/// Captures one Hotkey via a local NSEvent monitor (active only while our app
/// is key). Avoids CGEventTap to dodge macOS 26 PAC traps and double-tap races.
public final class HotkeyRecorder {
    public typealias Completion = (Hotkey?) -> Void  // nil if cancelled

    /// True while any recorder instance is actively listening. The global HotkeyMonitor
    /// reads this and suppresses normal hotkey dispatch so that pressing the existing
    /// meeting/record/modeToggle binding while configuring a new one in Settings doesn't
    /// trigger the bound action and steal the keystroke.
    public private(set) static var isCapturing: Bool = false

    private var monitor: Any?
    private var completion: Completion?
    private var existingTriggerMode: TriggerMode
    private var timeoutTimer: Timer?
    private static let timeoutSeconds: TimeInterval = 5

    /// Last non-empty flag set seen during this recording session. Used so we can wait
    /// for the user to finish building a multi-modifier combo before committing.
    private var pendingFlags: NSEvent.ModifierFlags = []
    /// Set true the moment we observe more than one modifier held simultaneously.
    /// If true, we will not interpret a flag-empty event as "user released a single
    /// modifier" — only as "abandoned, wait for further input or timeout."
    private var everSawMultiMod = false

    public init(existingTriggerMode: TriggerMode) {
        self.existingTriggerMode = existingTriggerMode
    }

    public func start(completion: @escaping Completion) -> Bool {
        self.completion = completion
        Self.isCapturing = true
        dlog("HotkeyRecorder start")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event)
        }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeoutSeconds, repeats: false) { [weak self] _ in
            self?.cancel()
        }
        return true
    }

    public func cancel() {
        finish(with: nil)
    }

    private func handle(event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags
        let kc = event.keyCode
        dlog("HotkeyRecorder event type=\(event.type.rawValue) kc=\(kc) flags=\(flags.rawValue)")

        if event.type == .keyDown && Int(kc) == kVK_Escape {
            DispatchQueue.main.async { [weak self] in self?.cancel() }
            return nil
        }

        switch event.type {
        case .flagsChanged:
            let active = flags.intersection([.function, .command, .control, .option, .shift])
            let count = [
                active.contains(.function),
                active.contains(.command),
                active.contains(.control),
                active.contains(.option),
                active.contains(.shift)
            ].filter { $0 }.count
            if count > 1 { everSawMultiMod = true }

            if active.isEmpty {
                // All modifiers released. If the user only ever held one and then released,
                // commit a single-modifier hotkey. If they held multiple at any point,
                // assume they were building a combo and abandoned it — don't commit.
                let single: Key? = everSawMultiMod ? nil : singleModifierKey(pendingFlags)
                pendingFlags = []
                everSawMultiMod = false
                if let key = single {
                    let h = Hotkey(key: key, modifiers: [], triggerMode: existingTriggerMode, enabled: true)
                    DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
                    return nil
                }
            } else {
                pendingFlags = active
            }
        case .keyDown:
            var mods: Set<Modifier> = []
            if flags.contains(.command) { mods.insert(.command) }
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.option)  { mods.insert(.option) }
            if flags.contains(.shift)   { mods.insert(.shift) }
            guard !mods.isEmpty else { return event }
            let h = Hotkey(key: .keycode(UInt16(kc)), modifiers: mods, triggerMode: existingTriggerMode, enabled: true)
            DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
            return nil
        default:
            break
        }
        return event
    }

    private func singleModifierKey(_ flags: NSEvent.ModifierFlags) -> Key? {
        switch flags.intersection([.function, .command, .control, .option, .shift]) {
        case [.function]: return .fn
        case [.command]:  return .modifier(.command)
        case [.control]:  return .modifier(.control)
        case [.option]:   return .modifier(.option)
        case [.shift]:    return .modifier(.shift)
        default:          return nil
        }
    }

    private func finish(with hotkey: Hotkey?) {
        guard completion != nil else { return }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
        monitor = nil
        Self.isCapturing = false
        let cb = completion
        completion = nil
        dlog("HotkeyRecorder finish -> \(hotkey.map { "\($0)" } ?? "nil")")
        cb?(hotkey)
    }
}
