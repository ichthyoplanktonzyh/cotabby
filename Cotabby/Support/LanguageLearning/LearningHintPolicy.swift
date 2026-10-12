import Foundation
import NaturalLanguage

/// A hint is display data, never an insertion result or a vocabulary mastery score. Its bounded
/// decoder is shared by the network response and the memory cache owned by the hint coordinator.
nonisolated struct LearningWordHint: Decodable, Equatable, Sendable {
    let expression: String
    let explanation: String
}

/// Small committed-word scopes avoid translating full sentences on every typing pause. The
/// caller supplies language identified from the field; only this word is sent to the hint model.
nonisolated enum LearningHintPolicy {
    static func source(in prefix: String, language: LearningLanguage) -> String? {
        guard !prefix.isEmpty else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(language.naturalLanguage)
        tokenizer.string = prefix
        var last: Range<String.Index>?
        tokenizer.enumerateTokens(in: prefix.startIndex..<prefix.endIndex) { range, _ in last = range; return true }
        guard let last, prefix[last.upperBound...].allSatisfy({ $0.isWhitespace || "。！？.!?,，;；".contains($0) }) else { return nil }
        let source = String(prefix[last])
        guard source.count <= 24, source.utf8.count <= 160, source.contains(where: \.isLetter),
              source.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }),
              !prefix.suffix(100).contains("://"), !prefix.suffix(100).contains("@") else { return nil }
        return source
    }

    static func decode(_ raw: String) throws -> LearningWordHint {
        guard raw.utf8.count <= 2_000, let hint = try? JSONDecoder().decode(LearningWordHint.self, from: Data(raw.utf8)),
              !hint.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hint.expression.count <= 80, hint.explanation.count <= 300,
              InsertionSafetyGate.isSafeToInsert(hint.expression), InsertionSafetyGate.isSafeToInsert(hint.explanation) else {
            throw LearningFailure.message("模型没有返回简短的词语提示。")
        }
        return hint
    }
}
