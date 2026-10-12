import ApplicationServices
import Foundation
import Testing
@testable import Cotabby

/// Locks down the write-permission evidence stored in a capture, independently of live AX I/O.
@Suite(.serialized)
@MainActor
struct LearningSelectionCaptureTests {
    @Test
    func copyOnlyRecaptureIsNotTheSameSafetyAsWritableCapture() {
        let writable = makeCapture(assessment: .replacementAllowed(.explicitlyEmpty))
        let copyOnly = makeCapture(
            assessment: .copyOnly(reason: LearningInputMethodPolicy.unavailableMarkedRangeReason),
            reason: LearningInputMethodPolicy.unavailableMarkedRangeReason
        )

        #expect(writable.supportsReplacement)
        #expect(!copyOnly.supportsReplacement)
        #expect(!writable.hasSameReplacementSafety(as: copyOnly))
    }

    @Test
    func changingMarkedRangeEvidenceInvalidatesTheSavedWriteDecision() {
        let explicitZero = makeCapture(assessment: .replacementAllowed(.explicitlyEmpty))
        let unavailableOnDirectLayout = makeCapture(
            assessment: .replacementAllowed(.unavailableWithoutComposition)
        )

        #expect(explicitZero.supportsReplacement)
        #expect(unavailableOnDirectLayout.supportsReplacement)
        #expect(!explicitZero.hasSameReplacementSafety(as: unavailableOnDirectLayout))
    }

    @Test
    func identicalAllowedEvidenceKeepsTheSameWriteDecision() {
        let first = makeCapture(assessment: .replacementAllowed(.explicitlyEmpty))
        let recaptured = makeCapture(assessment: .replacementAllowed(.explicitlyEmpty))

        #expect(first.supportsReplacement)
        #expect(first.hasSameReplacementSafety(as: recaptured))
    }

    @Test
    func missingReasonCannotTurnCopyOnlyAssessmentIntoWritePermission() {
        let capture = makeCapture(assessment: .copyOnly(reason: "AX evidence unavailable"))

        #expect(capture.replacementUnavailableReason == nil)
        #expect(!capture.supportsReplacement)
        #expect(capture.hasSameReplacementSafety(as: capture))
    }

    private func makeCapture(
        assessment: LearningInputMethodPolicy.Assessment,
        reason: String? = nil
    ) -> LearningSelectionCapture {
        let source = "A short source sentence."
        let selection = NSRange(location: 0, length: 0)
        let context = CotabbyTestFixtures.focusedInputSnapshot(
            precedingText: source,
            selection: selection,
            documentLength: (source as NSString).length
        )

        return LearningSelectionCapture(
            element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier),
            context: context,
            value: source,
            range: NSRange(location: 0, length: (source as NSString).length),
            source: source,
            usesTextMarkers: false,
            editorSelection: selection,
            replacementUnavailableReason: reason,
            inputMethodAssessment: assessment
        )
    }
}
