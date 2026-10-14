import AppKit
import SwiftUI

/// SwiftUI keeps the wrapping word layout, while a native button gives Dictionary Services an
/// actual source view and title baseline. The action carries its view to the panel for document
/// validation; this bridge neither reads the editor nor creates a dictionary service.
struct LearningDictionaryButton: NSViewRepresentable {
    let word: String
    let lookup: (String, NSButton) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(lookup: lookup) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: word, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.refusesFirstResponder = true
        button.toolTip = String(localized: "Look up \(word) in Dictionary", table: "Learning",
            comment: "Tooltip for opening the system Dictionary panel for this word; the word comes from the translated text.")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.lookup = lookup
        button.title = word
        button.toolTip = String(localized: "Look up \(word) in Dictionary", table: "Learning",
            comment: "Tooltip for opening the system Dictionary panel for this word; the word comes from the translated text.")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(size.width, proposal.width ?? size.width), height: size.height)
    }

    /// Owned by SwiftUI for this button's lifetime. Updating the closure keeps reused buttons
    /// tied to the current immutable chunk; the receiving panel rejects clicks from older chunks.
    @MainActor
    final class Coordinator: NSObject {
        var lookup: (String, NSButton) -> Void
        init(lookup: @escaping (String, NSButton) -> Void) { self.lookup = lookup }
        @objc func clicked(_ button: NSButton) { lookup(button.title, button) }
    }
}
