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

    /// Spoken currency words → symbol placed before the digits ("five dollars" → "$5").
    private static let currencyPrefix: [String: String] = [
        "dollar": "$", "dollars": "$",
        "buck": "$", "bucks": "$",
        "euro": "€", "euros": "€",
    ]

    /// Spoken currency words → symbol placed after the digits ("fifty cents" → "50¢").
    private static let currencySuffix: [String: String] = [
        "cent": "¢", "cents": "¢",
    ]

    /// Spoken data-size units → standard abbreviation ("one terabyte" → "1 TB").
    private static let dataUnits: [String: String] = [
        "kilobyte": "KB", "kilobytes": "KB",
        "megabyte": "MB", "megabytes": "MB",
        "gigabyte": "GB", "gigabytes": "GB",
        "terabyte": "TB", "terabytes": "TB",
        "petabyte": "PB", "petabytes": "PB",
    ]

    /// Units that force digit form for small numbers but keep the spoken unit word
    /// ("three hours" → "3 hours").
    private static let forceDigitUnits: Set<String> = [
        "hour", "hours", "minute", "minutes", "second", "seconds",
        "am", "pm",
        "percent", "percentage",
        "degree", "degrees",
        "mile", "miles", "kilometer", "kilometers", "kilometre", "kilometres",
        "meter", "meters", "metre", "metres",
        "centimeter", "centimeters", "centimetre", "centimetres",
        "millimeter", "millimeters", "millimetre", "millimetres",
        "inch", "inches", "foot", "feet",
        "kilogram", "kilograms", "gram", "grams",
        "pound", "pounds", "ounce", "ounces",
        "liter", "liters", "litre", "litres",
        "gallon", "gallons",
        "watt", "watts", "kilowatt", "kilowatts",
        "volt", "volts",
    ]

    private enum FollowingUnit {
        /// Replace number + unit with prefix+digits ("$5").
        case currencyPrefix(String)
        /// Replace number + unit with digits+suffix ("50¢").
        case currencySuffix(String)
        /// Replace number + unit with digits + abbreviation ("1 TB").
        case abbreviated(String)
        /// Force digits; leave the spoken unit in place ("3 hours").
        case forceDigit
        /// Force digits and consume a multi-token unit like "o'clock" / "a.m.".
        case forceDigitConsuming(tokenCount: Int)
        /// "five percent" → "5%".
        case percent
    }

    public init() {}

    /// Convert spelled-out numbers to digits.
    /// - Parameter aggressive: when true, convert *every* number word including
    ///   bare singles ("three" → "3"). When false (prose default), keep bare
    ///   singles < 10 as words unless a currency/time/measurement unit follows.
    public func normalize(_ input: String, aggressive: Bool = false) -> String {
        let contextualized = normalizeContextualNumbers(
            normalizeLetterSpelledNumbers(input)
        )
        let tokens = tokenize(contextualized)
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
                let following = Array(tokens[i..<tokens.count])
                let result = collapseRun(
                    tokens: Array(tokens[start..<i]),
                    following: following,
                    aggressive: aggressive
                )
                output.append(contentsOf: result.parts)
                i += result.consumedFollowing
                runStart = nil
                lastNumberWordInRun = nil
                continue
            }
            output.append(tok.original)
            i += 1
        }
        if let start = runStart {
            let result = collapseRun(
                tokens: Array(tokens[start..<tokens.count]),
                following: [],
                aggressive: aggressive
            )
            output.append(contentsOf: result.parts)
        }
        return output.joined()
    }

    /// STT sometimes spells a number as individual letters separated by
    /// hyphens ("F-I-F-T-Y feet"). Join only sequences that are themselves
    /// known number words, then let the normal parser handle their context.
    private func normalizeLetterSpelledNumbers(_ input: String) -> String {
        var result = input
        let numberWords = Array(Self.units.keys) + Array(Self.tens.keys)
        for word in numberWords {
            let letters = word.map(String.init).joined(separator: "-")
            result = result.replacingOccurrences(
                of: "(?i)\\b\(letters)\\b",
                with: word,
                options: .regularExpression
            )
        }
        return result
    }

    /// Options are labels/identifiers, so even small number words should be
    /// rendered as digits ("option one" → "option 1").
    private func normalizeContextualNumbers(_ input: String) -> String {
        var result = input
        for (word, value) in Self.units where value <= 9 {
            result = result.replacingOccurrences(
                of: "(?i)\\b(option\\s+)\(word)\\b",
                with: "$1\(value)",
                options: .regularExpression
            )
        }
        return result
    }

    private func isNumberWord(_ w: String) -> Bool {
        Self.units[w] != nil || Self.tens[w] != nil || Self.scales[w] != nil
    }

    private func collapseRun(
        tokens: [Token],
        following: [Token],
        aggressive: Bool
    ) -> (parts: [String], consumedFollowing: Int) {
        // Strip connectors/whitespace; keep only number words.
        let words = tokens.compactMap { t -> String? in
            let w = t.word.lowercased()
            return isNumberWord(w) ? w : nil
        }
        guard let n = parseWords(words) else {
            // Not a parseable number run — keep originals.
            return (tokens.map { $0.original }, 0)
        }

        let unit = peekUnit(following)
        let leading = tokens.first.map { String($0.leadingWhitespace) } ?? ""

        // Currency / abbreviated measurements / percent rewrite the unit too.
        if let unit {
            switch unit {
            case .currencyPrefix(let symbol):
                return ([leading + symbol + String(n)], unitTokenCount(following, matching: unit))
            case .currencySuffix(let symbol):
                return ([leading + String(n) + symbol], unitTokenCount(following, matching: unit))
            case .abbreviated(let abbr):
                return ([leading + String(n) + " " + abbr], unitTokenCount(following, matching: unit))
            case .percent:
                return ([leading + String(n) + "%"], unitTokenCount(following, matching: unit))
            case .forceDigit, .forceDigitConsuming:
                let consumed = unitTokenCount(following, matching: unit)
                if case .forceDigitConsuming = unit {
                    // Preserve the multi-token unit spelling ("o'clock", "a.m.").
                    let unitParts = following.prefix(consumed).map { $0.original }
                    return ([leading + String(n)] + Array(unitParts), consumed)
                }
                return ([leading + String(n)], 0)
            }
        }

        // In prose, single spelled-out word < 10 reads better as a word ("I have
        // three apples"). In command/terminal mode the user almost always means
        // a literal digit ("head -n three" → "head -n 3"), so aggressive=true
        // converts bare singles too.
        if !aggressive && words.count == 1 && n < 10 {
            return (tokens.map { $0.original }, 0)
        }
        let trailing = tokens.last.map { String($0.trailingWhitespace) } ?? ""
        return ([leading + String(n) + trailing], 0)
    }

    private func peekUnit(_ following: [Token]) -> FollowingUnit? {
        guard let first = following.first(where: { !$0.word.isEmpty }) else { return nil }
        let w = first.word.lowercased()

        if let symbol = Self.currencyPrefix[w] { return .currencyPrefix(symbol) }
        if let symbol = Self.currencySuffix[w] { return .currencySuffix(symbol) }
        if let abbr = Self.dataUnits[w] { return .abbreviated(abbr) }
        if w == "percent" || w == "percentage" { return .percent }
        if Self.forceDigitUnits.contains(w) { return .forceDigit }

        // "o'clock" tokenizes as o + ' + clock
        if w == "o", matchesOClock(following) {
            return .forceDigitConsuming(tokenCount: oClockTokenCount(following))
        }
        // "a.m." / "p.m." tokenizes as letter + . + letter + optional .
        if (w == "a" || w == "p"), matchesMeridiem(following) {
            return .forceDigitConsuming(tokenCount: meridiemTokenCount(following))
        }
        return nil
    }

    private func unitTokenCount(_ following: [Token], matching unit: FollowingUnit) -> Int {
        switch unit {
        case .forceDigit:
            return 0
        case .forceDigitConsuming(let count):
            return count
        case .currencyPrefix, .currencySuffix, .abbreviated, .percent:
            // Skip leading empty/whitespace-only tokens, then the unit word.
            var count = 0
            for t in following {
                count += 1
                if !t.word.isEmpty { break }
            }
            return count
        }
    }

    private func matchesOClock(_ following: [Token]) -> Bool {
        let words = following.map { $0.word.lowercased() }.filter { !$0.isEmpty }
        guard words.count >= 3 else { return false }
        return words[0] == "o" && words[1] == "'" && words[2] == "clock"
    }

    private func oClockTokenCount(_ following: [Token]) -> Int {
        var seen = 0
        var count = 0
        for t in following {
            count += 1
            if t.word.isEmpty { continue }
            seen += 1
            if seen == 3 { return count }
        }
        return count
    }

    private func matchesMeridiem(_ following: [Token]) -> Bool {
        let words = following.map { $0.word.lowercased() }.filter { !$0.isEmpty }
        // a . m  or  a . m .
        guard words.count >= 3 else { return false }
        let letter = words[0]
        guard letter == "a" || letter == "p" else { return false }
        guard words[1] == "." else { return false }
        return words[2] == "m"
    }

    private func meridiemTokenCount(_ following: [Token]) -> Int {
        // Consume a/p + . + m, plus an optional trailing "." ("a.m.").
        var seen = 0
        var count = 0
        for t in following {
            count += 1
            if t.word.isEmpty { continue }
            seen += 1
            if seen < 3 { continue }
            if seen == 3 {
                // Peek whether a trailing "." follows; if so, keep looping once more.
                let rest = following.dropFirst(count)
                if let next = rest.first(where: { !$0.word.isEmpty }), next.word == "." {
                    continue
                }
                return count
            }
            return count
        }
        return count
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
