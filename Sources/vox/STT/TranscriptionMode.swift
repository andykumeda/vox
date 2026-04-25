import Foundation

public enum TranscriptionMode: String, Sendable {
    case prose
    case command

    public var whisperPrompt: String {
        switch self {
        case .prose:
            return "Standard English prose with natural punctuation. Use commas to join related clauses; prefer flowing sentences over short fragments. Use digits for dates, years, phone numbers, addresses, prices, times, measurements, and quantities of ten or more; spell out small whole numbers in ordinary prose. Preserve URLs, domains, and file names exactly (e.g., youtube.com, github.com/user/repo, README.md) without inserting spaces around the dot."
        case .command:
            return "Unix/Linux shell commands with standard spacing. Always separate the command from its flags and arguments with a single space: write 'ls -l' not 'ls-l', 'git status' not 'gitstatus', 'wget https://example.com' not 'wgethttps'. Flags begin with '-' or '--' preceded by a space. Common tokens: sudo, ls, cd, cat, grep, awk, sed, chmod, ssh, scp, git, docker, kubectl, npm, brew, wget, curl. Do not capitalize. Do not add trailing punctuation."
        }
    }
}
