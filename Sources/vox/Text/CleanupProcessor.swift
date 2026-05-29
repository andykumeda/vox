import Foundation

public struct CleanupProcessor {
    public typealias LLMCleanFunc = @Sendable (_ input: String) async throws -> String

    public let mode: TranscriptionMode
    public let enabled: Bool
    public let llmCleaner: LLMCleanFunc?

    public init(
        mode: TranscriptionMode,
        enabled: Bool,
        llmCleaner: LLMCleanFunc? = nil
    ) {
        self.mode = mode
        self.enabled = enabled
        self.llmCleaner = llmCleaner
    }

    public func process(_ input: String) async -> String {
        // Spoken "verbatim" or "literal" prefix on a prose dictation skips
        // both trigger expansion and the LLM cleaner — the user explicitly
        // wants the raw transcribed text. Strip the prefix word and return
        // the rest unchanged.
        if let raw = stripVerbatimPrefix(input) {
            return raw
        }
        guard enabled else { return input }
        let triggered = applyTriggers(input)

        if mode == .command { return triggered }

        let trimmed = triggered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        // Short-input bypass. gpt-4o-mini sometimes treats very short
        // dictations as chat requests ("Sure, please provide the text…")
        // because the system prompt looks like a meta-instruction in
        // isolation. Skip the LLM for snippets too short to need cleanup —
        // there's nothing meaningful to remove at this scale anyway.
        if trimmed.count < 15 {
            return triggered
        }

        // If the trigger inserted explicit paragraph or line breaks, skip the
        // LLM call. gpt-4o-mini strips placeholder tokens reliably enough to be
        // unsafe even with prompt instructions, and losing the break is worse
        // than losing the prose polish on a paragraph-broken dictation.
        if triggered.contains("\n") {
            return triggered
        }

        guard let cleaner = llmCleaner else { return triggered }

        // Placeholder swap kept for any future case where input arrives with
        // newlines that didn't come from triggers (currently unreachable because
        // triggers are the only newline source — cheap insurance).
        let paraToken = "<<VOX_PARA>>"
        let lineToken = "<<VOX_LINE>>"
        let prepared = triggered
            .replacingOccurrences(of: "\n\n", with: paraToken)
            .replacingOccurrences(of: "\n", with: lineToken)

        do {
            let cleaned = try await cleaner(prepared)
            let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            // Suspicious-small-output guard: if the LLM returns far less than we sent,
            // treat it as a malformed completion and fail open. Threshold tuned to allow
            // legitimate aggressive cleanups (e.g. "Hi." -> "Hi.") while catching empty
            // or near-empty completions for normal-length input.
            if triggered.count >= 20 && trimmedCleaned.count < 3 {
                FileHandle.standardError.write(Data("Cleanup malformed response (length \(trimmedCleaned.count) < 3 for input length \(triggered.count))\n".utf8))
                return triggered
            }
            if looksLikeAssistantMetaResponse(trimmedCleaned),
               !looksLikeAssistantMetaResponse(triggered) {
                FileHandle.standardError.write(Data("Cleanup assistant response discarded: \(trimmedCleaned)\n".utf8))
                return triggered
            }
            let restored = trimmedCleaned
                .replacingOccurrences(of: paraToken, with: "\n\n")
                .replacingOccurrences(of: lineToken, with: "\n")
            return restored
        } catch {
            FileHandle.standardError.write(Data("Cleanup error: \(error)\n".utf8))
            return triggered
        }
    }

    // MARK: - Verbatim prefix

    /// If `input` starts with "verbatim" or "literal" (case-insensitive,
    /// optional trailing punctuation), returns everything after the prefix
    /// trimmed; otherwise nil. Used as an in-band escape hatch so the user
    /// can keep a single dictation literal without changing the global
    /// Smart Cleanup setting.
    static let verbatimPrefixPattern: String = #"^\s*(verbatim|literal)\b[\s,:;.!?-]*"#

    func stripVerbatimPrefix(_ input: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: Self.verbatimPrefixPattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)),
              match.range.location == 0
        else { return nil }
        let after = match.range.location + match.range.length
        let rest = ns.substring(from: after).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest
    }

    // MARK: - Triggers

    /// Runs the three trigger phrases over the input. Pure synchronous function.
    /// Prose mode uses sentence-tokenizer anchoring (low false-positive risk).
    /// Command mode uses substring-based logic — Whisper command-mode output
    /// often lacks sentence punctuation, so the tokenizer can't split it.
    func applyTriggers(_ input: String) -> String {
        if mode == .command {
            return applyTriggersCommand(input)
        }
        return applyTriggersProse(input)
    }

    // Command mode: "scratch that" / "delete that" splits the input; keep only
    // what's after the LAST occurrence (multiple corrections collapse to the
    // final attempt). "new paragraph" / "new line" replace as substrings.
    // Trades off some false-positive risk ("scratch that itch") — acceptable
    // because command-mode dictation rarely contains those phrases naturally.
    private func applyTriggersCommand(_ input: String) -> String {
        var s = input
        if let re = try? NSRegularExpression(
            pattern: "\\b(scratch|delete) that\\b\\s*[.,!?]?\\s*",
            options: [.caseInsensitive]
        ) {
            let ns = s as NSString
            let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            if let last = matches.last {
                let afterEnd = last.range.location + last.range.length
                s = ns.substring(from: afterEnd)
            }
        }
        if let re = try? NSRegularExpression(
            pattern: "\\s*\\bnew paragraph\\b\\s*[.,!?]?\\s*",
            options: [.caseInsensitive]
        ) {
            let ns = s as NSString
            s = re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "\n\n")
        }
        if let re = try? NSRegularExpression(
            pattern: "\\s*\\bnew line\\b\\s*[.,!?]?\\s*",
            options: [.caseInsensitive]
        ) {
            let ns = s as NSString
            s = re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyTriggersProse(_ input: String) -> String {
        let sentences = splitSentences(input)
        var output: [String] = []

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if isScratchThatTrigger(trimmed) {
                if !output.isEmpty {
                    output.removeLast()
                }
                continue
            }
            if isNewParagraphTrigger(trimmed) {
                output.append("\n\n")
                continue
            }
            if isNewLineTrigger(trimmed) {
                output.append("\n")
                continue
            }
            output.append(sentence)
        }

        return joinSentences(output)
    }

    private func splitSentences(_ input: String) -> [String] {
        var sentences: [String] = []
        let range = input.startIndex..<input.endIndex
        input.enumerateSubstrings(in: range, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let s = substring, !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty && !input.isEmpty {
            sentences = [input]
        }
        return sentences
    }

    private func joinSentences(_ pieces: [String]) -> String {
        var result = ""
        for piece in pieces {
            if piece == "\n\n" || piece == "\n" {
                while result.last?.isWhitespace == true {
                    result.removeLast()
                }
                result.append(piece)
                continue
            }
            result.append(piece)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isScratchThatTrigger(_ trimmed: String) -> Bool {
        let pattern = "^(?i)(scratch|delete) that[.,!?]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func isNewParagraphTrigger(_ trimmed: String) -> Bool {
        let pattern = "^(?i)new paragraph[.,!?]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func isNewLineTrigger(_ trimmed: String) -> Bool {
        let pattern = "^(?i)new line[.,!?]?$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func looksLikeAssistantMetaResponse(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")

        guard !normalized.isEmpty else { return false }

        let patterns = [
            #"^i\s+(can't|cannot|can not|am unable to|won't|will not)\s+(assist|help|comply|provide|fulfill)\b"#,
            #"^(i'm sorry|sorry)[,!]?\s+(but\s+)?i\s+(can't|cannot|can not|am unable to|won't|will not)\b"#,
            #"^as an ai\b"#,
            #"^(sure[,.]?\s+)?please provide (the )?(text|content|snippet)\b"#,
        ]

        return patterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
