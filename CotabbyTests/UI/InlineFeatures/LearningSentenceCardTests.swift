import AppKit
import SwiftUI
import Testing
import Vision
@testable import Cotabby

/// Renders the production SwiftUI card in a nonactivating AppKit host. Text recognition verifies that
/// details are painted inside the viewport, not merely retained in a presentation value. This
/// catches zero-preference collapse during compact-to-expanded root replacement without a model.
@Suite(.serialized)
@MainActor
struct LearningSentenceCardTests {
    @Test
    func expansionPaintsTheOriginalTranslationAndMeaningUnit() async throws {
        let id = UUID()
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        defer { window.close() }
        let detailState = LearningDetailState()
        let makeCard: (Bool) -> LearningSentenceCard = { expanded in
            LearningSentenceCard(presentation: Self.presentation(id: id, expanded: expanded), detailState: detailState,
                inspect: { _ in }, expand: {}, dismiss: {}, sizeChanged: { _ in })
        }
        let hosting = NSHostingView(rootView: makeCard(false))
        window.contentView = hosting
        // SwiftUI's content preferences need an attached display pass, as in the real panel.
        // Order this nonactivating window without making it key or changing the user's editor.
        window.orderFrontRegardless()
        await settle(hosting, in: window)
        #expect(hosting.fittingSize.height < 120)
        // Reuse one host and document, matching the real panel's preservation of SwiftUI state.
        for expanded in [true, false, true] {
            hosting.rootView = makeCard(expanded)
            await settle(hosting, in: window)
        }
        #expect(hosting.fittingSize.height > 160)
        #expect(hosting.fittingSize.height < 400)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if let output = ProcessInfo.processInfo.environment["COTABBY_UI_SCREENSHOT_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("expanded-sentence.png"))
        }
        let cgImage = try #require(bitmap.cgImage)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLanguages = ["en-US"]
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: cgImage).perform([recognition])
        let lines = recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        #expect(lines.contains { $0.contains("Source content must remain visible") })
        #expect(lines.contains { $0.contains("Target translation must remain visible") })
        // Mapping is now embedded in the sentences. Dictionary and duplicate mapping rows no
        // longer belong to this main card; both source and target must still be visibly painted.
        hosting.rootView = LearningSentenceCard(presentation: Self.presentation(id: id, expanded: true, repeats: 3),
            detailState: detailState, inspect: { _ in }, expand: {}, dismiss: {}, sizeChanged: { _ in })
        await settle(hosting, in: window)
        let longer = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: longer)
        if let output = ProcessInfo.processInfo.environment["COTABBY_UI_SCREENSHOT_DIR"] {
            try longer.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output).appendingPathComponent("expanded-long.png"))
        }
        let longRecognition = VNRecognizeTextRequest()
        longRecognition.recognitionLanguages = ["en-US"]
        longRecognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try #require(longer.cgImage)).perform([longRecognition])
        let longText = (longRecognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []).joined(separator: " ")
        #expect(longText.contains("Source content must remain visible") && longText.contains("Target translation must remain visible"))
    }

    private func settle(_ hosting: NSHostingView<LearningSentenceCard>, in window: NSWindow) async {
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.fittingSize)
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func presentation(id: UUID, expanded: Bool, repeats: Int = 1) -> LearningSentencePresentation {
        let source = Array(repeating: "Source content must remain visible.", count: repeats).joined(separator: " ")
        let target = Array(repeating: "Target translation must remain visible.", count: repeats).joined(separator: " ")
        return LearningSentencePresentation(id: id, source: source, translation: target,
            chunks: [.init(id: 0, sourceRanges: [.init(location: 0, length: source.utf16.count)],
                targetRanges: [.init(location: 0, length: target.utf16.count)])],
            sourceLanguage: .chinese, targetLanguage: .english, caret: .zero,
            isExpanded: expanded, isGenerating: false, message: "", previousTranslation: nil, shortcutLabel: "⌥T", unitStage: .ready)
    }
}
