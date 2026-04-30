import AppKit
import ApplicationServices
import Sparkle

/// Mutex hook: returns true when something else (currently only meeting recording)
/// has taken over the audio path and dictation hotkey must be ignored.
/// Production resolves to `MeetingTranscriptionSession.shared.isRecording`.
/// Tests swap this for a stub.
public enum DictationMutex {
    public static var isBlocked: () -> Bool = {
        MeetingTranscriptionSession.shared.isRecording
    }
}

private let logURL: URL = {
    let fm = FileManager.default
    let logs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
    try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
    return logs.appendingPathComponent("vox.log")
}()

private let logHandle: FileHandle? = {
    let path = logURL.path
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let h = try? FileHandle(forWritingTo: logURL) else { return nil }
    try? h.seekToEnd()
    return h
}()

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

@inline(__always) private func dlog(_ msg: @autoclosure () -> String) {
    let line = "\(isoFormatter.string(from: Date())) [vox] \(msg())\n"
    let data = Data(line.utf8)
    FileHandle.standardError.write(data)
    try? logHandle?.write(contentsOf: data)
}

enum MenuIconState {
    case idle, recording, transcribing, error
}

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let keychain = KeychainStore()
    private let contextDetector = ContextDetector()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let injector = TextInjector()
    private let sound = SoundPlayer()
    private lazy var transcriber = OpenAITranscriber(
        modelProvider: { AppSettings.transcriptionModel.rawValue },
        apiKeyProvider: { [keychain] in keychain.read() }
    )
    private lazy var liveLLMCleaner: CleanupProcessor.LLMCleanFunc = makeLiveLLMCleaner(
        apiKeyProvider: { [keychain] in keychain.read() }
    )
    private lazy var settingsController = SettingsWindowController(keychain: keychain)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var helpWindowController: HelpWindowController?

    private var currentMode: TranscriptionMode = .prose
    private var pulseTimer: Timer?
    private var state: MenuIconState = .idle {
        didSet { refreshIcon() }
    }

    func start() {
        configureMenu()
        refreshIcon()

        hotkey.onRecordPress = { [weak self] in
            dlog("Fn press")
            self?.beginRecording()
        }
        hotkey.onRecordRelease = { [weak self] in
            dlog("Fn release")
            self?.endRecordingAndTranscribe()
        }
        hotkey.onModeToggle = { [weak self] in
            self?.handleModeToggle()
        }

        NotificationCenter.default.addObserver(
            forName: .recordHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }
        NotificationCenter.default.addObserver(
            forName: .modeToggleHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconfigureHotkey()
        }

        Task {
            let granted = await recorder.requestPermission()
            dlog("mic permission granted=\(granted)")
        }

        let hkStarted = hotkey.start()
        dlog("hotkey.start() -> \(hkStarted)")
        if !hkStarted {
            state = .error
            presentAlert(
                title: "Couldn't start hotkey listener",
                message: "Grant Input Monitoring permission in System Settings, then quit and relaunch Vox."
            )
        }

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        dlog("AXIsProcessTrusted=\(trusted)")
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Hold Fn to dictate", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let helpItem = NSMenuItem(title: "Help…", action: #selector(showHelpAction(_:)), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self

        if AppSettings.meetingModeEnabled {
            menu.addItem(.separator())
            let startMeeting = NSMenuItem(
                title: "Start Meeting Transcript",
                action: #selector(startMeetingTranscript),
                keyEquivalent: ""
            )
            startMeeting.target = self
            menu.addItem(startMeeting)
            let stopMeeting = NSMenuItem(
                title: "Stop Meeting Transcript",
                action: #selector(stopMeetingTranscript),
                keyEquivalent: ""
            )
            stopMeeting.target = self
            menu.addItem(stopMeeting)
            let showTranscripts = NSMenuItem(
                title: "Show Meeting Transcripts…",
                action: #selector(showMeetingTranscripts),
                keyEquivalent: ""
            )
            showTranscripts.target = self
            menu.addItem(showTranscripts)
        }

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func appIconForMenuBar() -> NSImage? {
        let icon = NSApp.applicationIconImage
            ?? NSImage(named: NSImage.applicationIconName)
        guard let icon else { return nil }
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size)
        result.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func whiteBackgroundIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.white.setFill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                xRadius: 4, yRadius: 4)
        path.fill()
        let candidates = ["text.bubble", "bubble.left", "bubble.left.fill", "waveform"]
        if let glyph = candidates.lazy
            .compactMap({ NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") })
            .first {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.black])
            let tinted = glyph.withSymbolConfiguration(cfg) ?? glyph
            tinted.draw(in: NSRect(x: 2, y: 2, width: 14, height: 14))
        }
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func tintedSymbol(color: NSColor) -> NSImage? {
        let candidates = ["text.bubble.fill", "bubble.left.fill", "waveform", "mic.fill"]
        let base = candidates.lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") }
            .first
        let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
        let tinted = base?.withSymbolConfiguration(cfg)
        tinted?.isTemplate = false
        return tinted
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:
            // Bubble glyph on transparent background. Tint differs by mode.
            let candidates = ["text.bubble", "bubble.left", "ellipsis.bubble", "bubble.left.fill"]
            let base = candidates.lazy
                .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") }
                .first
            let tint: NSColor
            switch AppSettings.modeOverride {
            case .auto:    tint = .labelColor
            case .prose:   tint = .systemBlue
            case .command: tint = .systemPurple
            }
            let cfg = NSImage.SymbolConfiguration(paletteColors: [tint])
            let tinted = base?.withSymbolConfiguration(cfg)
            tinted?.isTemplate = false
            button.image = tinted
            button.contentTintColor = nil
        case .recording:
            button.image = tintedSymbol(color: .systemRed)
            button.contentTintColor = nil
        case .transcribing:
            button.image = tintedSymbol(color: .systemOrange)
            button.contentTintColor = nil
        case .error:
            let candidates = ["exclamationmark.triangle", "exclamationmark.circle"]
            let base = candidates.lazy
                .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Vox") }
                .first
            base?.isTemplate = true
            button.image = base
            button.contentTintColor = NSColor.labelColor
        }
        // Fallback: status item collapses to zero width if image is nil.
        button.title = (button.image == nil) ? "Vox" : ""
        if state == .transcribing {
            startPulsing()
        } else {
            stopPulsing()
        }
        button.toolTip = {
            switch state {
            case .idle: return "Vox — idle"
            case .recording: return "Vox — recording…"
            case .transcribing: return "Vox — transcribing…"
            case .error: return "Vox — error"
            }
        }()
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    public func showHelp() {
        if helpWindowController == nil {
            helpWindowController = HelpWindowController()
        }
        let controller = helpWindowController
        Task { @MainActor in
            controller?.show()
        }
    }

    @objc private func showHelpAction(_ sender: Any?) {
        showHelp()
    }

    @objc private func startMeetingTranscript() {
        let result = MeetingPreflight.gate(hasAPIKey: keychain.read()?.isEmpty == false)
        if case .failure(let err) = result {
            dlog("meeting gate denied: \(err)")
            presentMeetingError(err.userMessage)
            return
        }
        if state == .recording {
            presentMeetingError("Finish current dictation before starting a meeting.")
            return
        }
        Task { @MainActor in
            do {
                try await MeetingTranscriptionSession.shared.start()
            } catch {
                self.presentMeetingError("Could not start meeting: \(error)")
            }
        }
    }

    @objc private func stopMeetingTranscript() {
        Task { @MainActor in
            do {
                try await MeetingTranscriptionSession.shared.stop()
                MeetingTranscriptsWindow.shared.show()
            } catch {
                self.presentMeetingError("Could not stop meeting: \(error)")
            }
        }
    }

    @objc private func showMeetingTranscripts() {
        Task { @MainActor in
            MeetingTranscriptsWindow.shared.show()
        }
    }

    private func presentMeetingError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Meeting Transcription"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func handleModeToggle() {
        AppSettings.modeOverride = AppSettings.modeOverride.next()
        refreshIcon()
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func reconfigureHotkey() {
        hotkey.stop()
        hotkey.configure(
            record: AppSettings.recordHotkey,
            modeToggle: AppSettings.modeToggleHotkey
        )
        _ = hotkey.start()
    }

    // MARK: - Record / Transcribe

    private func beginRecording() {
        guard state == .idle else { return }
        if DictationMutex.isBlocked() {
            dlog("dictation Fn ignored — meeting recording active")
            return
        }
        switch AppSettings.modeOverride {
        case .auto:    currentMode = contextDetector.modeForFrontmost()
        case .prose:   currentMode = .prose
        case .command: currentMode = .command
        }
        do {
            try recorder.start()
            state = .recording
            sound.play(.start)
        } catch {
            state = .error
            sound.play(.error)
            NSLog("[vox] recorder.start failed: \(error)")
        }
    }

    private func endRecordingAndTranscribe() {
        guard state == .recording else { return }
        let wav = recorder.stop()
        sound.play(.stop)
        let mode = currentMode

        // Silence gate: skip the transcription API if too short or too quiet.
        // Whisper hallucinates / echoes the system prompt when fed silence.
        let (durationSec, rms) = wavStats(wav)
        dlog("wav bytes=\(wav.count) duration=\(durationSec)s rms=\(rms) mode=\(mode)")
        if durationSec < 0.35 || rms < 150 {
            dlog("silence gate tripped — skipping transcription")
            state = .idle
            return
        }

        state = .transcribing

        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.transcriber.transcribe(wav: wav, mode: mode)
                dlog("raw=\(raw)")

                // Hallucination guard. gpt-4o-mini-transcribe occasionally loops on
                // short / noisy audio and emits a runaway repetitive cascade
                // (e.g. "rm -rf X rm -rf Y rm -rf Z..." for 100s of repetitions).
                // Cap output at a generous chars-per-second ratio for the audio
                // duration; a real fast speaker tops out around 17 chars/sec so
                // 40 leaves margin for noisy speech and abbreviations.
                let maxChars = max(160, Int(durationSec * 40.0))
                if raw.count > maxChars {
                    dlog("hallucination guard: \(raw.count) chars for \(durationSec)s audio (max \(maxChars)) — suppressing paste")
                    await MainActor.run {
                        self.state = .error
                        self.sound.play(.error)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.state = .idle
                        }
                    }
                    return
                }
                let processed = await MainActor.run {
                    PostProcessor(mode: mode).process(raw)
                }

                let cleanupEnabled = AppSettings.smartCleanupEnabled
                let cleaner = CleanupProcessor(
                    mode: mode,
                    enabled: cleanupEnabled,
                    llmCleaner: cleanupEnabled ? self.liveLLMCleaner : nil
                )
                let cleanedText = await cleaner.process(processed.text)
                dlog("cleaned=\(cleanedText)")

                let wordCount = cleanedText.split(whereSeparator: { $0.isWhitespace }).count
                let model = AppSettings.transcriptionModel
                let cost = UsageTracker.costEstimate(durationSec: durationSec, model: model)
                UsageTracker.record(durationSec: durationSec, wordCount: wordCount, model: model)
                dlog("processed=\(processed.text) keys=\(processed.suffixKeys) words=\(wordCount) cost=$\(String(format: "%.4f", cost))")
                await MainActor.run {
                    let pasteDelay: Double
                    if cleanedText.isEmpty {
                        pasteDelay = 0
                    } else {
                        self.injector.paste(cleanedText, keepOnClipboard: AppSettings.keepTranscriptionOnClipboard)
                        pasteDelay = 0.2
                    }
                    for (i, key) in processed.suffixKeys.enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + 0.18 * Double(i)) {
                            self.injector.sendKey(key)
                        }
                    }
                    self.state = .idle
                }
            } catch {
                dlog("transcription failed: \(error)")
                await MainActor.run {
                    self.state = .error
                    self.sound.play(.error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.state = .idle
                    }
                }
            }
        }
    }

    private func startPulsing() {
        guard pulseTimer == nil, let button = statusItem.button else { return }
        var dim = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak button] _ in
            guard let button else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                button.animator().alphaValue = dim ? 1.0 : 0.35
            }
            dim.toggle()
        }
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusItem.button?.alphaValue = 1.0
    }

    private func wavStats(_ wav: Data) -> (durationSec: Double, rms: Double) {
        let headerSize = 44
        guard wav.count > headerSize else { return (0, 0) }
        let pcm = wav.subdata(in: headerSize..<wav.count)
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return (0, 0) }
        let duration = Double(sampleCount) / 16_000.0
        let rms = pcm.withUnsafeBytes { raw -> Double in
            let buf = raw.bindMemory(to: Int16.self)
            var sumSq = 0.0
            for s in buf { sumSq += Double(s) * Double(s) }
            return sqrt(sumSq / Double(buf.count))
        }
        return (duration, rms)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
