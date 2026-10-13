import AppKit
import SwiftUI

/// Owned once by the sentence panel. This nonactivating sibling publishes chunk selection to
/// both SwiftUI cards and owns the native dictionary presenter. Definition windows stay attached
/// to this panel, so closing or replacing the phrase also clears the system lookup UI.
@MainActor
final class LearningDetailPanel {
    let state = LearningDetailState()
    private let dictionary: LearningSystemDictionaryPresenter
    private var panel: NSPanel?
    private var hosting: NSHostingView<LearningDetailCard>?
    private var layoutRevision = UUID()
    private var measurementSequence: UInt64 = 0
    private var contentSize: CGSize?
    private var parentFrame: CGRect?
    private var caretRect = CGRect.zero
    private var reservedFrame: CGRect?
    private var screen = CGRect.zero
    private var anchorY: CGFloat = 0
    private var anchorOffsetFromTop: CGFloat = 0
    private(set) var isVisible = false

    init(dictionary: LearningSystemDictionaryPresenter? = nil) {
        self.dictionary = dictionary ?? LearningSystemDictionaryPresenter()
    }

    var visibleFrame: CGRect? { isVisible ? panel?.frame : nil }
    func owns(_ window: NSWindow?) -> Bool {
        // Dictionary popovers can have nested child windows. An ancestor check makes clicking
        // their content an internal interaction without depending on AppKit's private types.
        var ancestor = window
        while let current = ancestor {
            if current === panel { return true }
            ancestor = current.parent
        }
        return false
    }

    func dismissDictionary() -> Bool { dictionary.dismiss() }

    func show(_ chunk: LearningChunkDetail, placement: LearningDetailPlacement) {
        dictionary.dismiss()
        state.chunk = chunk
        anchorY = placement.anchorY
        anchorOffsetFromTop = placement.parent.maxY - placement.anchorY
        layoutRevision = UUID()
        let revision = layoutRevision
        let card = LearningDetailCard(state: state,
            selectWord: { [weak self] word, button in self?.selectWord(word, from: button, chunk: chunk) },
            close: { [weak self] in self?.hide() }, sizeChanged: { [weak self] in self?.scheduleLayout($0, revision: revision) })
        let window = panel ?? LearningDetailWindow(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        if let hosting { hosting.rootView = card } else {
            let view = NSHostingView(rootView: card)
            hosting = view
            window.contentView = view
        }
        panel = window
        window.title = "语块对应"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        hosting?.layoutSubtreeIfNeeded()
        contentSize = hosting?.fittingSize
        updateParent(placement.parent, caret: placement.caret, reserved: placement.reserved, screen: placement.screen)
    }

    func updateParent(_ parent: CGRect?, caret: CGRect, reserved: CGRect?, screen: CGRect) {
        parentFrame = parent
        // The parent may move to avoid a completion that arrives later. Keep the selected point
        // relative to the card rather than retaining an obsolete absolute mouse position.
        if let parent { anchorY = parent.maxY - anchorOffsetFromTop }
        caretRect = caret
        reservedFrame = reserved
        self.screen = screen
        layout()
    }

    func selectWord(_ word: String, from button: NSButton, chunk: LearningChunkDetail) {
        guard isVisible, state.chunk == chunk, chunk.words.contains(word), button.window === panel else { return }
        dictionary.show(word, from: button)
    }

    func hide() {
        dictionary.dismiss()
        layoutRevision = UUID()
        state.chunk = nil
        parentFrame = nil
        contentSize = nil
        isVisible = false
        panel?.orderOut(nil)
    }

    /// Geometry preferences are delivered during view layout. Queue only the latest valid size
    /// outside that transaction, and reject callbacks from a closed or changed meaning unit.
    private func scheduleLayout(_ size: CGSize, revision: UUID) {
        guard layoutRevision == revision, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        measurementSequence &+= 1
        let sequence = measurementSequence
        Task { @MainActor [weak self] in
            guard let self, self.layoutRevision == revision, self.measurementSequence == sequence,
                  self.state.chunk != nil else { return }
            self.contentSize = size
            self.layout()
        }
    }

    private func layout() {
        guard state.chunk != nil, let panel, let parentFrame, let size = contentSize,
              let frame = LearningDetailPanelLayout.frame(parent: parentFrame, anchorY: anchorY,
                size: CGSize(width: ceil(size.width), height: ceil(size.height)), screen: screen,
                obstacles: [caretRect] + (reservedFrame.map { [$0] } ?? [])) else {
            dictionary.dismiss()
            panel?.orderOut(nil)
            isVisible = false
            return
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        isVisible = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

private final class LearningDetailWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
