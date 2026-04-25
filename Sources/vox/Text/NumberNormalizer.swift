import Foundation

public struct NumberNormalizer {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let scales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
    ]

    public init() {}

    /// Convert spelled-out numbers to digits.
    /// - Parameter aggressive: when true, convert *every* number word including
    ///   bare singles ("three" → "3"). When false (prose default), keep bare
    ///   singles < 10 as words because "I have three apples" reads better.
    public func normalize(_ input: String, aggressive: Bool = false) -> String {
        let tokens = tokenize(input)
        var output: [String] = []
        var runStart: Int? = nil
        var lastNumberWordInRun: String? = nil

        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            let lower = tok.word.lowercased()
            if isNumberWord(lower) {
                if runStart == nil { runStart = i }
                lastNumberWordInRun = lower
                i += 1
                continue
            }
            // Connectors between number words. "-" always OK ("twenty-three").
            // "and" only OK after a scale word ("two hundred and fifty"); not
            // after a unit/teen/ten ("two and three apples" must stay split).
            if runStart != nil, i + 1 < tokens.count, isNumberWord(tokens[i + 1].word.lowercased()) {
                let isHyphen = tok.word == "-"
                let isScaleAnd = lower == "and" && (lastNumberWordInRun.flatMap { Self.scales[$0] } != nil)
                if isHyphen || isScaleAnd {
                    i += 1
                    continue
                }
            }
            if let start = runStart {
                output.append(contentsOf: collapseRun(tokens: Array(tokens[start..<i]), aggressive: aggressive))
                runStart = nil
                lastNumberWordInRun = nil
            }
            output.append(tok.original)
            i += 1
        }
        if let start = runStart {
            output.append(contentsOf: collapseRun(tokens: Array(tokens[start..<tokens.count]), aggressive: aggressive))
        }
        return output.joined()
    }

    private func isNumberWord(_ w: String) -> Bool {
        Self.units[w] != nil || Self.tens[w] != nil || Self.scales[w] != nil
    }

    private func collapseRun(tokens: [Token], aggressive: Bool) -> [String] {
        // Strip connectors/whitespace; keep only number words.
        let words = tokens.compactMap { t -> String? in
            let w = t.word.lowercased()
            return isNumberWord(w) ? w : nil
        }
        guard let n = parseWords(words) else {
            // Not a parseable number run — keep originals.
            return tokens.map { $0.original }
        }
        // In prose, single spelled-out word < 10 reads better as a word ("I have
        // three apples"). In command/terminal mode the user almost always means
        // a literal digit ("head -n three" → "head -n 3"), so aggressive=true
        // converts bare singles too.
        if !aggressive && words.count == 1 && n < 10 {
            return tokens.map { $0.original }
        }
        // Preserve leading whitespace of first token, trailing of last token.
        let leading = tokens.first.map { String($0.leadingWhitespace) } ?? ""
        let trailing = tokens.last.map { String($0.trailingWhitespace) } ?? ""
        return [leading + String(n) + trailing]
    }

    private func parseWords(_ words: [String]) -> Int? {
        guard !words.isEmpty else { return nil }
        var total = 0
        var current = 0
        for w in words {
            if let v = Self.units[w] {
                current += v
            } else if let v = Self.tens[w] {
                current += v
            } else if let scale = Self.scales[w] {
                if current == 0 { current = 1 }
                if scale == 100 {
                    current *= 100
                } else {
                    total += current * scale
                    current = 0
                }
            } else {
                return nil
            }
        }
        return total + current
    }

    // MARK: - Tokenization

    private struct Token {
        let original: String          // exact substring including surrounding whitespace
        let word: String              // the word itself (letters/hyphens)
        let leadingWhitespace: Substring
        let trailingWhitespace: Substring
    }

    private func tokenize(_ input: String) -> [Token] {
        // Split so whitespace is preserved with adjacent word. Also split on hyphen inside words
        // like "twenty-three" so each number word is its own token, while keeping the hyphen as a connector token.
        var tokens: [Token] = []
        let scalars = Array(input)
        var idx = 0
        while idx < scalars.count {
            // consume leading whitespace
            let leadingStart = idx
            while idx < scalars.count, scalars[idx].isWhitespace { idx += 1 }
            let leading = String(scalars[leadingStart..<idx])

            if idx >= scalars.count {
                if !leading.isEmpty {
                    tokens.append(Token(original: leading, word: "", leadingWhitespace: Substring(leading), trailingWhitespace: ""))
                }
                break
            }

            // consume word or single non-word char
            let wordStart = idx
            if scalars[idx].isLetter {
                while idx < scalars.count, scalars[idx].isLetter { idx += 1 }
                let word = String(scalars[wordStart..<idx])
                tokens.append(Token(
                    original: leading + word,
                    word: word,
                    leadingWhitespace: Substring(leading),
                    trailingWhitespace: ""
                ))
            } else {
                let ch = String(scalars[idx])
                idx += 1
                tokens.append(Token(
                    original: leading + ch,
                    word: ch,
                    leadingWhitespace: Substring(leading),
                    trailingWhitespace: ""
                ))
            }
        }
        return tokens
    }
}
