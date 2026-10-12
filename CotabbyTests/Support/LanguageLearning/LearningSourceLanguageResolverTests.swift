import Foundation
import Testing
@testable import Cotabby

/// Keeps explicit source choices reliable for short expressions and pins the multi-source
/// confidence rule independently from Natural Language's changing system probabilities.
@Suite
struct LearningSourceLanguageResolverTests {
    private let resolver = LearningSourceLanguageResolver()

    @Test(arguments: ["你好", "您好", "谢谢"])
    func shortChineseExpressionUsesTheOnlyConfiguredSource(_ text: String) {
        #expect(resolver.resolve(
            text: text,
            enabledSourceLanguages: [.chinese],
            targetLanguage: .english
        ) == .chinese)
    }

    @Test
    func shortTextUsesAnExplicitlyChosenLatinOrNonLatinSource() {
        #expect(resolver.resolve(text: "Hi", enabledSourceLanguages: [.english], targetLanguage: .spanish) == .english)
        #expect(resolver.resolve(text: "Hola", enabledSourceLanguages: [.spanish], targetLanguage: .english) == .spanish)
        #expect(resolver.resolve(text: "Привет", enabledSourceLanguages: [.russian], targetLanguage: .english) == .russian)
        #expect(resolver.resolve(text: "ありがとう", enabledSourceLanguages: [.japanese], targetLanguage: .english) == .japanese)
    }

    @Test
    func multipleSourcesConstrainShortChineseRecognitionToEnabledChoices() {
        // The exact probabilities vary by macOS version. This checks only that constraints keep a
        // script-variant hypothesis from rejecting the configured Chinese source direction.
        #expect(resolver.resolve(
            text: "你好",
            enabledSourceLanguages: [.chinese, .english],
            targetLanguage: .french
        ) == .chinese)
    }

    @Test
    func trimsInputAndRejectsTextWithoutLettersOrAnEligibleSource() {
        #expect(resolver.resolve(text: "  \n\t  ", enabledSourceLanguages: [.chinese], targetLanguage: .english) == nil)
        #expect(resolver.resolve(text: "123 !!!", enabledSourceLanguages: [.chinese], targetLanguage: .english) == nil)
        #expect(resolver.resolve(text: "hello", enabledSourceLanguages: [.english], targetLanguage: .english) == nil)
        #expect(resolver.resolve(text: "hello", enabledSourceLanguages: [], targetLanguage: .english) == nil)
    }

    @Test
    func duplicateSourceChoicesStillResolveAsOneExplicitPreference() {
        #expect(resolver.resolve(
            text: " 你好 ",
            enabledSourceLanguages: [.chinese, .chinese],
            targetLanguage: .english
        ) == .chinese)
    }

    @Test
    func requiresMinimumConfidenceAndMarginAndRejectsTies() {
        #expect(LearningSourceLanguageResolver.confidentLanguage(from: [.chinese: 0.75, .english: 0.60]) == .chinese)
        #expect(LearningSourceLanguageResolver.confidentLanguage(from: [.chinese: 0.549, .english: 0.10]) == nil)
        #expect(LearningSourceLanguageResolver.confidentLanguage(from: [.chinese: 0.70, .english: 0.56]) == nil)
        #expect(LearningSourceLanguageResolver.confidentLanguage(from: [.chinese: 0.70, .english: 0.70]) == nil)
        #expect(LearningSourceLanguageResolver.confidentLanguage(from: [:]) == nil)
    }
}
