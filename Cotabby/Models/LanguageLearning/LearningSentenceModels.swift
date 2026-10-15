import CoreGraphics
import Foundation

/// Drawable correspondence for one immutable sentence pair. Parsing owns exact UTF-16 ranges;
/// views own color and selection. Explanations are not part of the alignment model's contract.
nonisolated struct LearningMeaningChunk: Identifiable, Equatable, Sendable {
    let id: Int
    let sourceRanges: [NSRange]
    let targetRanges: [NSRange]
}

/// Each request produces one translation first, followed by its meaning units. Request identity
/// belongs to the coordinator so a late event cannot attach analysis to a newer sentence.
nonisolated enum LearningSentenceUpdate: Equatable, Sendable {
    case translation(String)
    /// Complete validated alignment is published as one batch, preserving atomic highlighting.
    case chunks([LearningMeaningChunk])
    /// Retained for the historical NDJSON evaluator and controlled coordinator test fixtures.
    case chunk(LearningMeaningChunk)
}

nonisolated struct LearningSentenceResult: Equatable, Sendable {
    let translation: String
    let chunks: [LearningMeaningChunk]
    var unresolvedChunkCount: Int = 0
}

/// Separate from continuation generation: learning has its own model, prompt and output contract.
/// The app environment owns the implementation; tests can supply a controllable event stream.
@MainActor
protocol LearningSentenceGenerating: LearningDisplayReporting {
    var settings: SuggestionSettingsModel { get }
    func translateSentence(source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage) async throws -> String
    func translateSentence(input: LearningTranslationInput, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage) async throws
        -> String
    func analyzeSentence(source: String, translation: String, sourceLanguage: LearningLanguage,
                         targetLanguage: LearningLanguage,
                         onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult
    func generateSentence(
        source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage,
        onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void
    ) async throws -> LearningSentenceResult
}

extension LearningSentenceGenerating {
    func translateSentence(input: LearningTranslationInput, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage) async throws
        -> String {
        try await translateSentence(source: input.source, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }
    func translateSentence(source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage) async throws -> String {
        try await generateSentence(source: source, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, onUpdate: { _ in }).translation
    }
    func analyzeSentence(source: String, translation: String, sourceLanguage: LearningLanguage,
                         targetLanguage: LearningLanguage,
                         onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
        .init(translation: translation, chunks: [])
    }
}

/// Memory-only learning display. The original AX capture stays in the coordinator; the view
/// receives only versioned text and an explicit confirmation callback. Ordinary typing stays in
/// the host editor, independently of whether the writer chooses to replace this preview.
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
    var units: [LearningUnit] = []
    var unitStage: LearningUnitStage = .pending
    var targetIsSelection = false
    var canReplace = false
    var replacementShortcutLabel = ""
    var isCommitting = false
    var isError = false
}

@MainActor
protocol LearningSentencePresenting: AnyObject {
    var isVisible: Bool { get }
    func hide()
    func dismissDetail() -> Bool
    func show(_ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void)
    func show(
        _ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void,
        replace: (() -> Void)?)
}

extension LearningSentencePresenting {
    func show(
        _ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void,
        replace: (() -> Void)?
    ) { show(presentation, expand: expand, dismiss: dismiss) }
    func dismissDetail() -> Bool { false }
}
