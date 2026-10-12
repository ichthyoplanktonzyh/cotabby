import Foundation
import NaturalLanguage

/// Pure UTF-16 scope resolution. AX captures keep the full value locally; only the selected text
/// or complete sentence leaves this boundary. No scope is truncated to fit a model budget.
nonisolated enum LearningTextScopePolicy {
    static func text(value: String, range: NSRange) throws -> String {
        let value = value as NSString
        guard range.location >= 0, range.length > 0, range.location <= value.length,
              range.length <= value.length - range.location,
              value.rangeOfComposedCharacterSequences(for: range) == range else {
            throw LearningFailure.message("文本范围不完整，请重新选择已提交的文本。")
        }
        let source = value.substring(with: range)
        guard source.utf8.count <= 6_000 else { throw LearningFailure.message("当前范围超过 6 KB，请手动选择较短文本；原文未截断。") }
        guard source.contains(where: \.isLetter) else { throw LearningFailure.message("当前范围没有可转换的文字。") }
        return source
    }

    static func conversionRange(value: String, selection: NSRange) throws -> NSRange {
        let utf16 = value as NSString
        guard selection.location >= 0, selection.length >= 0, selection.location <= utf16.length,
              selection.length <= utf16.length - selection.location,
              Range(selection, in: value) != nil,
              selection.location == utf16.length ||
                utf16.rangeOfComposedCharacterSequence(at: selection.location).location == selection.location
        else { throw LearningFailure.message("无法确认光标范围。") }
        if selection.length > 0 { _ = try text(value: value, range: selection); return selection }
        // AX exposes full document values, but NLP must not scan unbounded text on MainActor.
        // 6000 UTF-16 units on either side exceed the complete source's UTF-8 byte budget.
        // A token touching an artificial edge is rejected rather than sent as a partial sentence.
        let start = max(0, selection.location - 6_000)
        let end = min(utf16.length, selection.location + min(6_000, utf16.length - selection.location))
        let window = utf16.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        let local = utf16.substring(with: window)
        let caret = selection.location - window.location
        let beforeCaret = (local as NSString).substring(to: caret)
        let trailingSpaces = beforeCaret.reversed().prefix { $0.isWhitespace && !$0.isNewline }
        let probe = caret - String(trailingSpaces).utf16.count
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = local
        let nearCaret = beforeCaret.split(whereSeparator: \.isNewline).last.map(String.init) ?? String(local.prefix(600))
        if let language = LearningLanguage.detect(in: nearCaret) { tokenizer.setLanguage(language.naturalLanguage) }
        var result: NSRange?
        var previousSentence: NSRange?
        tokenizer.enumerateTokens(in: local.startIndex..<local.endIndex) { range, _ in
            let candidate = NSRange(range, in: local)
            // At the end of a sentence the caret still belongs to that sentence. At the start of
            // another sentence (after whitespace), the previous token does not include the caret.
            if caret >= candidate.location && caret < NSMaxRange(candidate) {
                result = candidate
                return false
            }
            if probe >= candidate.location && probe <= NSMaxRange(candidate) { previousSentence = candidate }
            return true
        }
        guard let result = result ?? previousSentence else { throw LearningFailure.message("光标处没有完整句子，请手动选择文本。") }
        guard !(window.location > 0 && result.location == 0),
              !(NSMaxRange(window) < utf16.length && NSMaxRange(result) == local.utf16.count) else {
            throw LearningFailure.message("当前句子边界超出可核对范围，请手动选择文本；未发送截断内容。")
        }
        let resolved = NSRange(location: result.location + window.location, length: result.length)
        _ = try text(value: value, range: resolved)
        return resolved
    }
}
