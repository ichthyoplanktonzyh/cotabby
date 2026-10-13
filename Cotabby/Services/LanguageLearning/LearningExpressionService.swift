import Foundation

/// Compatibility surface for explicit previews and automatic sentence learning. The app owns
/// this facade once; translation and analysis are separate collaborators with independent models.
@MainActor
final class LearningExpressionService: LearningExpressionGenerating {
    let settings: SuggestionSettingsModel
    let models: LearningModelCollection
    let translator: LearningTranslationService
    let analyzer: LearningAnalysisService
    let telemetry: LearningRequestTelemetry

    init(settings: SuggestionSettingsModel, client: OpenAICompatibleAPIClient,
         models: LearningModelCollection? = nil, telemetry: LearningRequestTelemetry? = nil) {
        self.settings = settings
        let models = models ?? LearningModelCollection(settings: settings.languageLearning, client: client, appSettings: settings)
        self.models = models
        let observer = telemetry ?? LearningRequestTelemetry()
        self.telemetry = observer
        translator = LearningTranslationService(settings: settings, model: models.translation, telemetry: observer)
        analyzer = LearningAnalysisService(settings: settings, model: models.analysis, telemetry: observer)
    }

    func recordDisplay(source: ModelRequestSource, requestID: String) {
        telemetry.recordDisplay(source: source, requestID: requestID)
    }

    func generate(source: String, task: LearningExpressionTask) async throws -> String {
        try await translator.generate(source: source, task: task)
    }
}
