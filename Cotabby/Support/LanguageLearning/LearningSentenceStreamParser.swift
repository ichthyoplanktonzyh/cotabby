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
        guard totalBytes <= 48_000 else { throw LearningFailure.message("表达分析超过可显示范围。") }
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
        guard let translation else { throw LearningFailure.message("模型没有返回可用译文。") }
        guard !chunks.isEmpty else { throw LearningFailure.message("译文已生成，语块对应尚不可用。") }
        return .init(translation: translation, chunks: chunks.map(\.meaning))
    }

    private mutating func decode(_ line: String) throws -> LearningSentenceUpdate? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard let data = line.data(using: .utf8), let record = try? JSONDecoder().decode(Record.self, from: data) else {
            throw LearningFailure.message("译文分析格式不可用，请稍后重试。")
        }
        switch record.type {
        case "translation":
            guard !fixedTranslation, translation == nil, chunks.isEmpty, let rawText = record.text else {
                throw LearningFailure.message("模型重复或改变了本次译文。")
            }
            let text = try LearningExpressionOutputPolicy.validatedText(rawText)
            translation = text
            return .translation(text)
        case "chunk":
            guard let translation, let sourceParts = record.source, let targetParts = record.target,
                  !sourceParts.isEmpty || !targetParts.isEmpty, chunks.count < 40,
                  sourceParts.count <= 8, targetParts.count <= 8,
                  let explanation = record.explanation, explanation.utf8.count <= 1_200 else {
                throw LearningFailure.message("语块对应不完整。")
            }
            let sourceRanges = try resolve(sourceParts, in: source, occupied: chunks.flatMap(\.sourceRanges))
            let targetRanges = try resolve(targetParts, in: translation, occupied: chunks.flatMap(\.targetRanges))
            let chunk = Chunk(id: chunks.count, sourceRanges: sourceRanges,
                targetRanges: targetRanges, explanation: explanation)
            chunks.append(chunk)
            return .chunk(chunk.meaning)
        default:
            throw LearningFailure.message("模型返回了未知的表达分析。")
        }
    }

    private func resolve(_ parts: [String], in text: String, occupied: [NSRange]) throws -> [NSRange] {
        let value = text as NSString
        var claimed = occupied
        var ranges: [NSRange] = []
        for part in parts {
            guard !part.isEmpty else { throw LearningFailure.message("语块包含空的文字范围。") }
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
            guard let resolved else { throw LearningFailure.message("语块与本次原文或译文不一致。") }
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
