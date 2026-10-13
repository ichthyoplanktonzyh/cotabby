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
        return try await telemetry.perform(source: .translation, profile: model.profile.snapshot) {
            try await self.generateValidated(source: source, task: task)
        }
    }

    private func generateValidated(source: String, task: LearningExpressionTask) async throws -> String {
        try Task.checkCancellation()
        let snapshot = settings.languageLearning.snapshot
        guard snapshot.translationEnabled, settings.isGloballyEnabled, !settings.isTemporarilyPaused else {
            throw CancellationError()
        }
        let sourceLanguage: LearningLanguage
        switch task {
        case .translation(let language, let target):
            guard snapshot.sourceLanguages.contains(language), snapshot.targetLanguage == target, language != target else {
                throw LearningFailure.message("源语言未启用或与目标相同，请检查翻译设置。")
            }
            sourceLanguage = language
        }
        let profile = model.profile.snapshot
        let family: LearningTranslationPrompt.Family
        if profile.backend == .local, !profile.localModel.isEmpty {
            let runtime = try BundledRuntimeLocator().resolve(configuration: .default, selectedModelFilename: profile.localModel)
            // Hy-MT template metadata may follow its tokenizer arrays. Inspect that bounded
            // header away from UI/input work, then reject a selection changed during the read.
            let template = try await Task.detached(priority: .userInitiated) {
                try LearningLocalPrompt.resolve(profile.template, modelURL: runtime.modelFileURL)
            }.value
            try Task.checkCancellation()
            guard model.profile.snapshot == profile else { throw CancellationError() }
            family = .init(template: template)
        } else if profile.backend == .endpoint {
            family = .init(endpointModel: profile.endpointModel)
        } else {
            family = .generic
        }
        let request = try LearningTranslationPrompt.render(source: source, sourceLanguage: sourceLanguage,
            targetLanguage: task.target, family: family)
        let raw = try await model.generate(prompt: request.prompt, maxTokens: 2_048,
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
