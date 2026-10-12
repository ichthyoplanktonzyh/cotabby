import AppKit
import SwiftUI

/// Owned once by the sentence panel. This sibling window owns dictionary task identity and
/// publishes selection to both SwiftUI cards. Its nonactivating AppKit boundary keeps editor focus
/// intact; hiding or changing a phrase cancels lookup delivery independently of model generation.
@MainActor
final class LearningDetailPanel {
    let state = LearningDetailState()
    private let dictionary: any LearningDictionaryProviding
    private var panel: NSPanel?
    private var hosting: NSHostingView<LearningDetailCard>?
    private var lookupTask: Task<Void, Never>?
    private var lookupRevision = UUID()
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

    init(dictionary: any LearningDictionaryProviding = LearningDictionaryService()) { self.dictionary = dictionary }

    var visibleFrame: CGRect? { isVisible ? panel?.frame : nil }
    func owns(_ window: NSWindow?) -> Bool { window != nil && window === panel }

    func show(_ chunk: LearningChunkDetail, placement: LearningDetailPlacement) {
        cancelLookup()
        state.chunk = chunk
        state.word = nil
        state.entry = nil
        anchorY = placement.anchorY
        anchorOffsetFromTop = placement.parent.maxY - placement.anchorY
        layoutRevision = UUID()
        let revision = layoutRevision
        let card = LearningDetailCard(state: state,
            selectWord: { [weak self] in self?.selectWord($0) }, back: { [weak self] in self?.back() },
            close: { [weak self] in self?.hide() }, sizeChanged: { [weak self] in self?.scheduleLayout($0, revision: revision) })
        let window = panel ?? LearningDetailWindow(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        if let hosting { hosting.rootView = card } else {
            let view = NSHostingView(rootView: card)
            hosting = view
            window.contentView = view
        }
        panel = window
        window.title = "语块说明"
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

    func selectWord(_ word: String) {
        guard let chunk = state.chunk, chunk.words.contains(word) else { return }
        cancelLookup()
        let revision = lookupRevision
        state.word = word
        state.entry = nil
        state.isLoading = true
        panel?.title = "系统词典 · \(word)"
        lookupTask = Task { [weak self, dictionary] in
            let entry = await dictionary.entry(for: word, language: chunk.language)
            guard !Task.isCancelled, let self, self.lookupRevision == revision,
                  self.state.chunk == chunk, self.state.word == word else { return }
            self.state.entry = entry
            self.state.isLoading = false
        }
    }

    func back() {
        cancelLookup()
        state.word = nil
        state.entry = nil
        panel?.title = "语块说明"
    }

    func hide() {
        cancelLookup()
        layoutRevision = UUID()
        state.chunk = nil
        state.word = nil
        state.entry = nil
        parentFrame = nil
        contentSize = nil
        isVisible = false
        panel?.orderOut(nil)
    }

    private func cancelLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        lookupRevision = UUID()
        state.isLoading = false
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
