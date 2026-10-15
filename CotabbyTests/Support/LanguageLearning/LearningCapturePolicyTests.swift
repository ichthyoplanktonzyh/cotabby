import Testing
@testable import Cotabby

/// A search-only autocomplete restriction must not remove an explicitly requested learning task.
@MainActor
struct LearningCapturePolicyTests {
    @Test
    func explicitLearningPermitsSearchAndSelectionRestrictions() {
        #expect(LearningCapturePolicy.permitsExplicitCapture(.supported))
        #expect(LearningCapturePolicy.permitsExplicitCapture(.blocked(FocusCapability.selectedTextReason)))
        #expect(LearningCapturePolicy.permitsExplicitCapture(.blocked(SearchFieldDetector.blockedReason)))
        #expect(!LearningCapturePolicy.permitsAutomaticCapture(.blocked(SearchFieldDetector.blockedReason)))
        #expect(LearningCapturePolicy.permitsAutomaticCapture(.supported))
        #expect(!LearningCapturePolicy.permitsPreview(.blocked(SearchFieldDetector.blockedReason), explicitlyRequested: false))
        #expect(LearningCapturePolicy.permitsPreview(.blocked(SearchFieldDetector.blockedReason), explicitlyRequested: true))
    }

    @Test
    func explicitLearningKeepsOtherRestrictions() {
        #expect(!LearningCapturePolicy.permitsExplicitCapture(.blocked(CredentialFieldDetector.blockedReason)))
        #expect(!LearningCapturePolicy.permitsPreview(.blocked(CredentialFieldDetector.blockedReason), explicitlyRequested: true))
        #expect(!LearningCapturePolicy.permitsExplicitCapture(.blocked("Secure field.")))
        #expect(!LearningCapturePolicy.permitsExplicitCapture(.unsupported("Missing selection range.")))
        #expect(!LearningCapturePolicy.permitsExplicitCapture(.blocked("Cotabby is disabled for this app.")))
    }
}
