import Foundation
import Testing
@testable import Cotabby

struct LearningLexiconServiceTests {
    @Test
    func bundledResourceRecognizesRealExpressionsAndTheirRecordedForms() async throws {
        let url = try #require(Bundle.main.url(forResource: "learning-expressions", withExtension: "json"))
        let service = LearningLexiconService(resourceURL: url)
        let units = try await service.recognize("I look forward to seeing you.", language: .english)
        #expect(units.map(\.surface) == ["I", "look forward to", "seeing", "you"])
        let result = try await service.lookup("looking forward to", language: .english, expression: true)
        guard case .entries(let entries) = result else { Issue.record("Explicit inflected expression should resolve to its dictionary entry"); return }
        #expect(entries.contains { $0.headword == "look forward to" && !$0.senses.isEmpty })
        #expect(entries.allSatisfy { $0.sourceURL.hasPrefix("https://en.wiktionary.org/") })
        #expect(try await service.lookup("blorblytastic snorf", language: .english, expression: true) == .notFound)
        for word in ["go", "figures"] {
            if case .entries = try await service.lookup(word, language: .english, expression: false) {
                Issue.record("A constituent word must not receive a whole-expression entry")
            }
        }
    }

    @Test
    func missingResourceIsAnUnavailableStateForExpressions() async {
        let service = LearningLexiconService(resourceURL: nil)
        await #expect(throws: LearningFailure.self) {
            try await service.lookup("look forward to", language: .english, expression: true)
        }
    }

    @Test(arguments: [("a pesar de", LearningLanguage.spanish),
                      ("auf jeden Fall", LearningLanguage.german),
                      ("afin de", LearningLanguage.french),
                      ("안녕하세요", LearningLanguage.korean),
                      ("一举两得", LearningLanguage.chinese),
                      ("一舉兩得", LearningLanguage.traditionalChinese)])
    func recordedNonEnglishExpressionsRemainWholeClickUnits(_ sample: (String, LearningLanguage)) async throws {
        let service = LearningLexiconService(resourceURL: try #require(Bundle.main.url(forResource: "learning-expressions", withExtension: "json")))
        let units = try await service.recognize(sample.0, language: sample.1)
        #expect(units.contains { $0.surface == sample.0 && $0.kind == .expression })
        guard case .entries(let entries) = try await service.lookup(sample.0, language: sample.1, expression: true) else {
            Issue.record("A recorded expression should retain its own entry"); return
        }
        let code = sample.1 == .chinese || sample.1 == .traditionalChinese ? "zh" : sample.1.rawValue
        #expect(entries.allSatisfy { $0.language == code })
    }
}
