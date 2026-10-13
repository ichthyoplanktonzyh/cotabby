import AppKit
import SwiftUI
import Testing
import Vision
@testable import Cotabby

@Suite(.serialized)
@MainActor
struct LearningDictionaryCardTests {
    @Test
    func expressionWordAndMissStatesPaintInOneWindow() async throws {
        let session = LearningDictionarySession(provider: CardDictionaryProbe())
        let text = "look forward to"
        let unit = LearningUnit(id: 0, surface: text, query: text, kind: .expression,
            ranges: [.init(location: 0, length: text.utf16.count)],
            words: LearningUnitPolicy.words(in: text, language: .english))
        let hosting = NSHostingView(rootView: LearningDictionaryCard(session: session, close: {}, sizeChanged: { _ in }))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.contentView = hosting
        defer { window.close(); session.close() }
        let number = window.windowNumber
        session.open(unit, documentID: UUID(), language: .english)
        await waitUntil { if case .result(.entries) = session.content { return true }; return false }
        let expressionText = try await paint(hosting, window: window, name: "dictionary-expression")
        #expect(expressionText.contains("look forward to") && expressionText.contains("anticipate"))
        #expect(expressionText.contains("CC BY-SA"), "Attribution must remain painted outside the scroll viewport")
        #expect(window.frame.height < 340, "A short definition must not reserve a full empty viewport")
        session.select(unit.words[1])
        await waitUntil { session.title == "forward" && session.content == .result(.systemDefinition("A direction in front of you.")) }
        let wordText = try await paint(hosting, window: window, name: "dictionary-word")
        #expect(wordText.contains("forward") && wordText.contains("direction"))
        #expect(!wordText.contains("anticipate"))
        #expect(window.windowNumber == number)
        session.returnToExpression()
        #expect(session.title == "look forward to")
        let miss = LearningUnit(id: 0, surface: "unknown expression", query: "unknown expression", kind: .expression,
            ranges: [.init(location: 0, length: 18)], words: unit.words)
        session.open(miss, documentID: UUID(), language: .english)
        await waitUntil { session.content == .result(.notFound) }
        let missText = try await paint(hosting, window: window, name: "dictionary-miss")
        #expect(missText.contains("unknown expression"))
        #expect(!missText.contains("anticipate") && !missText.contains("direction"))
        #expect(window.windowNumber == number)
    }

    private func paint(_ host: NSHostingView<LearningDictionaryCard>, window: NSWindow, name: String) async throws -> String {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded(); window.setContentSize(host.fittingSize)
            try await Task.sleep(for: .milliseconds(10))
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("build/LanguageLearning/LearningUnitStudy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLanguages = ["en-US", "zh-Hans"]
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([recognition])
        return (recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []).joined(separator: " ")
    }
}

private actor CardDictionaryProbe: LearningDictionaryProviding {
    func lookup(_ query: String, language: LearningLanguage, expression: Bool) async throws -> LearningDictionaryResult {
        if !expression { return .systemDefinition("A direction in front of you.") }
        if query != "look forward to" { return .notFound }
        return .entries([.init(id: "fixture", language: "en", headword: query, forms: [],
            senses: [.init(partOfSpeech: "verb", definitions: ["To anticipate an event."], labels: [])],
            sourceURL: "https://en.wiktionary.org/wiki/look_forward_to")])
    }
}
