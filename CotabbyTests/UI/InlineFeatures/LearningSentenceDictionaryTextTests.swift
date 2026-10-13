import AppKit
import Testing
@testable import Cotabby

/// Exercise native glyph hits using a local view, without an editor, system dictionary or global
/// input events. Whole-app rendering and real popup acceptance wait for the combined app build.
@MainActor
struct LearningSentenceDictionaryTextTests {
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
