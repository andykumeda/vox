import Foundation

enum TranscriptComparison {
    static func diff(raw: String, final: String) -> String {
        guard raw != final else { return "No changes." }
        return "− Raw: \(raw)\n+ Final: \(final)"
    }
}

/// Produces a reusable voice guide locally, without embedding transcript
/// excerpts or sending retained history to an external model.
enum WritingStyleExporter {
    static func markdown(
        dictations: [DictationEntry],
        meetings: [TranscriptSession]
    ) -> String {
        let prose = dictations.filter {
            $0.mode.caseInsensitiveCompare("command") != .orderedSame
        }
        let commandCount = dictations.count - prose.count
        // Remote and legacy unattributed meeting speech may belong to another
        // participant. Only explicit local-mic segments are user-authored evidence.
        let allMeetingSegments = meetings.flatMap(\.segments)
        let localMeetingSegments = allMeetingSegments.filter { $0.source == .local }
        let excludedMeetingSegments = allMeetingSegments.count - localMeetingSegments.count
        let texts = prose.map(\.text) + localMeetingSegments.map(\.text)
        let corpus = StyleCorpus(texts: texts)
        let cleanup = CleanupSignals(dictations: prose)

        guard !texts.isEmpty else {
            return emptyGuide(
                commandCount: commandCount,
                excludedMeetingSegments: excludedMeetingSegments
            )
        }

        let sentenceStyle: String
        switch corpus.averageSentenceWords {
        case ..<11:
            sentenceStyle = "mostly short sentences with occasional fragments for emphasis"
        case ..<20:
            sentenceStyle = "short-to-medium sentences with a natural spoken rhythm"
        default:
            sentenceStyle = "medium-to-long sentences that accumulate context and qualifications"
        }

        let connectors = corpus.rankedWords(
            ["so", "but", "because", "then", "after", "once", "although", "and"],
            limit: 5
        )
        let qualifiers = corpus.rankedPhrases(
            ["I think", "maybe", "I guess", "I'm not sure", "I’m not sure",
             "actually", "probably", "in hindsight", "or rather", "come to think of it"],
            limit: 5
        )
        let connectorObservation = connectors.isEmpty
            ? "No single transition dominates the current sample."
            : "Recurring transitions include \(naturalList(connectors))."
        let qualifierObservation = qualifiers.isEmpty
            ? "The current sample has limited explicit uncertainty markers; do not manufacture them."
            : "Observed qualification markers include \(naturalList(qualifiers)); preserve them when they express real uncertainty or revision."
        let contractionGuidance = corpus.contractionCount > 0
            ? "Use contractions naturally. The retained corpus uses them as part of its conversational cadence."
            : "Do not force contractions; the retained corpus provides little evidence for them."
        let questionGuidance = corpus.questionCount > 0
            ? "Questions should sound genuinely curious or practical, not rhetorical or sales-oriented."
            : "Use questions only when the purpose genuinely calls for one."
        let exclamationGuidance = corpus.exclamationCount > 0
            ? "Exclamation points appear in the corpus, but should remain tied to real emphasis or reaction."
            : "Do not add exclamation points merely to make the writing sound enthusiastic."
        let sampleAssessment = sampleAssessment(wordCount: corpus.wordCount, unitCount: texts.count)
        let period = evidencePeriod(dictations: prose, meetings: meetings)

        return """
        ---
        name: personal-writing-voice
        description: Use when drafting, rewriting, editing, or polishing text in the user's personal, professional, spoken, or reflective voice.
        ---

        # Personal Writing Voice

        Use this skill when composing or editing in my voice. Do not use it for unrelated technical answers or generic writing unless my voice is requested. This skill was generated locally by Vox; it contains aggregate observations and instructions, not transcript excerpts.

        ## Before composing

        - Identify the audience, medium, purpose, and desired tone.
        - Choose the professional, casual, spoken, or reflective register.
        - Preserve real uncertainty, personal phrasing, and concrete detail.
        - Lead with the point for professional writing.
        - Preserve chronology and useful side observations for reflective writing.
        - Never make the writing sound corporate, therapeutic, or artificially polished.

        ## The core voice

        The writing should sound like a capable person talking directly to another person:

        - Clear, conversational, and human
        - Direct without becoming abrupt
        - Practical and oriented toward the point or next action
        - Specific enough to be useful without sounding inflated
        - Comfortable preserving uncertainty when it is real
        - Technically exact when names, numbers, terminology, files, or commands matter
        - Polished enough to read easily, but never corporate for its own sake

        The current corpus points to \(sentenceStyle). Keep that cadence when it helps the thought remain recognizable.

        ## The deeper voice underneath the registers

        Treat these as working characteristics, not permission to invent personality:

        - **Observational:** retain concrete facts, constraints, sequence, and the detail that explains why something matters.
        - **Narrative:** preserve the order in which something happened unless the medium needs a shorter answer.
        - **Self-correcting:** keep genuine revisions or qualifications when they change the meaning; remove only abandoned wording.
        - **Analytical but personal:** explain the distinction or reasoning while keeping ownership in first-person statements.
        - **Candid:** do not replace uncertainty, limitations, mixed reactions, or incomplete information with false confidence.
        - **Associative but controlled:** a useful side detail is fine when it supports the point; return to the main thread.

        \(connectorObservation)
        \(qualifierObservation)

        ## Choose the register before writing

        ### Professional and practical

        Use for colleagues, recruiters, vendors, support teams, applications, and business email.

        - Lead with the point, decision, limitation, question, or status.
        - Give the concrete context the reader needs, but do not oversell.
        - Be candid about fit, constraints, and uncertainty.
        - Explain technical distinctions in plain language.
        - End with a clear next step or a simple courteous close.

        Illustrative shape—not a transcript excerpt:

        > Hi [Name],
        >
        > Thanks for reaching out. I'm interested, although I have one question about [specific issue]. Based on the description, it's difficult to tell [specific uncertainty].
        >
        > If that aligns with what you need, I'd be happy to talk. Thanks,
        > [Name]

        ### Casual and expressive

        Use for friends, family, and close collaborators.

        - Start with the real reaction rather than a formal introduction.
        - Allow contractions, fragments, shorthand, and light irreverence when the relationship supports them.
        - Use a specific image, comparison, or practical detail instead of generic enthusiasm.
        - Let humor or emojis intensify a real reaction; do not add them as decoration.
        - Keep annoyance, surprise, affection, excitement, or skepticism visible without becoming theatrical.

        ### Spoken and reflective

        Use for dictation, journaling, explanations, personal essays, and first drafts.

        - Preserve the natural order of observations and decisions.
        - Keep useful chains of observation → qualification → conclusion.
        - Allow “so,” “but,” and “because” to connect clauses when each clause adds information.
        - Keep phrases such as “I think,” “maybe,” or “I'm not sure” only when the thought is genuinely uncertain.
        - Do not manufacture a lesson, emotional resolution, or cleaner answer than the speaker provided.

        ## Sentence style

        - Prefer \(sentenceStyle).
        - Put the important fact early in professional writing.
        - Use plain verbs such as “use,” “help,” “look at,” “work with,” and “send.”
        - Use first-person statements for decisions, limits, observations, and reactions.
        - Break long explanations into short paragraphs instead of one dense block.
        - A longer sentence is acceptable when it follows a clear spoken thought and every clause contributes meaning.
        - Do not shorten technical explanations so aggressively that the key distinction disappears.

        ## Punctuation and mechanics

        - \(contractionGuidance)
        - Use dashes or parentheses for a useful aside or qualification, not for constant interruption.
        - Ellipses may indicate hesitation or a soft landing, but use them sparingly.
        - \(questionGuidance)
        - \(exclamationGuidance)
        - Keep spelling and grammar clean enough that the reader never has to decode the message.
        - Do not add a formal sign-off unless the audience or medium requires it.

        ## Editing and transcription cleanup

        Preserve meaning before improving surface polish.

        - Keep wording, tone, sentence structure, names, numbers, technical terms, URLs, filenames, and intentional repetition.
        - Remove obvious filler, abandoned false starts, accidental duplication, and explicit self-corrections only when the intended replacement is unambiguous.
        - Do not add facts, explanations, conclusions, enthusiasm, reassurance, or professional polish that the speaker did not provide.
        - Do not turn ordinary speech into corporate, therapeutic, motivational, or marketing language.
        - Preserve a qualification if removing it would make the statement more certain than the source.
        - Prefer the smallest edit that makes the text readable and faithful.

        Corpus comparison signals:

        - \(cleanup.changedCount) of \(prose.count) eligible dictations differed between raw provider text and final delivered text.
        - The average changed dictation moved by \(format(cleanup.averageAbsoluteWordChange)) words between raw and final text.
        - \(cleanup.fillerRemovalDescription)
        - \(cleanup.correctionDescription)

        These are aggregate observations. They do not justify a change when the intended wording is ambiguous.

        ## Structure by purpose

        ### Quick reply

        1. Acknowledge the message.
        2. Answer the question or give the decision.
        3. Add one useful detail if needed.
        4. Close with the next step.

        ### Request or follow-up

        1. Say what you are checking on.
        2. Give the relevant context, date, or constraint.
        3. Ask for the specific action or status.
        4. Be courteous without apologizing for a reasonable follow-up.

        ### Technical explanation

        1. Lead with the conclusion or observed behavior.
        2. Explain the important distinction, constraint, or failure mode.
        3. Give concrete evidence, examples, or options.
        4. State the recommendation or next verification step.

        ### Personal or reflective writing

        1. Start with what happened or the immediate reaction.
        2. Preserve the sequence and useful concrete details.
        3. Include the judgment, feeling, or practical consequence.
        4. Keep later doubt or reinterpretation if it is real.
        5. Allow the thought to remain unresolved when that is honest.

        ## What to favor

        - Direct openings that reveal the purpose quickly
        - Plain language and specific context
        - Real qualifications instead of false certainty
        - Practical next steps
        - Technical precision without unnecessary jargon
        - Warmth shown through attention, usefulness, and follow-through
        - Personality that fits the relationship and medium

        ## What to avoid

        - Corporate filler and ceremonial openings
        - Inflated enthusiasm or generic motivational language
        - Long throat-clearing before the point
        - Empty intensifiers that do not change the meaning
        - Excessive hedging or apologizing
        - Artificially formal vocabulary
        - Humor, emojis, or warmth added without evidence from the situation
        - Rewriting that sounds smoother but no longer sounds like the speaker

        ## A practical composition prompt

        > Write this in my voice. Be clear, conversational, practical, and direct. Lead with the point when the writing is professional. Use plain language, natural contractions, and \(sentenceStyle). Preserve uncertainty when it is real, but do not over-hedge. Include the concrete context the reader needs and make the next step clear. Keep professional writing polished but human; keep personal writing specific and expressive. Do not add facts, certainty, enthusiasm, humor, or emotional interpretation that I did not provide. Avoid corporate filler, inflated language, generic advice, and unnecessary formality.

        For reflective or dictated material, add:

        > Preserve the natural spoken cadence and order of events. Keep concrete details, useful side observations, and honest self-corrections. Remove only obvious filler, accidental repetition, and abandoned false starts. Do not make the writing sound formal, corporate, therapeutic, or more certain than the original.

        Then specify:

        > Audience: [who will read it]
        > Medium: [email, text, message, post, journal, etc.]
        > Goal: [what the writing should accomplish]
        > Tone: [professional / friendly / playful / reflective / frustrated but controlled]

        ## Final check

        - Is the point clear in the first sentence or two where the medium calls for that?
        - Does this sound like something I would actually say aloud?
        - Is the concrete detail the reader needs still present?
        - Is the request, decision, or next step unambiguous?
        - Did the edit preserve uncertainty and qualifications accurately?
        - Did it remove filler without removing personality?
        - Did it avoid corporate polish, invented emotion, or unsupported conclusions?

        ## Evidence and scope

        This guide is based only on text attributable to the Vox user: \(prose.count) prose dictations and \(localMeetingSegments.count) explicitly local-speaker meeting segments, totaling \(corpus.wordCount) words across \(texts.count) text units\(period.map { " from \($0)" } ?? ""). \(commandCount) command-mode dictations were excluded from voice analysis. \(excludedMeetingSegments) remote or unattributed meeting segments were excluded because they may contain other people's words.

        Sample assessment: \(sampleAssessment)

        No transcript excerpts are included. Incoming or remote-speaker language is not treated as evidence of the user's voice. As a practical target, about 100 prose dictations can produce a rough first pass; roughly 500 prose dictations or 10,000–15,000 attributable words across several audiences and contexts usually produces a relatively accurate guide. More varied evidence matters as much as raw count.
        """
    }

    private static func emptyGuide(
        commandCount: Int,
        excludedMeetingSegments: Int
    ) -> String {
        """
        ---
        name: personal-writing-voice
        description: Use when drafting, rewriting, editing, or polishing text in the user's personal, professional, spoken, or reflective voice.
        ---

        # Personal Writing Voice

        This is an importable starter skill, but Vox does not yet have enough attributable prose to infer a personal writing style. Command-mode dictations and remote or unattributed meeting speakers are deliberately excluded from voice analysis.

        ## Recommended sample size

        About 100 prose dictations can produce a rough first pass. For a relatively accurate guide, aim for roughly 500 prose dictations or 10,000–15,000 attributable words across professional, casual, technical, and reflective contexts. Variety matters as much as raw count.

        ## Safe starter instruction

        > Preserve my wording, tone, level of formality, uncertainty, and technical terminology. Make the smallest correction needed for readability. Remove only obvious filler, accidental repetition, and unambiguous false starts. Do not add facts, explanations, enthusiasm, corporate language, or emotional interpretation that I did not provide.

        ## Evidence and scope

        The current history contains no attributable prose units. \(commandCount) command-mode dictations and \(excludedMeetingSegments) remote or unattributed meeting segments were excluded. No transcript excerpts are included.
        """
    }

    private static func sampleAssessment(wordCount: Int, unitCount: Int) -> String {
        if wordCount >= 15_000 || unitCount >= 500 {
            return "The corpus is large enough for a relatively stable guide, assuming it spans several audiences and contexts."
        }
        if wordCount >= 3_000 || unitCount >= 100 {
            return "The corpus supports a useful first pass, but more varied professional, casual, technical, and reflective samples should improve it."
        }
        return "The corpus is still small. Treat inferred traits as provisional and export again after collecting at least 100 prose dictations; 500 dictations or 10,000–15,000 attributable words is the stronger target."
    }

    private static func evidencePeriod(
        dictations: [DictationEntry],
        meetings: [TranscriptSession]
    ) -> String? {
        let dates = dictations.map(\.timestamp) + meetings.compactMap { meeting in
            meeting.segments.contains(where: { $0.source == .local }) ? meeting.startedAt : nil
        }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy"
        if Calendar(identifier: .gregorian).isDate(first, inSameDayAs: last) {
            return formatter.string(from: first)
        }
        return "\(formatter.string(from: first)) through \(formatter.string(from: last))"
    }

    fileprivate static func naturalList(_ values: [String]) -> String {
        switch values.count {
        case 0: return ""
        case 1: return "“\(values[0])”"
        case 2: return "“\(values[0])” and “\(values[1])”"
        default:
            return values.dropLast().map { "“\($0)”" }.joined(separator: ", ")
                + ", and “\(values.last!)”"
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct StyleCorpus {
    let words: [String]
    let lowercasedText: String
    let sentenceCount: Int
    let contractionCount: Int
    let questionCount: Int
    let exclamationCount: Int

    init(texts: [String]) {
        lowercasedText = texts.joined(separator: "\n").lowercased()
        words = lowercasedText.split { !$0.isLetter && $0 != "'" && $0 != "’" }
            .map(String.init)
        sentenceCount = max(1, texts.reduce(0) { count, text in
            count + max(1, text.filter { ".!?".contains($0) }.count)
        })
        contractionCount = words.filter { $0.contains("'") || $0.contains("’") }.count
        questionCount = texts.reduce(0) { $0 + $1.filter { $0 == "?" }.count }
        exclamationCount = texts.reduce(0) { $0 + $1.filter { $0 == "!" }.count }
    }

    var wordCount: Int { words.count }
    var averageSentenceWords: Double {
        wordCount == 0 ? 0 : Double(wordCount) / Double(sentenceCount)
    }

    func rankedWords(_ candidates: [String], limit: Int) -> [String] {
        let counts = Dictionary(grouping: words, by: { $0 }).mapValues(\.count)
        var ranked: [(value: String, count: Int)] = []
        for candidate in candidates {
            let count = counts[candidate.lowercased(), default: 0]
            if count > 0 { ranked.append((candidate, count)) }
        }
        ranked.sort {
            $0.count == $1.count ? $0.value < $1.value : $0.count > $1.count
        }
        return ranked.prefix(limit).map(\.value)
    }

    func rankedPhrases(_ candidates: [String], limit: Int) -> [String] {
        var ranked: [(value: String, count: Int)] = []
        for candidate in candidates {
            let count = occurrenceCount(of: candidate.lowercased())
            if count > 0 { ranked.append((candidate, count)) }
        }
        ranked.sort {
            $0.count == $1.count ? $0.value < $1.value : $0.count > $1.count
        }
        return ranked.prefix(limit).map(\.value)
    }

    private func occurrenceCount(of phrase: String) -> Int {
        var count = 0
        var remainder = lowercasedText[...]
        while let range = remainder.range(of: phrase) {
            count += 1
            remainder = remainder[range.upperBound...]
        }
        return count
    }
}

private struct CleanupSignals {
    let changedCount: Int
    let averageAbsoluteWordChange: Double
    let fillerRemovalDescription: String
    let correctionDescription: String

    init(dictations: [DictationEntry]) {
        let changed = dictations.filter { $0.rawText != $0.text }
        changedCount = changed.count
        let deltas = changed.map { abs(Self.wordCount($0.rawText) - Self.wordCount($0.text)) }
        averageAbsoluteWordChange = deltas.isEmpty ? 0
            : Double(deltas.reduce(0, +)) / Double(deltas.count)

        let raw = dictations.map(\.rawText).joined(separator: " ").lowercased()
        let final = dictations.map(\.text).joined(separator: " ").lowercased()
        let removedFillers = ["um", "uh", "er", "ah"].filter {
            Self.tokenCount($0, in: raw) > Self.tokenCount($0, in: final)
        }
        fillerRemovalDescription = removedFillers.isEmpty
            ? "No consistent filler-word removal is established by the current comparisons."
            : "Raw-to-final comparisons show recurring removal of speech fillers such as \(WritingStyleExporter.naturalList(removedFillers))."

        let corrections = ["scratch that", "or rather", "i mean"].filter {
            raw.localizedCaseInsensitiveContains($0)
        }
        correctionDescription = corrections.isEmpty
            ? "The current comparisons provide limited evidence about explicit self-correction markers."
            : "Raw text contains self-correction markers such as \(WritingStyleExporter.naturalList(corrections)); keep the replacement thought when the correction is unambiguous."
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private static func tokenCount(_ token: String, in text: String) -> Int {
        text.split { !$0.isLetter }.filter { $0 == Substring(token) }.count
    }
}
