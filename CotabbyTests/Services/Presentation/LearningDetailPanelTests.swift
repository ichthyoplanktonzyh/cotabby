import AppKit
import Testing
@testable import Cotabby

/// Controllable actor replies verify page changes and cancellation without installed dictionaries
/// or model requests. Each test owns its nonactivating child and releases every held continuation.
@Suite(.serialized)
@MainActor
struct LearningDetailPanelTests {
    @Test
    func movingTheParentKeepsTheChildAttached() throws {
        let panel = LearningDetailPanel(dictionary: HeldDictionary())
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
    func onlyTheLatestClickedWordCanPopulateTheSameChild() async throws {
        let dictionary = HeldDictionary()
        let panel = LearningDetailPanel(dictionary: dictionary)
        defer { panel.hide() }
        panel.show(Self.chunk(), placement: try placement())
        panel.selectWord("can")
        await waitUntil { await dictionary.hasRequest("can") }
        panel.selectWord("do")
        await waitUntil { await dictionary.hasRequest("do") }
        await dictionary.finish("do")
        await waitUntil { panel.state.entry?.requestedTerm == "do" }
        await dictionary.finish("can")
        await Task.yield()
        #expect(panel.state.word == "do")
        #expect(panel.state.entry?.requestedTerm == "do")
        panel.back()
        #expect(panel.state.word == nil)
        #expect(panel.state.chunk?.target == "can do it")
        #expect(panel.state.entry == nil)
    }

    @Test
    func closingOrChangingThePhraseRejectsAnOldDictionaryReply() async throws {
        let dictionary = HeldDictionary()
        let panel = LearningDetailPanel(dictionary: dictionary)
        defer { panel.hide() }
        panel.show(Self.chunk(), placement: try placement())
        panel.selectWord("can")
        await waitUntil { await dictionary.hasRequest("can") }
        panel.hide()
        panel.show(Self.chunk(identifier: 1), placement: try placement())
        await dictionary.finish("can")
        await Task.yield()
        #expect(panel.state.chunk?.chunkID == 1)
        #expect(panel.state.word == nil)
        #expect(panel.state.entry == nil)
    }

    private static func chunk(identifier: Int = 0) -> LearningChunkDetail {
        .init(documentID: UUID(), chunkID: identifier, source: "能做到", target: "can do it",
            explanation: "表达完成某事的能力。", language: .english, words: ["can", "do", "it"])
    }

    private func placement() throws -> LearningDetailPlacement {
        let screen = try #require(NSScreen.main?.visibleFrame)
        let parent = CGRect(x: screen.minX + 40, y: screen.midY, width: 480, height: 200)
        return .init(parent: parent, caret: CGRect(x: parent.minX, y: parent.minY - 30, width: 2, height: 20),
            reserved: nil, screen: screen, anchorY: parent.maxY)
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The controlled dictionary did not reach the expected state")
    }

    private actor HeldDictionary: LearningDictionaryProviding {
        private var replies: [String: CheckedContinuation<LearningDictionaryEntry, Never>] = [:]
        func entry(for term: String, language: LearningLanguage) async -> LearningDictionaryEntry {
            await withCheckedContinuation { replies[term] = $0 }
        }
        func hasRequest(_ word: String) -> Bool { replies[word] != nil }
        func finish(_ word: String) {
            replies.removeValue(forKey: word)?.resume(returning: .init(requestedTerm: word, resolvedTerm: word,
                paragraphs: ["A dictionary meaning.", "An example sentence."], isFound: true))
        }
    }
}
