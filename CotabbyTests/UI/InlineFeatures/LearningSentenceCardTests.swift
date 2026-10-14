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
    func compactLongTranslationScrollsToItsEndAndShortContentShrinksAgain() async throws {
        let id = UUID()
        let target = "Opening sentence remains visible. "
            + Array(repeating: "The full translation stays readable inside a compact scrolling viewport.", count: 8)
                .joined(separator: " ") + " Final words remain visible."
        let state = LearningDetailState()
        func card(_ text: String) -> LearningSentenceCard {
            let presentation = LearningSentencePresentation(id: id, source: "原文", translation: text, chunks: [],
                sourceLanguage: .chinese, targetLanguage: .english, caret: .zero, isExpanded: false,
                isGenerating: false, message: "", previousTranslation: nil, shortcutLabel: "⌥T", unitStage: .ready)
            return LearningSentenceCard(presentation: presentation, detailState: state,
                inspect: { _ in }, expand: {}, dismiss: {}, sizeChanged: { _ in })
        }
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: card(target))
        window.contentView = hosting
        defer { window.close() }
        window.orderFrontRegardless()
        await settle(hosting, in: window)
        #expect(hosting.fittingSize.height < 250, "Long text must keep a bounded compact viewport")
        let textView = try #require(findTranslation(target, in: hosting))
        #expect(textView.textContainer?.maximumNumberOfLines == 0)
        #expect(textView.textContainer?.lineBreakMode == .byWordWrapping)
        let tail = (target as NSString).range(of: "Final words remain visible")
        textView.scrollRangeToVisible(tail)
        await settle(hosting, in: window)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if let output = ProcessInfo.processInfo.environment["COTABBY_UI_SCREENSHOT_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("compact-long-tail.png"))
        }
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLanguages = ["en-US"]
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([recognition])
        let painted = (recognition.results?.compactMap { $0.topCandidates(1).first?.string } ?? []).joined(separator: " ")
        #expect(painted.contains("Final words remain visible"), "The final line must be painted after scrolling")
        hosting.rootView = card("Hello.")
        await settle(hosting, in: window)
        #expect(hosting.fittingSize.height < 120, "A reused compact card must shrink back for a short translation")
    }

    private func findTranslation(_ text: String, in view: NSView) -> LearningDictionaryTextView? {
        if let textView = view as? LearningDictionaryTextView, textView.string == text { return textView }
        return view.subviews.lazy.compactMap { findTranslation(text, in: $0) }.first
    }

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
