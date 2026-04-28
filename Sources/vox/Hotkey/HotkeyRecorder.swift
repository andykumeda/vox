import AppKit
import Carbon.HIToolbox

/// Captures one Hotkey via a local NSEvent monitor (active only while our app
/// is key). Avoids CGEventTap to dodge macOS 26 PAC traps and double-tap races.
public final class HotkeyRecorder {
    public typealias Completion = (Hotkey?) -> Void  // nil if cancelled

    private var monitor: Any?
    private var completion: Completion?
    private var existingTriggerMode: TriggerMode
    private var timeoutTimer: Timer?
    private static let timeoutSeconds: TimeInterval = 5

    public init(existingTriggerMode: TriggerMode) {
        self.existingTriggerMode = existingTriggerMode
    }

    public func start(completion: @escaping Completion) -> Bool {
        self.completion = completion
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

        if event.type == .keyDown && Int(kc) == kVK_Escape {
            DispatchQueue.main.async { [weak self] in self?.cancel() }
            return nil
        }

        switch event.type {
        case .flagsChanged:
            // Single-modifier-only capture: exactly one of fn/cmd/ctrl/opt/shift set.
            let captured: Key?
            switch flags.intersection([.function, .command, .control, .option, .shift]) {
            case [.function]: captured = .fn
            case [.command]:  captured = .modifier(.command)
            case [.control]:  captured = .modifier(.control)
            case [.option]:   captured = .modifier(.option)
            case [.shift]:    captured = .modifier(.shift)
            default:          captured = nil
            }
            if let key = captured {
                let h = Hotkey(key: key, modifiers: [], triggerMode: existingTriggerMode, enabled: true)
                DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
                return nil
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

    private func finish(with hotkey: Hotkey?) {
        guard completion != nil else { return }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
        monitor = nil
        let cb = completion
        completion = nil
        cb?(hotkey)
    }
}
