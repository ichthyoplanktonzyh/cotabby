import AppKit
import SwiftUI

/// Displays the original compact translation as one text layout, preserving spaces, punctuation,
/// wrapping and right-to-left reading order. SwiftUI owns this view through the sentence card;
/// double-clicks carry only a word occurrence and native anchor to the panel's existing dictionary.
struct LearningSentenceDictionaryText: NSViewRepresentable {
    let text: String
    let language: LearningLanguage
    let lookup: (LearningDictionaryTextAnchor, NSTextView) -> Void

    func makeNSView(context: Context) -> LearningDictionaryTextView {
        let view = LearningDictionaryTextView(frame: .zero, textContainer: nil)
        view.isEditable = false
        view.isSelectable = false
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.maximumNumberOfLines = 3
        view.textContainer?.lineBreakMode = .byTruncatingTail
        view.textContainer?.widthTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.font = .systemFont(ofSize: 16)
        view.textColor = .labelColor
        return view
    }

    func updateNSView(_ view: LearningDictionaryTextView, context: Context) {
        if view.string != text { view.string = text }
        view.language = language
        view.baseWritingDirection = language == .arabic ? .rightToLeft : .natural
        view.lookup = lookup
        view.toolTip = "双击单词查词"
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LearningDictionaryTextView, context: Context) -> CGSize? {
        nsView.measuredSize(width: proposal.width ?? 300)
    }
}

/// A read-only NSTextView borrows TextKit's real glyph geometry. Its mouse handling never invokes
/// NSTextView's selection/editing path, so single clicks and double clicks cannot take keyboard
/// focus away from the editor or select the translation as editable text.
@MainActor
final class LearningDictionaryTextView: NSTextView {
    var language: LearningLanguage = .english
    var lookup: (LearningDictionaryTextAnchor, NSTextView) -> Void = { _, _ in }

    override var acceptsFirstResponder: Bool { false }

    func measuredSize(width: CGFloat) -> CGSize {
        guard let textContainer, let layoutManager else { return .zero }
        let width = max(1, width)
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height
        return CGSize(width: width, height: ceil(max(height, layoutManager.defaultLineHeight(for: font ?? .systemFont(ofSize: 16)))))
    }

    override func mouseDown(with event: NSEvent) {
        handleClick(at: convert(event.locationInWindow, from: nil), count: event.clickCount)
    }

    /// Extracted from event delivery so hidden-window tests can exercise exact glyph clicks without
    /// posting global mouse events. Ignore blank areas and the ellipsis/hidden tail of line three.
    func handleClick(at point: NSPoint, count: Int) {
        guard count == 2, let textContainer, let layoutManager, let font else { return }
        layoutManager.ensureLayout(for: textContainer)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              NSLocationInRange(glyph, layoutManager.glyphRange(for: textContainer)),
              !NSLocationInRange(glyph, layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: glyph)),
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(local),
              let word = LearningDictionaryWordPolicy.word(atUTF16Location: layoutManager.characterIndexForGlyph(at: glyph),
                  in: string, language: language.naturalLanguage) else { return }
        var lineRange = NSRange()
        _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        let wordGlyphs = layoutManager.glyphRange(forCharacterRange: word.range, actualCharacterRange: nil)
        let visibleGlyphs = NSIntersectionRange(wordGlyphs, lineRange)
        var bounds = layoutManager.boundingRect(forGlyphRange: visibleGlyphs, in: textContainer)
        bounds.origin.x += textContainerOrigin.x
        bounds.origin.y += textContainerOrigin.y
        lookup(.init(word: word, bounds: bounds, font: font), self)
    }
}
