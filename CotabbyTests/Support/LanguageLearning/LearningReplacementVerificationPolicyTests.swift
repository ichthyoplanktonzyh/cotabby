import Testing
@testable import Cotabby

/// Locks the receipt rule after the one permitted replacement attempt: exact text is sufficient
/// for native fields even if focus identity moved, while reusable web composers also need the saved
/// editing session to remain current.
@Suite
struct LearningReplacementVerificationPolicyTests {
    private let expected = "I did not hand over 2 books at 3 PM."

    @Test
    func nativeExactValueIsAcceptedEvenWhenSessionIdentityChanged() {
        #expect(LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: expected,
            isWebContentField: false,
            sameSession: false
        ))
    }

    @Test
    func webExactValueRequiresTheSameSession() {
        #expect(LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: expected,
            isWebContentField: true,
            sameSession: true
        ))
        #expect(!LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: expected,
            isWebContentField: true,
            sameSession: false
        ))
    }

    @Test
    func anyValueMismatchOrMissingValueFailsForBothFieldKinds() {
        #expect(!LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: "I did not hand over 2 books at 3 PM",
            isWebContentField: false,
            sameSession: false
        ))
        #expect(!LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: "I did not hand over 2 books at 3 PM",
            isWebContentField: true,
            sameSession: true
        ))
        #expect(!LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: nil,
            isWebContentField: false,
            sameSession: false
        ))
        #expect(!LearningReplacementVerificationPolicy.accepts(
            expectedValue: expected,
            actualValue: nil,
            isWebContentField: true,
            sameSession: true
        ))
    }
}
