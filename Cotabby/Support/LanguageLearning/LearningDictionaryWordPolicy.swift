import Foundation
import NaturalLanguage

/// Maps a clicked character to a lexical occurrence using the configured target language. This
/// keeps whitespace/punctuation and UTF-16 validation separate from AppKit hit testing and I/O.
nonisolated enum LearningDictionaryWordPolicy {
    static func word(atUTF16Location location: Int, in text: String, language: NLLanguage) -> LearningDictionaryWord? {
        guard location >= 0, location < text.utf16.count,
              let point = Range(NSRange(location: location, length: 0), in: text)?.lowerBound else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language)
        let range = tokenizer.tokenRange(at: point)
        guard range.contains(point) else { return nil }
        let word = String(text[range])
        guard word.contains(where: \.isLetter), word.utf8.count <= 256 else { return nil }
        return LearningDictionaryWord(text: word, range: NSRange(range, in: text))
    }
}
