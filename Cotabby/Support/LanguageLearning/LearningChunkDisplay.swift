import Foundation
import NaturalLanguage

/// One visible fragment retains its original characters. A meaning ID can occur in several
/// fragments on either side of a sentence; color never changes translation text or copy output.
nonisolated struct LearningTextFragment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let chunkID: Int?
}

/// Stateless display preparation, separate from model parsing and window state. Uncovered text
/// stays neutral; malformed or overlapping spans are skipped rather than losing source characters.
nonisolated enum LearningChunkDisplay {
    static func fragments(text: String, chunks: [LearningMeaningChunk], source: Bool) -> [LearningTextFragment] {
        let boundaries = Set(text.indices).union([text.endIndex])
        let count = text.utf16.count
        let rawSpans: [(range: NSRange, identifier: Int)] = chunks.flatMap { chunk in
            (source ? chunk.sourceRanges : chunk.targetRanges).map { (range: $0, identifier: chunk.id) }
        }
        let validSpans = rawSpans.filter { span in
            guard span.range.location >= 0, span.range.location <= count,
                  span.range.length > 0, span.range.length <= count - span.range.location,
                  let range = Range(span.range, in: text) else { return false }
            return boundaries.contains(range.lowerBound) && boundaries.contains(range.upperBound)
        }
        let spans = validSpans.sorted {
            $0.range.location == $1.range.location ? $0.identifier < $1.identifier : $0.range.location < $1.range.location
        }
        var fragments: [LearningTextFragment] = []
        var cursor = 0
        for span in spans {
            guard span.range.location >= cursor, let range = Range(span.range, in: text) else { continue }
            appendPlain(text, range: NSRange(location: cursor, length: span.range.location - cursor), to: &fragments)
            fragments.append(.init(id: fragments.count, text: String(text[range]), chunkID: span.identifier))
            cursor = NSMaxRange(span.range)
        }
        appendPlain(text, range: NSRange(location: cursor, length: count - cursor), to: &fragments)
        return fragments
    }

    static func quote(_ text: String, ranges: [NSRange]) -> String {
        let count = text.utf16.count
        let valid = ranges.filter { $0.location >= 0 && $0.location <= count && $0.length > 0 && $0.length <= count - $0.location }
            .sorted { $0.location < $1.location }
        // Model array order need not be reading order. The popup and its word buttons follow
        // the actual sentence, just like the colored fragments in the main card.
        return valid.compactMap { Range($0, in: text).map { String(text[$0]) } }.joined(separator: " … ")
    }

    static func words(in text: String, language: LearningLanguage) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language.naturalLanguage)
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if word.contains(where: \.isLetter), !result.contains(word) { result.append(word) }
            return true
        }
        return result
    }

    private static func appendPlain(_ text: String, range: NSRange, to fragments: inout [LearningTextFragment]) {
        guard range.length > 0, let range = Range(range, in: text) else { return }
        // Neutral newlines get their own fragment so the wrapping layout can preserve paragraph
        // breaks without inserting synthetic characters into the copied translation.
        var run = ""
        for character in text[range] {
            if character.isNewline {
                if !run.isEmpty { fragments.append(.init(id: fragments.count, text: run, chunkID: nil)); run = "" }
                fragments.append(.init(id: fragments.count, text: String(character), chunkID: nil))
            } else { run.append(character) }
        }
        if !run.isEmpty { fragments.append(.init(id: fragments.count, text: run, chunkID: nil)) }
    }
}
