import Foundation

/// Optional analysis owns a separate model and consumes a fixed sentence pair. It publishes only
/// a validated complete set of exact-quote chunks; it cannot replace the translator's wording
/// or modify the editor. Buffering until completion makes publication an atomic state change.
@MainActor
final class LearningAnalysisService {
    let settings: SuggestionSettingsModel
    let model: LearningModelController
    private let telemetry: LearningRequestTelemetry
    init(settings: SuggestionSettingsModel, model: LearningModelController, telemetry: LearningRequestTelemetry) {
        self.settings = settings; self.model = model; self.telemetry = telemetry
    }

    func generate(source: String, translation: String, sourceLanguage: LearningLanguage,
                  targetLanguage: LearningLanguage,
                  onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
        try await telemetry.perform(source: .analysis, profile: model.profile.snapshot) {
            try await self.generateValidated(source: source, translation: translation,
                sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, onUpdate: onUpdate)
        }
    }

    private func generateValidated(source: String, translation: String, sourceLanguage: LearningLanguage,
                  targetLanguage: LearningLanguage,
                  onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
        let learning = settings.languageLearning
        let profile = learning.analysis.snapshot
        let validate: () throws -> Void = {
            try Task.checkCancellation()
            guard learning.translationEnabled, learning.analysisEnabled, learning.analysis.snapshot == profile,
                  learning.sourceLanguages.contains(sourceLanguage), learning.targetLanguage == targetLanguage,
                  self.settings.isGloballyEnabled, !self.settings.isTemporarilyPaused else { throw CancellationError() }
        }
        try validate()
        let text = try LearningExpressionOutputPolicy.validatedText(translation)
        let prompt = try LearningAnalysisPrompt.render(source: source, translation: text,
            sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        var bytes = 0
        let raw = try await model.generate(prompt: prompt, maxTokens: 4_096) { delta in
            try validate()
            bytes += delta.utf8.count
            guard bytes <= 48_000 else {
                throw LearningFailure.message(String(localized: "Phrase-matching output exceeds the display limit.",
                    table: "Learning", comment: "Error shown when phrase-alignment output is too large to display safely."))
            }
        }
        try validate()
        let result = try LearningAlignmentParser.parse(raw, source: source, translation: text)
        LearningRequestTrace.measurement?.usable()
        // No await occurs between validation and publication. The next sentence or a setting
        // change cannot interleave with this complete batch on MainActor.
        onUpdate(.chunks(result.chunks))
        return result
    }
}
