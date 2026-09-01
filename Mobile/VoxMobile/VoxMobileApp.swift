import SwiftUI
import VoxCore

@main
struct VoxMobileApp: App {
    @StateObject private var coordinator = MobileDictationCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRootView(coordinator: coordinator)
                .onOpenURL { coordinator.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        coordinator.resumePendingRequestIfNeeded()
                    }
                }
        }
    }
}

struct MobileRootView: View {
    @ObservedObject var coordinator: MobileDictationCoordinator

    var body: some View {
        TabView {
            NavigationStack { SetupView(coordinator: coordinator) }
                .tabItem { Label("Setup", systemImage: "checklist") }
            NavigationStack { HistoryView(store: coordinator.history) }
                .tabItem { Label("History", systemImage: "clock") }
            NavigationStack { DictionaryListView(store: coordinator.dictionary) }
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            NavigationStack { SettingsView(settings: coordinator.settings) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct SetupView: View {
    @ObservedObject var coordinator: MobileDictationCoordinator

    var body: some View {
        List {
            Section {
                Label("Open Settings → General → Keyboard → Keyboards", systemImage: "1.circle")
                Label("Add Vox Keyboard", systemImage: "2.circle")
                Label("Enable Allow Full Access", systemImage: "3.circle")
                Label("Enter your OpenAI API key in Settings", systemImage: "4.circle")
            } header: {
                Text("Get started")
            } footer: {
                Text("Full Access lets the keyboard exchange only Vox request state and completed transcription text with this app.")
            }

            Section("Status") {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(coordinator.statusMessage)
                }
                if coordinator.phase == .recording {
                    Button("Stop recording", role: .destructive) {
                        coordinator.stopRecording()
                    }
                    Button("Cancel", role: .cancel) {
                        coordinator.cancel()
                    }
                } else if ![.transcribing, .requestingHandoff].contains(coordinator.phase) {
                Button("Test dictation in Vox") {
                    coordinator.startTestDictation()
                }
                Button("Reset dictation state", role: .destructive) {
                    coordinator.resetExchangeState()
                }
            }
            }
        }
        .navigationTitle("Vox for iPhone")
    }

    private var statusColor: Color {
        switch coordinator.phase {
        case .recording: return .red
        case .transcribing, .requestingHandoff, .stopRequested: return .orange
        case .ready, .consumed: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var store: MobileHistoryStore

    var body: some View {
        List {
            ForEach(store.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.text)
                        .textSelection(.enabled)
                    Text(entry.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("Copy") { UIPasteboard.general.string = entry.text }
                }
            }
            .onDelete { reversedOffsets in
                let count = store.entries.count
                let original = IndexSet(reversedOffsets.map { count - 1 - $0 })
                store.delete(at: original)
            }
        }
        .overlay {
            if store.entries.isEmpty {
                ContentUnavailableView("No Dictations Yet", systemImage: "waveform")
            }
        }
        .navigationTitle("History")
    }
}

private struct DictionaryListView: View {
    @ObservedObject var store: DictionaryStore
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(store.entries) { entry in
                VStack(alignment: .leading) {
                    Text(entry.replacement).font(.headline)
                    Text("Say “\(entry.spoken)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { store.delete(id: entry.id) }
                }
            }
        }
        .overlay {
            if store.entries.isEmpty {
                ContentUnavailableView("No Dictionary Entries", systemImage: "character.book.closed")
            }
        }
        .navigationTitle("Dictionary")
        .toolbar {
            Button("Add", systemImage: "plus") { showingAdd = true }
        }
        .sheet(isPresented: $showingAdd) {
            AddDictionaryEntryView(store: store)
        }
    }
}

private struct AddDictionaryEntryView: View {
    @ObservedObject var store: DictionaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var spoken = ""
    @State private var replacement = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("What Vox hears", text: $spoken)
                TextField("What Vox should write", text: $replacement)
            }
            .navigationTitle("Add Word")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.add(DictionaryEntry(
                            id: UUID().uuidString,
                            spoken: spoken,
                            replacement: replacement,
                            mode: .prose
                        ))
                        dismiss()
                    }
                    .disabled(spoken.trimmingCharacters(in: .whitespaces).isEmpty || replacement.isEmpty)
                }
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: MobileSettings

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $settings.apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save API Key") { settings.saveAPIKey() }
                if let message = settings.saveMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Dictation") {
                Toggle("Smart Cleanup", isOn: $settings.smartCleanupEnabled)
                Text("Say “verbatim” or “literal” first to bypass cleanup for one dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Audio is deleted after transcription or cancellation. Transcripts and dictionary entries remain only on this iPhone for this MVP.")
            }
        }
        .navigationTitle("Settings")
    }
}
