import Combine
import Foundation

/// Independent, app-lifetime passive workflow owned by InlineCommandCoordinator. AX changes
/// schedule one latest-wins task; keystrokes only dismiss stale display and never start requests.
/// Its bounded memory cache stores words and replies, with no persistent writing history.
@MainActor
final class LanguageLearningHintCoordinator {
    private let service: any LearningExpressionGenerating
    private let reader: any LearningHintReading
    private let panel: any LearningHintPresenting
    private let focus: any SuggestionFocusProviding
    private let availability: () -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var work: Task<Void, Never>?
    private var requestID = UUID()
    private var previous: FocusedInputSnapshot?
    private var dismissed: LearningHintCandidate?
    private var visibleCandidate: LearningHintCandidate?
    private var cache: [String: LearningWordHint] = [:]
    private var lastRequest = Date.distantPast

    init(service: any LearningExpressionGenerating, reader: any LearningHintReading,
         panel: any LearningHintPresenting, focus: any SuggestionFocusProviding, availability: @escaping () -> Bool) {
        self.service = service
        self.reader = reader
        self.panel = panel
        self.focus = focus
        self.availability = availability
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        focus.snapshotPublisher.sink { [weak self] snapshot in self?.changed(snapshot.context) }.store(in: &subscriptions)
        Publishers.MergeMany([
            service.settings.languageLearning.changes,
            service.settings.snapshotPublisher.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.$endpointCredentialRevision.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ])
            .sink { [weak self] in self?.cache.removeAll(); self?.invalidate() }.store(in: &subscriptions)
    }

    func stop() { invalidate(); previous = nil; dismissed = nil; cache.removeAll(); subscriptions.removeAll() }

    func observe(_ event: CapturedInputEvent) {
        let settings = service.settings.languageLearning
        let opensConversion = settings.translationEnabled && event.keyCode == settings.keyCode &&
            ShortcutModifierMask(eventFlags: event.flags) == settings.modifiers
        if event.shouldClearSuggestion || opensConversion { invalidate() }
    }

    func decide(_ event: InputMonitorKeyEvent) -> InputMonitorAcceptTapDecision {
        guard event.keyCode == 53, panel.isVisible else { return .notHandled }
        dismissed = visibleCandidate
        invalidate()
        return .consume
    }

    private func changed(_ context: FocusedInputSnapshot?) {
        let old = previous
        previous = context
        guard needsRefresh(from: old, to: context) else { return }
        invalidate()
        // Focus entry alone does not send existing editor text. A changed value/selection in the
        // same field is required, and reader verifies the host has finished its composition.
        let settings = service.settings.languageLearning
        guard settings.translationEnabled, settings.hintsEnabled,
              let old, let context, old.sessionIdentity == context.sessionIdentity,
              LearningCommittedTextChangePolicy.hasMutation(from: old, to: context) else { return }
        let identifier = requestID
        work = Task { [weak self] in
            guard let self else { return }
            do {
                // No cross-process AX work runs in the focus publisher or keyboard tap. Read a
                // committed candidate only after typing has settled, then revalidate on delivery.
                try await Task.sleep(for: .milliseconds(700))
                guard self.requestID == identifier, self.availability(),
                      let candidate = self.reader.candidate(), candidate != self.dismissed else { return }
                let hint = try await self.resolve(candidate, identifier: identifier)
                guard self.isValid(candidate, identifier: identifier) else { return }
                self.work = nil
                self.visibleCandidate = candidate
                self.panel.show(hint, candidate: candidate, dismiss: { [weak self] in
                    self?.dismissed = candidate
                    self?.invalidate()
                })
            } catch {
                // Passive failures never interrupt input or open a modal error. Active conversion
                // retains its explicit error/copy recovery UI for the same configured endpoint.
                if self.requestID == identifier { self.work = nil }
            }
        }
    }

    private func needsRefresh(from old: FocusedInputSnapshot?, to new: FocusedInputSnapshot?) -> Bool {
        old?.sessionIdentity != new?.sessionIdentity || old?.contentSignature != new?.contentSignature ||
            old?.documentSelection != new?.documentSelection || old?.hasHostMarkedText != new?.hasHostMarkedText
    }

    private func isValid(_ candidate: LearningHintCandidate, identifier: UUID) -> Bool {
        requestID == identifier && !Task.isCancelled && availability() && reader.isCurrent(candidate)
    }

    private func resolve(_ candidate: LearningHintCandidate, identifier: UUID) async throws -> LearningWordHint {
        guard isValid(candidate, identifier: identifier) else { throw CancellationError() }
        let key = candidate.sourceLanguage.rawValue + ":" + candidate.targetLanguage.rawValue + ":" + candidate.source
        if let cached = cache[key] { return cached }
        let remaining = 2 - Date().timeIntervalSince(lastRequest)
        if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
        guard isValid(candidate, identifier: identifier) else { throw CancellationError() }
        lastRequest = Date()
        let raw = try await service.generate(source: candidate.source,
            task: .hint(source: candidate.sourceLanguage, target: candidate.targetLanguage))
        guard isValid(candidate, identifier: identifier) else { throw CancellationError() }
        let hint = try LearningHintPolicy.decode(raw)
        if cache.count >= 128 { cache.removeAll() }
        cache[key] = hint
        return hint
    }

    private func invalidate() { requestID = UUID(); work?.cancel(); work = nil; visibleCandidate = nil; panel.hide() }
}
