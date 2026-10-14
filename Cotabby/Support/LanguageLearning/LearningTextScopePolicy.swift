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
            throw LearningFailure.message(String(localized: "The text range is incomplete. Select the committed text again.",
                table: "Learning", comment: "Error shown when the requested learning text range cannot be verified as complete."))
        }
        let source = value.substring(with: range)
        guard source.utf8.count <= 6_000 else {
            throw LearningFailure.message(String(localized: """
            The selected range exceeds 6 KB. Select shorter text manually; the source was not truncated.
            """,
                table: "Learning", comment: """
                Error shown when the selected text exceeds the safe request limit; no shortened text was sent.
                """))
        }
        guard source.contains(where: \.isLetter) else {
            throw LearningFailure.message(String(localized: "The selected range contains no text that can be converted.",
                table: "Learning", comment: "Error shown when the selected range contains no letters to translate."))
        }
        return source
    }

    static func conversionRange(value: String, selection: NSRange) throws -> NSRange {
        let utf16 = value as NSString
        guard selection.location >= 0, selection.length >= 0, selection.location <= utf16.length,
              selection.length <= utf16.length - selection.location,
              Range(selection, in: value) != nil,
              selection.location == utf16.length ||
                utf16.rangeOfComposedCharacterSequence(at: selection.location).location == selection.location
        else {
            throw LearningFailure.message(String(localized: "Could not confirm the caret range.",
                table: "Learning", comment: "Error shown when the caret's sentence range cannot be resolved safely."))
        }
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
        guard let result = result ?? previousSentence else {
            throw LearningFailure.message(String(localized: "There is no complete sentence at the caret. Select text manually.",
                table: "Learning", comment: "Guidance shown when the caret is not inside a complete sentence suitable for preview."))
        }
        guard !(window.location > 0 && result.location == 0),
              !(NSMaxRange(window) < utf16.length && NSMaxRange(result) == local.utf16.count) else {
            throw LearningFailure.message(String(localized: """
            The current sentence extends beyond the verifiable range. Select text manually; truncated text was not sent.
            """,
                table: "Learning", comment: """
                Error shown when sentence boundaries extend outside verified editor text; no truncated content was sent.
                """))
        }
        let resolved = NSRange(location: result.location + window.location, length: result.length)
        _ = try text(value: value, range: resolved)
        return resolved
    }
}
