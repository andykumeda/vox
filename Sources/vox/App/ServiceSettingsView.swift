import SwiftUI

/// Explicit routing and advanced service controls; credentials stay in Keychain.
struct ServiceSettingsView: View {
    @AppStorage("cleanupProvider") private var cleanupProvider = "followDictation"
    @AppStorage("summaryProvider") private var summaryProvider = "followDictation"
    @State private var overrides: [ServiceConfiguration.Key: String] = Dictionary(
        uniqueKeysWithValues: ServiceConfiguration.Key.allCases.filter { ![.dictationProvider, .cleanupProvider, .summaryProvider, .meetingProvider].contains($0) }.map {
            ($0, UserDefaults.standard.string(forKey: $0.settingsName) ?? "")
        }
    )
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text providers").font(.headline)
            Text(routingStatus).font(.caption).foregroundStyle(.secondary)
            providerPicker("Smart Cleanup", selection: $cleanupProvider)
            providerPicker("Meeting summaries", selection: $summaryProvider)
            Text("Follow dictation provider uses its API key for text requests too. Meeting audio uses the separate meeting transcription provider below. Vox never falls back to a different provider. VOX_DICTATION_PROVIDER, VOX_CLEANUP_PROVIDER, VOX_SUMMARY_PROVIDER, and VOX_MEETING_PROVIDER override the pickers when set.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("API and service configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blank fields use the bundled defaults shown as placeholders. Environment variables override saved fields. Endpoints must use HTTPS and the selected provider’s response format. Restart Vox after changing meetingChunkDuration or meetingRetryDelays.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ServiceConfiguration.Key.allCases.filter { ![.dictationProvider, .cleanupProvider, .summaryProvider, .meetingProvider].contains($0) }, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.rawValue).font(.caption).fontWeight(.medium)
                            TextField(ServiceConfiguration.defaultValue(key), text: Binding(
                                get: { overrides[key] ?? "" },
                                set: { overrides[key] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Text(key.environmentName).font(.caption2).foregroundStyle(.secondary)
                            if let effective = ProcessInfo.processInfo.environment[key.environmentName] {
                                Text("Environment override active: \(effective)").font(.caption2)
                            }
                        }
                    }
                    Button("Save service configuration") {
                        do {
                            try ServiceConfiguration.save(overrides.mapValues {
                                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            })
                            result = "Service configuration saved. Applies to new requests."
                        } catch { result = error.localizedDescription }
                    }
                    if let result { Text(result).font(.caption) }
                }
                .padding(.top, 8)
            }
        }
    }

    private var routingStatus: String {
        do {
            let dictation = try AppSettings.resolvedDictationProvider()
            let cleanup = try AppSettings.resolvedTextProvider(.cleanupProvider)
            let summary = try AppSettings.resolvedTextProvider(.summaryProvider)
            let meeting = try AppSettings.resolvedMeetingProvider()
            return "Effective: dictation \(dictation.displayName), cleanup \(cleanup.displayName), summaries \(summary.displayName), meeting audio \(meeting.displayName)."
        } catch { return error.localizedDescription }
    }

    private func providerPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Follow dictation provider").tag("followDictation")
            ForEach(DictationProvider.allCases, id: \.self) { provider in
                Text(provider.displayName).tag(provider.rawValue)
            }
        }
    }
}
