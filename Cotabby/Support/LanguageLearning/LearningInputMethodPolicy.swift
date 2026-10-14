import Foundation

/// Decides whether the current input-method state permits expression preview and later replacement.
/// The service supplies only the AX marked-range result and Cotabby's generic composing-input flag;
/// this pure boundary deliberately has no keyboard-brand or input-source-name allowlist.
nonisolated enum LearningInputMethodPolicy {
    enum MarkedRangeEvidence: Equatable, Sendable {
        /// The host returned a zero-length range, which is an explicit report that no text is marked.
        case explicitlyEmpty
        /// No range was available and no composing input method was selected, so existing write
        /// behavior remains available for direct keyboard layouts and native fields.
        case unavailableWithoutComposition
    }

    enum Assessment: Equatable, Sendable {
        case replacementAllowed(MarkedRangeEvidence)
        case copyOnly(reason: String)
        case rejectPreview(reason: String)

        var permitsReplacement: Bool {
            if case .replacementAllowed = self { return true }
            return false
        }

        var replacementUnavailableReason: String? {
            if case let .copyOnly(reason) = self { return reason }
            return nil
        }

        var previewRejectionReason: String? {
            if case let .rejectPreview(reason) = self { return reason }
            return nil
        }
    }

    static let markedTextConfirmationMessage = String(localized: """
    Your input method has uncommitted text. Confirm the candidate and finish composing before previewing; the original text was kept.
    """,
        table: "Learning", comment: """
        Guidance shown when the host input method still has marked text and the learning feature cannot safely capture it.
        """)

    static let unavailableMarkedRangeReason = String(localized: """
    You can read or copy the result. This editor cannot confirm that writing is safe, so the preview is read-only.
    """,
        table: "Learning", comment: "Explains why a learning preview is read-only when editor or input-method state cannot be verified.")

    /// Manual expression preview is allowed when AX positively reports no marked text or when no
    /// composing input method is selected. Missing AX evidence under a composing input method still
    /// permits the caller's bounded, explicit preview, but never a write into the host field.
    static func assess(markedRange: NSRange?, isComposingInputMethod: Bool) -> Assessment {
        if let markedRange, markedRange.length > 0 {
            return .rejectPreview(reason: markedTextConfirmationMessage)
        }

        if let markedRange, markedRange.length == 0 {
            return .replacementAllowed(.explicitlyEmpty)
        }

        if isComposingInputMethod {
            return .copyOnly(reason: unavailableMarkedRangeReason)
        }

        return .replacementAllowed(.unavailableWithoutComposition)
    }
}
