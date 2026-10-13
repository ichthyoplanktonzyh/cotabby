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
        let name = profile.backend == .local ? profile.localModel : profile.endpointModel
        var hy = profile.template == .hyMT || name.lowercased().contains("hy-mt") || name.lowercased().contains("hymt")
        if profile.backend == .local, profile.template == .automatic, !profile.localModel.isEmpty {
            let runtime = try BundledRuntimeLocator().resolve(configuration: .default, selectedModelFilename: profile.localModel)
            hy = try LearningLocalPrompt.resolve(.automatic, modelURL: runtime.modelFileURL) == .hyMT
        }
        let prompt: String, budget: Int
        let userOnly: Bool
        switch task {
        case .translation:
            // Hy-MT's user-only translation instruction does not ask a specialist to become a
            // chat assistant or produce structural analysis. Other models use the bounded prompt.
            if hy {
                _ = try LearningExpressionPrompt.translation(source: source, sourceLanguage: sourceLanguage,
                    targetLanguage: task.target)
                prompt = "Translate the following text into \(task.target == .chinese ? "Chinese" : task.target.name). " +
                    "Note that you should only output the translated result without any additional explanation:\n" + source
            } else {
                prompt = try LearningExpressionPrompt.translation(source: source, sourceLanguage: sourceLanguage, targetLanguage: task.target)
            }
            budget = 2_048
            userOnly = hy
        }
        let raw = try await model.generate(prompt: prompt, maxTokens: budget, userOnly: userOnly)
        try Task.checkCancellation()
        guard settings.languageLearning.snapshot == snapshot, settings.isGloballyEnabled, !settings.isTemporarilyPaused else {
            throw CancellationError()
        }
        let result = try LearningExpressionOutputPolicy.validatedText(raw)
        LearningRequestTrace.measurement?.usable()
        return result
    }
}
