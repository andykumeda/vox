import CoreGraphics
import Foundation

enum MeetingGateError: Error, Equatable, Sendable {
    case modeDisabled
    case consentRequired
    case backendUnavailable(reason: String)
    case missingAPIKey
    case permissionDenied(MeetingPermission)
    case captureFailed(String)
    case chunkingFailed(String)

    enum MeetingPermission: String, Equatable, Sendable {
        case screenRecording
    }

    var userMessage: String {
        switch self {
        case .modeDisabled:
            return "Meeting Mode is off. Enable it in Settings → Meeting Transcription (Beta)."
        case .consentRequired:
            return "Meeting capture requires a one-time acknowledgment. Open Settings → Meeting Transcription (Beta)."
        case .backendUnavailable(let reason):
            return "Meeting capture is unavailable: \(reason)"
        case .missingAPIKey:
            return "OpenAI API key is required. Add one in Settings."
        case .permissionDenied(let perm):
            switch perm {
            case .screenRecording:
                return "Screen Recording permission required. Open System Settings → Privacy & Security → Screen Recording and enable Vox."
            }
        case .captureFailed(let msg):
            return "Meeting capture failed: \(msg)"
        case .chunkingFailed(let msg):
            return "Could not split audio for transcription: \(msg)"
        }
    }
}

struct MeetingBackendStatus: Equatable, Sendable {
    let available: Bool
    let detail: String

    static let pendingImplementation = MeetingBackendStatus(
        available: false,
        detail: "System-audio capture backend lands in M2."
    )
}

/// Reads settings, runs a backend availability check, and returns either a green light or
/// an actionable gate error. Pure function — no side effects, safe to call from UI threads
/// before showing menu state, and safe to call again right before starting a session.
enum MeetingPreflight {
    /// Backend availability hook injected for tests; production resolves to the live status check.
    static var backendStatusProvider: @Sendable (MeetingCaptureBackend) -> MeetingBackendStatus = { backend in
        liveStatus(for: backend)
    }

    static func liveStatus(for backend: MeetingCaptureBackend) -> MeetingBackendStatus {
        switch backend {
        case .systemAudio:
            if CGPreflightScreenCaptureAccess() {
                return MeetingBackendStatus(
                    available: true,
                    detail: "ScreenCaptureKit ready."
                )
            } else {
                return MeetingBackendStatus(
                    available: false,
                    detail: "Screen Recording permission not granted."
                )
            }
        }
    }

    static func gate(
        modeEnabled: Bool = AppSettings.meetingModeEnabled,
        consentAcknowledged: Bool = AppSettings.meetingConsentAcknowledged,
        backend: MeetingCaptureBackend = AppSettings.meetingCaptureBackend,
        hasAPIKey: Bool
    ) -> Result<Void, MeetingGateError> {
        guard modeEnabled else { return .failure(.modeDisabled) }
        guard consentAcknowledged else { return .failure(.consentRequired) }
        guard hasAPIKey else { return .failure(.missingAPIKey) }
        let status = backendStatusProvider(backend)
        guard status.available else {
            return .failure(.backendUnavailable(reason: status.detail))
        }
        return .success(())
    }
}
