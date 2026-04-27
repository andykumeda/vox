import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Monitors the configured record and mode-toggle hotkeys via a single CGEventTap.
/// Emits press / release / mode-toggle callbacks on the main queue.
public final class HotkeyMonitor {
    public var onRecordPress: (() -> Void)?
    public var onRecordRelease: (() -> Void)?
    public var onModeToggle: (() -> Void)?

    private var record: Hotkey
    private var modeToggle: Hotkey

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isRecordActive = false            // pressHold-held or tapToggle-on
    private var pressedKeycode: UInt16?           // captured at keyDown, used at keyUp
    private var lastModeToggleAt: CFAbsoluteTime = 0
    private static let modeToggleDebounceSeconds: CFAbsoluteTime = 0.150

    public init(record: Hotkey? = nil, modeToggle: Hotkey? = nil) {
        self.record = record ?? AppSettings.recordHotkey
        self.modeToggle = modeToggle ?? AppSettings.modeToggleHotkey
    }

    /// Update bindings without restarting the tap.
    public func configure(record: Hotkey, modeToggle: Hotkey) {
        self.record = record
        self.modeToggle = modeToggle
        // If recording was active under an old binding, finalize it.
        if isRecordActive {
            isRecordActive = false
            pressedKeycode = nil
            DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
        }
    }

    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

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

    // MARK: - Dispatch

    private func handle(type: CGEventType, event: CGEvent) {
        let flags = event.flags
        let keycode: UInt16? = {
            if type == .keyDown || type == .keyUp {
                return UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            }
            return nil
        }()

        // Mode toggle (always tap-toggle, debounced).
        if type == .keyDown,
           Self.matches(keycode: keycode, flags: flags, hotkey: modeToggle) {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastModeToggleAt >= Self.modeToggleDebounceSeconds {
                lastModeToggleAt = now
                DispatchQueue.main.async { [weak self] in self?.onModeToggle?() }
            }
            return
        }

        // Record hotkey.
        let recordEvent: Bool
        switch record.key {
        case .fn:
            recordEvent = (type == .flagsChanged)
        case .keycode:
            recordEvent = (type == .keyDown || type == .keyUp)
        }
        guard recordEvent else { return }

        let isMatch = Self.matches(keycode: keycode, flags: flags, hotkey: record)

        switch record.triggerMode {
        case .pressHold:
            handlePressHold(type: type, isMatch: isMatch, keycode: keycode)
        case .tapToggle:
            handleTapToggle(type: type, isMatch: isMatch)
        }
    }

    private func handlePressHold(type: CGEventType, isMatch: Bool, keycode: UInt16?) {
        switch type {
        case .flagsChanged:
            // Used for Fn-only bindings. isMatch reflects whether Fn is held now.
            if isMatch && !isRecordActive {
                isRecordActive = true
                DispatchQueue.main.async { [weak self] in self?.onRecordPress?() }
            } else if !isMatch && isRecordActive && record.key == .fn {
                isRecordActive = false
                pressedKeycode = nil
                DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
            }
        case .keyDown:
            if isMatch && !isRecordActive {
                isRecordActive = true
                pressedKeycode = keycode
                DispatchQueue.main.async { [weak self] in self?.onRecordPress?() }
            }
        case .keyUp:
            // Modifier flags may already be cleared by the time keyUp fires, so
            // match strictly on the keycode captured at press time.
            if let kc = keycode, kc == pressedKeycode, isRecordActive {
                isRecordActive = false
                pressedKeycode = nil
                DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
            }
        default:
            break
        }
    }

    private func handleTapToggle(type: CGEventType, isMatch: Bool) {
        guard type == .keyDown, isMatch else { return }
        isRecordActive.toggle()
        if isRecordActive {
            DispatchQueue.main.async { [weak self] in self?.onRecordPress?() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onRecordRelease?() }
        }
    }

    // MARK: - Temporary back-compat aliases (removed in HK6)

    @available(*, deprecated, message: "Use onRecordPress")
    public var onPress: (() -> Void)? {
        get { onRecordPress }
        set { onRecordPress = newValue }
    }

    @available(*, deprecated, message: "Use onRecordRelease")
    public var onRelease: (() -> Void)? {
        get { onRecordRelease }
        set { onRecordRelease = newValue }
    }

    // MARK: - Static helper (kept from HK3)

    public static func matches(keycode: UInt16?, flags: CGEventFlags, hotkey: Hotkey) -> Bool {
        guard hotkey.enabled else { return false }
        switch hotkey.key {
        case .fn:
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
