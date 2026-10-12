import Foundation

/// Validates complete text returned by the learning endpoint before a translation preview or a
/// structured hint decoder can consume it. This boundary keeps output size and insertion safety
/// consistent even though translation and hints have different response formats.
nonisolated enum LearningExpressionOutputPolicy {
    static func validatedText(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 12_000, InsertionSafetyGate.isSafeToInsert(text) else {
            throw LearningFailure.message("模型返回空内容、过长内容或无法安全插入的字符；原文保留。")
        }
        return text
    }
}
