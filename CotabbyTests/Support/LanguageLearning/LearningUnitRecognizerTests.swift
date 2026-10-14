import Foundation
import Testing
@testable import Cotabby

struct LearningUnitRecognizerTests {
    private func entry(_ head: String, forms: [String] = [], language: String = "en") -> LearningLexiconEntry {
        .init(id: head, language: language, headword: head, forms: forms,
            senses: [.init(partOfSpeech: "verb", definitions: ["An expression."], labels: [])],
            sourceURL: "https://en.wiktionary.org/wiki/test")
    }

    @Test
    func preservesExpressionAndLeavesItsComplementAsIndependentWords() {
        let text = "I look forward to seeing you."
        let recognizer = LearningUnitRecognizer(entries: [entry("look forward to")])
        let units = recognizer.recognize(text, language: .english)
        #expect(units.map(\.surface) == ["I", "look forward to", "seeing", "you"])
        #expect(units[1].words.map(\.text) == ["look", "forward", "to"])
        #expect((text as NSString).substring(with: units[1].ranges[0]) == units[1].surface)
        #expect(LearningUnitPolicy.unit(at: 8, units: units)?.surface == "look forward to")
        #expect(text == "I look forward to seeing you.")
    }

    @Test
    func explicitInflectedFormsMatchButUnknownVariantsAndPunctuationDoNot() {
        let recognizer = LearningUnitRecognizer(entries: [entry("look forward to", forms: ["looking forward to", "looked forward to"])])
        #expect(recognizer.recognize("I'm looking forward to it.", language: .english).contains { $0.kind == .expression && $0.surface == "looking forward to" })
        #expect(!recognizer.recognize("lookz forward to it", language: .english).contains { $0.kind == .expression })
        #expect(!recognizer.recognize("look, forward to it", language: .english).contains { $0.kind == .expression })
        #expect(!recognizer.recognize("look\nforward to it", language: .english).contains { $0.kind == .expression })
    }

    @Test
    func possessiveSlotsRemainSeparatelyClickableInsideAKnownPattern() {
        let recognizer = LearningUnitRecognizer(entries: [entry("take one's time")])
        let text = "Please take your time."
        let units = recognizer.recognize(text, language: .english)
        let pattern = units.first { $0.kind == .pattern }
        #expect(pattern?.query == "take one's time")
        #expect(pattern?.ranges.count == 2)
        #expect(LearningUnitPolicy.unit(at: (text as NSString).range(of: "your").location, units: units)?.kind == .word)
        #expect(!recognizer.recognize("take cake time", language: .english).contains { $0.kind == .pattern })
    }

    @Test
    func slotsRejectContractionsAndArbitraryVerbs() {
        let recognizer = LearningUnitRecognizer(entries: [entry("one's own boss"),
            entry("a little of something goes a long way")])
        #expect(!recognizer.recognize("it's own boss", language: .english).contains { $0.kind == .pattern })
        #expect(recognizer.recognize("your own boss", language: .english).contains { $0.kind == .pattern })
        #expect(!recognizer.recognize("a little of goes goes a long way", language: .english).contains { $0.kind == .pattern })
        #expect(recognizer.recognize("a little of it goes a long way", language: .english).contains { $0.kind == .pattern })
    }

    @Test
    func unicodeOccurrenceRangesAndRepeatsRemainDistinct() {
        let text = "😀 gracias a ti; gracias a él."
        let units = LearningUnitRecognizer(entries: [entry("gracias a", language: "es")]).recognize(text, language: .spanish)
        let expressions = units.filter { $0.kind == .expression }
        #expect(expressions.count == 2)
        #expect(expressions[0].id != expressions[1].id)
        #expect(expressions.allSatisfy { (text as NSString).substring(with: $0.ranges[0]) == "gracias a" })
    }

    @Test
    func isolatedVerbFormsNeverBecomeCompleteExpressionHits() {
        let recognizer = LearningUnitRecognizer(entries: [entry("it figures", forms: ["figures"]),
            entry("go jump in the lake", forms: ["go"])])
        #expect(recognizer.lookup("go").isEmpty && recognizer.lookup("figures").isEmpty)
        #expect(recognizer.recognize("Those figures look good. Go now.", language: .english).allSatisfy { $0.kind == .word })
    }
}
