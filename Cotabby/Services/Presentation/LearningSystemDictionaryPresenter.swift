import AppKit

/// The correspondence panel owns this narrow AppKit boundary for its lifetime. A clicked button
/// supplies text and geometry; AppKit supplies the dictionary's original UI. Each lookup owns
/// a separate transparent source window because showDefinition has no async cancellation token.
@MainActor
final class LearningSystemDictionaryPresenter {
    private var sourceWindow: LearningDictionarySourcePanel?
    private let display: @MainActor (NSView, NSAttributedString, NSPoint) -> Void

    /// Tests replace only the OS display call, preserving real anchor geometry and window lifetime.
    init(display: @escaping @MainActor (NSView, NSAttributedString, NSPoint) -> Void = displayDefinition) {
        self.display = display
    }

    func show(_ word: String, from button: NSButton) {
        guard button.title == word else { return }
        let title = button.cell?.titleRect(forBounds: button.bounds) ?? button.bounds
        show(word, from: button, textBounds: title, font: button.font ?? .systemFont(ofSize: NSFont.smallSystemFontSize))
    }

    /// Inline sentence lookup and existing word buttons share the same native popup lifetime.
    /// Callers validate document/text identity; this boundary validates the live view and geometry.
    func show(_ word: String, from sourceView: NSView, textBounds: CGRect, font: NSFont) {
        guard !word.isEmpty, word.utf8.count <= 256,
              let parent = sourceView.window, parent.isVisible, !sourceView.isHiddenOrHasHiddenAncestor,
              !sourceView.visibleRect.isEmpty, textBounds.origin.x.isFinite, textBounds.origin.y.isFinite,
              textBounds.width.isFinite, textBounds.height.isFinite,
              textBounds.width > 0, textBounds.height > 0,
              sourceView.visibleRect.intersects(textBounds) else { return }
        let frame = parent.convertToScreen(sourceView.convert(textBounds, to: nil))
        guard frame.width > 0, frame.height > 0 else { return }
        dismiss()
        let source = LearningDictionarySourcePanel(contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        source.isReleasedWhenClosed = false
        source.isOpaque = false
        source.backgroundColor = .clear
        source.hasShadow = false
        source.ignoresMouseEvents = true
        source.level = parent.level
        source.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        source.hidesOnDeactivate = false
        let view = NSView(frame: CGRect(origin: .zero, size: source.contentLayoutRect.size))
        source.contentView = view
        source.allowsDictionaryWindows = true
        sourceWindow = source
        // The empty transparent view paints nothing over the real button. Its child relationship
        // makes native lookup move with the correspondence detail and stay inside its click-monitor family.
        parent.addChildWindow(source, ordered: .above)
        source.orderFrontRegardless()
        let text = NSAttributedString(string: word, attributes: [.font: font])
        // The proxy is unflipped. The baseline is view-local, not a screen point or a window origin.
        // NSWindow aligns its frame to backing pixels. Carry the title's fractional offset into
        // the view-local baseline so that rounding the transparent window does not move the word.
        let localTitle = source.convertFromScreen(frame)
        let baseline = NSPoint(x: localTitle.minX, y: localTitle.midY - (font.ascender + font.descender) / 2)
        display(view, text, baseline)
    }

    func owns(_ window: NSWindow?) -> Bool {
        guard let sourceWindow else { return false }
        var ancestor = window
        while let current = ancestor {
            if current === sourceWindow { return true }
            ancestor = current.parent
        }
        return false
    }

    @discardableResult
    func dismiss() -> Bool {
        guard let source = sourceWindow else { return false }
        sourceWindow = nil
        source.allowsDictionaryWindows = false
        // The transparent source can outlive a popover dismissed by AppKit itself. Only visible
        // native children justify consuming an extra Escape before closing the correspondence detail.
        let wasVisible = (source.childWindows ?? []).contains { $0.isVisible }
        // Hide the source before closing its descendants. Closing only the synchronous highlight
        // does not cancel a pending popover; AppKit can otherwise show it after the user resumed.
        source.orderOut(nil)
        closeDescendants(of: source)
        source.close()
        return wasVisible
    }

    private func closeDescendants(of window: NSWindow) {
        for child in window.childWindows ?? [] { closeDescendants(of: child); child.close() }
    }

    private static func displayDefinition(_ view: NSView, text: NSAttributedString, baseline: NSPoint) {
        // Nil options follow Dictionary preferences and can launch the Dictionary application.
        // The explicit public overlay option keeps lookup beside the word in the learning window.
        view.showDefinition(for: text, range: NSRange(location: 0, length: text.length),
            options: [.presentationType: NSView.DefinitionPresentationType.overlay],
            baselineOriginProvider: { _ in baseline })
    }
}

/// One lookup owns one source panel; it is never reused for another word. AppKit may attach
/// dictionary children after lookup was dismissed. This public hook rejects those late windows,
/// including when a newer lookup has already begun in a different source panel. No private
/// window class names, editor activation, or synthetic keyboard events are involved.
final class LearningDictionarySourcePanel: NSPanel {
    var allowsDictionaryWindows = false
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        super.addChildWindow(childWin, ordered: place)
        guard !allowsDictionaryWindows else { return }
        childWin.orderOut(nil)
        // AppKit may order the window front after attaching it. Retain this rejected window until
        // the next main-actor job closes it outside that transaction; orderOut can detach its parent.
        Task { @MainActor [weak self] in
            // orderOut normally detaches the child. If AppKit reused it under another source
            // before this job ran, that newer owner now decides its lifetime.
            guard childWin.parent == nil || childWin.parent === self else { return }
            childWin.close()
        }
    }
}
