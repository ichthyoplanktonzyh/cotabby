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

}
