import Foundation

/// Read-only receipt policy after the single editor mutation. Native documents can change their
/// title or briefly lose AX focus when becoming dirty, so the retained field's exact value is the
/// receipt. Web composers can be reused after navigation and still require the saved session.
nonisolated enum LearningReplacementVerificationPolicy {
    static func accepts(expectedValue: String, actualValue: String?, isWebContentField: Bool, sameSession: Bool) -> Bool {
        actualValue?.utf16.elementsEqual(expectedValue.utf16) == true && (!isWebContentField || sameSession)
    }
}
