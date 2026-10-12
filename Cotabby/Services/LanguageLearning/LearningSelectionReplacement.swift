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
        let capability = focus.snapshot.capability
        let supported = capability == .supported || capability == .blocked(FocusCapability.selectedTextReason)
        guard supported, let context = focus.snapshot.context,
              !context.isSecure, !context.isIntegratedTerminal,
              let element = AXHelper.focusedElement(forApplicationPID: context.processIdentifier),
              AXHelper.elementIdentifier(for: element, bundleIdentifier: context.bundleIdentifier) == context.elementIdentifier,
              let receipt = AXHelper.exactEditableTextSelection(on: element),
              receipt.range == context.documentSelection else {
            throw LearningFailure.message("当前字段或选区不可信。请重新选中已提交的原文；原文保留。")
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
            throw LearningFailure.message("选区文本与字段范围不一致；原文保留。")
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
                "此编辑器只提供文本标记。请复制当前句子译文，或手动选择原文后再转换。")
        }
        guard isCurrent(saved) else { throw LearningFailure.message("文本、选区或聊天已改变，旧翻译已失效。") }
        let transaction = try prepareSelection(saved)
        // `prepareSelection` may cross the AX boundary and recapture the selected sentence. Recheck
        // permission here so a newly unavailable IME state cannot fall through to native write or Paste.
        guard transaction.supportsReplacement,
              transaction.hasSameReplacementSafety(as: saved) else {
            throw LearningFailure.message(transaction.replacementUnavailableReason ??
                "输入法或选区状态已改变；原文保留。")
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
                throw LearningFailure.message("此字段不支持安全选区替换。请复制译文手动粘贴；原文保留。")
            }
            // Capability reads are synchronous cross-process calls during which the host may edit.
            // Re-read the entire capture afterward, immediately before the single scoped mutation.
            guard isCurrent(transaction) else { throw LearningFailure.message("选区已改变；原文保留。") }
            try Task.checkCancellation()
            guard AXUIElementSetAttributeValue(saved.element, kAXSelectedTextAttribute as CFString, english as CFString) == .success else {
                throw LearningFailure.message("编辑器拒绝替换。请检查原文；可复制译文或原文恢复。")
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
        throw LearningFailure.message("未能核对替换结果。请检查编辑器；卡片保留原文和译文复制入口，避免再次覆盖。")
    }

    private func prepareSelection(_ saved: LearningSelectionCapture) throws -> LearningSelectionCapture {
        guard saved.supportsReplacement else {
            throw LearningFailure.message(saved.replacementUnavailableReason ??
                "此编辑器只提供文本标记。请复制当前句子译文，或手动选择原文后再转换。")
        }
        if saved.originalSelection.length == 0 {
            // Generation never selects the host text. Only explicit confirmation may change the
            // caret into the saved sentence range, and both the setter and a fresh capture must
            // agree before the actual text write. Failure leaves the source available to copy.
            var writable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(saved.element, kAXSelectedTextRangeAttribute as CFString, &writable) == .success,
                  writable.boolValue, isCurrent(saved) else {
                throw LearningFailure.message("无法可靠选中当前句子，请复制译文或手动选择原文。")
            }
            var range = CFRange(location: saved.range.location, length: saved.range.length)
            guard let axRange = AXValueCreate(.cfRange, &range),
                  AXUIElementSetAttributeValue(saved.element, kAXSelectedTextRangeAttribute as CFString, axRange) == .success else {
                throw LearningFailure.message("编辑器无法选择当前句子，请手动选择或复制译文。")
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
                throw LearningFailure.message("句子选区未能核对，未执行文本替换；请手动选择或复制译文。")
            }
            return selected
        }
        return saved
    }
}
