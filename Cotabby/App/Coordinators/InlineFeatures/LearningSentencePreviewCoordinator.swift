import Combine
import AppKit
import CoreGraphics
import Foundation
import Logging

/// App-lifetime sibling of autocomplete. It observes the existing focus stream, waits for edits
/// to settle and owns one versioned translation and optional explicit replacement transaction.
/// Ordinary typing, Tab and Return remain owned by the host and autocomplete pipeline.
@MainActor
final class LearningSentencePreviewCoordinator {
    private let service: any LearningSentenceGenerating
    private let reader: any LearningSelectionReplacing
    private let focus: any SuggestionFocusProviding
    private let panel: any LearningSentencePresenting
    private let availability: () -> String?
    private let debounce: Duration
    private let unitRecognizer: (any LearningUnitRecognizing)?
    private let waitForPause: @MainActor (Duration) async throws -> Void
    private let isFrontmost: @MainActor (Int32) -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var work: Task<Void, Never>?
    private var analysisWork: Task<Void, Never>?
    private var analysisID = UUID()
    private var unitWork: Task<Void, Never>?
    private var unitID = UUID()
    private var unitCache: [String: [LearningUnit]] = [:]
    private var analysisCache: [AnalysisKey: LearningSentenceResult] = [:]
    private var requestID = UUID()
    private var previousContext: FocusedInputSnapshot?
    private var document: Document?
    private var expanded = false
    private var dismissedSource: String?
    private var cache: [TranslationKey: LearningSentenceResult] = [:]
    private var running = false
    /// A write can outlive a document switch while AX verification settles. Keep a single
    /// transaction gate, but show its spinner only on the document that owns that transaction.
    private var committingID: UUID?
    private var committing: Bool { committingID != nil }

    /// Reference and effective model are meaning-bearing inputs, even when target text is unchanged.
    private struct TranslationKey: Hashable {
        let input: LearningTranslationInput
        let sourceLanguage: LearningLanguage
        let targetLanguage: LearningLanguage
        let model: LearningModelSnapshot
        let mode: LearningReferenceMode
    }

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
        var units: [LearningUnit] = []
        var unitStage: LearningUnitStage = .pending
        var generating = true
        var message = String(localized: "Generating expression…", table: "Learning",
            comment: "Status shown in the sentence card while a translation is being generated.")
        var previousSentence: PreviousSentence?
        var isStale = false
        /// An explicit shortcut may keep a preview in a search field; a passive preview cannot.
        var explicitlyRequested = false
        var replacementBlocked = false
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
        unitRecognizer: (any LearningUnitRecognizing)? = nil,
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
        self.unitRecognizer = unitRecognizer
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
        service.settings.languageLearning.shortcutChanges.sink { [weak self] in
            // @Published fires before storage; repaint labels after the new binding is committed.
            Task { @MainActor [weak self] in self?.render() }
        }.store(in: &subscriptions)
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
        if event.shouldClearSuggestion, event.keyCode != 53,
            !matchesShortcut(event.keyCode, flags: event.flags), !matchesReplacement(event.keyCode, flags: event.flags) {
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
        if matchesReplacement(event.keyCode, flags: event.flags) {
            guard !replacementConflicts, panel.isVisible, let document, !document.isStale,
                !document.replacementBlocked, document.capture.supportsReplacement,
                !document.translation.isEmpty
            else { return .notHandled }
            if !event.isAutorepeat, !committing {
                let identifier = document.id
                Task { [weak self] in self?.replacePreview(identifier) }
            }
            return .consume
        }
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
        return running && settings.translationEnabled
    }

    private var shortcutConflicts: Bool {
        let settings = service.settings.languageLearning
        return service.settings.learningShortcutConflict(
            keyCode: CGKeyCode(settings.keyCode), modifiers: settings.modifiers,
            replacement: false, bundleIdentifier: focus.snapshot.bundleIdentifier ?? "") != nil
    }

    private var replacementConflicts: Bool {
        let settings = service.settings.languageLearning
        return service.settings.learningShortcutConflict(
            keyCode: CGKeyCode(settings.replacementKeyCode),
            modifiers: settings.replacementModifiers, replacement: true, bundleIdentifier: focus.snapshot.bundleIdentifier ?? "") != nil
    }

    private func matchesReplacement(_ code: UInt16, flags: CGEventFlags) -> Bool {
        let settings = service.settings.languageLearning
        return code == settings.replacementKeyCode && ShortcutModifierMask(eventFlags: flags) == settings.replacementModifiers
    }

    private func matchesShortcut(_ code: UInt16, flags: CGEventFlags) -> Bool {
        let settings = service.settings.languageLearning
        return code == settings.keyCode && ShortcutModifierMask(eventFlags: flags) == settings.modifiers
    }

    private func changed(_ context: FocusedInputSnapshot?) {
        let old = previousContext
        previousContext = context
        // Our confirmed transaction may select the saved sentence before replacing it. Its AX
        // revalidation owns that transition; a genuine field switch still retires the whole offer.
        if let committingID, document?.id == committingID {
            if old?.sessionIdentity != context?.sessionIdentity { clear() }
            return
        }
        guard LearningCapturePolicy.permitsPreview(focus.snapshot.capability,
            explicitlyRequested: document?.explicitlyRequested == true) else {
            // Capability can change on a reused AX node without changing its text or identity.
            // Retire passive work before the content-only early returns below can preserve it.
            clear()
            return
        }
        guard old?.sessionIdentity == context?.sessionIdentity else { clear(); return }
        guard let old, let context else { return }
        let changed = old.contentSignature != context.contentSignature || old.documentSelection != context.documentSelection ||
            old.hasHostMarkedText != context.hasHostMarkedText
        guard changed else { return }
        suspendPreview()
        guard enabled, service.settings.languageLearning.sentencePreviewEnabled,
            availability() == nil, LearningCapturePolicy.permitsAutomaticCapture(focus.snapshot.capability),
            !context.isSecure, !context.isIntegratedTerminal,
              context.documentSelection.length == 0,
              LearningCommittedTextChangePolicy.hasMutation(from: old, to: context) else {
            // Caret navigation is not consent to translate existing text. Also remove a preview
            // whose field became secure or unavailable rather than retaining it over another UI.
            panel.hide()
            return
        }
        dismissedSource = nil
        scheduleAutomaticPreview(for: context)
    }

    /// Owns one edit's debounce task. The request identity and post-capture capability check keep
    /// a delayed callback from reopening a passive preview after the host reclassifies its field.
    private func scheduleAutomaticPreview(for context: FocusedInputSnapshot) {
        guard !context.hasHostMarkedText else { return }
        let identifier = requestID
        work = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.waitForPause(self.debounce)
                guard self.requestID == identifier, !Task.isCancelled, self.enabled,
                    self.service.settings.languageLearning.sentencePreviewEnabled, self.availability() == nil
                else { return }
                let capture = try self.reader.capture()
                // Capture refreshes AX. Recheck the passive gate after that refresh, since the
                // field may have become a search box during the debounce without changing text.
                guard LearningCapturePolicy.permitsAutomaticCapture(self.focus.snapshot.capability),
                      capture.originalSelection.length == 0, !capture.context.hasHostMarkedText,
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
            self.document?.explicitlyRequested = true
            expanded.toggle()
            dismissedSource = nil
            render()
            return
        }
        do {
            let capture = try reader.capture()
            begin(capture, expanded: true)
        } catch {
            // Explicit commands deserve feedback even with no previous document. This error-only
            // card owns no AX capture and therefore cannot offer a replacement action.
            clear()
            let settings = service.settings.languageLearning
            panel.show(
                .init(
                    id: requestID, source: "", translation: "", chunks: [],
                    sourceLanguage: settings.sourceLanguages.first ?? .chinese, targetLanguage: settings.targetLanguage,
                    caret: focus.snapshot.context?.caretRect ?? .zero, isExpanded: false, isGenerating: false,
                    message: error.localizedDescription, previousTranslation: nil, shortcutLabel: settings.keyLabel, isError: true),
                expand: {}, dismiss: { [weak self] in self?.clear() }, replace: nil)
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
        document?.explicitlyRequested = expanded
        self.expanded = expanded
        let input = LearningTranslationInput.captured(
            value: capture.value, range: capture.range,
            source: capture.source, mode: settings.referenceMode)
        let key = TranslationKey(
            input: input, sourceLanguage: language, targetLanguage: settings.targetLanguage,
            model: settings.translation.snapshot, mode: settings.referenceMode)
        if let cached = cache[key] {
            CotabbyLogger.learning.info("Learning translation cache hit", metadata: [
                "request_id": .string(document?.traceID ?? ""), "source": .string("translation"), "phase": .string("cache_hit")])
            document?.translation = cached.translation
            document?.chunks = []
            document?.generating = false
            document?.message = ""
            render()
            startUnits()
            startAnalysis()
            return
        }
        render()
        let traceIdentifier = document?.traceID ?? RequestID.generate()
        work = Task { [weak self] in
            guard let self else { return }
            await LearningRequestTrace.$requestID.withValue(traceIdentifier) {
                do {
                    let translation = try await self.service.translateSentence(
                        input: input,
                        sourceLanguage: language, targetLanguage: settings.targetLanguage)
                    guard self.isCurrent(identifier, capture: capture, verifyCapture: true) else { return }
                    self.work = nil
                    self.document?.translation = translation
                    self.document?.generating = false
                    self.document?.message = ""
                    if self.cache.count >= 64 { self.cache.removeAll() }
                    self.cache[key] = .init(translation: translation, chunks: [])
                    self.render()
                    self.startUnits()
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

    /// Translation is already visible when these independent lexical tasks begin. Model analysis
    /// settings never participate in unit identity; failing/turning off alignment keeps units.
    private func startUnits() {
        unitID = UUID()
        unitWork?.cancel(); unitWork = nil
        guard let current = document, !current.translation.isEmpty, !current.isStale else { return }
        guard let unitRecognizer else { document?.unitStage = .ready; return }
        let key = current.targetLanguage.rawValue + ":" + current.translation
        if let units = unitCache[key] {
            document?.units = units; document?.unitStage = .ready; render(); return
        }
        let id = unitID
        unitWork = Task { [weak self] in
            do {
                let units = try await unitRecognizer.recognize(current.translation, language: current.targetLanguage)
                guard let self, self.unitID == id, self.isCurrent(current.id, capture: current.capture),
                      self.document?.translation == current.translation else { return }
                self.unitWork = nil
                self.document?.units = units; self.document?.unitStage = .ready
                if self.unitCache.count >= 64 { self.unitCache.removeAll() }
                self.unitCache[key] = units
                self.render()
            } catch {
                guard let self, self.unitID == id, self.isCurrent(current.id, capture: current.capture),
                      !(error is CancellationError) else { return }
                self.unitWork = nil
                self.document?.unitStage = .failed
                self.render()
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
            document?.message = String(localized: "Chunk alignment is off; dictionary lookup is still available.",
                table: "Learning", comment: "Status shown when chunk alignment is disabled while the translation remains available.")
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
            document?.message = result.unresolvedChunkCount > 0
                ? String(localized: "Some chunk alignments could not be located reliably; confirmed matches are kept.",
                    table: "Learning", comment: """
                    Status when uncertain alignments are omitted while verified chunk alignments remain visible.
                    """)
                : ""
            render()
            return
        }
        document?.generating = true
        document?.message = String(localized: "Preparing chunk alignments…", table: "Learning",
            comment: "Status while the separate model aligns source and translated phrases.")
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
                        switch update {
                        case .chunks(let chunks): self.document?.chunks = chunks
                        case .chunk(let chunk): self.document?.chunks.append(chunk)
                        case .translation: return
                        }
                        self.render()
                    }
                    guard self.analysisID == id, self.isCurrent(current.id, capture: current.capture, verifyCapture: true),
                          result.translation == current.translation else { return }
                    self.analysisWork = nil
                    self.document?.chunks = result.chunks
                    self.document?.generating = false
                    self.document?.message = result.unresolvedChunkCount > 0
                        ? String(localized: "Some chunk alignments could not be located reliably; confirmed matches are kept.",
                            table: "Learning", comment: """
                            Status when uncertain alignments are omitted while verified chunk alignments remain visible.
                            """)
                        : ""
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
                isStale: document.isStale, units: document.units, unitStage: document.unitStage,
                targetIsSelection: document.capture.originalSelection.length > 0,
                canReplace: !committing && !document.replacementBlocked && !document.translation.isEmpty
                    && document.capture.supportsReplacement,
                replacementShortcutLabel: service.settings.languageLearning.replacementKeyLabel, isCommitting: committingID == document.id),
            expand: { [weak self] in self?.expandOrRequest() }, dismiss: { [weak self] in self?.dismiss() },
            replace: { [weak self] in self?.replacePreview(document.id) })
        if panel.isVisible, !document.isStale, !document.translation.isEmpty {
            service.recordDisplay(source: .translation, requestID: document.traceID)
            if expanded, !document.chunks.isEmpty {
                service.recordDisplay(source: .analysis, requestID: document.traceID)
            }
        }
    }

    /// The click/shortcut itself confirms this exact preview version. The AX service rechecks the
    /// capture immediately before its single scoped write; an uncertain write is never retried.
    private func replacePreview(_ identifier: UUID) {
        guard !committing, let current = document, current.id == identifier, !current.isStale,
            !current.replacementBlocked, current.capture.supportsReplacement, !current.translation.isEmpty,
            isCurrent(identifier, capture: current.capture, verifyCapture: true)
        else { return }
        committingID = identifier
        document?.generating = false
        analysisWork?.cancel(); unitWork?.cancel()
        render()
        work = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.committingID == identifier { self.committingID = nil }
                // A newer preview may have waited for this old write's verification. Repaint its
                // enabled state without attaching this transaction's failure to the new document.
                self.render()
            }
            do {
                try Task.checkCancellation()
                guard self.requestID == identifier, self.availability() == nil else { throw CancellationError() }
                try await self.reader.replace(current.capture, with: current.translation)
                guard self.requestID == identifier else { return }
                self.clear()
            } catch {
                guard self.requestID == identifier else { return }
                self.work = nil
                self.document?.replacementBlocked = true
                self.document?.message = error.localizedDescription
                self.expanded = true
                self.render()
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
        unitID = UUID(); unitWork?.cancel(); unitWork = nil
    }
    private func clear() { cancelWork(); document = nil; expanded = false; dismissedSource = nil; cache.removeAll(); analysisCache.removeAll(); unitCache.removeAll(); panel.hide() }
}
