import Foundation

/// An immutable per-language index owns only explicit dictionary forms and fixed expression
/// patterns. It never guesses spelling from suffixes. One app-owned lexicon service caches it;
/// tests can supply small resources without model or OS dependencies.
nonisolated struct LearningUnitRecognizer: Sendable {
    private let entries: [LearningLexiconEntry]
    private let aliases: [String: [Int]]
    private let patterns: [String: [(entry: Int, tokens: [String])]]

    init(entries: [LearningLexiconEntry]) {
        self.entries = entries
        var aliases: [String: [Int]] = [:]
        var patterns: [(Int, [String])] = []
        for (index, entry) in entries.enumerated() {
            for form in [entry.headword] + entry.forms {
                let key = LearningUnitPolicy.key(form)
                // Extracted tables sometimes include the verb's isolated conjugation instead
                // of the whole expression ("go" for "go jump in the lake"). Such a form is
                // not evidence that an ordinary word means the complete phrase.
                if entry.headword.contains(where: \.isWhitespace), key.split(separator: " ").count < 2 { continue }
                if ["zh", "ja", "ko"].contains(entry.language), key.count < 2 { continue }
                if !key.isEmpty { aliases[key, default: []].append(index) }
            }
            // Wiktionary writes these possessive placeholders as part of a pattern's headword.
            // Only that explicit form licenses a slot; an ordinary pronoun is never inferred.
            for form in [entry.headword] + entry.forms {
                let tokens = LearningUnitPolicy.key(form).split(separator: " ").map(String.init)
                let slots = Set(["one's", "someone's", "someone", "somebody", "something"])
                if tokens.contains(where: { slots.contains($0) }), tokens.filter({ !slots.contains($0) }).count >= 2 {
                    patterns.append((index, tokens))
                }
            }
        }
        self.aliases = aliases
        let slots = Set(["one's", "someone's", "someone", "somebody", "something"])
        self.patterns = Dictionary(grouping: patterns.sorted { $0.1.count > $1.1.count }) {
            slots.contains($0.1[0]) ? "*" : $0.1[0]
        }
    }

    func lookup(_ query: String) -> [LearningLexiconEntry] {
        let ids = Set(aliases[LearningUnitPolicy.key(query)] ?? [])
        return ids.sorted().map { entries[$0] }
    }

    func recognize(_ text: String, language: LearningLanguage) -> [LearningUnit] {
        let words = LearningUnitPolicy.words(in: text, language: language)
        let value = text as NSString
        var units: [LearningUnit] = []
        var index = 0
        while index < words.count {
            var match: (end: Int, entry: LearningLexiconEntry)?
            // Prefer a longer explicit expression, keeping punctuation/newlines from becoming
            // invented phrase boundaries. A fixed input budget bounds the scan independently.
            for end in index..<min(words.count, index + 12) {
                let range = NSRange(location: words[index].range.location,
                    length: NSMaxRange(words[end].range) - words[index].range.location)
                let quote = value.substring(with: range)
                if quote.contains(where: \.isNewline) { break }
                if let entry = lookup(quote).first {
                    match = (end, entry)
                }
            }
            if let match {
                let parts = Array(words[index...match.end])
                let range = NSRange(location: parts[0].range.location,
                    length: NSMaxRange(parts.last!.range) - parts[0].range.location)
                let surface = value.substring(with: range)
                units.append(.init(id: range.location, surface: surface,
                    query: surface.split(whereSeparator: \.isWhitespace).joined(separator: " "), kind: .expression, ranges: [range], words: parts, entryID: match.entry.id))
                index = match.end + 1
                continue
            }
            if let result = pattern(at: index, words: words, value: value) {
                units.append(result.unit)
                units.append(contentsOf: result.slots.map(LearningUnit.word))
                index += result.length
                continue
            }
            units.append(.word(words[index]))
            index += 1
        }
        return units.sorted { $0.id < $1.id }
    }

    private func pattern(at index: Int, words: [LearningDictionaryWord], value: NSString)
        -> (unit: LearningUnit, slots: [LearningDictionaryWord], length: Int)? {
        let first = LearningUnitPolicy.key(words[index].text)
        for pattern in (patterns[first] ?? []) + (patterns["*"] ?? []) {
            guard index + pattern.tokens.count <= words.count else { continue }
            let parts = Array(words[index..<(index + pattern.tokens.count)])
            var fixed: [NSRange] = [], slots: [LearningDictionaryWord] = []
            var matches = true
            for (token, word) in zip(pattern.tokens, parts) {
                let key = LearningUnitPolicy.key(word.text)
                if token == "one's" || token == "someone's" {
                    let contractions = ["it's", "that's", "there's", "here's", "what's", "who's", "where's", "when's", "why's", "how's", "let's", "he's", "she's"]
                    guard !contractions.contains(key),
                          ["my", "your", "his", "her", "its", "our", "their"].contains(key) || key.hasSuffix("'s") else { matches = false; break }
                    slots.append(word)
                } else if token == "someone" || token == "somebody" {
                    guard ["me", "you", "him", "her", "us", "them", "someone", "somebody"].contains(key) || word.text.first?.isUppercase == true else { matches = false; break }
                    slots.append(word)
                } else if token == "something" {
                    // This first version accepts explicit pronominal objects only. Accepting
                    // any token would turn a repeated verb ("of goes goes") into a known pattern;
                    // richer noun-phrase slots need a separate grammatical recognizer.
                    guard ["it", "this", "that", "these", "those", "something", "anything", "everything", "nothing"].contains(key) else { matches = false; break }
                    slots.append(word)
                } else if token == key { fixed.append(word.range) }
                else { matches = false; break }
            }
            let extent = NSRange(location: parts[0].range.location,
                length: NSMaxRange(parts.last!.range) - parts[0].range.location)
            // Matching words around punctuation would invent a grammatical pattern.
            let quote = value.substring(with: extent)
            guard matches, !fixed.isEmpty, !quote.contains(where: \.isNewline),
                  quote.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "'" || $0 == "’" }) else { continue }
            var ranges: [NSRange] = []
            for range in fixed {
                if let last = ranges.last {
                    let gap = NSRange(location: NSMaxRange(last), length: range.location - NSMaxRange(last))
                    if value.substring(with: gap).allSatisfy(\.isWhitespace) {
                        ranges[ranges.count - 1].length = NSMaxRange(range) - last.location
                        continue
                    }
                }
                ranges.append(range)
            }
            let entry = entries[pattern.entry]
            return (.init(id: ranges[0].location, surface: ranges.map { value.substring(with: $0) }.joined(separator: " … "),
                query: entry.headword, kind: .pattern, ranges: ranges, words: parts, entryID: entry.id), slots, parts.count)
        }
        return nil
    }
}
