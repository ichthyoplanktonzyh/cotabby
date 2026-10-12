import Foundation

/// Recoverable user-facing rejection shared by pure language-learning rules and the endpoint
/// service. Keeping this error independent of a feature policy lets each boundary report why it
/// rejected a value without coupling the other policies to its file.
nonisolated enum LearningFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        guard case .message(let message) = self else { return nil }
        return message
    }
}
