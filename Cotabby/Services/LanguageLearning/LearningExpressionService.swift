import Foundation

/// App-lifetime adapter for explicit translations and passive word hints. Coordinators choose a
/// task and the service snapshots settings, sends only that bounded source, then rejects stale
/// replies if settings, endpoint credentials, or app-wide availability changed during the await.
@MainActor
final class LearningExpressionService: LearningExpressionGenerating {
    let settings: SuggestionSettingsModel
    let client: OpenAICompatibleAPIClient

    init(settings: SuggestionSettingsModel, client: OpenAICompatibleAPIClient) {
        self.settings = settings
        self.client = client
    }

    func generate(source: String, task: LearningExpressionTask) async throws -> String {
        try Task.checkCancellation()
        let learning = settings.languageLearning
        let snapshot = learning.snapshot
        let request = try instruction(source: source, task: task)
        let baseURL = settings.openAICompatibleBaseURL
        let credentialRevision = settings.endpointCredentialRevision
        guard !learning.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LearningFailure.message("请在 Writing → 跨语言表达学习中指定指令模型，并配置 Endpoint 地址。")
        }
        let configuration = try OpenAICompatibleEndpointConfiguration(
            baseURLString: settings.openAICompatibleBaseURL,
            modelName: learning.model,
            apiMode: .chatCompletions
        )
        try Task.checkCancellation()

        let raw: String
        do {
            raw = try await client.generateInstruction(
                configuration: configuration,
                apiKey: settings.openAICompatibleAPIKey(),
                prompt: request.text,
                options: .init(maxPredictionTokens: request.maxTokens, temperature: 0.3, topP: 0.9)
            )
        } catch OpenAICompatibleClientError.incompleteTextResponse {
            throw LearningFailure.message("模型未返回完整文本（可能达到输出上限）；原文保留，请分段重试。")
        }

        try Task.checkCancellation()
        guard learning.snapshot == snapshot,
              settings.openAICompatibleBaseURL == baseURL,
              settings.endpointCredentialRevision == credentialRevision,
              settings.isGloballyEnabled,
              !settings.isTemporarilyPaused else {
            throw CancellationError()
        }
        return try LearningExpressionOutputPolicy.validatedText(raw)
    }

    private func instruction(source: String, task: LearningExpressionTask) throws -> (text: String, maxTokens: Int) {
        let learning = settings.languageLearning
        switch task {
        case .translation(let sourceLanguage, let target):
            guard learning.translationEnabled else { throw CancellationError() }
            guard learning.sourceLanguages.contains(sourceLanguage),
                  target == learning.targetLanguage,
                  sourceLanguage != target else {
                throw LearningFailure.message("源语言未启用或与目标相同，请检查跨语言辅助设置。")
            }
            return (
                try LearningExpressionPrompt.translation(
                    source: source,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: target
                ),
                2_048
            )
        case .hint(let sourceLanguage, let target):
            guard learning.translationEnabled,
                  learning.hintsEnabled,
                  learning.sourceLanguages.contains(sourceLanguage),
                  target == learning.targetLanguage,
                  sourceLanguage != target else {
                throw CancellationError()
            }
            guard source.utf8.count <= 160 else { throw LearningFailure.message("词语提示范围过长。") }
            return (
                try LearningExpressionPrompt.hint(
                    source: source,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: target
                ),
                192
            )
        }
    }
}
