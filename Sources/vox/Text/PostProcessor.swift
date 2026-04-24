import Foundation

public struct PostProcessor {
    public let mode: TranscriptionMode
    private let numberNormalizer = NumberNormalizer()

    public init(mode: TranscriptionMode) {
        self.mode = mode
    }

    public func apply(_ raw: String) -> String {
        var s = raw

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = collapseInternalWhitespace(s)
        s = numberNormalizer.normalize(s)
        s = ensureSpaceAfterSentenceEnd(s)

        switch mode {
        case .prose:
            s = capitalizeSentenceStarts(s)
            s = ensureTrailingTerminator(s)
            s = s + " "
        case .command:
            s = lowercaseFirstLetter(s)
            s = stripTrailingSentencePunctuation(s)
        }

        return s
    }

    // Prose mode: guarantee output ends with . ! or ? so the next dictation starts a new sentence.
    private func ensureTrailingTerminator(_ input: String) -> String {
        guard let last = input.last else { return input }
        if last == "." || last == "!" || last == "?" { return input }
        return input + "."
    }

    // Collapse runs of internal whitespace to a single space. Keep newlines intact.
    private func collapseInternalWhitespace(_ input: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in input {
            if ch == " " || ch == "\t" {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    // Ensure exactly one space after . ! ? when followed by a non-whitespace character.
    private func ensureSpaceAfterSentenceEnd(_ input: String) -> String {
        var out = ""
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            out.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if let n = next, !n.isWhitespace {
                    out.append(" ")
                }
            }
            i += 1
        }
        return out
    }

    private func capitalizeSentenceStarts(_ input: String) -> String {
        var chars = Array(input)
        var capitalizeNext = true
        for i in chars.indices {
            let ch = chars[i]
            if ch.isLetter {
                if capitalizeNext {
                    chars[i] = Character(ch.uppercased())
                    capitalizeNext = false
                }
            } else if ch == "." || ch == "!" || ch == "?" {
                capitalizeNext = true
            } else if !ch.isWhitespace {
                capitalizeNext = false
            }
        }
        return String(chars)
    }

    private func lowercaseFirstLetter(_ input: String) -> String {
        guard let first = input.first, first.isLetter, first.isUppercase else { return input }
        return first.lowercased() + input.dropFirst()
    }

    private func stripTrailingSentencePunctuation(_ input: String) -> String {
        var s = input
        while let last = s.last, last == "." || last == "!" || last == "?" || last.isWhitespace {
            s.removeLast()
        }
        return s
    }
}
