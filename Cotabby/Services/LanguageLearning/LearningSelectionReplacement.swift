import AppKit
import ApplicationServices

/// Captures the exact editor value and selection in memory after the user explicitly requests an
/// expression preview. The source remains bounded by `LearningTextScopePolicy`; AX handles retain
/// their CF object and never enter a model request. A coordinator owns one capture until cancellation
/// or commit, and must keep a capture with unverified IME state copy-only.
@MainActor
struct LearningSelectionCapture {
    let element: AXUIElement
    let context: FocusedInputSnapshot
    let value: String
    let range: NSRange
    let source: String
    var usesTextMarkers: Bool = false
    var editorSelection: NSRange?
    /// Set when capture is safe for preview but AX could not prove that a composing input method
    /// has committed its text. The coordinator uses this to present a copy-only result.
    var replacementUnavailableReason: String?
    /// Kept with the capture so revalidation detects changes in the host's write-safety evidence.
    var inputMethodAssessment: LearningInputMethodPolicy.Assessment
    var originalSelection: NSRange { editorSelection ?? context.documentSelection }
    var supportsReplacement: Bool {
        replacementUnavailableReason == nil && inputMethodAssessment.permitsReplacement &&
            (!usesTextMarkers || originalSelection.length > 0)
    }

    /// Compares only the evidence that determines whether a saved capture can still be written.
    /// Preview freshness has additional field/value checks owned by `LearningSelectionReplacement`.
    func hasSameReplacementSafety(as other: LearningSelectionCapture) -> Bool {
        inputMethodAssessment == other.inputMethodAssessment &&
            replacementUnavailableReason == other.replacementUnavailableReason &&
            usesTextMarkers == other.usesTextMarkers &&
            supportsReplacement == other.supportsReplacement
    }
}

/// Narrow AX transaction boundary. Native fields use selected-text writes; web fields use a
/// verified Paste command. Neither path overwrites a whole field or retries an uncertain edit. Verification
/// distinguishes a successful AX call from a successful editor edit; uncertain edits are not retried.
@MainActor
final class LearningSelectionReplacement: LearningSelectionReplacing {
    private let focus: FocusTrackingModel
    private let inputSource: KeyboardInputSourceMonitor
    private let inserter: SuggestionInserter

    init(focus: FocusTrackingModel, inputSource: KeyboardInputSourceMonitor, inserter: SuggestionInserter) {
        self.inserter = inserter
        self.focus = focus
        self.inputSource = inputSource
    }

    func capture() throws -> LearningSelectionCapture {
        focus.refreshNow()
        guard LearningCapturePolicy.permitsExplicitCapture(focus.snapshot.capability), let context = focus.snapshot.context,
              !context.isSecure, !context.isIntegratedTerminal,
              let element = AXHelper.focusedElement(forApplicationPID: context.processIdentifier),
              AXHelper.elementIdentifier(for: element, bundleIdentifier: context.bundleIdentifier) == context.elementIdentifier,
              let receipt = AXHelper.exactEditableTextSelection(on: element),
              receipt.range == context.documentSelection else {
            throw LearningFailure.message(String(localized: """
            This field or selection cannot be verified. Select the committed source text again; the original text was kept.
            """,
                table: "Learning", comment: """
                Error shown when Accessibility cannot verify the field, selection, or committed source text for a translation preview.
                """))
        }
        guard !context.hasHostMarkedText else {
            throw LearningFailure.message(LearningInputMethodPolicy.markedTextConfirmationMessage)
        }
        let value = receipt.value
        let range = receipt.range
        let marked = AXHelper.rangeValue(for: HostMarkedTextPolicy.markedRangeAttribute as CFString, on: element)
        let inputMethodAssessment = LearningInputMethodPolicy.assess(
            markedRange: marked,
            isComposingInputMethod: inputSource.isComposingIMEActive
        )
        if let reason = inputMethodAssessment.previewRejectionReason {
            throw LearningFailure.message(reason)
        }
        let replacementRange = try LearningTextScopePolicy.conversionRange(value: value, selection: range)
        let source = try LearningTextScopePolicy.text(value: value, range: replacementRange)
        guard receipt.usesTextMarkers || range.length == 0 ||
                AXHelper.stringValue(for: kAXSelectedTextAttribute as CFString, on: element) == source else {
            throw LearningFailure.message(String(localized: "The selected text does not match the field range; the original text was kept.",
                table: "Learning", comment: "Error shown when the selected text differs from the verified range in the editor."))
        }
        return LearningSelectionCapture(element: element, context: context, value: value, range: replacementRange, source: source,
            usesTextMarkers: receipt.usesTextMarkers, editorSelection: range,
            replacementUnavailableReason: inputMethodAssessment.replacementUnavailableReason,
            inputMethodAssessment: inputMethodAssessment)
    }

    func isCurrent(_ saved: LearningSelectionCapture) -> Bool {
        guard let current = try? capture() else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.context.processIdentifier &&
            current.context.sessionIdentity == saved.context.sessionIdentity &&
            CFEqual(current.element, saved.element) && current.value.utf16.elementsEqual(saved.value.utf16) &&
            current.range == saved.range &&
            current.originalSelection == saved.originalSelection &&
            current.hasSameReplacementSafety(as: saved)
    }

    func replace(_ saved: LearningSelectionCapture, with english: String) async throws {
        try Task.checkCancellation()
        guard saved.supportsReplacement else {
            throw LearningFailure.message(saved.replacementUnavailableReason ??
                String(localized: """
                This editor only provides text markers. Copy the current sentence translation, or select the source manually and \
                preview it again.
                """,
                    table: "Learning", comment: """
                    Copy-only recovery guidance when the editor does not expose a safe text-selection replacement action.
                    """))
        }
        guard isCurrent(saved) else {
            throw LearningFailure.message(String(localized: """
            The text, selection, or conversation changed. The previous translation is no longer valid.
            """,
                table: "Learning", comment: "Error shown when the saved source text or host conversation changes before replacement."))
        }
        let transaction = try prepareSelection(saved)
        // `prepareSelection` may cross the AX boundary and recapture the selected sentence. Recheck
        // permission here so a newly unavailable IME state cannot fall through to native write or Paste.
        guard transaction.supportsReplacement,
              transaction.hasSameReplacementSafety(as: saved) else {
            throw LearningFailure.message(transaction.replacementUnavailableReason ??
                String(localized: "The input method or selection changed; the original text was kept.",
                    table: "Learning", comment: """
                    Error shown when input-method composition or selection safety changes before replacement.
                    """))
        }
        let expected = (saved.value as NSString).replacingCharacters(in: saved.range, with: english)
        let isWeb = saved.context.isWebContentField || saved.usesTextMarkers
        if isWeb {
            // Chromium can acknowledge AXSelectedText while doing nothing. Use its real Paste
            // command, with final selection validation after locating the menu item. A failed
            // AXPress is still an uncertain dispatch; inspect the editor without retrying it.
            _ = inserter.pasteSelectedText(english, inApplicationPID: saved.context.processIdentifier,
                validateSelection: { !Task.isCancelled && self.isCurrent(transaction) })
        } else {
            var writable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(saved.element, kAXSelectedTextAttribute as CFString, &writable) == .success,
                  writable.boolValue else {
                throw LearningFailure.message(String(localized: """
                This field does not support safe selection replacement. Copy and paste the translation manually; the original text was \
                kept.
                """,
                    table: "Learning", comment: """
                    Recovery guidance when the host field does not allow safe replacement of the selected source.
                    """))
            }
            // Capability reads are synchronous cross-process calls during which the host may edit.
            // Re-read the entire capture afterward, immediately before the single scoped mutation.
            guard isCurrent(transaction) else {
                throw LearningFailure.message(String(localized: "The selection changed; the original text was kept.",
                    table: "Learning", comment: "Error shown when the selection changes just before a confirmed replacement."))
            }
            try Task.checkCancellation()
            guard AXUIElementSetAttributeValue(saved.element, kAXSelectedTextAttribute as CFString, english as CFString) == .success else {
                throw LearningFailure.message(String(localized: """
                The editor refused the replacement. Check the source text; you can copy the translation or restore the original.
                """,
                    table: "Learning", comment: "Recovery guidance when the editor rejects a confirmed selection replacement."))
            }
        }
        // Editors publish AX state asynchronously. Never roll back an unverified value: the user
        // may already have typed, and an automatic restoration could overwrite their new content.
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(60))
            focus.refreshNow()
            let sameSession = focus.snapshot.context?.sessionIdentity == saved.context.sessionIdentity
            if LearningReplacementVerificationPolicy.accepts(expectedValue: expected,
                actualValue: AXHelper.exactEditableTextSelection(on: saved.element)?.value,
                isWebContentField: isWeb, sameSession: sameSession) { return }
            if isWeb, !sameSession { break }
        }
        throw LearningFailure.message(String(localized: """
        Could not verify the replacement. Check the editor. The card keeps copy actions for the source and translation to avoid \
        another overwrite.
        """,
            table: "Learning", comment: "Recovery guidance when Accessibility cannot confirm whether the editor applied the replacement."))
    }

    private func prepareSelection(_ saved: LearningSelectionCapture) throws -> LearningSelectionCapture {
        guard saved.supportsReplacement else {
            throw LearningFailure.message(saved.replacementUnavailableReason ??
                String(localized: """
                This editor only provides text markers. Copy the current sentence translation, or select the source manually and \
                preview it again.
                """,
                    table: "Learning", comment: """
                    Copy-only recovery guidance when the editor does not expose a safe text-selection replacement action.
                    """))
        }
        if saved.originalSelection.length == 0 {
            // Generation never selects the host text. Only explicit confirmation may change the
            // caret into the saved sentence range, and both the setter and a fresh capture must
            // agree before the actual text write. Failure leaves the source available to copy.
            var writable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(saved.element, kAXSelectedTextRangeAttribute as CFString, &writable) == .success,
                  writable.boolValue, isCurrent(saved) else {
                throw LearningFailure.message(String(localized: """
                Could not safely select the current sentence. Copy the translation or select the source manually.
                """,
                    table: "Learning", comment: "Recovery guidance when the current sentence cannot be selected safely for replacement."))
            }
            var range = CFRange(location: saved.range.location, length: saved.range.length)
            guard let axRange = AXValueCreate(.cfRange, &range),
                  AXUIElementSetAttributeValue(saved.element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success else {
                throw LearningFailure.message(String(localized: """
                The editor could not select the current sentence. Select the source manually or copy the translation.
                """,
                    table: "Learning", comment: "Recovery guidance when the editor refuses to select the current sentence."))
            }
            let selected = try capture()
            guard selected.context.sessionIdentity == saved.context.sessionIdentity,
                  CFEqual(selected.element, saved.element), selected.value.utf16.elementsEqual(saved.value.utf16),
                  selected.range == saved.range, selected.source == saved.source,
                  selected.originalSelection == saved.range,
                  selected.supportsReplacement,
                  selected.inputMethodAssessment == saved.inputMethodAssessment,
                  selected.replacementUnavailableReason == saved.replacementUnavailableReason,
                  selected.hasSameReplacementSafety(as: saved) else {
                throw LearningFailure.message(String(localized: """
                Could not verify the sentence selection. No text was replaced; select the source manually or copy the translation.
                """,
                    table: "Learning", comment: """
                    Error shown when the selected sentence does not match the saved source; replacement has not run.
                    """))
            }
            return selected
        }
        return saved
    }
}
