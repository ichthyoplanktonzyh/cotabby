import AppKit
import Foundation

/// One occurrence in the fixed translation, rather than a deduplicated word-list entry. UTF-16
/// identity lets the panel validate a click against the same sentence TextKit laid out.
nonisolated struct LearningDictionaryWord: Equatable, Sendable {
    let text: String
    let range: NSRange
}

/// View-local geometry exists only for one main-actor lookup event. The text view supplies it;
/// the panel validates document/word identity before the dictionary presenter converts to screen.
/// Keeping font and geometry together avoids guessing a baseline from the whole sentence window.
@MainActor
struct LearningDictionaryTextAnchor {
    let word: LearningDictionaryWord
    let bounds: CGRect
    let font: NSFont
}
