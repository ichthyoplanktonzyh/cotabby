import AppKit
import ApplicationServices

/// Borrows the existing focus tracker and input-source monitor; no duplicate AX observers exist.
/// Passive hints require the same positive evidence of committed IME text as active conversion.
@MainActor
final class LearningHintSourceReader: LearningHintReading {
    private let focus: FocusTrackingModel
    private let inputSource: KeyboardInputSourceMonitor
    private let settings: LanguageLearningSettings

    init(focus: FocusTrackingModel, inputSource: KeyboardInputSourceMonitor, settings: LanguageLearningSettings) {
        self.focus = focus
        self.inputSource = inputSource
        self.settings = settings
    }

    func candidate() -> LearningHintCandidate? {
        guard settings.translationEnabled, settings.hintsEnabled, focus.snapshot.capability == .supported,
              let context = focus.snapshot.context, context.selection.length == 0,
              !context.isSecure, !context.isIntegratedTerminal, !context.hasHostMarkedText,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processIdentifier,
              let element = AXHelper.focusedElement(forApplicationPID: context.processIdentifier),
              AXHelper.elementIdentifier(for: element, bundleIdentifier: context.bundleIdentifier) == context.elementIdentifier,
              let receipt = AXHelper.exactEditableTextSelection(on: element),
              receipt.range == context.documentSelection,
              (receipt.value as NSString).substring(to: receipt.range.location).hasSuffix(context.precedingText) else { return nil }
        let marked = AXHelper.rangeValue(for: HostMarkedTextPolicy.markedRangeAttribute as CFString, on: element)
        guard (marked?.length ?? 0) == 0, !inputSource.isComposingIMEActive || marked != nil,
              let language = LearningLanguage.detect(in: context.precedingText), settings.sourceLanguages.contains(language),
              language != settings.targetLanguage,
              let source = LearningHintPolicy.source(in: context.precedingText, language: language) else { return nil }
        return .init(context: context, source: source, sourceLanguage: language, targetLanguage: settings.targetLanguage)
    }

    func isCurrent(_ candidate: LearningHintCandidate) -> Bool {
        focus.refreshNow()
        return self.candidate() == candidate
    }
}
