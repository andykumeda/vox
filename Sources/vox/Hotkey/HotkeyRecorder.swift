import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Ephemeral CGEventTap that captures one Hotkey, then auto-stops.
public final class HotkeyRecorder {
    public typealias Completion = (Hotkey?) -> Void  // nil if cancelled

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var completion: Completion?
    private var existingTriggerMode: TriggerMode
    private var timeoutTimer: Timer?
    private static let timeoutSeconds: TimeInterval = 5

    public init(existingTriggerMode: TriggerMode) {
        self.existingTriggerMode = existingTriggerMode
    }

    public func start(completion: @escaping Completion) -> Bool {
        self.completion = completion
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let r = Unmanaged<HotkeyRecorder>.fromOpaque(refcon).takeUnretainedValue()
                r.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            completion(nil)
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeoutSeconds, repeats: false) { [weak self] _ in
            self?.cancel()
        }
        return true
    }

    public func cancel() {
        finish(with: nil)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        // Esc cancels.
        if type == .keyDown,
           UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == UInt16(kVK_Escape) {
            DispatchQueue.main.async { [weak self] in self?.cancel() }
            return
        }
        switch type {
        case .flagsChanged:
            // Fn-only: maskSecondaryFn set, no other modifiers.
            let otherMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            if flags.contains(.maskSecondaryFn) && flags.intersection(otherMods).isEmpty {
                let h = Hotkey(key: .fn, modifiers: [], triggerMode: existingTriggerMode, enabled: true)
                DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
            }
        case .keyDown:
            let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            var mods: Set<Modifier> = []
            if flags.contains(.maskCommand)   { mods.insert(.command) }
            if flags.contains(.maskControl)   { mods.insert(.control) }
            if flags.contains(.maskAlternate) { mods.insert(.option) }
            if flags.contains(.maskShift)     { mods.insert(.shift) }
            guard !mods.isEmpty else { return }  // require at least one modifier
            let h = Hotkey(key: .keycode(kc), modifiers: mods, triggerMode: existingTriggerMode, enabled: true)
            DispatchQueue.main.async { [weak self] in self?.finish(with: h) }
        default:
            break
        }
    }

    private func finish(with hotkey: Hotkey?) {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        eventTap = nil
        runLoopSource = nil
        let cb = completion
        completion = nil
        cb?(hotkey)
    }
}
