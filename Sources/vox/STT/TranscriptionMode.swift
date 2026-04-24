import Foundation

public enum TranscriptionMode: String, Sendable {
    case prose
    case command

    public var whisperPrompt: String {
        switch self {
        case .prose:
            return "Standard English prose. Use digits for all numbers. End each sentence with punctuation followed by a space."
        case .command:
            return "Unix/Linux shell commands. Preserve exact syntax including flags (-la, --verbose). Common tokens: sudo, ls, cd, cat, grep, awk, sed, chmod, ssh, scp, git, docker, kubectl, npm, brew. Do not capitalize. Do not add trailing punctuation."
        }
    }
}
