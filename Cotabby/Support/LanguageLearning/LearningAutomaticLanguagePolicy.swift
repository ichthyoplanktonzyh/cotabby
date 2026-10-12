import Foundation

/// Automatic requests need evidence of the configured source script, unlike an explicit shortcut
/// where the user's language choice is sufficient. This keeps target-language typing and a lone
/// Latin IME preedit from starting Chinese/Korean/etc. learning, without naming any input method.
nonisolated enum LearningAutomaticLanguagePolicy {
    static func accepts(_ text: String, sourceLanguage: LearningLanguage) -> Bool {
        let script: String
        switch sourceLanguage {
        case .chinese, .traditionalChinese: script = #"\p{Han}"#
        case .japanese: script = #"[\p{Han}\p{Hiragana}\p{Katakana}]"#
        case .korean: script = #"\p{Hangul}"#
        case .russian: script = #"\p{Cyrillic}"#
        case .hindi: script = #"\p{Devanagari}"#
        case .arabic: script = #"\p{Arabic}"#
        default: script = #"\p{Latin}"#
        }
        return text.range(of: script, options: .regularExpression) != nil
    }
}
