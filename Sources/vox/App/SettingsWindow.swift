import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var savedMessage: String?
    @State private var keepOnClipboard: Bool = AppSettings.keepTranscriptionOnClipboard
    @State private var forceProse: Bool = AppSettings.forceProseMode
    @State private var model: TranscriptionModel = AppSettings.transcriptionModel
    @State private var totals: UsageTotals = UsageTracker.totals()
    @StateObject private var dict = DictionaryStore.shared
    @State private var editingEntry: DictionaryEntry?
    @State private var isAddingEntry: Bool = false
    let keychain: KeychainStore

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vox — Settings")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API key")
                    .font(.headline)
                HStack {
                    if showKey {
                        TextField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                }
                Text("Stored in macOS Keychain. Get a key at platform.openai.com/api-keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                Button("Clear") {
                    try? keychain.delete()
                    apiKey = ""
                    savedMessage = "Cleared."
                }
                if let msg = savedMessage {
                    Text(msg).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                Picker("", selection: $model) {
                    ForEach(TranscriptionModel.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .onChange(of: model) { newValue in
                    AppSettings.transcriptionModel = newValue
                }
                Text(String(format: "≈ $%.4f / minute of audio", model.usdPerMinute))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Usage (lifetime)")
                    .font(.headline)
                Text("Calls: \(totals.calls)   Words: \(totals.words)")
                    .font(.system(.body, design: .monospaced))
                Text(String(format: "Audio: %.1f min   Cost: $%.3f",
                            totals.audioSeconds / 60.0, totals.usd))
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Refresh") { totals = UsageTracker.totals() }
                    Button("Reset") {
                        UsageTracker.reset()
                        totals = UsageTracker.totals()
                    }
                }
                Text("Estimate based on audio duration × model rate. Output text tokens add a tiny extra charge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode")
                    .font(.headline)
                Toggle("Always use prose mode (ignore terminal detection)", isOn: Binding(
                    get: { forceProse },
                    set: { newValue in
                        forceProse = newValue
                        AppSettings.forceProseMode = newValue
                    }
                ))
                Text("Off: dictation in Terminal/iTerm/Wave/etc gets command formatting (no period, no caps, dash/NATO/control). On: always treat dictation as prose with sentence punctuation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste behavior")
                    .font(.headline)
                Toggle("Keep transcription on clipboard after paste", isOn: Binding(
                    get: { keepOnClipboard },
                    set: { newValue in
                        keepOnClipboard = newValue
                        AppSettings.keepTranscriptionOnClipboard = newValue
                    }
                ))
                Text("When on, the transcribed text stays on your clipboard so you can Cmd+V again if focus moved away. Your prior clipboard contents are overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.headline)
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Open Input Monitoring Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                Button("Open Microphone Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Dictionary")
                        .font(.headline)
                    Spacer()
                    Button {
                        editingEntry = DictionaryEntry(
                            id: "user-\(UUID().uuidString)",
                            spoken: "", replacement: "",
                            mode: .command, isBuiltIn: false
                        )
                        isAddingEntry = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([dict.fileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }

                if let err = dict.loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                let userEntries = dict.entries.filter { !$0.isBuiltIn }
                let builtinCount = dict.entries.count - userEntries.count
                let disabledCount = userEntries.filter { !$0.enabled }.count

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if userEntries.isEmpty {
                            VStack(spacing: 6) {
                                Text("No custom entries yet.")
                                    .foregroundStyle(.secondary)
                                Text("Click Add to create one.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(builtinCount) built-in fixups active")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(userEntries.enumerated()), id: \.element.id) { idx, entry in
                                DictionaryRow(
                                    entry: entry,
                                    onToggle: { dict.setEnabled(id: entry.id, enabled: !entry.enabled) },
                                    onEdit: { editingEntry = entry; isAddingEntry = false },
                                    onDelete: { dict.delete(id: entry.id) }
                                )
                                .padding(.horizontal, 8)
                                if idx < userEntries.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 240, maxHeight: 400)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

                Text("\(userEntries.count) custom entries · \(disabledCount) disabled · \(builtinCount) built-in fixups active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .sheet(item: $editingEntry) { entry in
                DictionaryEditSheet(
                    entry: entry,
                    isNew: isAddingEntry,
                    onSave: { saved in
                        if isAddingEntry { dict.add(saved) } else { dict.update(saved) }
                        editingEntry = nil
                    },
                    onCancel: { editingEntry = nil }
                )
            }

        }
        .padding(20)
        }
        .frame(width: 480, height: 800)
        .onAppear {
            apiKey = keychain.read() ?? ""
            totals = UsageTracker.totals()
            model = AppSettings.transcriptionModel
            forceProse = AppSettings.forceProseMode
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        do {
            try keychain.save(trimmed)
            savedMessage = "Saved."
        } catch {
            savedMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.spoken).font(.system(.body, design: .monospaced))
                    Text("→").foregroundStyle(.secondary)
                    Text(entry.replacement.isEmpty ? "(delete)" : entry.replacement)
                        .font(.system(.body, design: .monospaced))
                }
                HStack(spacing: 8) {
                    Text(entry.mode.rawValue).font(.caption).foregroundStyle(.secondary)
                    if entry.startsWith {
                        Text("start").font(.caption).foregroundStyle(.secondary)
                    }
                    if entry.isBuiltIn {
                        Text("built-in").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            if !entry.isBuiltIn {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DictionaryEditSheet: View {
    @State var entry: DictionaryEntry
    let isNew: Bool
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add entry" : "Edit entry").font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spoken").font(.caption)
                TextField("e.g. vox", text: $entry.spoken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Replacement").font(.caption)
                TextField("e.g. Vox", text: $entry.replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                Picker("Mode", selection: $entry.mode) {
                    ForEach(Scope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .frame(maxWidth: 180)

                Toggle("Match only at start", isOn: $entry.startsWith)
                Toggle("Case-insensitive", isOn: $entry.caseInsensitive)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isNew ? "Add" : "Save") { onSave(entry) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry.spoken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init(keychain: KeychainStore) {
        let hosting = NSHostingController(rootView: SettingsView(keychain: keychain))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Vox"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
