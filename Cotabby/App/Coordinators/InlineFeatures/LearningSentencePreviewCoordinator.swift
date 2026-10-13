import Combine
import AppKit
import CoreGraphics
import Foundation
import Logging

/// App-lifetime sibling of autocomplete. It observes the existing focus stream, waits for edits
/// to settle and owns one versioned learning request. Its panel is read-only: ordinary keystrokes,
/// including Tab and Return, always continue to the editor and original autocomplete pipeline.
@MainActor
final class LearningSentencePreviewCoordinator {
    private let service: any LearningSentenceGenerating
    private let reader: any LearningSelectionReplacing
    private let focus: any SuggestionFocusProviding
    private let panel: any LearningSentencePresenting
    private let availability: () -> String?
    private let debounce: Duration
    private let waitForPause: @MainActor (Duration) async throws -> Void
    private let isFrontmost: @MainActor (Int32) -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var work: Task<Void, Never>?
    private var analysisWork: Task<Void, Never>?
    private var analysisID = UUID()
    private var analysisCache: [AnalysisKey: LearningSentenceResult] = [:]
    private var requestID = UUID()
    private var previousContext: FocusedInputSnapshot?
    private var document: Document?
    private var expanded = false
    private var dismissedSource: String?
    private var cache: [String: LearningSentenceResult] = [:]
    private var running = false

    private struct AnalysisKey: Hashable {
        let source: String
        let translation: String
        let sourceLanguage: LearningLanguage
        let targetLanguage: LearningLanguage
        let model: LearningModelSnapshot
    }

    private struct Document {
        let id: UUID
        let traceID: String
        let capture: LearningSelectionCapture
        let sourceLanguage: LearningLanguage
        let targetLanguage: LearningLanguage
        var translation = ""
        var chunks: [LearningMeaningChunk] = []
        var generating = true
        var message = "正在生成目标表达…"
        var previousSentence: PreviousSentence?
        var isStale = false
    }

    /// A previous result carries its source evidence, so editing earlier text cannot relabel an
    /// old version of that same sentence as its predecessor. This value lives only in the panel session.
    private struct PreviousSentence {
        let source: String
        let range: NSRange
        let translation: String
    }

    init(
        service: any LearningSentenceGenerating,
        reader: any LearningSelectionReplacing,
        focus: any SuggestionFocusProviding,
        panel: any LearningSentencePresenting,
        debounce: Duration = .milliseconds(600),
        waitForPause: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        isFrontmost: @escaping @MainActor (Int32) -> Bool = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == $0
        },
        availability: @escaping () -> String? = { nil }
    ) {
        self.service = service
        self.reader = reader
        self.focus = focus
        self.panel = panel
        self.debounce = debounce
        self.waitForPause = waitForPause
        self.isFrontmost = isFrontmost
        self.availability = availability
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        running = true
        previousContext = focus.snapshot.context
        focus.snapshotPublisher.sink { [weak self] in self?.changed($0.context) }.store(in: &subscriptions)
        Publishers.MergeMany([
            service.settings.languageLearning.changes,
            service.settings.$isGloballyEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.$pauseState.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.snapshotPublisher.map(\.isLowPowerModeAutoDisableEnabled).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.snapshotPublisher.map(\.disabledAppBundleIdentifiers).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]).sink { [weak self] in self?.clear() }.store(in: &subscriptions)
        service.settings.languageLearning.analysisChanges.sink { [weak self] in
            // @Published delivers before the edited value is stored. Defer configuration work
            // one main-actor turn and keep the already displayed translation intact.
            Task { @MainActor [weak self] in
                self?.analysisCache.removeAll()
                self?.startAnalysis()
            }
        }.store(in: &subscriptions)
    }

    func stop() { running = false; clear(); previousContext = nil; subscriptions.removeAll() }
    /// A device-wide pause cancels current work immediately; resuming still requires a new edit.
    func availabilityChanged() { clear() }

    /// Observing typing never claims it. Hide immediately, even before AX publishes committed
    /// text; only the next settled edit or an explicit shortcut may present a new version.
    func observe(_ event: CapturedInputEvent) -> Bool {
        if event.shouldClearSuggestion, event.keyCode != 53, !matchesShortcut(event.keyCode, flags: event.flags) {
            suspendPreview()
        }
        return false
    }

    func decide(_ event: InputMonitorKeyEvent) -> InputMonitorAcceptTapDecision {
        // Closing already visible UI must remain possible after availability changes (for
        // example Low Power Mode). Eligibility gates new work, not dismissal of existing panels.
        if event.keyCode == 53, panel.dismissDetail() { return .consume }
        if event.keyCode == 53, panel.isVisible {
            dismiss()
            return .consume
        }
        guard enabled, availability() == nil else { return .notHandled }
        guard matchesShortcut(event.keyCode, flags: event.flags), !shortcutConflicts else { return .notHandled }
        guard !event.isAutorepeat else { return .consume }
        // AX reads cannot block the consuming keyboard tap. The following task either expands
        // the current version or explicitly reads a selected/current sentence for a fresh preview.
        let identifier = requestID
        Task { [weak self] in
            guard let self, self.running, self.requestID == identifier else { return }
            self.expandOrRequest()
        }
        return .consume
    }

    private var enabled: Bool {
        let settings = service.settings.languageLearning
        return running && settings.translationEnabled && settings.sentencePreviewEnabled
    }

    private var shortcutConflicts: Bool {
        let settings = service.settings.languageLearning
        return service.settings.conflictingPerAppShortcutName(
            forBundleIdentifier: focus.snapshot.bundleIdentifier ?? "", keyCode: CGKeyCode(settings.keyCode),
            modifiers: settings.modifiers, excluding: .toggleTabby, includingLearningShortcut: false
        ) != nil
    }

    private func matchesShortcut(_ code: UInt16, flags: CGEventFlags) -> Bool {
        let settings = service.settings.languageLearning
        return code == settings.keyCode && ShortcutModifierMask(eventFlags: flags) == settings.modifiers
    }

    private func changed(_ context: FocusedInputSnapshot?) {
        let old = previousContext
        previousContext = context
        guard old?.sessionIdentity == context?.sessionIdentity else { clear(); return }
        guard let old, let context else { return }
        let changed = old.contentSignature != context.contentSignature || old.documentSelection != context.documentSelection ||
            old.hasHostMarkedText != context.hasHostMarkedText
        guard changed else { return }
        suspendPreview()
        guard enabled, availability() == nil, !context.isSecure, !context.isIntegratedTerminal,
              context.documentSelection.length == 0,
              LearningCommittedTextChangePolicy.hasMutation(from: old, to: context) else {
            // Caret navigation is not consent to translate existing text. Also remove a preview
            // whose field became secure or unavailable rather than retaining it over another UI.
            panel.hide()
            return
        }
        dismissedSource = nil
        guard !context.hasHostMarkedText else { return }
        let identifier = requestID
        work = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.waitForPause(self.debounce)
                guard self.requestID == identifier, !Task.isCancelled, self.enabled, self.availability() == nil else { return }
                let capture = try self.reader.capture()
                guard capture.originalSelection.length == 0, !capture.context.hasHostMarkedText,
                      capture.context.sessionIdentity == context.sessionIdentity,
                      self.reader.isCurrent(capture), self.requestID == identifier, !Task.isCancelled else { return }
                // This debounce is handing ownership to the generation/cache path. Remove its
                // handle first so begin's cancellation cannot cancel the task currently executing
                // a cache hit (which would make startAnalysis reject an otherwise current pair).
                self.work = nil
                self.begin(capture, expanded: false)
            } catch {
                if self.requestID == identifier { self.work = nil }
            }
        }
    }

    private func expandOrRequest() {
        guard enabled, availability() == nil else { return }
        focus.refreshNow()
        if let document, !document.isStale, reader.isCurrent(document.capture) {
            expanded.toggle()
            dismissedSource = nil
            render()
            return
        }
        do {
            let capture = try reader.capture()
            begin(capture, expanded: true)
        } catch {
            // An explicit shortcut may report an error; passive AX failures stay silent.
            if document != nil { document?.message = error.localizedDescription; expanded = true; render() }
        }
    }

    private func begin(_ capture: LearningSelectionCapture, expanded: Bool) {
        let settings = service.settings.languageLearning
        guard enabled, availability() == nil, capture.source != dismissedSource,
              let language = LearningSourceLanguageResolver().resolve(text: capture.source,
                  enabledSourceLanguages: settings.sourceLanguages, targetLanguage: settings.targetLanguage) else { return }
        guard expanded || LearningAutomaticLanguagePolicy.accepts(capture.source, sourceLanguage: language) else {
            panel.hide()
            return
        }
        cancelWork()
        let identifier = requestID
        let old = document
        // Only an explicit sentence boundary creates a previous-sentence line. Appending to an
        // unfinished sentence replaces its preview, even when a pause previously showed a result.
        let prior = precedingSentence(from: old, capture: capture)
        document = Document(id: identifier, traceID: RequestID.generate(), capture: capture, sourceLanguage: language,
            targetLanguage: settings.targetLanguage, previousSentence: prior)
        self.expanded = expanded
        let key = language.rawValue + ":" + settings.targetLanguage.rawValue + ":" + capture.source
        if let cached = cache[key] {
            CotabbyLogger.learning.info("Learning translation cache hit", metadata: [
                "request_id": .string(document?.traceID ?? ""), "source": .string("translation"), "phase": .string("cache_hit")])
            document?.translation = cached.translation
            document?.chunks = []
            document?.generating = false
            document?.message = ""
            render()
            startAnalysis()
            return
        }
        render()
        let traceIdentifier = document?.traceID ?? RequestID.generate()
        work = Task { [weak self] in
            guard let self else { return }
            await LearningRequestTrace.$requestID.withValue(traceIdentifier) {
                do {
                    let translation = try await self.service.translateSentence(source: capture.source,
                        sourceLanguage: language, targetLanguage: settings.targetLanguage)
                    guard self.isCurrent(identifier, capture: capture, verifyCapture: true) else { return }
                    self.work = nil
                    self.document?.translation = translation
                    self.document?.generating = false
                    self.document?.message = ""
                    if self.cache.count >= 64 { self.cache.removeAll() }
                    self.cache[key] = .init(translation: translation, chunks: [])
                    self.render()
                    self.startAnalysis()
                } catch {
                    guard self.isCurrent(identifier, capture: capture), !(error is CancellationError) else { return }
                    self.work = nil
                    self.document?.generating = false
                    self.document?.message = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    /// Analysis is a second task, bound to this exact sentence pair. Editing analysis settings
    /// only invalidates this task/cache; it never discards or re-requests the translation.
    private func startAnalysis() {
        analysisID = UUID()
        analysisWork?.cancel()
        analysisWork = nil
        guard let current = document, !current.translation.isEmpty, !current.isStale,
              isCurrent(current.id, capture: current.capture) else { return }
        document?.chunks = []
        guard service.settings.languageLearning.analysisEnabled else {
            document?.generating = false
            document?.message = "语块分析已关闭，可直接查词。"
            render()
            return
        }
        let key = AnalysisKey(source: current.capture.source, translation: current.translation,
            sourceLanguage: current.sourceLanguage, targetLanguage: current.targetLanguage,
            model: service.settings.languageLearning.analysis.snapshot)
        if let result = analysisCache[key] {
            CotabbyLogger.learning.info("Learning analysis cache hit", metadata: [
                "request_id": .string(current.traceID), "source": .string("analysis"), "phase": .string("cache_hit")])
            document?.chunks = result.chunks
            document?.generating = false
            document?.message = ""
            render()
            return
        }
        document?.generating = true
        document?.message = "正在准备语块对应…"
        render()
        let id = analysisID
        analysisWork = Task { [weak self] in
            guard let self else { return }
            await LearningRequestTrace.$requestID.withValue(current.traceID) {
                do {
                    let result = try await self.service.analyzeSentence(source: current.capture.source,
                        translation: current.translation, sourceLanguage: current.sourceLanguage,
                        targetLanguage: current.targetLanguage) { [weak self] update in
                        guard let self, self.analysisID == id, self.service.settings.languageLearning.analysisEnabled,
                              self.isCurrent(current.id, capture: current.capture),
                              self.document?.translation == current.translation else { return }
                        if case .chunk(let chunk) = update { self.document?.chunks.append(chunk); self.render() }
                    }
                    guard self.analysisID == id, self.isCurrent(current.id, capture: current.capture, verifyCapture: true),
                          result.translation == current.translation else { return }
                    self.analysisWork = nil
                    self.document?.chunks = result.chunks
                    self.document?.generating = false
                    self.document?.message = ""
                    if self.analysisCache.count >= 64 { self.analysisCache.removeAll() }
                    self.analysisCache[key] = result
                    self.render()
                } catch {
                    guard self.analysisID == id, self.isCurrent(current.id, capture: current.capture),
                          !(error is CancellationError) else { return }
                    self.analysisWork = nil
                    self.document?.generating = false
                    self.document?.message = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    private func isCurrent(_ id: UUID, capture: LearningSelectionCapture, verifyCapture: Bool = false) -> Bool {
        guard requestID == id, !Task.isCancelled, enabled, availability() == nil,
              isFrontmost(capture.context.processIdentifier), let current = focus.snapshot.context else { return false }
        guard current.sessionIdentity == capture.context.sessionIdentity &&
            current.contentSignature == capture.context.contentSignature &&
            current.documentSelection == capture.originalSelection && !current.hasHostMarkedText else { return false }
        // Keyboard tokens, the existing focus publisher and the actual frontmost PID guard every
        // chunk cheaply. Full cross-process AX reads are reserved for first translation and finish.
        if verifyCapture, !reader.isCurrent(capture) { return false }
        // Reading AX may publish a new focus snapshot synchronously and invalidate this request.
        return requestID == id && enabled && !Task.isCancelled
    }

    private func precedingSentence(from previous: Document?, capture: LearningSelectionCapture) -> PreviousSentence? {
        guard let previous else { return nil }
        let candidates = [PreviousSentence(source: previous.capture.source,
            range: previous.capture.range, translation: previous.translation), previous.previousSentence].compactMap { $0 }
        let value = capture.value as NSString
        return candidates.first { candidate in
            let end = NSMaxRange(candidate.range)
            guard !candidate.translation.isEmpty, end <= capture.range.location,
                  end <= value.length, candidate.range.location < capture.range.location,
                  value.substring(with: candidate.range) == candidate.source else { return false }
            // The gap may contain a newly typed sentence terminator, but no intervening sentence.
            let gap = value.substring(with: NSRange(location: end, length: capture.range.location - end))
            return gap.allSatisfy { $0.isWhitespace || $0.isPunctuation }
        }
    }

    private func render() {
        // Keep prior source/translation evidence for cache and sentence-history reconciliation,
        // but never let a settings callback or late render make it visible during renewed input.
        guard let document, !document.isStale, enabled else { return }
        panel.show(.init(id: document.id, source: document.capture.source, translation: document.translation,
            chunks: document.chunks, sourceLanguage: document.sourceLanguage, targetLanguage: document.targetLanguage,
            caret: focus.snapshot.context?.caretRect ?? document.capture.context.caretRect,
            isExpanded: expanded, isGenerating: document.generating, message: document.message,
            previousTranslation: document.previousSentence?.translation, shortcutLabel: service.settings.languageLearning.keyLabel,
            isStale: document.isStale),
            expand: { [weak self] in self?.expandOrRequest() }, dismiss: { [weak self] in self?.dismiss() })
        if panel.isVisible, !document.isStale, !document.translation.isEmpty {
            service.recordDisplay(source: .translation, requestID: document.traceID)
            if expanded, !document.chunks.isEmpty {
                service.recordDisplay(source: .analysis, requestID: document.traceID)
            }
        }
    }

    private func dismiss() { dismissedSource = document?.capture.source; cancelWork(); panel.hide() }
    private func suspendPreview() {
        cancelWork()
        expanded = false
        document?.isStale = true
        panel.hide()
    }
    private func cancelWork() {
        requestID = UUID(); work?.cancel(); work = nil
        analysisID = UUID(); analysisWork?.cancel(); analysisWork = nil
    }
    private func clear() { cancelWork(); document = nil; expanded = false; dismissedSource = nil; cache.removeAll(); analysisCache.removeAll(); panel.hide() }
}
