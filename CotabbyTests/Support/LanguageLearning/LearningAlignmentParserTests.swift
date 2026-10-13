import Foundation
import Testing
@testable import Cotabby

/// Pair decoding is independent of inference and AppKit. These fixtures check the places where
/// a syntactically valid answer could paint the wrong occurrence or expose unvalidated text.
struct LearningAlignmentParserTests {
    @Test
    func sortsSourceButAllowsReorderedTranslation() throws {
        let result = try LearningAlignmentParser.parse(#"[["今天","today"],["她","She"],["能做到","can do it"]]"#,
            source: "她今天能做到", translation: "She can do it today.")
        #expect(result.chunks.map(\.id) == [0, 1, 2])
        #expect(result.chunks.map { $0.sourceRanges[0].location } == [0, 1, 3])
        #expect(result.chunks.map { $0.targetRanges[0].location } == [0, 14, 4])
        #expect(result.translation == "She can do it today.")
    }

    @Test
    func resolvesRepeatsAfterUniqueLongerPairClaimsItsOccurrence() throws {
        let result = try LearningAlignmentParser.parse(#"[["你","you"],["你好","hello"]]"#,
            source: "你好，你", translation: "hello, you")
        #expect(result.chunks.map { $0.sourceRanges[0].location } == [0, 3])
        #expect(result.unresolvedChunkCount == 0)
    }

    @Test
    func preservesUniquePairsAndLeavesAmbiguousRepeatsUncolored() throws {
        let result = try LearningAlignmentParser.parse(#"[["我","I"],["你","you"]]"#,
            source: "我，你，你", translation: "I, you, you")
        #expect(result.chunks.count == 1)
        #expect(result.chunks[0].sourceRanges == [NSRange(location: 0, length: 1)])
        #expect(result.unresolvedChunkCount == 1)
    }

    @Test(arguments: ["[]", "null", "{}", #"[["我"]]"#, #"[["我","I","note"]]"#,
        #"[["我",1]]"#, #"[["","I"]]"#, #"[["我"," "]]"#, #"[{"source":"我","translation":"I"}]"#,
        "```json\n[[\"我\",\"I\"]]\n```", #"[["我","I"]] explanation"#, #"[["我","I"]"#])
    func rejectsInvalidOrIncompletePayload(_ raw: String) {
        #expect(throws: (any Error).self) { try LearningAlignmentParser.parse(raw, source: "我", translation: "I") }
    }

    @Test(arguments: [#"[["我","Me"]]"#, #"[["不存在","I"]]"#,
        #"[["我","I"],["我","I"]]"#, #"[["我","I"],["我能","I can"]]"#])
    func rejectsRewritingAndOverlaps(_ raw: String) {
        #expect(throws: (any Error).self) { try LearningAlignmentParser.parse(raw, source: "我能", translation: "I can") }
    }

    @Test
    func rejectsWholeOutputWhenNoRepeatedPairCanBeLocatedReliably() {
        #expect(throws: (any Error).self) {
            try LearningAlignmentParser.parse(#"[["你","you"]]"#, source: "你，你", translation: "you, you")
        }
    }

    @Test
    func preservesEscapesAndWholeGraphemes() throws {
        let pairs = [["😀", "😀"], ["引号\"换行\n", "quote\"newline\n"]]
        let raw = String(decoding: try JSONEncoder().encode(pairs), as: UTF8.self)
        let result = try LearningAlignmentParser.parse(raw, source: "😀引号\"换行\n", translation: "😀quote\"newline\n")
        #expect(result.chunks[0].sourceRanges == [NSRange(location: 0, length: 2)])
        #expect(result.chunks[1].targetRanges[0].location == 2)
        #expect(throws: (any Error).self) {
            try LearningAlignmentParser.parse(#"[["👨","👨"]]"#, source: "👨‍👩‍👧", translation: "👨‍👩‍👧")
        }
    }

    @Test
    func boundsOutputAndGroupCount() throws {
        #expect(throws: (any Error).self) {
            try LearningAlignmentParser.parse(String(repeating: " ", count: 48_001), source: "我", translation: "I")
        }
        let pairs = Array(repeating: ["我", "I"], count: 41)
        let raw = String(decoding: try JSONEncoder().encode(pairs), as: UTF8.self)
        #expect(throws: (any Error).self) { try LearningAlignmentParser.parse(raw, source: "我", translation: "I") }
    }
}
