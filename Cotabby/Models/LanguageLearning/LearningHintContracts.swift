import Foundation

/// Local-only identity accompanying one hint. Field context never enters its model request.
/// Keeping the candidate comparable makes stale text, selection and session checks explicit.
nonisolated struct LearningHintCandidate: Equatable {
    let context: FocusedInputSnapshot
    let source: String
    let sourceLanguage: LearningLanguage
    let targetLanguage: LearningLanguage
}

@MainActor
protocol LearningHintReading: AnyObject {
    func candidate() -> LearningHintCandidate?
    func isCurrent(_ candidate: LearningHintCandidate) -> Bool
}

@MainActor
protocol LearningHintPresenting: AnyObject {
    var isVisible: Bool { get }
    func hide()
    func show(_ hint: LearningWordHint, candidate: LearningHintCandidate, dismiss: @escaping () -> Void)
}
