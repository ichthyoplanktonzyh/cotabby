import Testing
@testable import Cotabby

struct LearningDictionaryTextTests {
    @Test
    func retainsRealParagraphsWithoutInventingSenseFields() {
        #expect(LearningDictionaryText.paragraphs("  can\r\n\nmodal verb\n1. be able to\n\nExample: I can do it. ") ==
            ["can", "modal verb", "1. be able to", "Example: I can do it."])
    }

    @Test
    func longTextIsBoundedAndReflowedAtSentences() {
        let sentence = "This is a dictionary example with a full sentence. "
        let result = LearningDictionaryText.paragraphs(String(repeating: sentence, count: 200))
        #expect(result.count > 1)
        #expect(result.joined().count <= 8_000)
        #expect(result.dropLast().allSatisfy { $0.hasSuffix(".") })
        #expect(result.allSatisfy { !$0.isEmpty })
        let normalize: (String) -> String = { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        #expect(normalize(result.joined(separator: " ")) == normalize(String(String(repeating: sentence, count: 200).prefix(8_000))))
    }
}
