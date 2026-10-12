import AppKit
import Combine
import SwiftUI

/// Owns one nonactivating learning window and one local dictionary actor. Updating its hosting
/// root preserves SwiftUI selection within a document; a new request ID resets that selection.
/// The window never becomes key, so showing, expanding or clicking learning content leaves typing
/// focus in the host editor. Its position follows the existing caret geometry policy.
@MainActor
final class LearningSentencePanel: LearningSentencePresenting {
    private let detailPanel = LearningDetailPanel()
    private var panel: NSPanel?
    private var hosting: NSHostingView<LearningSentenceCard>?
    private(set) var isVisible = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dismissAction: (() -> Void)?
    private var clickMonitorsInstalled = false
    private var currentPresentation: LearningSentencePresentation?
    private var layoutRevision = UUID()
    private var measurementSequence: UInt64 = 0
    private var reservedFrame: CGRect?
    private var contentSize: CGSize?
    private var reservationSubscription: AnyCancellable?

    /// App composition supplies only geometry, keeping translation independent of completion
    /// generation. A later completion can move this panel even when no new translation arrives.
    init(reservedFramePublisher: AnyPublisher<CGRect?, Never>? = nil) {
        reservationSubscription = reservedFramePublisher?.removeDuplicates().sink { [weak self] frame in
            guard let self else { return }
            self.reservedFrame = frame
            if self.currentPresentation != nil, let size = self.contentSize { self.layout(size: size) }
        }
    }

    var visibleFrame: CGRect? { isVisible ? panel?.frame : nil }
    var detailState: LearningDetailState { detailPanel.state }

    /// Esc closes the child first, preserving the sentence pair and its already generated result.
    func dismissDetail() -> Bool {
        guard detailPanel.state.chunk != nil else { return false }
        detailPanel.hide()
        return true
    }

    func hide() {
        isVisible = false
        detailPanel.hide()
        panel?.orderOut(nil)
        dismissAction = nil
        currentPresentation = nil
        contentSize = nil
        layoutRevision = UUID()
        clickMonitorsInstalled = false
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor); self.globalMouseMonitor = nil }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
    }

    func show(_ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void) {
        if let selection = detailPanel.state.chunk,
           selection.documentID != presentation.id || !presentation.isExpanded || presentation.isStale {
            detailPanel.hide()
        }
        currentPresentation = presentation
        let revision = UUID()
        layoutRevision = revision
        let card = LearningSentenceCard(
            presentation: presentation, detailState: detailPanel.state,
            inspect: { [weak self] in self?.inspectChunk($0, documentID: presentation.id) }, expand: expand, dismiss: dismiss,
            sizeChanged: { [weak self] size in
                self?.scheduleLayout(size: size, revision: revision)
            }
        )
        let window = panel ?? LearningSentenceWindow(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        if let hosting, hosting.rootView.presentation.id == presentation.id {
            hosting.rootView = card
        } else {
            let view = NSHostingView(rootView: card)
            hosting = view
            window.contentView = view
        }
        panel = window
        window.title = "表达学习"
        dismissAction = dismiss
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        hosting?.layoutSubtreeIfNeeded()
        if let size = hosting?.fittingSize { layout(size: size) }
        installClickMonitors()
    }

    /// The click carries only a validated meaning ID; the current document supplies its quotes
    /// and explanation, so a stale view cannot query a term from a replaced sentence.
    func inspectChunk(_ identifier: Int, documentID: UUID) {
        guard let presentation = currentPresentation, presentation.isExpanded, !presentation.isStale,
              presentation.id == documentID,
              let chunk = presentation.chunks.first(where: { $0.id == identifier }), let parent = visibleFrame else { return }
        let target = LearningChunkDisplay.quote(presentation.translation, ranges: chunk.targetRanges)
        let detail = LearningChunkDetail(documentID: presentation.id, chunkID: identifier,
            source: LearningChunkDisplay.quote(presentation.source, ranges: chunk.sourceRanges), target: target,
            explanation: chunk.explanation, language: presentation.targetLanguage,
            words: LearningChunkDisplay.words(in: target, language: presentation.targetLanguage))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.intersects(parent) } ?? NSScreen.main
        detailPanel.show(detail, placement: LearningDetailPlacement(parent: parent, caret: presentation.caret, reserved: reservedFrame,
            screen: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600),
            anchorY: parent.contains(mouse) ? mouse.y + 18 : parent.maxY))
    }

    /// Preferences arrive during SwiftUI layout/commit. Changing an AppKit window there can start
    /// a nested transaction, so resize on a later main-actor job. A sequence rejects an older size
    /// even if several measurements arrive before that job runs; the document revision rejects
    /// jobs from a closed or replaced card.
    private func scheduleLayout(size: CGSize, revision: UUID) {
        guard layoutRevision == revision, currentPresentation != nil,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        measurementSequence &+= 1
        let sequence = measurementSequence
        Task { @MainActor [weak self] in
            guard let self, self.layoutRevision == revision, self.measurementSequence == sequence,
                  self.currentPresentation != nil else { return }
            self.layout(size: size)
        }
    }

    /// The view supplies its measured size rather than duplicating dimensions in two layers.
    /// Revision checks above discard queued measurements from a replaced or hidden card.
    private func layout(size: CGSize) {
        guard let presentation = currentPresentation, let panel,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let caret = presentation.caret
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        contentSize = size
        guard let frame = LearningSentencePanelLayout.frame(caretRect: caret, contentSize: size,
            visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600), reservedFrame: reservedFrame) else {
            // Retain the document and its size while space is unavailable. The geometry stream
            // can show it again when completion moves or disappears; no model request is repeated.
            panel.orderOut(nil)
            isVisible = false
            updateDetailParent(nil, presentation: presentation, screen: screen)
            return
        }
        panel.setFrame(frame, display: true)
        isVisible = true
        if !panel.isVisible { panel.orderFrontRegardless() }
        updateDetailParent(panel.frame, presentation: presentation, screen: screen)
    }

    private func updateDetailParent(_ frame: CGRect?, presentation: LearningSentencePresentation, screen: NSScreen?) {
        detailPanel.updateParent(frame, caret: presentation.caret, reserved: reservedFrame,
            screen: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    /// Some chat hosts reuse the same AX field and metadata after navigation. An outside click
    /// invalidates the display even before the next AX observation can identify the new context.
    private func installClickMonitors() {
        guard !clickMonitorsInstalled else { return }
        clickMonitorsInstalled = true
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissAction?() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel, !self.detailPanel.owns(event.window) else { return }
                self.dismissAction?()
            }
            return event
        }
    }
}

private final class LearningSentenceWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
