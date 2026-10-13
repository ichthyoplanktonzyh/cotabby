import Foundation
import NaturalLanguage

/// Deterministic lexical preparation. All ranges refer to the untouched translation; normalized
/// text is only an index key, never replacement text or a proposed source correspondence.
nonisolated enum LearningUnitPolicy {
    static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func words(in text: String, language: LearningLanguage) -> [LearningDictionaryWord] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language.naturalLanguage)
        var result: [LearningDictionaryWord] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if word.contains(where: \.isLetter), word.utf8.count <= 256 {
                result.append(.init(text: word, range: NSRange(range, in: text)))
            }
            return true
        }
        return result
    }

    static func fallback(in text: String, language: LearningLanguage) -> [LearningUnit] {
        words(in: text, language: language).map(LearningUnit.word)
    }

    static func unit(at location: Int, units: [LearningUnit]) -> LearningUnit? {
        units.first { unit in unit.ranges.contains { NSLocationInRange(location, $0) } }
    }

    /// Do not paint a partial fixed expression as if the model had aligned the whole expression.
    /// Unit recognition can finish after analysis: recomputing this projection requires no new
    /// model call and does not change either result. Neutral unit clicks remain available.
    static func correspondence(_ chunks: [LearningMeaningChunk], respecting units: [LearningUnit]) -> [LearningMeaningChunk] {
        chunks.filter { chunk in
            units.allSatisfy { unit in
                let touches = unit.ranges.contains { fixed in
                    chunk.targetRanges.contains { NSIntersectionRange(fixed, $0).length > 0 }
                }
                return !touches || unit.ranges.allSatisfy { fixed in
                    chunk.targetRanges.contains { $0.location <= fixed.location && NSMaxRange($0) >= NSMaxRange(fixed) }
                }
            }
        }
    }
}
