import AppKit
import SwiftUI

/// Displays the original compact translation as one text layout, preserving spaces, punctuation,
/// wrapping and right-to-left reading order. SwiftUI owns this view through the sentence card;
/// double-clicks carry only a word occurrence and native anchor to the panel's existing dictionary.
struct LearningSentenceDictionaryText: NSViewRepresentable {
    let text: String
    let language: LearningLanguage
    let lookup: (LearningDictionaryTextAnchor, NSTextView) -> Void
    var units: [LearningUnit] = []
    var chunks: [LearningMeaningChunk] = []
    var selectedChunk: Int? = nil
    var source = false
    var maximumLines = 3
    var fontSize: CGFloat = 16
    var lookupUnit: ((LearningUnitTextAnchor, NSTextView) -> Void)? = nil
    var inspect: (Int) -> Void = { _ in }

    func makeNSView(context: Context) -> LearningDictionaryTextView {
        let view = LearningDictionaryTextView(frame: .zero, textContainer: nil)
        view.isEditable = false
        view.isSelectable = false
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.maximumNumberOfLines = maximumLines
        view.textContainer?.lineBreakMode = .byTruncatingTail
        view.textContainer?.widthTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = .labelColor
        return view
    }

    func updateNSView(_ view: LearningDictionaryTextView, context: Context) {
        view.language = language
        view.units = units
        view.chunks = chunks
        view.source = source
        view.lookupUnit = lookupUnit
        view.inspect = inspect
        view.textContainer?.maximumNumberOfLines = maximumLines
        view.font = .systemFont(ofSize: fontSize)
        view.present(text, selectedChunk: selectedChunk)
        view.baseWritingDirection = language == .arabic ? .rightToLeft : .natural
        view.lookup = lookup
        view.toolTip = source
            ? String(localized: "Click to inspect the source phrase match", table: "Learning",
                comment: "Tooltip for the source sentence text; clicking a highlighted range inspects its target-language match.")
            : String(localized: "Double-click an expression to look it up · browse its words in Dictionary", table: "Learning",
                comment: "Tooltip for translated sentence text; complete expressions and their words can be looked up.")
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
    /// Retain the TextKit 1 ownership graph for this view's lifetime. Recent macOS defaults may
    /// create TextKit 2 when init receives nil; then layoutManager is nil and both our size and
    /// exact glyph-hit calculations become unavailable. This view deliberately uses TextKit 1.
    private var ownedTextStorage: NSTextStorage?
    var language: LearningLanguage = .english
    var lookup: (LearningDictionaryTextAnchor, NSTextView) -> Void = { _, _ in }
    var lookupUnit: ((LearningUnitTextAnchor, NSTextView) -> Void)?
    var inspect: (Int) -> Void = { _ in }
    var units: [LearningUnit] = []
    var chunks: [LearningMeaningChunk] = []
    var source = false

    /// Attributes annotate the original string; they never introduce separators or replacement
    /// characters. Neutral expression underlines and source-correspondence colors are separate.
    func present(_ text: String, selectedChunk: Int?) {
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: font ?? .systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor])
        func valid(_ range: NSRange) -> Bool {
            range.location >= 0 && range.length > 0 && range.location <= value.length &&
                range.length <= value.length - range.location && Range(range, in: text) != nil
        }
        if !source {
            for unit in units where unit.kind != .word {
                for range in unit.ranges where valid(range) {
                    value.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor.secondaryLabelColor.withAlphaComponent(0.45)], range: range)
                }
            }
        }
        for chunk in chunks {
            for range in source ? chunk.sourceRanges : chunk.targetRanges where valid(range) {
                value.addAttribute(.backgroundColor,
                    value: NSColor(LearningChunkPalette.color(chunk.id)).withAlphaComponent(selectedChunk == chunk.id ? 0.3 : 0.13),
                    range: range)
            }
        }
        textStorage?.setAttributedString(value)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let resolved: NSTextContainer
        if let container {
            resolved = container
        } else {
            let storage = NSTextStorage(), manager = NSLayoutManager()
            let container = NSTextContainer(size: frameRect.size)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            ownedTextStorage = storage
            resolved = container
        }
        super.init(frame: frameRect, textContainer: resolved)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

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
        guard count == 1 || count == 2, let textContainer, let layoutManager, let font else { return }
        layoutManager.ensureLayout(for: textContainer)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              NSLocationInRange(glyph, layoutManager.glyphRange(for: textContainer)),
              !NSLocationInRange(glyph, layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: glyph)),
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(local) else { return }
        let location = layoutManager.characterIndexForGlyph(at: glyph)
        if count == 1 {
            if let chunk = chunks.first(where: { (source ? $0.sourceRanges : $0.targetRanges).contains { NSLocationInRange(location, $0) } }) {
                inspect(chunk.id)
            }
            return
        }
        guard !source, let word = LearningDictionaryWordPolicy.word(atUTF16Location: location,
            in: string, language: language.naturalLanguage) else { return }
        let unit = LearningUnitPolicy.unit(at: location, units: units) ?? .word(word)
        var lineRange = NSRange()
        _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        let hitRange = unit.ranges.first { NSLocationInRange(location, $0) } ?? word.range
        let wordGlyphs = layoutManager.glyphRange(forCharacterRange: hitRange, actualCharacterRange: nil)
        let visibleGlyphs = NSIntersectionRange(wordGlyphs, lineRange)
        var bounds = layoutManager.boundingRect(forGlyphRange: visibleGlyphs, in: textContainer)
        bounds.origin.x += textContainerOrigin.x
        bounds.origin.y += textContainerOrigin.y
        if let lookupUnit { lookupUnit(.init(unit: unit, bounds: bounds, font: font), self) }
        else { lookup(.init(word: word, bounds: bounds, font: font), self) }
    }
}
