import CoreGraphics
import Foundation

/// Narrow task boundary lets coordinator tests supply delayed model responses without a server.
/// The app environment owns the production service; a coordinator borrows it for each request.
@MainActor
protocol LearningExpressionGenerating: AnyObject {
    var settings: SuggestionSettingsModel { get }
    func generate(source: String, task: LearningExpressionTask) async throws -> String
}

/// Editor transaction contract separates cancellation/preview policy from cross-process AX calls.
/// Captures are memory-only handles; they are never included in the generation payload.
@MainActor
protocol LearningSelectionReplacing: AnyObject {
    func capture() throws -> LearningSelectionCapture
    func isCurrent(_ saved: LearningSelectionCapture) -> Bool
    func replace(_ saved: LearningSelectionCapture, with english: String) async throws
}

/// Short-lived display data owned by the translation coordinator, consumed by the panel.
/// Keeping data separate from callbacks avoids making presentation know about editing services.
struct LearningTranslationPresentation {
    let source: String
    let english: String
    let message: String
    let caret: CGRect
    /// Source resolution can fail before a request exists. The card then shows the configured
    /// target without inventing a Chinese-to-English direction for the error state.
    var sourceLanguage: LearningLanguage?
    var targetLanguage: LearningLanguage = .english
    var isSentence: Bool = false
}

@MainActor
protocol LearningTranslationPresenting: AnyObject {
    var isVisible: Bool { get }
    func hide()
    func show(_ presentation: LearningTranslationPresentation, accept: (() -> Void)?, cancel: @escaping () -> Void)
}
