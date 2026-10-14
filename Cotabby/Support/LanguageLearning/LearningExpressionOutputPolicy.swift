import Foundation

/// Validates complete text returned by the learning endpoint before a translation preview or a
/// structured hint decoder can consume it. This boundary keeps output size and insertion safety
/// consistent even though translation and hints have different response formats.
nonisolated enum LearningExpressionOutputPolicy {
    static func validatedText(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 12_000, InsertionSafetyGate.isSafeToInsert(text) else {
            throw LearningFailure.message(String(localized: """
            The model returned empty, oversized, or unsafe-to-insert text. The original text was kept.
            """,
                table: "Learning", comment: "Error shown when generated text fails validation and is not inserted into the editor."))
        }
        return text
    }
}
