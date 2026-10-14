import AppKit
import SwiftUI
import Testing
import Vision
@testable import Cotabby

@Suite(.serialized)
@MainActor
struct LearningDictionaryCardTests {
    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func expressionWordAndMissStatesPaintInOneWindow(_ interfaceDirection: LayoutDirection) async throws {
        let session = LearningDictionarySession(provider: CardDictionaryProbe())
        let text = "look forward to"
        let unit = LearningUnit(id: 0, surface: text, query: text, kind: .expression,
            ranges: [.init(location: 0, length: text.utf16.count)],
            words: LearningUnitPolicy.words(in: text, language: .english))
        let card = LearningDictionaryCard(session: session, close: {}, sizeChanged: { _ in })
            .environment(\.layoutDirection, interfaceDirection)
        let hosting = NSHostingView(rootView: card)
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
        let expression = try await paint(hosting, window: window, name: "dictionary-expression")
        let expressionText = expression.text
        #expect(expressionText.contains("look forward to") && expressionText.contains("anticipate"))
        #expect(expressionText.contains("CC BY-SA"), "Attribution must remain painted outside the scroll viewport")
        #expect(window.frame.height < 340, "A short definition must not reserve a full empty viewport")
        try expectEnglishComponentWordOrder(expression.observations)
        session.select(unit.words[1])
        await waitUntil { session.title == "forward" && session.content == .result(.systemDefinition("A direction in front of you.")) }
        let wordText = try await paint(hosting, window: window, name: "dictionary-word").text
        #expect(wordText.contains("forward") && wordText.contains("direction"))
        #expect(!wordText.contains("anticipate"))
        #expect(window.windowNumber == number)
        session.returnToExpression()
        #expect(session.title == "look forward to")
        let miss = LearningUnit(id: 0, surface: "unknown expression", query: "unknown expression", kind: .expression,
            ranges: [.init(location: 0, length: 18)], words: unit.words)
        session.open(miss, documentID: UUID(), language: .english)
        await waitUntil { session.content == .result(.notFound) }
        let missText = try await paint(hosting, window: window, name: "dictionary-miss").text
        #expect(missText.contains("unknown expression"))
        #expect(!missText.contains("anticipate") && !missText.contains("direction"))
        #expect(window.windowNumber == number)
    }

    private func paint<Content: View>(
        _ host: NSHostingView<Content>, window: NSWindow, name: String
    ) async throws -> (text: String, observations: [VNRecognizedTextObservation]) {
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
        let observations = recognition.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        return (text, observations)
    }

    private func expectEnglishComponentWordOrder(_ observations: [VNRecognizedTextObservation]) throws {
        func centerX(of word: String) throws -> CGFloat {
            let candidates = try observations.compactMap { observation -> (x: CGFloat, y: CGFloat)? in
                guard let recognizedText = observation.topCandidates(1).first,
                      let range = recognizedText.string.range(of: word, options: .caseInsensitive),
                      let match = try recognizedText.boundingBox(for: range) else { return nil }
                let bounds = match.boundingBox
                return (bounds.midX, bounds.midY)
            }
            // Vision's normalized image coordinates start at the bottom-left, so the smallest
            // y among repeated occurrences selects the visually lowest one: the component chip.
            return try #require(candidates.min { $0.y < $1.y }?.x,
                "OCR should find the \(word) label in the expression's component row")
        }

        let look = try centerX(of: "look")
        let forward = try centerX(of: "forward")
        let to = try centerX(of: "to")
        #expect(look < forward && forward < to,
            "English component chips should retain their left-to-right source order under either UI direction")
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
