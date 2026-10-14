import AppKit
import Testing
@testable import Cotabby

/// These fixtures exercise correspondence geometry and the public window-family relationship;
/// no real dictionary, editor, or generation service participates.
@Suite(.serialized)
@MainActor
struct LearningDetailPanelTests {
    @Test
    func movingTheParentKeepsTheChildAttached() throws {
        let panel = LearningDetailPanel()
        defer { panel.hide() }
        let original = try placement()
        panel.show(Self.chunk(), placement: original)
        let first = try #require(panel.visibleFrame)
        panel.updateParent(original.parent.offsetBy(dx: 0, dy: -80),
            caret: original.caret.offsetBy(dx: 0, dy: -80), reserved: nil, screen: original.screen)
        let moved = try #require(panel.visibleFrame)
        #expect(abs(moved.minY - first.minY + 80) < 1)
    }

    @Test
    func nativeLookupDescendantsArePartOfTheExplanationWindowFamily() throws {
        let panel = LearningDetailPanel()
        defer { panel.hide() }
        panel.show(Self.chunk(), placement: try placement())
        let source = try #require(NSApp.windows.first { panel.owns($0) && $0.parent == nil })
        let anchor = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        let popup = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        anchor.isReleasedWhenClosed = false
        popup.isReleasedWhenClosed = false
        defer { popup.close(); anchor.close() }
        source.addChildWindow(anchor, ordered: .above)
        anchor.addChildWindow(popup, ordered: .above)
        #expect(panel.owns(source))
        #expect(panel.owns(anchor))
        #expect(panel.owns(popup))
        #expect(!panel.owns(nil))
    }

    @Test
    func replacingOrClosingTheExplanationClearsItsSelection() throws {
        let panel = LearningDetailPanel()
        panel.show(Self.chunk(), placement: try placement())
        panel.show(Self.chunk(identifier: 1), placement: try placement())
        #expect(panel.state.chunk?.chunkID == 1)
        panel.hide()
        #expect(panel.state.chunk == nil)
        #expect(!panel.isVisible)
    }

    @Test
    func lookupRejectsStaleChunksAndClosesBeforeTheExplanation() throws {
        var calls = 0
        let definition = NSPanel(contentRect: CGRect(x: 100, y: 220, width: 220, height: 140),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        definition.isReleasedWhenClosed = false
        defer { definition.close() }
        let dictionary = LearningSystemDictionaryPresenter { view, _, _ in
            calls += 1
            view.window?.addChildWindow(definition, ordered: .above)
            definition.orderFrontRegardless()
        }
        let panel = LearningDetailPanel(dictionary: dictionary)
        defer { panel.hide() }
        let original = Self.chunk()
        panel.show(original, placement: try placement())
        let source = try #require(NSApp.windows.first { panel.owns($0) && $0.parent == nil })
        let button = NSButton(title: "can", target: nil, action: nil)
        button.frame = CGRect(x: 20, y: 20, width: 80, height: 24)
        source.contentView?.addSubview(button)
        panel.selectWord("can", from: button, chunk: original)
        #expect(calls == 1)
        #expect(panel.dismissDictionary())
        #expect(panel.isVisible)
        #expect(panel.state.chunk == original)
        #expect(!panel.dismissDictionary())
        let next = Self.chunk(identifier: 1)
        panel.show(next, placement: try placement())
        source.contentView?.addSubview(button)
        panel.selectWord("can", from: button, chunk: original)
        button.title = "unlisted"
        panel.selectWord("unlisted", from: button, chunk: next)
        #expect(calls == 1)
        panel.hide()
        button.title = "can"
        panel.selectWord("can", from: button, chunk: next)
        #expect(calls == 1)
    }

    @Test
    func expressionComponentLookupKeepsItsEntryAndRejectsReplacedDocumentControls() async throws {
        var displayed: [String] = []
        let popup = NSPanel(contentRect: CGRect(x: 100, y: 220, width: 220, height: 140),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        popup.isReleasedWhenClosed = false
        defer { popup.close() }
        let dictionary = LearningSystemDictionaryPresenter { view, text, _ in
            displayed.append(text.string)
            view.window?.addChildWindow(popup, ordered: .above)
            popup.orderFrontRegardless()
        }
        let panel = LearningDetailPanel(dictionary: dictionary, provider: ExpressionDictionaryProbe())
        defer { panel.hide() }
        let text = "look forward to"
        let unit = LearningUnit(id: 0, surface: text, query: text, kind: .expression,
            ranges: [.init(location: 0, length: text.utf16.count)],
            words: LearningUnitPolicy.words(in: text, language: .english))
        let id = UUID()
        let placement = try placement()
        panel.show(unit, documentID: id, language: .english, correspondence: nil, placement: placement)
        await waitUntil { panel.dictionarySession.content == .result(.notFound) && panel.isVisible }
        let source = try #require(NSApp.windows.first { panel.owns($0) && $0.parent == nil })
        let button = NSButton(title: "forward", target: nil, action: nil)
        button.frame = CGRect(x: 20, y: 20, width: 100, height: 24)
        source.contentView?.addSubview(button)
        panel.selectDictionaryTerm("forward", from: button, unit: unit, documentID: id)
        #expect(displayed == ["forward"] && popup.isVisible && panel.owns(popup))
        #expect(panel.dictionarySession.unit == unit && panel.dictionarySession.selectedWord == nil)
        #expect(panel.dictionarySession.content == .result(.notFound))
        #expect(panel.dismissDictionary())
        #expect(panel.isVisible && !popup.isVisible)
        // A full phrase miss must not open native lookup that might substitute one constituent.
        button.title = text
        panel.selectDictionaryTerm(text, from: button, unit: unit, documentID: id)
        #expect(displayed == ["forward"])
        let nextID = UUID()
        panel.show(unit, documentID: nextID, language: .english, correspondence: nil, placement: placement)
        source.contentView?.addSubview(button)
        button.title = "forward"
        panel.selectDictionaryTerm("forward", from: button, unit: unit, documentID: id)
        #expect(displayed == ["forward"], "The same text in a newer document must reject an old control")
        panel.selectDictionaryTerm("forward", from: button, unit: unit, documentID: nextID)
        #expect(displayed == ["forward", "forward"])
        panel.hide()
        #expect(!popup.isVisible)
        panel.selectDictionaryTerm("forward", from: button, unit: unit, documentID: nextID)
        #expect(displayed.count == 2)
    }

    private static func chunk(identifier: Int = 0) -> LearningChunkDetail {
        .init(documentID: UUID(), chunkID: identifier, source: "能做到", target: "can do it",
            language: .english, words: ["can", "do", "it"])
    }

    private func placement() throws -> LearningDetailPlacement {
        let screen = try #require(NSScreen.main?.visibleFrame)
        let parent = CGRect(x: screen.minX + 40, y: screen.midY, width: 480, height: 200)
        return .init(parent: parent, caret: CGRect(x: parent.minX, y: parent.minY - 30, width: 2, height: 20),
            reserved: nil, screen: screen, anchorY: parent.maxY)
    }
}

private actor ExpressionDictionaryProbe: LearningDictionaryProviding {
    func lookup(_ query: String, language: LearningLanguage, expression: Bool) async throws -> LearningDictionaryResult {
        .notFound
    }
}
