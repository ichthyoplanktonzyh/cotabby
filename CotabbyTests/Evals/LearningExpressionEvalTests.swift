import Foundation
import Testing
@testable import Cotabby

/// Local-only, human-reviewed eval for the same six translation inputs used by the former
/// no-vocabulary variants. It calls the production service once per case, records the original
/// prompt and output with timing, and writes to a fresh artifact name so earlier comparison data
/// remains available. The suite requires explicit opt-in and a loopback endpoint.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["COTABBY_RUN_LEARNING_EVAL"] == "1")
)
@MainActor
struct LearningExpressionEvalTests {
    @Test
    func reportSixLocalTranslationResults() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let configuredModel = environment["COTABBY_LEARNING_EVAL_MODEL"] else {
            throw LearningEvalFailure.configuration("COTABBY_LEARNING_EVAL_MODEL is required when the eval is enabled.")
        }
        let model = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw LearningEvalFailure.configuration("COTABBY_LEARNING_EVAL_MODEL is required when the eval is enabled.")
        }

        let baseURL = environment["COTABBY_LEARNING_EVAL_URL"]
            ?? OpenAICompatibleEndpointConfiguration.defaultBaseURLString
        let endpoint = try OpenAICompatibleEndpointConfiguration(
            baseURLString: baseURL,
            modelName: model,
            apiMode: .chatCompletions
        )
        guard endpoint.hostScope == .loopback else {
            throw LearningEvalFailure.configuration(
                "COTABBY_LEARNING_EVAL_URL must use a loopback host (localhost, 127/8, or ::1)."
            )
        }

        let (suiteName, defaults) = try Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.setOpenAICompatibleBaseURL(baseURL)
        settings.languageLearning.model = model
        settings.languageLearning.sourceLanguages = [.chinese, .english]
        settings.languageLearning.translationEnabled = true

        let service = LearningExpressionService(settings: settings, client: OpenAICompatibleAPIClient())
        var results: [LearningTranslationEvalResult] = []
        for example in Self.translationExamples {
            settings.languageLearning.targetLanguage = example.targetLanguage
            let prompt = try LearningExpressionPrompt.translation(
                source: example.source,
                sourceLanguage: example.sourceLanguage,
                targetLanguage: example.targetLanguage
            )
            let start = Date()
            let translation = try await service.generate(
                source: example.source,
                task: .translation(source: example.sourceLanguage, target: example.targetLanguage)
            )
            let latencyMilliseconds = Date().timeIntervalSince(start) * 1_000

            results.append(LearningTranslationEvalResult(
                category: example.category,
                sourceLanguage: example.sourceLanguage,
                targetLanguage: example.targetLanguage,
                source: example.source,
                prompt: prompt,
                translation: translation,
                latencyMilliseconds: latencyMilliseconds
            ))
        }

        let report = LearningExpressionEvalReport(
            model: model,
            endpoint: endpoint.baseURL.absoluteString,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            translationOptions: .init(maxPredictionTokens: 2_048, temperature: 0.3, topP: 0.9),
            translations: results
        )
        let data = try Self.encode(report)
        try Self.writeArtifact(data)

        // Keep stdout machine-readable and unscored so reviewers can judge meaning and tone by hand.
        print(String(decoding: data, as: UTF8.self))
    }

    /// These are the same six source cases as the former disabled/enabled vocabulary pairs. Each
    /// now runs once with the ordinary translation prompt, matching the old disabled-vocabulary arm.
    private static let translationExamples: [LearningTranslationEvalCase] = [
        .init(category: "daily-chat", sourceLanguage: .chinese, targetLanguage: .english, source: "我刚到家，今天路上有点堵。"),
        .init(category: "tactful-refusal", sourceLanguage: .chinese, targetLanguage: .english,
            source: "谢谢你想到我，不过这周我可能没办法参加，改天再约吧。"),
        .init(category: "negation", sourceLanguage: .chinese, targetLanguage: .english,
            source: "我不是不想帮你，只是今天实在抽不开身。"),
        .init(category: "time-and-numbers", sourceLanguage: .chinese, targetLanguage: .english,
            source: "我们明天下午三点半见，会议大概持续45分钟。"),
        .init(category: "necessary-technical-term", sourceLanguage: .chinese, targetLanguage: .english,
            source: "请把这个函数的返回值改成 Optional，这样调用方才能处理空值。"),
        .init(category: "english-to-chinese", sourceLanguage: .english, targetLanguage: .chinese,
            source: "I may be a few minutes late, but I will message you when I arrive.")
    ]

    private static func makeIsolatedDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "io.cotabby.tests.LearningExpressionEval-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw LearningEvalFailure.configuration("Could not create an isolated UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: "cotabbyGloballyEnabled")
        defaults.set(try JSONEncoder().encode(SuggestionPauseState.until(.distantPast)),
            forKey: "cotabbySuggestionPauseState")
        return (name, defaults)
    }

    /// Derives the repository root from this source file so the artifact stays under the ignored
    /// build directory even when Xcode launches the test host from another directory.
    private static func writeArtifact(_ data: Data) throws {
        guard let root = repositoryRoot(startingAt: URL(fileURLWithPath: #filePath)) else {
            throw LearningEvalFailure.configuration("Could not find project.yml above the eval source path.")
        }
        let directory = root.appendingPathComponent("build/eval", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("learning-expression-translation-only.json"), options: .atomic)
    }

    private static func repositoryRoot(startingAt sourceURL: URL) -> URL? {
        var candidate = sourceURL.deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("project.yml").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private static func encode(_ report: LearningExpressionEvalReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }
}

/// Missing local eval setup is a test failure after explicit opt-in, never an empty report.
private enum LearningEvalFailure: LocalizedError {
    case configuration(String)

    var errorDescription: String? {
        guard case .configuration(let message) = self else { return nil }
        return message
    }
}

private struct LearningTranslationEvalCase {
    let category: String
    let sourceLanguage: LearningLanguage
    let targetLanguage: LearningLanguage
    let source: String
}

/// The artifact retains model configuration, prompt, output, and latency for manual comparison;
/// it deliberately records no score because a short translation has no simple quality metric.
private struct LearningExpressionEvalReport: Encodable {
    let model: String
    let endpoint: String
    let generatedAt: String
    let translationOptions: LearningEvalGenerationOptions
    let translations: [LearningTranslationEvalResult]
}

private struct LearningEvalGenerationOptions: Encodable {
    let maxPredictionTokens: Int
    let temperature: Double
    let topP: Double
}

private struct LearningTranslationEvalResult: Encodable {
    let category: String
    let sourceLanguage: LearningLanguage
    let targetLanguage: LearningLanguage
    let source: String
    let prompt: String
    let translation: String
    let latencyMilliseconds: Double
}
