import AppKit
import SwiftUI
import Testing
import Vision
@testable import Cotabby

/// Hidden-window rendering verifies both pages without using a installed dictionary or editor.
/// The generated PNGs contain only these explicit fixtures and help review the presentation.
@Suite(.serialized)
@MainActor
struct LearningDetailCardTests {
    @Test(arguments: [false, true])
    func phraseAndWordPagesPaintTheirOwnContent(_ dictionaryPage: Bool) async throws {
        let state = LearningDetailState()
        state.chunk = .init(documentID: UUID(), chunkID: 1, source: "能做到", target: "can do it",
            explanation: "Ability to perform this action.", language: .english, words: ["can", "do", "it"])
        if dictionaryPage {
            state.word = "can"
            state.entry = .init(requestedTerm: "can", resolvedTerm: "can",
                paragraphs: ["Dictionary meaning remains readable.", "Example: I can do it."], isFound: true)
        }
        let hosting = NSHostingView(rootView: LearningDetailCard(state: state,
            selectWord: { _ in }, back: {}, close: {}, sizeChanged: { _ in }))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.contentView = hosting
        defer { window.close() }
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(hosting.fittingSize.width == 320)
        #expect(hosting.fittingSize.height < 350)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([recognition])
        let text = (recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []).joined(separator: " ")
        #expect(text.contains(dictionaryPage ? "Dictionary meaning remains readable" : "Ability to perform this action"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("build/LanguageLearning/Validation/meaning-popup-\(dictionaryPage ? "word" : "phrase")-test.png")
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output) }
    }
}
