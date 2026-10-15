import Foundation

/// Separates explicit learning from autocomplete eligibility. A selected query may be translated
/// on purpose even though search fields must never receive unsolicited continuations. This pure,
/// stateless policy is called by LearningSelectionReplacement for each capture; it grants no AX
/// write permission, and the service still verifies the field, selection and input-method state.
enum LearningCapturePolicy {
    /// Passive previews keep the original capability gate. Search-field exceptions require an
    /// explicit shortcut and must never be inherited by the shared AX capture service's callers.
    static func permitsAutomaticCapture(_ capability: FocusCapability) -> Bool {
        capability == .supported || capability == .blocked(FocusCapability.selectedTextReason)
    }

    static func permitsExplicitCapture(_ capability: FocusCapability) -> Bool {
        permitsAutomaticCapture(capability) || capability == .blocked(SearchFieldDetector.blockedReason)
    }

    /// Capability-only focus updates must withdraw passive previews, while a user-requested
    /// preview may remain in a search box. Keeping this rule here prevents coordinator gates drifting.
    static func permitsPreview(_ capability: FocusCapability, explicitlyRequested: Bool) -> Bool {
        permitsAutomaticCapture(capability) || (explicitlyRequested && permitsExplicitCapture(capability))
    }
}
