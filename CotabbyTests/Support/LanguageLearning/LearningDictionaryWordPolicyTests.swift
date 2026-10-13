import Foundation
import NaturalLanguage
import Testing
@testable import Cotabby

struct LearningDictionaryWordPolicyTests {
    @Test
    func repeatedWordsKeepTheirClickedOccurrence() {
        let text = "You can do it, and you can learn."
        let range = (text as NSString).range(of: "can", options: .backwards)
        let word = LearningDictionaryWordPolicy.word(atUTF16Location: range.location + 1, in: text, language: .english)
        #expect(word == .init(text: "can", range: range))
    }

    @Test(arguments: [-1, 3, 4, 5, 6, 100])
    func whitespacePunctuationAndInvalidOffsetsDoNotLookUp(_ location: Int) {
        #expect(LearningDictionaryWordPolicy.word(atUTF16Location: location, in: "can,  ", language: .english) == nil)
    }

    @Test
    func unicodeOffsetsAndNonLatinTargetsUseTheSamePolicy() {
        let text = "🙂 학교에 가요."
        let range = (text as NSString).range(of: "학교")
        let word = LearningDictionaryWordPolicy.word(atUTF16Location: range.location, in: text, language: .korean)
        #expect(word?.text.contains("학교") == true)
        #expect(word.map { (text as NSString).substring(with: $0.range) == $0.text } == true)
        #expect(LearningDictionaryWordPolicy.word(atUTF16Location: 1, in: text, language: .korean) == nil)
        #expect(LearningDictionaryWordPolicy.word(atUTF16Location: 0, in: "你好世界", language: .simplifiedChinese) != nil)
    }
}
