import Foundation

/// The existing app-owned endpoint adapter also provides a distinct sentence-learning contract.
/// Cancellation and preference checks precede every streamed delivery, so a settings edit cannot
/// expose an old model's translation even when URLSession has already buffered its response.
extension LearningExpressionService: LearningSentenceGenerating {
    func generateSentence(
        source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage,
        onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void
    ) async throws -> LearningSentenceResult {
        let snapshot = settings.languageLearning.snapshot
        let baseURL = settings.openAICompatibleBaseURL
        let credentialRevision = settings.endpointCredentialRevision
        guard snapshot.translationEnabled, snapshot.sourceLanguages.contains(sourceLanguage),
              snapshot.targetLanguage == targetLanguage, sourceLanguage != targetLanguage else { throw CancellationError() }
        let configuration = try OpenAICompatibleEndpointConfiguration(
            baseURLString: baseURL, modelName: snapshot.model, apiMode: .chatCompletions
        )
        let prompt = try LearningSentencePrompt.render(
            source: source, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage
        )
        var parser = LearningSentenceStreamParser(source: source)
        var deliveredTranslation = false
        var deliveredChunks = 0
        let publish: () -> Void = {
            if !deliveredTranslation, let translation = parser.translation {
                deliveredTranslation = true
                onUpdate(.translation(translation))
            }
            while deliveredChunks < parser.chunks.count {
                onUpdate(.chunk(parser.chunks[deliveredChunks]))
                deliveredChunks += 1
            }
        }
        let validate: () throws -> Void = {
            try Task.checkCancellation()
            guard self.settings.languageLearning.snapshot == snapshot,
                  self.settings.openAICompatibleBaseURL == baseURL,
                  self.settings.endpointCredentialRevision == credentialRevision,
                  self.settings.isGloballyEnabled, !self.settings.isTemporarilyPaused else { throw CancellationError() }
        }
        try validate()
        try await client.streamInstruction(
            configuration: configuration, apiKey: settings.openAICompatibleAPIKey(), prompt: prompt,
            options: .init(maxPredictionTokens: 4_096, temperature: 0.3, topP: 0.9)
        ) { delta in
            try validate()
            // A packet may contain a valid translation followed by malformed analysis. Publish
            // the validated prefix even when parsing the later line throws, preserving read-only output.
            defer { publish() }
            _ = try parser.append(delta)
        }
        try validate()
        defer { publish() }
        _ = try parser.finish()
        return try parser.result()
    }
}
