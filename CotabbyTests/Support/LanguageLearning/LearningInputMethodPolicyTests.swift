import Foundation
import Testing
@testable import Cotabby

/// Protects the preview/write boundary across input methods whose hosts expose different AX data.
@Suite
struct LearningInputMethodPolicyTests {
    @Test
    func positiveMarkedRangeRejectsPreviewUntilCandidatesAreCommitted() {
        let assessment = LearningInputMethodPolicy.assess(
            markedRange: NSRange(location: 4, length: 2),
            isComposingInputMethod: true
        )

        #expect(!assessment.permitsReplacement)
        #expect(assessment.replacementUnavailableReason == nil)
        #expect(assessment.previewRejectionReason?.contains("候选词") == true)
    }

    @Test
    func explicitZeroMarkedRangePreservesWritableBehaviorEvenForComposingInputMethod() {
        let assessment = LearningInputMethodPolicy.assess(
            markedRange: NSRange(location: 4, length: 0),
            isComposingInputMethod: true
        )

        #expect(assessment == .replacementAllowed(.explicitlyEmpty))
        #expect(assessment.permitsReplacement)
    }

    @Test
    func missingRangeUnderComposingInputMethodAllowsOnlyCopyablePreview() {
        let assessment = LearningInputMethodPolicy.assess(
            markedRange: nil,
            isComposingInputMethod: true
        )

        #expect(assessment == .copyOnly(reason: LearningInputMethodPolicy.unavailableMarkedRangeReason))
        #expect(!assessment.permitsReplacement)
        #expect(assessment.replacementUnavailableReason?.contains("只读") == true)
    }

    @Test
    func missingRangeWithDirectLayoutKeepsExistingWritableBehavior() {
        let assessment = LearningInputMethodPolicy.assess(
            markedRange: nil,
            isComposingInputMethod: false
        )

        #expect(assessment == .replacementAllowed(.unavailableWithoutComposition))
        #expect(assessment.permitsReplacement)
    }
}
