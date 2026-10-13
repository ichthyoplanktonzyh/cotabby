import Foundation

/// The coordinator uses the two explicit methods so analysis settings can cancel/restart only
/// analysis. The combined method remains a convenience for callers outside the passive pipeline.
extension LearningExpressionService: LearningSentenceGenerating {
    func translateSentence(source: String, sourceLanguage: LearningLanguage,
                           targetLanguage: LearningLanguage) async throws -> String {
        try await translator.generate(source: source, task: .translation(source: sourceLanguage, target: targetLanguage))
    }

    func analyzeSentence(source: String, translation: String, sourceLanguage: LearningLanguage,
                         targetLanguage: LearningLanguage,
                         onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
        try await analyzer.generate(source: source, translation: translation, sourceLanguage: sourceLanguage,
                                    targetLanguage: targetLanguage, onUpdate: onUpdate)
    }

    func generateSentence(source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage,
                          onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
        return try await LearningRequestTrace.$requestID.withValue(LearningRequestTrace.requestID ?? RequestID.generate()) {
            let translation = try await translateSentence(source: source, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            onUpdate(.translation(translation))
            guard settings.languageLearning.analysisEnabled else { return .init(translation: translation, chunks: []) }
            return try await analyzeSentence(source: source, translation: translation, sourceLanguage: sourceLanguage,
                                             targetLanguage: targetLanguage, onUpdate: onUpdate)
        }
    }
}
