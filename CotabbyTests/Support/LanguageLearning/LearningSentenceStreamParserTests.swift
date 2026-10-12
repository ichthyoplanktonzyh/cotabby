import Foundation
import Testing
@testable import Cotabby

struct LearningSentenceStreamParserTests {
    @Test
    func translationIsAvailableBeforeAnalysisAcrossArbitraryFragments() throws {
        var parser = LearningSentenceStreamParser(source: "我能做到 😀")
        #expect(try parser.append(#"{"type":"trans"#).isEmpty)
        #expect(try parser.append("lation\",\"text\":\"I can do it 😀.\"}\n") == [.translation("I can do it 😀.")])
        #expect(parser.chunks.isEmpty)
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"能\"],\"target\":[\"can\"],\"explanation\":\"能力\"}")
        #expect(parser.chunks.isEmpty)
        let updates = try parser.finish()
        #expect(updates.count == 1)
        #expect(try parser.result().translation == "I can do it 😀.")
        #expect(parser.chunks.first?.sourceRanges == [NSRange(location: 1, length: 1)])
        #expect(parser.chunks.first?.targetRanges == [NSRange(location: 2, length: 3)])
    }

    @Test
    func supportsDiscontinuousReorderedAndImplicitGrammar() throws {
        var parser = LearningSentenceStreamParser(source: "我把书给你")
        _ = try parser.append("{\"type\":\"translation\",\"text\":\"I give you the book.\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"把\",\"给\"],\"target\":[\"give\"],\"explanation\":\"给予结构\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[],\"target\":[\"the\"],\"explanation\":\"冠词\"}\n")
        #expect(parser.chunks[0].sourceRanges.count == 2)
        #expect(parser.chunks[1].sourceRanges.isEmpty)
    }

    @Test
    func repeatedQuotesResolveToSeparateUnclaimedOccurrences() throws {
        var parser = LearningSentenceStreamParser(source: "你喜欢你")
        _ = try parser.append("{\"type\":\"translation\",\"text\":\"You like you.\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"你\"],\"target\":[\"You\"],\"explanation\":\"主语\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"你\"],\"target\":[\"you\"],\"explanation\":\"宾语\"}\n")
        #expect(parser.chunks[1].sourceRanges == [NSRange(location: 3, length: 1)])
    }

    @Test
    func findsAnUnclaimedOccurrenceOverlappingARejectedMatch() throws {
        var parser = LearningSentenceStreamParser(source: "banana")
        _ = try parser.append("{\"type\":\"translation\",\"text\":\"banana\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"ba\"],\"target\":[\"ba\"],\"explanation\":\"first\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"ana\"],\"target\":[\"ana\"],\"explanation\":\"second\"}\n")
        #expect(parser.chunks[1].sourceRanges == [NSRange(location: 3, length: 3)])
    }

    @Test(arguments: [
        #"{"type":"translation","text":"Another translation."}"#,
        #"{"type":"chunk","source":["能"],"target":["am able to"],"explanation":"different wording"}"#,
        #"{"type":"chunk","source":["不在原文"],"target":["can"],"explanation":"bad quote"}"#,
        #"{"type":"chunk","source":[],"target":[],"explanation":"no meaning"}"#,
        #"{"type":"chunk","source":["能"],"target":[""],"explanation":"empty quote"}"#,
        #"{"type":"unknown"}"#,
        "not JSON"
    ])
    func rejectsInvalidAnalysisWithoutLosingValidatedTranslation(_ record: String) throws {
        var parser = LearningSentenceStreamParser(source: "我能做到")
        _ = try parser.append("{\"type\":\"translation\",\"text\":\"I can do it.\"}\n")
        #expect(throws: (any Error).self) { _ = try parser.append(record + "\n") }
        #expect(parser.translation == "I can do it.")
    }

    @Test
    func rejectsOverlappingAndPartialGraphemeQuotes() throws {
        var parser = LearningSentenceStreamParser(source: "能 👨‍👩‍👧")
        _ = try parser.append("{\"type\":\"translation\",\"text\":\"can 👨‍👩‍👧\"}\n")
        _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"能\"],\"target\":[\"can\"],\"explanation\":\"能力\"}\n")
        #expect(throws: (any Error).self) {
            _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"能\"],\"target\":[\"can\"],\"explanation\":\"重叠\"}\n")
        }
        #expect(throws: (any Error).self) {
            _ = try parser.append("{\"type\":\"chunk\",\"source\":[\"👨\"],\"target\":[\"👨\"],\"explanation\":\"不完整字符\"}\n")
        }
    }

    @Test
    func rejectsMissingTranslationAndBoundsPayload() throws {
        var parser = LearningSentenceStreamParser(source: "你好")
        #expect(throws: (any Error).self) { _ = try parser.result() }
        #expect(throws: (any Error).self) { _ = try parser.append(String(repeating: "x", count: 48_001)) }
    }
}
