import AppKit
import Combine
import Testing
@testable import Cotabby

/// One geometry subscription must handle both arrival orders. The fixtures contain no real editor
/// or generation service; only the learning panel's screen rectangle is observed.
@Suite(.serialized)
@MainActor
struct LearningSentencePanelTests {
    @Test
    func staleClicksCannotOpenAChildAndCollapsingClearsItsSelection() throws {
        let screen = try #require(NSScreen.main?.visibleFrame)
        let identifier = UUID()
        let panel = LearningSentencePanel()
        defer { panel.hide() }
        let presentation = LearningSentencePresentation(id: identifier, source: "能做到", translation: "can do it",
            chunks: [.init(id: 0, sourceRanges: [.init(location: 0, length: 3)],
                targetRanges: [.init(location: 0, length: 9)], explanation: "ability")],
            sourceLanguage: .chinese, targetLanguage: .english,
            caret: CGRect(x: screen.minX + 100, y: screen.midY, width: 2, height: 20),
            isExpanded: true, isGenerating: false, message: "", previousTranslation: nil, shortcutLabel: "⌥T")
        panel.show(presentation, expand: {}, dismiss: {})
        panel.inspectChunk(0, documentID: UUID())
        #expect(panel.detailState.chunk == nil)
        panel.inspectChunk(0, documentID: identifier)
        #expect(panel.detailState.chunk?.target == "can do it")
        #expect(panel.dismissDetail())
        #expect(panel.isVisible)
        panel.inspectChunk(0, documentID: identifier)
        panel.show(LearningSentencePresentation(id: identifier, source: "能做到", translation: "can do it",
            chunks: presentation.chunks, sourceLanguage: .chinese, targetLanguage: .english, caret: presentation.caret,
            isExpanded: false, isGenerating: false, message: "", previousTranslation: nil, shortcutLabel: "⌥T"),
            expand: {}, dismiss: {})
        #expect(panel.detailState.chunk == nil)
    }

    @Test
    func aLaterCompletionMovesLearningAndReleasedSpaceRestoresIt() throws {
        let screen = try #require(NSScreen.main?.visibleFrame)
        let reserved = CurrentValueSubject<CGRect?, Never>(nil)
        let panel = LearningSentencePanel(reservedFramePublisher: reserved.eraseToAnyPublisher())
        defer { panel.hide() }
        panel.show(LearningSentencePresentation(id: UUID(), source: "fixture", translation: "Learning fixture",
            chunks: [], sourceLanguage: .chinese, targetLanguage: .english,
            caret: CGRect(x: screen.midX, y: screen.midY, width: 2, height: 20),
            isExpanded: false, isGenerating: false, message: "", previousTranslation: nil, shortcutLabel: "⌥T"),
            expand: {}, dismiss: {})
        let initial = try #require(panel.visibleFrame)
        reserved.send(initial)
        let moved = try #require(panel.visibleFrame)
        #expect(!moved.intersects(initial.insetBy(dx: -8, dy: -8)))
        reserved.send(screen)
        #expect(!panel.isVisible)
        reserved.send(nil)
        #expect(panel.isVisible)
        panel.hide()
        reserved.send(initial)
        reserved.send(nil)
        #expect(!panel.isVisible)
    }
}
