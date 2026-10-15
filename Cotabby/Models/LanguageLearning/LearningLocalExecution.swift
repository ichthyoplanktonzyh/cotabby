import Foundation

/// Narrow native ownership seam. The controller owns one executor; the production implementation
/// serializes C++ state and tests simulate load/decode/unload without touching real model files.
nonisolated protocol LearningLocalExecuting: AnyObject, Sendable {
    func claim(_ operation: UUID)
    func invalidate() -> UUID
    func prepare(modelURL: URL, operationID: UUID, trace: LearningRequestContext?) throws
    func generate(modelURL: URL, template: LearningChatTemplate, prompt: String, maxTokens: Int,
                  operationID: UUID, trace: LearningRequestContext?, onLoad: (@Sendable (Int) -> Void)?,
                  onDelta: @Sendable (String) -> Void) throws -> String
    func cancel(_ operation: UUID?)
    func unload(expectedLease: UUID?, trace: LearningRequestContext?)
    func shutdownSync()
    func prepare(modelURL: URL, contextWindowTokens: Int, operationID: UUID, trace: LearningRequestContext?) throws
    func generate(
        configuration: LearningLocalModelConfiguration, prompt: String, maxTokens: Int,
        operationID: UUID, trace: LearningRequestContext?, onLoad: (@Sendable (Int) -> Void)?,
        onDelta: @Sendable (String) -> Void
    ) throws -> String
    func translationPlan(
        configuration: LearningLocalModelConfiguration, input: LearningTranslationInput,
        sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage, output: Int,
        operationID: UUID, trace: LearningRequestContext?
    ) throws -> LearningTranslationPrompt.Request
}

extension LearningLocalExecuting {
    // Existing alternate executors retain their narrow interface. The production adapter below
    // overrides these seams to use its actual allocation and tokenizer; fakes remain text-only.
    func prepare(modelURL: URL, contextWindowTokens: Int, operationID: UUID, trace: LearningRequestContext?) throws {
        try prepare(modelURL: modelURL, operationID: operationID, trace: trace)
    }
    func generate(
        configuration: LearningLocalModelConfiguration, prompt: String, maxTokens: Int,
        operationID: UUID, trace: LearningRequestContext?, onLoad: (@Sendable (Int) -> Void)?,
        onDelta: @Sendable (String) -> Void
    ) throws -> String {
        try generate(
            modelURL: configuration.modelURL, template: configuration.template, prompt: prompt, maxTokens: maxTokens,
            operationID: operationID, trace: trace, onLoad: onLoad, onDelta: onDelta)
    }
    func translationPlan(
        configuration: LearningLocalModelConfiguration, input: LearningTranslationInput,
        sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage, output: Int,
        operationID: UUID, trace: LearningRequestContext?
    ) throws -> LearningTranslationPrompt.Request {
        try LearningTranslationBudget.prompt(
            input: input, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
            family: .init(template: configuration.template), total: configuration.contextWindowTokens, output: output, estimated: true,
            count: ModelContextBudget.estimatedTokens)
    }
}
