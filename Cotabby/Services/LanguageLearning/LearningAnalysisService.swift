import Foundation

/// Optional analysis owns a separate model and consumes a fixed sentence pair. It publishes only
/// exact-quote chunks; it cannot replace the translator's wording or modify the user's editor.
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
        var parser = LearningSentenceStreamParser(source: source, translation: text)
        var delivered = 0
        let publish: () -> Void = {
            while delivered < parser.chunks.count {
                LearningRequestTrace.measurement?.usable()
                onUpdate(.chunk(parser.chunks[delivered])); delivered += 1
            }
        }
        _ = try await model.generate(prompt: prompt, maxTokens: 4_096) { delta in
            try validate()
            defer { publish() }
            _ = try parser.append(delta)
        }
        try validate()
        defer { publish() }
        _ = try parser.finish()
        return try parser.result()
    }
}
