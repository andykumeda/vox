import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Monitors the Fn / Globe key via a CGEventTap. Emits press / release via callbacks on the main queue.
public final class HotkeyMonitor {
    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnDown = false

    public init() {}

    public func start() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return false
        }
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard type == .flagsChanged else { return }
        let flags = event.flags
        // Secondary Fn flag mask
        let fnMask = CGEventFlags.maskSecondaryFn
        let nowDown = flags.contains(fnMask)
        if nowDown == isFnDown { return }
        isFnDown = nowDown
        DispatchQueue.main.async { [weak self] in
            if nowDown {
                self?.onPress?()
            } else {
                self?.onRelease?()
            }
        }
    }

    /// Pure-function event matcher. `keycode == nil` means "modifier-only event"
    /// (e.g., Fn flag changes). Returns true when the event represents this hotkey.
    public static func matches(keycode: UInt16?, flags: CGEventFlags, hotkey: Hotkey) -> Bool {
        guard hotkey.enabled else { return false }
        switch hotkey.key {
        case .fn:
            // Fn-only: secondaryFn flag set, no other modifier flags, no keycode.
            let otherMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            return flags.contains(.maskSecondaryFn)
                && flags.intersection(otherMods).isEmpty
                && keycode == nil
        case .keycode(let target):
            guard let kc = keycode, kc == target else { return false }
            let actual: Set<Modifier> = {
                var s: Set<Modifier> = []
                if flags.contains(.maskCommand)   { s.insert(.command) }
                if flags.contains(.maskControl)   { s.insert(.control) }
                if flags.contains(.maskAlternate) { s.insert(.option) }
                if flags.contains(.maskShift)     { s.insert(.shift) }
                return s
            }()
            return actual == hotkey.modifiers
        }
    }
}
