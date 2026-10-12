import Testing
@testable import Cotabby

struct LearningAutomaticLanguagePolicyTests {
    @Test(arguments: [
        ("你好", LearningLanguage.chinese, true), ("謝謝", .traditionalChinese, true),
        ("nihao", .chinese, false), ("I can do it.", .chinese, false),
        ("안녕", .korean, true), ("hello", .korean, false),
        ("こんにちは", .japanese, true), ("日本", .japanese, true),
        ("Привет", .russian, true), ("привет", .english, false),
        ("नमस्ते", .hindi, true), ("مرحبا", .arabic, true),
        ("Café", .french, true), ("", .english, false)
    ])
    func automaticRequestsRequireTheConfiguredSourceScript(_ text: String, _ language: LearningLanguage, _ expected: Bool) {
        #expect(LearningAutomaticLanguagePolicy.accepts(text, sourceLanguage: language) == expected)
    }
}
