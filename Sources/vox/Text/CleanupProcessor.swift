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
        guard enabled else { return input }
        return applyTriggers(input)
    }

    // MARK: - Triggers

    /// Runs the three trigger phrases over the input. Pure synchronous function.
    func applyTriggers(_ input: String) -> String {
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
}
