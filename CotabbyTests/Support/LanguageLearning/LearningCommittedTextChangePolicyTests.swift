import Foundation
import Testing
@testable import Cotabby

/// Verifies committed-text detection across FocusTracker's bounded windows. Caret navigation can
/// move the window without editing the document, while a true insertion inside shared context or
/// an append at the caret must still count as a mutation.
@Suite
struct LearningCommittedTextChangePolicyTests {
    @Test
    func movingCaretAcrossBoundedWindowsInTheSameDocumentIsNotAMutation() {
        let document = String(repeating: "a", count: 5_000) + "中心段落" + String(repeating: "b", count: 5_000)
        let old = snapshot(document: document, caret: 6_000)
        let moved = snapshot(document: document, caret: 6_100)

        #expect(old.precedingTextMayBeTruncated)
        #expect(moved.precedingTextMayBeTruncated)
        #expect(old.selection.location == FocusedInputSnapshot.textWindowUTF16)
        #expect(moved.selection.location == FocusedInputSnapshot.textWindowUTF16)
        #expect(old.documentSelection.location == 6_000)
        #expect(moved.documentSelection.location == 6_100)
        #expect(old.precedingText != moved.precedingText)
        #expect(old.trailingText != moved.trailingText)
        #expect(!LearningCommittedTextChangePolicy.hasMutation(from: old, to: moved))
    }

    @Test
    func unknownDocumentLengthAndUnavailableTrailingTextDoNotTurnCaretMotionIntoAnAppend() {
        let document = String(repeating: "a", count: 10_000)
        let old = snapshot(document: document, caret: 5_000, trailingTextAvailable: false, documentLengthKnown: false)
        let moved = snapshot(document: document, caret: 5_200, trailingTextAvailable: false, documentLengthKnown: false)

        #expect(old.trailingText.isEmpty && moved.trailingText.isEmpty)
        #expect(old.documentLength == nil && moved.documentLength == nil)
        #expect(!LearningCommittedTextChangePolicy.hasMutation(from: old, to: moved))
    }

    @Test
    func insertionWithinSharedDocumentContextIsAMutation() {
        let oldDocument = "We can solve the problem"
        let newDocument = "We can quickly solve the problem"
        let old = snapshot(document: oldDocument, caret: (oldDocument as NSString).length)
        let newCaret = ("We can quickly" as NSString).length
        let edited = snapshot(document: newDocument, caret: newCaret)

        #expect(LearningCommittedTextChangePolicy.hasMutation(from: old, to: edited))
    }

    @Test
    func appendedTextAtTheCaretIsAMutationEvenWhenBothTrailingWindowsAreEmpty() {
        let oldDocument = "The answer"
        let newDocument = "The answer."
        let old = snapshot(document: oldDocument, caret: (oldDocument as NSString).length)
        let appended = snapshot(document: newDocument, caret: (newDocument as NSString).length)

        #expect(old.trailingText.isEmpty)
        #expect(appended.trailingText.isEmpty)
        #expect(LearningCommittedTextChangePolicy.hasMutation(from: old, to: appended))
    }

    @Test
    func appendInADocumentLongerThanTheCaptureWindowIsAMutation() {
        let oldDocument = String(repeating: "a", count: 8_000)
        let newDocument = oldDocument + "."
        let old = snapshot(document: oldDocument, caret: (oldDocument as NSString).length)
        let appended = snapshot(document: newDocument, caret: (newDocument as NSString).length)

        #expect(old.precedingText.utf16.count == FocusedInputSnapshot.textWindowUTF16)
        #expect(appended.precedingText.utf16.count == FocusedInputSnapshot.textWindowUTF16)
        #expect(old.selection.location == appended.selection.location)
        #expect(old.documentSelection.location != appended.documentSelection.location)
        #expect(old.trailingText.isEmpty && appended.trailingText.isEmpty)
        #expect(LearningCommittedTextChangePolicy.hasMutation(from: old, to: appended))
    }

    @Test
    func clearingAnImeMarkedRangeAtTheSameTextAndCaretCountsAsCommit() {
        let document = "我喜欢"
        let caret = (document as NSString).length
        let markedRange = NSRange(location: caret - 1, length: 1)
        let composing = snapshot(document: document, caret: caret, hostMarkedTextRange: markedRange)
        let committed = snapshot(document: document, caret: caret)

        #expect(composing.precedingText == committed.precedingText)
        #expect(composing.documentSelection == committed.documentSelection)
        #expect(composing.hasHostMarkedText)
        #expect(!committed.hasHostMarkedText)
        #expect(LearningCommittedTextChangePolicy.hasMutation(from: composing, to: committed))
    }

    @Test
    func clearingAnImeMarkedRangeByMovingBackToItsStartIsCancellationNotCommit() {
        let composingDocument = "我喜欢"
        let markedRange = NSRange(location: 2, length: 1)
        let composing = snapshot(
            document: composingDocument,
            caret: (composingDocument as NSString).length,
            hostMarkedTextRange: markedRange
        )
        let cancelledDocument = "我喜"
        let cancelled = snapshot(document: cancelledDocument, caret: markedRange.location)

        #expect(composing.hasHostMarkedText)
        #expect(!cancelled.hasHostMarkedText)
        #expect(!LearningCommittedTextChangePolicy.hasMutation(from: composing, to: cancelled))
    }

    @Test
    func changingSessionOrSelectingTextIsNotACommittedTypingMutation() {
        let oldDocument = "A short editor value"
        let oldCaret = (oldDocument as NSString).length
        let old = snapshot(document: oldDocument, caret: oldCaret)
        let changedDocument = "A replacement editor value"
        let newCaret = (changedDocument as NSString).length
        let newSession = snapshot(document: changedDocument, caret: newCaret, focusChangeSequence: 2)
        let selected = snapshot(document: changedDocument, caret: 2, selectionLength: 4)

        #expect(!LearningCommittedTextChangePolicy.hasMutation(from: old, to: newSession))
        #expect(!LearningCommittedTextChangePolicy.hasMutation(from: old, to: selected))
    }

    private func snapshot(
        document: String,
        caret: Int,
        selectionLength: Int = 0,
        focusChangeSequence: UInt64 = 1,
        hostMarkedTextRange: NSRange? = nil,
        trailingTextAvailable: Bool = true,
        documentLengthKnown: Bool = true
    ) -> FocusedInputSnapshot {
        let text = document as NSString
        let window = FocusedInputSnapshot.textWindowUTF16
        let leftStart = max(0, caret - window)
        let left = text.substring(with: NSRange(location: leftStart, length: caret - leftStart))
        let rightLength = min(window, text.length - caret)
        let right = trailingTextAvailable
            ? text.substring(with: NSRange(location: caret, length: rightLength))
            : ""
        let localSelection = NSRange(location: caret - leftStart, length: selectionLength)

        return FocusedInputSnapshot(
            applicationName: "Test Editor",
            bundleIdentifier: "com.example.editor",
            processIdentifier: 123,
            elementIdentifier: "field",
            role: "AXTextField",
            subrole: nil,
            caretRect: .zero,
            inputFrameRect: nil,
            caretSource: "test",
            caretQuality: .exact,
            observedCharWidth: nil,
            precedingText: left,
            trailingText: right,
            selection: localSelection,
            isSecure: false,
            focusChangeSequence: focusChangeSequence,
            hostMarkedTextRange: hostMarkedTextRange,
            documentSelection: NSRange(location: caret, length: selectionLength),
            documentLength: documentLengthKnown ? text.length : nil
        )
    }
}
