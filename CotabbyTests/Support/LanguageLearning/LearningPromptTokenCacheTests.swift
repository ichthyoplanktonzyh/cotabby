import Foundation
import Testing
@testable import Cotabby

struct LearningPromptTokenCacheTests {
    private let configuration = LearningLocalModelConfiguration(
        modelURL: URL(fileURLWithPath: "/fixture/model.gguf"), template: .automatic, contextWindowTokens: 8_192)

    @Test
    func exactPlanIsConsumedOnceAndResetRetiresVocabularyWork() {
        var cache = LearningPromptTokenCache()
        cache.store(configuration: configuration, prompt: "target", template: .hyMT, tokens: [1, 2, 3])
        #expect(cache.take(configuration: configuration, prompt: "target", template: .hyMT) == [1, 2, 3])
        #expect(cache.take(configuration: configuration, prompt: "target", template: .hyMT) == nil)
        cache.store(configuration: configuration, prompt: "target", template: .hyMT, tokens: [4])
        cache.reset()
        #expect(cache.take(configuration: configuration, prompt: "target", template: .hyMT) == nil)
    }

    @Test(arguments: ["prompt", "model", "context", "configured-template", "resolved-template"])
    func mismatchesDiscardThePendingPlan(_ change: String) {
        var cache = LearningPromptTokenCache()
        cache.store(configuration: configuration, prompt: "target", template: .hyMT, tokens: [1])
        let changed = LearningLocalModelConfiguration(
            modelURL: change == "model" ? URL(fileURLWithPath: "/fixture/other.gguf") : configuration.modelURL,
            template: change == "configured-template" ? .chatML : configuration.template,
            contextWindowTokens: change == "context" ? 4_096 : configuration.contextWindowTokens)
        #expect(cache.take(configuration: changed, prompt: change == "prompt" ? "other" : "target",
                           template: change == "resolved-template" ? .chatML : .hyMT) == nil)
        #expect(cache.take(configuration: configuration, prompt: "target", template: .hyMT) == nil)
    }

    @Test
    func onlyTheMostRecentPlanIsRetained() {
        var cache = LearningPromptTokenCache()
        cache.store(configuration: configuration, prompt: "old", template: .hyMT, tokens: [1])
        cache.store(configuration: configuration, prompt: "new", template: .hyMT, tokens: [2])
        #expect(cache.take(configuration: configuration, prompt: "new", template: .hyMT) == [2])
        #expect(cache.take(configuration: configuration, prompt: "old", template: .hyMT) == nil)
    }

    @Test
    func budgetPayloadBelongsToWinningCandidateRatherThanLastProbe() throws {
        let expected = try LearningTranslationPrompt.render(
            input: .init(source: "target", referenceBefore: "b"), sourceLanguage: .chinese,
            targetLanguage: .english, family: .generic)
        let bare = try LearningTranslationPrompt.render(
            source: "target", sourceLanguage: .chinese, targetLanguage: .english, family: .generic)
        var measured: [String] = []
        let plan = try LearningTranslationBudget.plan(
            input: .init(source: "target", referenceBefore: "ab"), sourceLanguage: .chinese,
            targetLanguage: .english, limits: .init(family: .generic, total: 1_024, output: 256, estimated: false)
        ) { text in
            measured.append(text)
            return (text == bare.prompt || text == expected.prompt ? 1 : 10_000, Array(text.utf8))
        }
        #expect(plan.request.prompt == expected.prompt)
        #expect(plan.payload == Array(expected.prompt.utf8))
        #expect(measured.last != plan.request.prompt, "The final oversized probe must not replace the winning payload")
    }

    @Test
    func aSentenceWithoutReferenceIsMeasuredOnce() throws {
        var measurements = 0
        let plan = try LearningTranslationBudget.plan(
            input: .init(source: "你好。"), sourceLanguage: .chinese, targetLanguage: .english,
            limits: .init(family: .translateGemma, total: 8_192, output: 2_048, estimated: false)
        ) { text in
            measurements += 1
            return (90, Array(text.utf8))
        }
        #expect(measurements == 1)
        #expect(plan.payload == Array(plan.request.prompt.utf8))
    }
}
