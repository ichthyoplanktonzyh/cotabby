import Foundation
import Testing
@testable import Cotabby

/// Counts canonicalization work, not wall time, so unchanged inputs must demonstrate actual reuse.
@MainActor
struct ModelContextIdentityCacheTests {
    @Test
    func repeatedReadsAndEndpointEditsKeepOnlyTwoUsefulDestinations() {
        var computations = 0
        var cache = ModelContextIdentityCache { input in
            computations += 1
            return ModelContextBudget.identity(backend: input.backend, model: input.model,
                                               baseURL: input.baseURL, mode: input.mode)
        }
        func identity(_ engine: SuggestionEngineKind, model: String = "a.gguf", url: String = "", endpoint: String = "") -> String {
            cache.identity(engine: engine, localModel: model, baseURL: url, endpointModel: endpoint, mode: .chatCompletions)
        }
        let local = identity(.llamaOpenSource)
        for _ in 0..<1_000 { #expect(identity(.llamaOpenSource, url: "ignored", endpoint: "ignored") == local) }
        #expect(computations == 1)
        _ = identity(.openAICompatible, url: "https://example.invalid/v1", endpoint: "first")
        for _ in 0..<100 { _ = identity(.llamaOpenSource) }
        #expect(computations == 2, "The endpoint slot must not evict the local fallback")
        _ = identity(.openAICompatible, url: "https://example.invalid/v1", endpoint: "second")
        #expect(computations == 3)
        _ = identity(.openAICompatible, url: "https://example.invalid/v1", endpoint: "first")
        #expect(computations == 4, "Old typed destinations are evicted rather than accumulating")
        #expect(identity(.llamaOpenSource) == local)
        #expect(identity(.llamaOpenSource, model: "b.gguf") != local)
        #expect(computations == 5)
    }

    @Test
    func emittedEndpointAndModelValuesDoNotReadWillSetEraStorage() throws {
        let suite = "cotabby.test.context-memo.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.selectEngine(.openAICompatible)
        settings.setCompletionLocalModelFilename("first.gguf")
        var values: [SuggestionSettingsSnapshot] = []
        let subscription = settings.snapshotPublisher.sink { values.append($0) }
        defer { subscription.cancel() }
        settings.setOpenAICompatibleBaseURL("https://example.invalid/v1")
        settings.setOpenAICompatibleModelName("new-model")
        #expect(values.last?.completionModelIdentity == SuggestionSettingsModel.completionContextIdentity(
            engine: .openAICompatible, localModel: "first.gguf", baseURL: "https://example.invalid/v1",
            endpointModel: "new-model", mode: settings.openAICompatibleAPIMode))
        settings.setCompletionLocalModelFilename("second.gguf")
        #expect(values.last?.localModelIdentity == SuggestionSettingsModel.completionContextIdentity(
            engine: .llamaOpenSource, localModel: "second.gguf", baseURL: "", endpointModel: "", mode: .chatCompletions))
        #expect(settings.snapshot == values.last)
    }

    @Test
    func runtimeFilenameAndLearningEndpointChangesUseTheirOwnBudgets() throws {
        let suite = "cotabby.test.context-destinations.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.selectEngine(.llamaOpenSource)
        settings.setCompletionLocalModelFilename("first.gguf")
        settings.setCompletionContextWindowTokens(16_384)
        settings.setCompletionLocalModelFilename("second.gguf")
        settings.setCompletionContextWindowTokens(24_576)
        #expect(settings.localCompletionContextWindowTokens(modelFilename: "first.gguf") == 16_384)
        #expect(settings.localCompletionContextWindowTokens(modelFilename: "second.gguf") == 24_576)
        settings.setCompletionContextWindowTokens(nil)
        #expect(settings.localCompletionContextWindowTokens(modelFilename: "second.gguf") == nil)

        let translation = settings.languageLearning.translation
        translation.backend = .local
        translation.localModel = "first.gguf"
        translation.setContextWindowTokens(16_384)
        for _ in 0..<100 { #expect(translation.snapshot.contextWindowTokens == 16_384) }
        translation.backend = .endpoint
        translation.endpointModel = "same-model"
        translation.baseURL = "https://first.invalid/v1"
        translation.setContextWindowTokens(65_536)
        translation.baseURL = "https://second.invalid/v1"
        #expect(translation.snapshot.contextWindowTokens == 8_192)
        translation.baseURL = "https://first.invalid/v1"
        #expect(translation.snapshot.contextWindowTokens == 65_536)
        translation.backend = .local
        #expect(translation.snapshot.contextWindowTokens == 16_384)
    }
}
