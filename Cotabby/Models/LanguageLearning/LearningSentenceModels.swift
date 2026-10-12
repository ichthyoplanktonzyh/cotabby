import CoreGraphics
import Foundation

/// A meaning unit joins exact spans in the source and the displayed translation. Multiple spans
/// support reordered or discontinuous expressions; an empty side represents an explicit omission
/// or a grammatical addition. The stream parser, rather than the model, owns UTF-16 offsets.
nonisolated struct LearningMeaningChunk: Identifiable, Equatable, Sendable {
    let id: Int
    let sourceRanges: [NSRange]
    let targetRanges: [NSRange]
    let explanation: String
}

/// Each request produces one translation first, followed by its meaning units. Request identity
/// belongs to the coordinator so a late event cannot attach analysis to a newer sentence.
nonisolated enum LearningSentenceUpdate: Equatable, Sendable {
    case translation(String)
    case chunk(LearningMeaningChunk)
}

nonisolated struct LearningSentenceResult: Equatable, Sendable {
    let translation: String
    let chunks: [LearningMeaningChunk]
}

/// Separate from continuation generation: learning has its own model, prompt and output contract.
/// The app environment owns the implementation; tests can supply a controllable event stream.
@MainActor
protocol LearningSentenceGenerating: AnyObject {
    var settings: SuggestionSettingsModel { get }
    func generateSentence(
        source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage,
        onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void
    ) async throws -> LearningSentenceResult
}

/// Memory-only learning display. The original editor capture never leaves the coordinator and
/// this surface has no insertion capability, keeping passive learning independent of Tab/Enter.
struct LearningSentencePresentation {
    let id: UUID
    let source: String
    let translation: String
    let chunks: [LearningMeaningChunk]
    let sourceLanguage: LearningLanguage
    let targetLanguage: LearningLanguage
    let caret: CGRect
    let isExpanded: Bool
    let isGenerating: Bool
    let message: String
    let previousTranslation: String?
    let shortcutLabel: String
    var isStale: Bool = false
}

@MainActor
protocol LearningSentencePresenting: AnyObject {
    var isVisible: Bool { get }
    func hide()
    func dismissDetail() -> Bool
    func show(_ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void)
}

extension LearningSentencePresenting {
    func dismissDetail() -> Bool { false }
}
