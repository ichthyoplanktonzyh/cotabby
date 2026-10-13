import AppKit
import SwiftUI
import Testing
import Vision
@testable import Cotabby

/// Hidden-window rendering verifies the correspondence and native word controls without a dictionary or editor.
/// The generated PNGs contain only these explicit fixtures and help review the presentation.
@Suite(.serialized)
@MainActor
struct LearningDetailCardTests {
    @Test
    func correspondenceAndWordControlsRemainReadable() async throws {
        let state = LearningDetailState()
        state.chunk = .init(documentID: UUID(), chunkID: 1, source: "能做到", target: "can do it",
            language: .english, words: ["can", "do", "it"])
        let hosting = NSHostingView(rootView: LearningDetailCard(state: state,
            selectWord: { _, _ in }, close: {}, sizeChanged: { _ in }))
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
        let buttons = wordButtons(in: hosting)
        #expect(Set(buttons.map(\.title)) == Set(["can", "do", "it"]))
        #expect(buttons.allSatisfy { $0.refusesFirstResponder && $0.frame.width > 0 })
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([recognition])
        let text = (recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []).joined(separator: " ")
        #expect(text.contains("can do it"))
        #expect(!text.contains("Ability to perform"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("build/LanguageLearning/Validation/native-dictionary-phrase-test.png")
        if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: output) }
    }

    private func wordButtons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { wordButtons(in: $0) }
    }
}
