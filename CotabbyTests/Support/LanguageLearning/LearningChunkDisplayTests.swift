import Foundation
import Testing
@testable import Cotabby

struct LearningChunkDisplayTests {
    @Test
    func discontinuousUnitsPreserveExactTextAndMeaningIdentity() {
        let text = "I was able to do it.\nAgain!"
        let chunk = LearningMeaningChunk(id: 3, sourceRanges: [],
            targetRanges: [.init(location: 2, length: 11), .init(location: 17, length: 2)])
        let fragments = LearningChunkDisplay.fragments(text: text, chunks: [chunk], source: false)
        #expect(fragments.map(\.text).joined() == text)
        #expect(fragments.filter { $0.chunkID == 3 }.map(\.text) == ["was able to", "it"])
        #expect(fragments.contains { $0.text == "\n" && $0.chunkID == nil })
    }

    @Test
    func popupQuotesUseSentenceOrderEvenWhenModelSpansAreReordered() {
        let text = "I will try to go"
        #expect(LearningChunkDisplay.quote(text, ranges: [.init(location: 7, length: 6), .init(location: 0, length: 1)]) ==
            "I … try to")
    }

    @Test
    func malformedOverlapsAndEmojiSplitsCannotDropCharacters() {
        let text = "👩🏽‍💻中文 hello"
        let chunks = [
            LearningMeaningChunk(id: 0, sourceRanges: [.init(location: 0, length: 2)], targetRanges: []),
            LearningMeaningChunk(id: 1, sourceRanges: [.init(location: 7, length: 2)], targetRanges: []),
            LearningMeaningChunk(id: 2, sourceRanges: [.init(location: 8, length: 2)], targetRanges: []),
            LearningMeaningChunk(id: 3, sourceRanges: [.init(location: 999, length: 1)], targetRanges: [])
        ]
        let fragments = LearningChunkDisplay.fragments(text: text, chunks: chunks, source: true)
        #expect(fragments.map(\.text).joined() == text)
        #expect(!fragments.contains { $0.chunkID == 0 || $0.chunkID == 2 || $0.chunkID == 3 })
    }
}
