import Foundation
import NaturalLanguage

/// Resolves the source direction for an explicit translation preview from the user's enabled
/// source choices. The coordinator calls this once for each captured expression, before it builds
/// a translation task; passive word hints keep their separate language-detection policy.
///
/// One remaining source is the user's explicit direction preference, so short text such as `你好`
/// does not need to win Natural Language's script-variant contest. Several enabled sources require
/// constrained recognition with both a confidence floor and a margin over the runner-up.
nonisolated struct LearningSourceLanguageResolver: Sendable {
    private static let maximumSampleCharacters = 600
    private static let minimumConfidence = 0.55
    private static let minimumMargin = 0.15

    /// Returns a source language selected by the user's current preferences, or `nil` when the
    /// text is empty, every enabled source is the target, or multi-source recognition is uncertain.
    func resolve(
        text: String,
        enabledSourceLanguages: [LearningLanguage],
        targetLanguage: LearningLanguage
    ) -> LearningLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isLetter) else { return nil }

        // Settings can contain duplicates after migrations or direct UserDefaults edits. Preserve
        // the user's order while treating a language as one candidate and never as its own target.
        var seen = Set<LearningLanguage>()
        let candidates = enabledSourceLanguages.filter { language in
            language != targetLanguage && seen.insert(language).inserted
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        let sample = String(trimmed.suffix(Self.maximumSampleCharacters))
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map(\.naturalLanguage)
        recognizer.processString(sample)

        // Fill absent candidates with zero so the confidence margin is always measured against
        // every enabled alternative, not only hypotheses Natural Language chose to return.
        let hypotheses = recognizer.languageHypotheses(withMaximum: candidates.count)
        let scores = Dictionary(uniqueKeysWithValues: candidates.map { language in
            (language, hypotheses[language.naturalLanguage] ?? 0)
        })
        return Self.confidentLanguage(from: scores)
    }

    /// The ranking rule is separated from Natural Language so thresholds, ties, and close scores
    /// stay deterministic in tests even if the system model's probabilities shift between releases.
    static func confidentLanguage(
        from scores: [LearningLanguage: Double]
    ) -> LearningLanguage? {
        let ranked = scores
            .filter { $0.value.isFinite }
            .sorted { $0.value > $1.value }
        guard let best = ranked.first,
              best.value >= minimumConfidence,
              ranked.count == 1 || best.value - ranked[1].value >= minimumMargin else {
            return nil
        }
        return best.key
    }
}
