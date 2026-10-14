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
    func alignmentPaintsWhileUnitsArePendingAndKeepsItsRangesWhenRecognitionArrivesOrFails() async throws {
        let id = UUID(), state = LearningDetailState()
        let source = "我期待见到你。", target = "I look forward to seeing you."
        let phraseRange = (target as NSString).range(of: "look forward to")
        let coloredRange = (target as NSString).range(of: "forward")
        let complementRange = (target as NSString).range(of: "seeing you")
        // These literal ranges are layout fixtures, not a claim about model translation quality.
        // One color crosses several click units; another deliberately covers part of a phrase.
        let chunks = [LearningMeaningChunk(id: 0, sourceRanges: [.init(location: 1, length: 2)], targetRanges: [coloredRange]),
                      LearningMeaningChunk(id: 1, sourceRanges: [.init(location: 3, length: 3)], targetRanges: [complementRange])]
        let unit = LearningUnit(id: phraseRange.location, surface: "look forward to", query: "look forward to",
            kind: .expression, ranges: [phraseRange], words: LearningUnitPolicy.words(in: "look forward to", language: .english))
        var inspected: [Int] = [], lookedUp: [LearningUnit] = []
        func card(_ stage: LearningUnitStage) -> LearningSentenceCard {
            let units = stage == .ready ? [unit] : []
            let presentation = LearningSentencePresentation(id: id, source: source, translation: target, chunks: chunks,
                sourceLanguage: .chinese, targetLanguage: .english, caret: .zero, isExpanded: true,
                isGenerating: false, message: "", previousTranslation: nil, shortcutLabel: "⌥T", units: units, unitStage: stage)
            return LearningSentenceCard(presentation: presentation, detailState: state,
                inspect: { inspected.append($0) }, expand: {}, dismiss: {},
                lookupUnit: { anchor, _ in lookedUp.append(anchor.unit) }, sizeChanged: { _ in })
        }
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 280),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: card(.pending))
        window.contentView = host
        defer { window.close() }
        window.orderFrontRegardless()
        for stage in [LearningUnitStage.pending, .ready, .failed] {
            host.rootView = card(stage)
            await settle(host, in: window)
            let sourceView = try #require(findTranslation(source, in: host))
            let targetView = try #require(findTranslation(target, in: host))
            let left = try #require(sourceView.textStorage), right = try #require(targetView.textStorage)
            let sourceColor = try #require(left.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? NSColor)
            let targetColor = try #require(right.attribute(.backgroundColor, at: coloredRange.location, effectiveRange: nil) as? NSColor)
            #expect(sourceColor == targetColor)
            #expect(right.attribute(.backgroundColor, at: (target as NSString).range(of: "seeing").location, effectiveRange: nil) as? NSColor
                == right.attribute(.backgroundColor, at: (target as NSString).range(of: "you").location, effectiveRange: nil) as? NSColor)
            #expect(right.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
            #expect(right.attribute(.backgroundColor, at: phraseRange.location, effectiveRange: nil) == nil)
            #expect(targetView.string == target && sourceView.string == source)
            let underline = right.attribute(.underlineStyle, at: phraseRange.location, effectiveRange: nil)
            #expect((underline != nil) == (stage == .ready))
            if stage == .ready {
                let point = try glyphPoint(coloredRange, in: targetView)
                targetView.handleClick(at: point, count: 1)
                targetView.handleClick(at: point, count: 2)
                #expect(inspected == [0] && lookedUp == [unit], "Color clicks and whole-expression lookup have independent extents")
            }
            if let output = ProcessInfo.processInfo.environment["COTABBY_UI_SCREENSHOT_DIR"] {
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("independent-\(stage).png"))
            }
        }
    }

    private func glyphPoint(_ range: NSRange, in view: LearningDictionaryTextView) throws -> NSPoint {
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = manager.boundingRect(forGlyphRange: glyphs, in: container)
        return .init(x: bounds.midX + view.textContainerOrigin.x, y: bounds.midY + view.textContainerOrigin.y)
    }

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
