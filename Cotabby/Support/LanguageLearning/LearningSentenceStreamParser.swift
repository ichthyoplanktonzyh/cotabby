import Foundation

/// Historical NDJSON decoder retained for standalone translation/teaching experiments. The
/// product's pair-only analysis uses LearningAlignmentParser instead. Keeping the legacy wire
/// chunk here lets old evaluation scripts inspect explanations without adding them to UI models.
nonisolated struct LearningSentenceStreamParser {
    struct Chunk {
        // This request-local wire value keeps historical evaluation evidence, including its
        // explanation. Only the geometry projection enters today's shared presentation model.
        let id: Int
        let sourceRanges: [NSRange]
        let targetRanges: [NSRange]
        let explanation: String
        var meaning: LearningMeaningChunk {
            .init(id: id, sourceRanges: sourceRanges, targetRanges: targetRanges)
        }
    }
    private let source: String
    private var pending = ""
    private(set) var translation: String?
    private(set) var chunks: [Chunk] = []
    private var totalBytes = 0
    private let fixedTranslation: Bool

    init(source: String, translation: String? = nil) {
        self.source = source
        self.translation = translation
        fixedTranslation = translation != nil
    }

    mutating func append(_ delta: String) throws -> [LearningSentenceUpdate] {
        totalBytes += delta.utf8.count
        guard totalBytes <= 48_000 else {
            throw LearningFailure.message(String(localized: "Expression analysis exceeds the display limit.",
                table: "Learning", comment: "Error shown when the streamed analysis output exceeds the supported display size."))
        }
        pending += delta
        var updates: [LearningSentenceUpdate] = []
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            if let update = try decode(line) { updates.append(update) }
        }
        return updates
    }

    mutating func finish() throws -> [LearningSentenceUpdate] {
        let line = pending
        pending = ""
        return try decode(line).map { [$0] } ?? []
    }

    func result() throws -> LearningSentenceResult {
        guard let translation else {
            throw LearningFailure.message(String(localized: "The model did not return a usable translation.",
                table: "Learning", comment: "Error shown when the model response contains no valid translation."))
        }
        guard !chunks.isEmpty else {
            throw LearningFailure.message(String(localized: "The translation was generated, but chunk alignments are unavailable.",
                table: "Learning", comment: "Error shown when translation succeeded but no valid chunk alignments were returned."))
        }
        return .init(translation: translation, chunks: chunks.map(\.meaning))
    }

    private mutating func decode(_ line: String) throws -> LearningSentenceUpdate? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard let data = line.data(using: .utf8), let record = try? JSONDecoder().decode(Record.self, from: data) else {
            throw LearningFailure.message(String(localized: "The translation analysis format is unavailable. Try again later.",
                table: "Learning", comment: "Error shown when the model's translation-analysis response cannot be parsed."))
        }
        switch record.type {
        case "translation":
            guard !fixedTranslation, translation == nil, chunks.isEmpty, let rawText = record.text else {
                throw LearningFailure.message(String(localized: "The model repeated or changed the current translation.",
                    table: "Learning", comment: "Error shown when streamed analysis does not preserve the already displayed translation."))
            }
            let text = try LearningExpressionOutputPolicy.validatedText(rawText)
            translation = text
            return .translation(text)
        case "chunk":
            guard let translation, let sourceParts = record.source, let targetParts = record.target,
                  !sourceParts.isEmpty || !targetParts.isEmpty, chunks.count < 40,
                  sourceParts.count <= 8, targetParts.count <= 8,
                  let explanation = record.explanation, explanation.utf8.count <= 1_200 else {
                throw LearningFailure.message(String(localized: "Chunk alignments are incomplete.",
                    table: "Learning", comment: """
                    Error shown when the returned chunk alignments do not cover a valid complete analysis result.
                    """))
            }
            let sourceRanges = try resolve(sourceParts, in: source, occupied: chunks.flatMap(\.sourceRanges))
            let targetRanges = try resolve(targetParts, in: translation, occupied: chunks.flatMap(\.targetRanges))
            let chunk = Chunk(id: chunks.count, sourceRanges: sourceRanges,
                targetRanges: targetRanges, explanation: explanation)
            chunks.append(chunk)
            return .chunk(chunk.meaning)
        default:
            throw LearningFailure.message(String(localized: "The model returned an unknown expression-analysis result.",
                table: "Learning", comment: "Error shown when the model response contains an unsupported analysis result."))
        }
    }

    private func resolve(_ parts: [String], in text: String, occupied: [NSRange]) throws -> [NSRange] {
        let value = text as NSString
        var claimed = occupied
        var ranges: [NSRange] = []
        for part in parts {
            guard !part.isEmpty else {
                throw LearningFailure.message(String(localized: "A phrase contains an empty text range.",
                    table: "Learning", comment: "Error shown when an analysis item has no quoted text to align."))
            }
            var search = NSRange(location: 0, length: value.length)
            var resolved: NSRange?
            while search.length > 0 {
                let match = value.range(of: part, options: .literal, range: search)
                guard match.location != NSNotFound else { break }
                if value.rangeOfComposedCharacterSequences(for: match) == match,
                   !claimed.contains(where: { NSIntersectionRange($0, match).length > 0 }) {
                    resolved = match
                    break
                }
                // Advance one grapheme from the start, not the entire rejected match: a later
                // unclaimed occurrence can overlap that match ("ana" inside "banana").
                let next = NSMaxRange(value.rangeOfComposedCharacterSequence(at: match.location))
                search = NSRange(location: next, length: value.length - next)
            }
            guard let resolved else {
                throw LearningFailure.message(String(localized: "A phrase does not match the current source or translation.",
                    table: "Learning", comment: """
                    Error shown when an exact phrase quote cannot be found in the current source or translation.
                    """))
            }
            claimed.append(resolved)
            ranges.append(resolved)
        }
        return ranges
    }

    private struct Record: Decodable {
        let type: String
        let text: String?
        let source: [String]?
        let target: [String]?
        let explanation: String?
    }
}
