import Foundation

/// Translation owns only the quick expression task. The facade retains it for the app lifetime;
/// analysis toggles/credentials never participate in its snapshot or cancel its result.
@MainActor
final class LearningTranslationService {
    let settings: SuggestionSettingsModel
    let model: LearningModelController
    private let telemetry: LearningRequestTelemetry
    init(settings: SuggestionSettingsModel, model: LearningModelController, telemetry: LearningRequestTelemetry) {
        self.settings = settings; self.model = model; self.telemetry = telemetry
    }

    func generate(source: String, task: LearningExpressionTask) async throws -> String {
        try await generate(input: .init(source: source), task: task)
    }

    func generate(input: LearningTranslationInput, task: LearningExpressionTask) async throws -> String {
        return try await telemetry.perform(source: .translation, profile: model.profile.snapshot) {
            try await self.generateValidated(input: input, task: task)
        }
    }

    private func generateValidated(input: LearningTranslationInput, task: LearningExpressionTask) async throws -> String {
        try Task.checkCancellation()
        let snapshot = settings.languageLearning.snapshot
        guard snapshot.translationEnabled, settings.isGloballyEnabled, !settings.isTemporarilyPaused else {
            throw CancellationError()
        }
        let sourceLanguage: LearningLanguage
        switch task {
        case .translation(let language, let target):
            guard snapshot.sourceLanguages.contains(language), snapshot.targetLanguage == target, language != target else {
                throw LearningFailure.message(String(localized: """
                The source language is not enabled or matches the target. Check the translation settings.
                """,
                    table: "Learning", comment: """
                    Error shown when the requested translation direction is not enabled or has identical source and target languages.
                    """))
            }
            sourceLanguage = language
        }
        let profile = model.profile.snapshot
        guard input.source.utf8.count <= ModelContextBudget.maximumTextBytes else { throw ModelContextBudget.oversizedTarget() }
        let output = try ModelContextBudget.translationOutputTokens(source: input.source, total: profile.contextWindowTokens)
        let request = try await model.translationPlan(
            input: input, sourceLanguage: sourceLanguage,
            targetLanguage: task.target, output: output)
        try Task.checkCancellation()
        guard model.profile.snapshot == profile, settings.languageLearning.snapshot == snapshot else { throw CancellationError() }
        let raw = try await model.generate(
            prompt: request.prompt, maxTokens: output,
            userOnly: request.userOnly, sampling: request.sampling)
        try Task.checkCancellation()
        guard settings.languageLearning.snapshot == snapshot, settings.isGloballyEnabled, !settings.isTemporarilyPaused else {
            throw CancellationError()
        }
        let result = try LearningExpressionOutputPolicy.validatedText(raw)
        LearningRequestTrace.measurement?.usable()
        return result
    }
}
