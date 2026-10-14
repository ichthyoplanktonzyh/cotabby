import Foundation

/// A request-scoped pure boundary between untrusted pair JSON and drawable meaning units.
/// LearningAnalysisService calls it only after generation finishes: no provisional chunk reaches
/// AppKit. The model supplies quotes; this parser supplies grapheme-safe UTF-16 positions and IDs.
/// Literal positioning cannot prove semantic correspondence, and ambiguous repeats stay uncolored.
nonisolated enum LearningAlignmentParser {
    static func parse(_ raw: String, source: String, translation: String) throws -> LearningSentenceResult {
        guard raw.utf8.count <= 48_000,
              let data = raw.data(using: .utf8),
              let pairs = try? JSONDecoder().decode([[String]].self, from: data),
              !pairs.isEmpty, pairs.count <= 40,
              pairs.allSatisfy({ $0.count == 2 && $0.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }) else {
            throw LearningFailure.message(String(localized: """
            Phrase matching is unavailable; you can still read the translation and look up words.
            """,
                table: "Learning", comment: """
                Status shown when phrase-alignment output cannot be parsed but the translation remains usable.
                """))
        }
        // Keep every literal candidate until other unique pairs claim their ranges. This can
        // disambiguate a repeat enclosed by a larger unique phrase without assuming target order.
        var pending = try pairs.enumerated().map { index, pair in
            let left = candidates(pair[0], in: source), right = candidates(pair[1], in: translation)
            guard !left.isEmpty, !right.isEmpty else {
                throw LearningFailure.message(String(localized: "A phrase match does not match the current source or translation.",
                    table: "Learning", comment: """
                    Error shown when an alignment quote does not exactly match this request's source or translation.
                    """))
            }
            return (index: index, source: left, target: right)
        }
        var located: [(index: Int, source: NSRange, target: NSRange)] = []
        while !pending.isEmpty {
            let count = located.count
            var unresolved: [(index: Int, source: [NSRange], target: [NSRange])] = []
            for pair in pending {
                let left = pair.source.filter { candidate in
                    !located.contains { NSIntersectionRange($0.source, candidate).length > 0 }
                }
                let right = pair.target.filter { candidate in
                    !located.contains { NSIntersectionRange($0.target, candidate).length > 0 }
                }
                guard !left.isEmpty, !right.isEmpty else {
                    throw LearningFailure.message(String(localized: "A phrase match contains duplicate or overlapping text ranges.",
                        table: "Learning", comment: "Error shown when phrase-alignment ranges overlap or repeat text."))
                }
                if left.count == 1, right.count == 1 {
                    located.append((pair.index, left[0], right[0]))
                } else {
                    unresolved.append((pair.index, left, right))
                }
            }
            pending = unresolved
            if located.count == count { break }
        }
        guard !located.isEmpty else {
            throw LearningFailure.message(String(localized: """
            Repeated text could not be located reliably; you can still read the translation and look up words.
            """,
                table: "Learning", comment: """
                Status shown when repeated phrases make alignment ambiguous but translation and lookup remain available.
                """))
        }
        // Source order assigns stable colors even if the model returns pairs in another order.
        // Target order is independent: translation may reorder subjects, time or conditions.
        let chunks = located.sorted { $0.source.location < $1.source.location }.enumerated().map { id, pair in
            LearningMeaningChunk(id: id, sourceRanges: [pair.source], targetRanges: [pair.target])
        }
        return .init(translation: translation, chunks: chunks, unresolvedChunkCount: pending.count)
    }

    private static func candidates(_ quote: String, in text: String) -> [NSRange] {
        let value = text as NSString
        var search = NSRange(location: 0, length: value.length)
        var result: [NSRange] = []
        while search.length > 0 {
            let match = value.range(of: quote, options: .literal, range: search)
            guard match.location != NSNotFound else { break }
            if value.rangeOfComposedCharacterSequences(for: match) == match { result.append(match) }
            // Advance one grapheme, not the full quote, so overlapping candidates are visible.
            let next = NSMaxRange(value.rangeOfComposedCharacterSequence(at: match.location))
            search = NSRange(location: next, length: value.length - next)
        }
        return result
    }
}
