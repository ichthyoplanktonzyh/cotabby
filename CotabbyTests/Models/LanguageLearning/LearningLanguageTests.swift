import Foundation
import Testing
@testable import Cotabby

/// Guards the language identifiers and value models shared by settings, prompt selection, and
/// language direction. The enum reuses `LanguageCatalog`'s established codes and labels, so these
/// tests catch accidental drift between durable language settings and the catalog.
@Suite
struct LearningLanguageTests {
    @Test
    func everyCatalogLanguageHasExactlyOneLearningLanguageIdentifier() {
        let catalogCodes = Set(LanguageCatalog.commonLanguages.map(\.code))
        let learningCodes = LearningLanguage.allCases.map(\.rawValue)

        #expect(LearningLanguage.allCases.count == 14)
        #expect(Set(learningCodes).count == learningCodes.count)
        #expect(Set(learningCodes) == catalogCodes)
    }

    @Test(arguments: LearningLanguage.allCases)
    func languageNamesAndNativeLabelsMatchTheExistingCatalog(_ language: LearningLanguage) throws {
        let option = try #require(LanguageCatalog.commonLanguages.first { $0.code == language.rawValue })

        #expect(language.name == option.name)
        #expect(language.label == option.nativeLabel)
    }

    @Test
    func chineseTokenizerLocalesMatchTheirScriptIdentifiers() {
        #expect(LearningLanguage.chinese.naturalLanguage.rawValue == "zh-Hans")
        #expect(LearningLanguage.traditionalChinese.naturalLanguage.rawValue == "zh-Hant")
    }

    @Test
    func languageIdentifiersEncodeAsStableCatalogCodes() throws {
        let data = try JSONEncoder().encode(LearningLanguage.chinese)

        #expect(String(decoding: data, as: UTF8.self) == "\"zh-Hans\"")
        #expect(try JSONDecoder().decode(LearningLanguage.self, from: data) == .chinese)
        #expect(LearningLanguage(rawValue: "unsupported") == nil)
    }

    @Test
    func translationTasksKeepTheirTargetLanguage() {
        let tasks: [LearningExpressionTask] = [
            .translation(source: .chinese, target: .spanish),
            .translation(source: .japanese, target: .arabic)
        ]

        #expect(tasks.map(\.target) == [.spanish, .arabic])
    }
}
