import Foundation
import NaturalLanguage

/// Makes plain dictionary output readable without guessing part-of-speech or sense metadata.
/// Existing line breaks are retained; only long paragraphs are reflowed at linguistic sentence
/// boundaries. The local service calls this off MainActor before publishing an immutable entry.
nonisolated enum LearningDictionaryText {
    static func paragraphs(_ text: String) -> [String] {
        let lines = String(text.prefix(8_000)).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.flatMap { line -> [String] in
            guard line.count > 280 else { return [line] }
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = line
            var paragraphs: [String] = []
            var start = line.startIndex
            var previousEnd = line.startIndex
            tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
                if previousEnd > start, line.distance(from: start, to: range.upperBound) > 280 {
                    paragraphs.append(String(line[start..<previousEnd]).trimmingCharacters(in: .whitespacesAndNewlines))
                    start = previousEnd
                }
                // Token ranges choose break points only. Copying the original slice also keeps
                // punctuation and gaps that the linguistic tokenizer did not include in a token.
                previousEnd = range.upperBound
                return true
            }
            if start < line.endIndex { paragraphs.append(String(line[start...]).trimmingCharacters(in: .whitespacesAndNewlines)) }
            return paragraphs.isEmpty ? [line] : paragraphs
        }
    }
}
