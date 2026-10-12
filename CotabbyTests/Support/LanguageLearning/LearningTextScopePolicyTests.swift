import Foundation
import Testing
@testable import Cotabby

/// Tests the pure boundary that turns an editor value and UTF-16 selection/caret into source text.
/// It keeps whole graphemes and bounded complete sentences intact before any translation request is
/// formed, while leaving the older Chinese-only `selectedText` compatibility policy covered by the
/// neighboring vocabulary tests.
@Suite
struct LearningTextScopePolicyTests {
    @Test
    func explicitSelectionTakesPriorityAndPreservesItsExactSpelling() throws {
        let value = "First sentence. 请只转换这里！Another sentence."
        let selected = "请只转换这里"
        let range = (value as NSString).range(of: selected)

        let resolved = try LearningTextScopePolicy.conversionRange(value: value, selection: range)

        #expect(resolved == range)
        #expect(try LearningTextScopePolicy.text(value: value, range: resolved) == selected)
    }

    @Test
    func emptySelectionResolvesToTheSentenceContainingTheCaret() throws {
        let value = "First sentence. The cursor is here! Third sentence."
        let cursorWord = (value as NSString).range(of: "cursor")
        let caret = NSRange(location: cursorWord.location + 2, length: 0)

        let range = try LearningTextScopePolicy.conversionRange(value: value, selection: caret)
        let sentence = try LearningTextScopePolicy.text(value: value, range: range)

        #expect(sentence.contains("The cursor is here!"))
        #expect(!sentence.contains("First sentence."))
        #expect(!sentence.contains("Third sentence."))
    }

    @Test
    func caretAfterSentenceTrailingWhitespaceStillFindsTheCompletedSentence() throws {
        let value = "The final sentence is complete.   "
        let caret = NSRange(location: (value as NSString).length, length: 0)

        let range = try LearningTextScopePolicy.conversionRange(value: value, selection: caret)
        let sentence = try LearningTextScopePolicy.text(value: value, range: range)

        #expect(sentence.trimmingCharacters(in: .whitespacesAndNewlines) == "The final sentence is complete.")
    }

    @Test
    func caretAtTheNextSentenceStartSelectsTheNextSentence() throws {
        let value = "The previous sentence ends here.   This sentence starts here! Last sentence."
        let nextSentence = (value as NSString).range(of: "This sentence")

        let range = try LearningTextScopePolicy.conversionRange(
            value: value,
            selection: NSRange(location: nextSentence.location, length: 0)
        )
        let sentence = try LearningTextScopePolicy.text(value: value, range: range)

        #expect(sentence.contains("This sentence starts here!"))
        #expect(!sentence.contains("The previous sentence"))
        #expect(!sentence.contains("Last sentence."))
    }

    @Test
    func caretNearChineseUsesTheLocalSentenceInAMixedLanguageDocument() throws {
        let olderEnglish = String(repeating: "Earlier English context remains in the document. ", count: 250)
        let target = "我今天没有时间，可能明天再安排。"
        let newerEnglish = String(repeating: "Later English context remains in the document. ", count: 250)
        let value = olderEnglish + target + newerEnglish
        let targetWord = (value as NSString).range(of: "可能明天")

        let range = try LearningTextScopePolicy.conversionRange(
            value: value,
            selection: NSRange(location: targetWord.location + 2, length: 0)
        )
        let sentence = try LearningTextScopePolicy.text(value: value, range: range)

        #expect(sentence.contains(target))
        #expect(!sentence.contains("Earlier English"))
        #expect(!sentence.contains("Later English"))
    }

    @Test
    func currentSentenceInALongDocumentIsReturnedWhole() throws {
        let olderSentences = String(repeating: "Earlier paragraph stays outside the selected sentence. ", count: 300)
        let target = "The complete sentence around the caret must survive the document window."
        let newerSentences = String(repeating: "Later paragraph stays outside the selected sentence. ", count: 300)
        let value = olderSentences + target + " " + newerSentences
        let caretWord = (value as NSString).range(of: "caret")

        let range = try LearningTextScopePolicy.conversionRange(
            value: value,
            selection: NSRange(location: caretWord.location + 2, length: 0)
        )
        let sentence = try LearningTextScopePolicy.text(value: value, range: range)

        #expect(sentence.contains(target))
        #expect(!sentence.contains("Earlier paragraph"))
        #expect(!sentence.contains("Later paragraph"))
    }

    @Test
    func textReturnsTheCompleteUnicodeGraphemesWithoutRewritingThem() throws {
        let value = "A👩🏽‍💻e\u{301}中文"
        let wholeValue = NSRange(location: 0, length: (value as NSString).length)

        #expect(try LearningTextScopePolicy.text(value: value, range: wholeValue) == value)
    }

    @Test(arguments: ["👩🏽‍💻", "e\u{301}"])
    func textRejectsRangesThatCutAComposedGrapheme(_ grapheme: String) {
        let value = "A\(grapheme)中文"
        let graphemeRange = (value as NSString).range(of: grapheme)
        let partialRange = NSRange(location: graphemeRange.location + 1, length: (value as NSString).length - graphemeRange.location - 1)

        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.text(value: value, range: partialRange)
        }
    }

    @Test(arguments: ["👩🏽‍💻", "e\u{301}"])
    func emptySelectionRejectsCaretInsideAComposedGrapheme(_ grapheme: String) {
        let value = "A\(grapheme)中文"
        let graphemeRange = (value as NSString).range(of: grapheme)
        let caretInside = NSRange(location: graphemeRange.location + 1, length: 0)

        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.conversionRange(value: value, selection: caretInside)
        }
    }

    @Test
    func rangeValidationRejectsOverflowingAndEmptyScopes() {
        let value = "A sentence."

        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.conversionRange(
                value: value,
                selection: NSRange(location: Int.max, length: 1)
            )
        }
        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.conversionRange(value: "   ", selection: NSRange(location: 1, length: 0))
        }
        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.text(value: "😀!?", range: NSRange(location: 0, length: 4))
        }
    }

    @Test
    func sourceAtTheByteLimitIsAcceptedAndLongerSourceIsRejectedWhole() throws {
        let atLimit = String(repeating: "a", count: 6_000)
        let overLimit = String(repeating: "a", count: 6_001)
        let atLimitRange = NSRange(location: 0, length: (atLimit as NSString).length)
        let overLimitRange = NSRange(location: 0, length: (overLimit as NSString).length)
        let oversizedSentence = String(repeating: "language ", count: 750) + "lesson."

        #expect(try LearningTextScopePolicy.text(value: atLimit, range: atLimitRange) == atLimit)
        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.text(value: overLimit, range: overLimitRange)
        }
        #expect(throws: LearningFailure.self) {
            try LearningTextScopePolicy.conversionRange(
                value: oversizedSentence,
                selection: NSRange(location: 3_000, length: 0)
            )
        }
    }
}
