import AppKit
import Testing
@testable import Cotabby

/// Exercise native glyph hits using a local view, without an editor, system dictionary or global
/// input events. Whole-app rendering and real popup acceptance wait for the combined app build.
@MainActor
struct LearningSentenceDictionaryTextTests {
    @Test
    func anyInternalWordOpensTheWholeExpressionAndNeutralMarksNeverChangeText() throws {
        let view = LearningDictionaryTextView(frame: CGRect(x: 0, y: 0, width: 350, height: 100), textContainer: nil)
        view.font = .systemFont(ofSize: 16)
        let text = "I look forward to seeing you."
        let range = (text as NSString).range(of: "look forward to")
        let unit = LearningUnit(id: range.location, surface: "look forward to", query: "look forward to",
            kind: .expression, ranges: [range], words: LearningUnitPolicy.words(in: "look forward to", language: .english))
        view.units = [unit]
        view.present(text, selectedChunk: nil)
        _ = view.measuredSize(width: 350)
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        let target = (text as NSString).range(of: "forward")
        let glyphs = manager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
        var queried: LearningUnit?
        view.lookupUnit = { anchor, _ in queried = anchor.unit }
        view.handleClick(at: .init(x: bounds.midX + view.textContainerOrigin.x, y: bounds.midY + view.textContainerOrigin.y), count: 2)
        #expect(queried == unit)
        #expect(view.string == text)
        #expect(view.textStorage?.attribute(.underlineStyle, at: target.location, effectiveRange: nil) != nil)
        #expect(view.textStorage?.attribute(.backgroundColor, at: target.location, effectiveRange: nil) == nil)
        #expect(!view.acceptsFirstResponder)
    }

    @Test
    func doubleClickLooksUpTheWordAndSingleClickLeavesInputFocusAlone() throws {
        let view = LearningDictionaryTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 80), textContainer: nil)
        view.font = .systemFont(ofSize: 16)
        view.string = "I like you."
        view.language = .english
        var words: [LearningDictionaryWord] = []
        view.lookup = { anchor, _ in words.append(anchor.word) }
        _ = view.measuredSize(width: 300)
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        let range = (view.string as NSString).range(of: "like")
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let point = NSPoint(x: bounds.midX + view.textContainerOrigin.x, y: bounds.midY + view.textContainerOrigin.y)
        view.handleClick(at: point, count: 1)
        #expect(words.isEmpty)
        view.handleClick(at: point, count: 2)
        #expect(words == [.init(text: "like", range: range)])
        #expect(!view.acceptsFirstResponder)
        #expect(view.string == "I like you.")
        view.handleClick(at: NSPoint(x: 299, y: 79), count: 2)
        #expect(words.count == 1)
    }
}
