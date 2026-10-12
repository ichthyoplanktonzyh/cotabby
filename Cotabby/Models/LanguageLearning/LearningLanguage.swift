import Foundation
import NaturalLanguage

/// Stable identifiers for translation settings, borrowing the original language palette's labels.
/// A language selects a direction and text-segmentation locale; it does not promise model support.
nonisolated enum LearningLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en", spanish = "es", french = "fr", german = "de", italian = "it"
    case portuguese = "pt", dutch = "nl", russian = "ru", chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja", korean = "ko", hindi = "hi", arabic = "ar"

    var id: String { rawValue }
    var name: String { LanguageCatalog.commonLanguages.first { $0.code == rawValue }?.name ?? rawValue }
    var label: String { LanguageCatalog.commonLanguages.first { $0.code == rawValue }?.nativeLabel ?? rawValue }
    var naturalLanguage: NLLanguage { self == .chinese ? .simplifiedChinese : NLLanguage(rawValue: rawValue) }

    /// Only recent committed text is inspected. An uncertain result leaves the configured source
    /// language unavailable rather than guessing which translation direction to use.
    static func detect(in text: String) -> Self? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.suffix(600)))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        guard let first = hypotheses.first, first.value >= 0.55,
              hypotheses.count == 1 || first.value - hypotheses[1].value >= 0.15 else { return nil }
        if first.key == .traditionalChinese { return .traditionalChinese }
        if first.key == .simplifiedChinese { return .chinese }
        return Self(rawValue: first.key.rawValue)
    }
}

/// An operation captures its languages before awaiting the model so later setting edits cannot
/// relabel or commit an old reply. Hints never own an editor replacement transaction.
nonisolated enum LearningExpressionTask: Equatable, Sendable {
    case translation(source: LearningLanguage, target: LearningLanguage)
    case hint(source: LearningLanguage, target: LearningLanguage)

    var target: LearningLanguage {
        switch self {
        case .translation(_, let target), .hint(_, let target): target
        }
    }
}
