import AppKit
import SwiftUI

/// App-lifetime nonactivating translation card. The coordinator supplies immutable display values
/// and callbacks; this controller owns only the window. Copy always remains available after errors.
@MainActor
final class LearningTranslationPanel: LearningTranslationPresenting {
    private var panel: NSPanel?
    private(set) var isVisible = false
    private var cancelAction: (() -> Void)?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func hide() {
        isVisible = false
        cancelAction = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor); self.globalMouseMonitor = nil }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
        panel?.orderOut(nil)
    }

    func show(_ presentation: LearningTranslationPresentation, accept: (() -> Void)?, cancel: @escaping () -> Void) {
        cancelAction = cancel
        let caret = presentation.caret
        let window = panel ?? LearningNonactivatingPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel = window
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: LearningTranslationCard(
            source: presentation.source, english: presentation.english,
            message: presentation.message,
            sourceLanguage: presentation.sourceLanguage, targetLanguage: presentation.targetLanguage,
            isSentence: presentation.isSentence,
            accept: accept, cancel: cancel
        ))
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
        window.setFrame(EmojiPickerPanelLayout.frame(caretRect: caret, contentSize: CGSize(width: 420, height: 330),
            visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)), display: true)
        isVisible = true
        window.orderFrontRegardless()
        installClickMonitorsIfNeeded()
    }
    /// Clicking another conversation must cancel even when a host reuses the same AX composer,
    /// URL, title and text. Local panel buttons are excluded so explicit confirmation stays valid.
    private func installClickMonitorsIfNeeded() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelAction?() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                self.cancelAction?()
            }
            return event
        }
    }

}

private final class LearningNonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
