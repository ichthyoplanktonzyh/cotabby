import AppKit
import Testing
@testable import Cotabby

@Suite(.serialized)
@MainActor
struct LearningSentencePanelTests {
    @Test
    func partialAlignmentSelectionAndWholeExpressionLookupUseDifferentRanges() async throws {
        let provider = PanelDictionaryProbe(), panel = LearningSentencePanel(dictionaryProvider: provider)
        defer { panel.hide() }
        let id = UUID(), text = "I look forward to seeing you."
        let phrase = (text as NSString).range(of: "look forward to")
        let unit = LearningUnit(id: phrase.location, surface: "look forward to", query: "look forward to",
            kind: .expression, ranges: [phrase], words: LearningUnitPolicy.words(in: "look forward to", language: .english))
        // Artificial source fragments isolate selection/range behavior from model quality.
        let chunks = [LearningMeaningChunk(id: 0, sourceRanges: [.init(location: 0, length: 1)],
                                          targetRanges: [(text as NSString).range(of: "forward")]),
                      LearningMeaningChunk(id: 1, sourceRanges: [.init(location: 1, length: 1)],
                                          targetRanges: [(text as NSString).range(of: "to")])]
        func presentation(_ documentID: UUID) -> LearningSentencePresentation {
            .init(id: documentID, source: "甲乙", translation: text, chunks: chunks,
                sourceLanguage: .chinese, targetLanguage: .english,
                caret: CGRect(x: 180, y: 220, width: 1, height: 18), isExpanded: true, isGenerating: false,
                message: "", previousTranslation: nil, shortcutLabel: "⌥T", units: [unit], unitStage: .ready)
        }
        panel.show(presentation(id), expand: {}, dismiss: {})
        await waitUntil { self.textView(in: panel, matching: text)?.frame.height ?? 0 > 0 }
        let view = try #require(textView(in: panel, matching: text))
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: chunks[1].targetRanges[0], actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
        let point = NSPoint(x: bounds.midX + view.textContainerOrigin.x, y: bounds.midY + view.textContainerOrigin.y)
        view.handleClick(at: point, count: 1)
        #expect(panel.detailState.chunk?.chunkID == 1 && panel.detailState.chunk?.target == "to")
        let oldInspect = view.inspect, oldLookup = try #require(view.lookupUnit)
        view.handleClick(at: point, count: 2)
        for _ in 0..<200 {
            if await provider.queries == ["look forward to"] { break }
            await Task.yield()
        }
        #expect(await provider.queries == ["look forward to"])
        #expect(panel.detailState.chunk?.chunkID == 1, "Whole-expression lookup must preserve the clicked color, not choose the first overlap")
        panel.show(presentation(UUID()), expand: {}, dismiss: {})
        oldInspect(1)
        oldLookup(.init(unit: unit, bounds: bounds, font: .systemFont(ofSize: 18)), view)
        #expect(panel.detailState.chunk == nil, "An old document's color callback must not select a new document")
        #expect(await provider.queries == ["look forward to"], "An old dictionary callback must not issue another query")
    }

    @Test(arguments: [false, true])
    func nativeWordLookupSurvivesAnalysisUpdatesAndClosesWithInputPreview(_ expanded: Bool) async throws {
        let provider = PanelDictionaryProbe()
        var displayed = ""
        var anchor: NSWindow?
        let popup = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 220, height: 120),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        popup.isReleasedWhenClosed = false
        defer { popup.close() }
        let dictionary = LearningSystemDictionaryPresenter { view, text, _ in
            displayed = text.string
            anchor = view.window
            view.window?.addChildWindow(popup, ordered: .above)
            popup.orderFrontRegardless()
        }
        let panel = LearningSentencePanel(dictionary: dictionary, dictionaryProvider: provider)
        defer { panel.hide() }
        let id = UUID()
        func presentation(chunks: [LearningMeaningChunk]) -> LearningSentencePresentation {
            .init(id: id, source: "我喜欢你", translation: "I like you.", chunks: chunks,
                sourceLanguage: .chinese, targetLanguage: .english,
                caret: CGRect(x: 180, y: 220, width: 1, height: 18), isExpanded: expanded, isGenerating: true,
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
        let originalLookup = try #require(view.lookupUnit)
        var clickedUnit: LearningUnit?
        view.lookupUnit = { anchor, view in clickedUnit = anchor.unit; originalLookup(anchor, view) }
        view.handleClick(at: NSPoint(x: bounds.midX + view.textContainerOrigin.x,
            y: bounds.midY + view.textContainerOrigin.y), count: 2)
        #expect(clickedUnit == .word(.init(text: "like", range: range)))
        #expect(displayed == "like", "A word click must dispatch to native dictionary presentation")
        #expect(await provider.calls == 0, "Word lookup must bypass the flattened Dictionary Services provider")
        let source = try #require(anchor)
        #expect(source.isVisible)
        panel.show(presentation(chunks: [.init(id: 0, sourceRanges: [.init(location: 1, length: 2)],
            targetRanges: [.init(location: 2, length: 4)])]), expand: {}, dismiss: {})
        #expect(source.isVisible, "Background analysis must not close the fixed translation's word lookup")
        if expanded {
            await waitUntil { self.textView(in: panel)?.chunks.count == 1 }
            let updated = try #require(textView(in: panel))
            updated.handleClick(at: NSPoint(x: bounds.midX + updated.textContainerOrigin.x,
                y: bounds.midY + updated.textContainerOrigin.y), count: 1)
            #expect(panel.detailState.chunk?.chunkID == 0)
            updated.handleClick(at: NSPoint(x: bounds.midX + updated.textContainerOrigin.x,
                y: bounds.midY + updated.textContainerOrigin.y), count: 2)
            #expect(panel.detailState.chunk?.chunkID == 0, "Native word lookup must keep the selected meaning relation")
        }
        panel.hide()
        #expect(!source.isVisible)
        #expect(!popup.isVisible)
        #expect(panel.detailState.chunk == nil)
    }

    private func textView(in panel: LearningSentencePanel, matching text: String = "I like you.") -> LearningDictionaryTextView? {
        NSApp.windows.first {
            $0.frame == panel.visibleFrame && $0.title == String(localized: "Expression Learning", table: "Learning")
        }
            .flatMap { $0.contentView }.flatMap { findTextView($0, matching: text) }
    }

    private func findTextView(_ view: NSView, matching text: String) -> LearningDictionaryTextView? {
        if let textView = view as? LearningDictionaryTextView, textView.string == text { return textView }
        return view.subviews.lazy.compactMap { findTextView($0, matching: text) }.first
    }
}

private actor PanelDictionaryProbe: LearningDictionaryProviding {
    private(set) var calls = 0
    private(set) var queries: [String] = []
    func lookup(_ query: String, language: LearningLanguage, expression: Bool) async throws -> LearningDictionaryResult {
        calls += 1
        queries.append(query)
        return .systemEntry
    }
}
