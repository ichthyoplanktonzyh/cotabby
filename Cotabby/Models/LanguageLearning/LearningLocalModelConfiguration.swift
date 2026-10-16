import Foundation

/// The controller freezes a model destination, adapter and native capacity before leaving
/// MainActor. Planning and generation consume this same short-lived value; neither reaches back
/// into mutable UI preferences while a native operation is queued. It owns no model allocation.
nonisolated struct LearningLocalModelConfiguration: Equatable, Sendable {
    let modelURL: URL
    let template: LearningChatTemplate
    let contextWindowTokens: Int
}
