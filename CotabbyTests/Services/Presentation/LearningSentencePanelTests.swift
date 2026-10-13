import AppKit
import Testing
@testable import Cotabby

@Suite(.serialized)
@MainActor
struct LearningSentencePanelTests {
    @Test
    func compactLookupSurvivesAnalysisUpdatesAndClosesWithInputPreview() async throws {
        var dictionarySource: NSWindow?
        let dictionary = LearningSystemDictionaryPresenter { view, _, _ in dictionarySource = view.window }
        let panel = LearningSentencePanel(dictionary: dictionary)
        defer { panel.hide() }
        let id = UUID()
        func presentation(chunks: [LearningMeaningChunk]) -> LearningSentencePresentation {
            .init(id: id, source: "我喜欢你", translation: "I like you.", chunks: chunks,
                sourceLanguage: .chinese, targetLanguage: .english,
                caret: CGRect(x: 180, y: 220, width: 1, height: 18), isExpanded: false, isGenerating: true,
                message: "正在准备语块对应…", previousTranslation: nil, shortcutLabel: "⌥T")
        }
        panel.show(presentation(chunks: []), expand: {}, dismiss: {})
        // SwiftUI assigns width before the fitted height/window transaction finishes. A real
        // click can only target painted content; wait for that same geometry in this fixture.
        await waitUntil {
            guard let view = self.textView(in: panel) else { return false }
            return view.frame.width > 0 && view.frame.height > 0 && view.visibleRect.contains(view.bounds)
        }
        let view = try #require(textView(in: panel))
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let range = (view.string as NSString).range(of: "like")
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let originalLookup = view.lookup
        var clickedWord: LearningDictionaryWord?
        view.lookup = { anchor, view in clickedWord = anchor.word; originalLookup(anchor, view) }
        view.handleClick(at: NSPoint(x: bounds.midX + view.textContainerOrigin.x,
            y: bounds.midY + view.textContainerOrigin.y), count: 2)
        #expect(clickedWord == .init(text: "like", range: range))
        let source = try #require(dictionarySource)
        #expect(source.isVisible)
        panel.show(presentation(chunks: [.init(id: 0, sourceRanges: [.init(location: 1, length: 2)],
            targetRanges: [.init(location: 2, length: 4)])]), expand: {}, dismiss: {})
        #expect(source.isVisible, "Background analysis must not close the fixed translation's word lookup")
        panel.hide()
        #expect(!source.isVisible)
    }

    private func textView(in panel: LearningSentencePanel) -> LearningDictionaryTextView? {
        NSApp.windows.first { $0.frame == panel.visibleFrame && $0.title == "表达学习" }
            .flatMap { $0.contentView }.flatMap(findTextView)
    }

    private func findTextView(_ view: NSView) -> LearningDictionaryTextView? {
        if let text = view as? LearningDictionaryTextView { return text }
        return view.subviews.lazy.compactMap(findTextView).first
    }
}
