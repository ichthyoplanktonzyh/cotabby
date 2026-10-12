import AppKit
import SwiftUI

/// Nonactivating display-only hint panel. It has no acceptance key or editor service; expanding a
/// definition and copying an expression cannot change the host's text. Coordinator owns validity.
@MainActor
final class LearningHintPanel: LearningHintPresenting {
    private var panel: NSPanel?
    private(set) var isVisible = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    func hide() {
        isVisible = false
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor); self.globalMouseMonitor = nil }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
        panel?.orderOut(nil)
    }

    func show(_ hint: LearningWordHint, candidate: LearningHintCandidate, dismiss: @escaping () -> Void) {
        let window = panel ?? LearningHintWindow(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel = window
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: LearningHintCard(hint: hint, source: candidate.source, dismiss: dismiss))
        let caret = candidate.context.caretRect
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
        window.setFrame(EmojiPickerPanelLayout.frame(caretRect: caret, contentSize: CGSize(width: 320, height: 150),
            visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)), display: true)
        isVisible = true
        window.orderFrontRegardless()
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { dismiss() }
            }
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { if event.window !== self?.panel { dismiss() } }
                return event
            }
        }
    }
}

private final class LearningHintWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
