import Foundation
import Testing
@testable import Cotabby

/// Regression tests for passive word-hint policy. The source picker limits what text can be sent,
/// and the decoder accepts only a small, safe JSON value before it can reach the hint card.
@Suite
struct LearningHintPolicyTests {
    @Test
    func sourceReturnsOnlyTheLastCommittedWord() throws {
        #expect(LearningHintPolicy.source(in: "We should learn vocabulary, ", language: .english) == "vocabulary")
        #expect(LearningHintPolicy.source(in: "This sentence ends with a word.\n", language: .english) == "word")
    }

    @Test(arguments: [
        "Open https://example.com",
        "Contact help@example.com",
        "The score is 2048"
    ])
    func sourceRejectsURLsEmailsAndNumericFinalTokens(_ prefix: String) {
        #expect(LearningHintPolicy.source(in: prefix, language: .english) == nil)
    }

    @Test
    func sourceRejectsAnOverlongFinalWordButKeepsTheInclusiveLimit() {
        let atLimit = String(repeating: "x", count: 24)
        let overLimit = String(repeating: "x", count: 25)

        #expect(LearningHintPolicy.source(in: "Learn \(atLimit)", language: .english) == atLimit)
        #expect(LearningHintPolicy.source(in: "Learn \(overLimit)", language: .english) == nil)
    }

    @Test
    func sourcePickerUsesTheProvidedCjkLanguageForTheLastToken() {
        #expect(LearningHintPolicy.source(in: "今日は猫", language: .japanese) == "猫")
        #expect(LearningHintPolicy.source(in: "我喜欢猫", language: .chinese) == "猫")
        #expect(LearningHintPolicy.source(in: "我喜歡貓", language: .traditionalChinese) == "貓")
    }

    @Test
    func decoderAcceptsBoundedUnicodeHintAndEmptyExplanationIsRejectedBySafetyGate() throws {
        let hint = try LearningHintPolicy.decode(encodeHint(expression: "猫", explanation: "一种常见动物。"))

        #expect(hint.expression == "猫")
        #expect(hint.explanation == "一种常见动物。")
        // InsertionSafetyGate rejects whitespace-only payloads, so an omitted definition is not
        // accepted as a valid hint even though the JSON schema itself permits an empty string.
        #expect(throws: LearningFailure.self) {
            try LearningHintPolicy.decode(encodeHint(expression: "run", explanation: ""))
        }
    }

    @Test(arguments: ["", " \n\t "])
    func decoderRejectsAnEmptyOrWhitespaceExpression(_ expression: String) throws {
        #expect(throws: LearningFailure.self) {
            try LearningHintPolicy.decode(encodeHint(expression: expression, explanation: "meaning"))
        }
    }

    @Test(arguments: ["\u{0001}", "\u{001B}", "\u{007F}", "\u{FFFD}"])
    func decoderRejectsUnsafeCharactersInEitherField(_ invalid: String) throws {
        #expect(throws: LearningFailure.self) {
            try LearningHintPolicy.decode(encodeHint(expression: "go\(invalid)", explanation: "move"))
        }
        #expect(throws: LearningFailure.self) {
            try LearningHintPolicy.decode(encodeHint(expression: "go", explanation: "move\(invalid)"))
        }
    }

    @Test
    func decoderRejectsFieldAndWholePayloadOverages() throws {
        let longExpression = String(repeating: "a", count: 81)
        let longExplanation = String(repeating: "a", count: 301)
        let oversizedPayload = try encodeHint(expression: "go", explanation: "move", padding: String(repeating: "x", count: 2_100))

        #expect(throws: LearningFailure.self) {
            try LearningHintPolicy.decode(encodeHint(expression: longExpression, explanation: "meaning"))
        }
        #expect(throws: LearningFailure.self) {
            try LearningHintPolicy.decode(encodeHint(expression: "go", explanation: longExplanation))
        }
        #expect(oversizedPayload.utf8.count > 2_000)
        #expect(throws: LearningFailure.self) { try LearningHintPolicy.decode(oversizedPayload) }
        #expect(throws: LearningFailure.self) { try LearningHintPolicy.decode("not JSON") }
    }

    private func encodeHint(expression: String, explanation: String, padding: String? = nil) throws -> String {
        var object: [String: Any] = ["expression": expression, "explanation": explanation]
        if let padding { object["padding"] = padding }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
