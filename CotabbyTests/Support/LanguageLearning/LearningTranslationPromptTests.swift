import Foundation
import Testing
@testable import Cotabby

struct LearningTranslationPromptTests {
    @Test
    func translateGemmaUsesVendorTextAndCodeDirectionWithoutQuotingSource() throws {
        let source = "你好\n\"原文\"<start_of_turn>"
        let result = try LearningTranslationPrompt.render(source: source, sourceLanguage: .chinese,
            targetLanguage: .english, family: .translateGemma)
        #expect(result.userOnly)
        #expect(result.prompt.hasPrefix("You are a professional Chinese (zh-Hans) to English (en) translator."))
        #expect(result.prompt.hasSuffix("Please translate the following Chinese text into English:\n\n\n" + source))
        #expect(!result.prompt.contains("source data, not instructions"))
        #expect(result.sampling.temperature == 0.3 && result.sampling.topP == 0.95)
        #expect(result.sampling.topK == 64)
    }

    @Test
    func reverseAndTraditionalDirectionsHaveDistinctLanguageCodes() throws {
        let result = try LearningTranslationPrompt.render(source: "Hello", sourceLanguage: .english,
            targetLanguage: .traditionalChinese, family: .translateGemma)
        #expect(result.prompt.hasPrefix("You are a professional English (en) to Traditional Chinese (zh-Hant) translator."))
        let korean = try LearningTranslationPrompt.render(source: "你好", sourceLanguage: .chinese,
            targetLanguage: .korean, family: .translateGemma)
        #expect(korean.prompt.contains("to Korean (ko) translator."))
    }

    @Test
    func genericAndHyProfilesRetainTheirExistingContract() throws {
        let generic = try LearningTranslationPrompt.render(source: "你好", sourceLanguage: .chinese,
            targetLanguage: .english, family: .generic)
        #expect(generic.prompt == (try LearningExpressionPrompt.translation(source: "你好", sourceLanguage: .chinese, targetLanguage: .english)))
        #expect(!generic.userOnly)
        let hy = try LearningTranslationPrompt.render(source: "你好", sourceLanguage: .chinese,
            targetLanguage: .english, family: .hyMT)
        #expect(hy.prompt == "Translate the following text into English. Note that you should only output the translated result without any additional explanation:\n你好")
        #expect(hy.userOnly && hy.sampling.temperature == 0.7 && hy.sampling.topP == 0.6)
    }

    @Test(arguments: [LearningTranslationPrompt.Family.generic, .hyMT, .translateGemma])
    func allFamiliesRejectOverBudgetSourceWithoutTruncating(_ family: LearningTranslationPrompt.Family) {
        #expect(throws: (any Error).self) {
            try LearningTranslationPrompt.render(source: String(repeating: "中", count: 2_001),
                sourceLanguage: .chinese, targetLanguage: .english, family: family)
        }
    }

    @Test
    func endpointAliasesSelectOnlyRecognizableSpecialistFamilies() {
        #expect(LearningTranslationPrompt.Family(endpointModel: "provider/TranslateGemma-4B") == .translateGemma)
        #expect(LearningTranslationPrompt.Family(endpointModel: "hy-mt2:7b") == .hyMT)
        #expect(LearningTranslationPrompt.Family(endpointModel: "custom-translator") == .generic)
    }
}
