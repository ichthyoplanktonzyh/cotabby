import CoreGraphics
import Combine
import Foundation
import Logging

/// Sibling of the completion coordinator, owned by InlineCommandCoordinator. One task and one
/// exact selection capture live until cancel/commit. Every input or focus change invalidates them;
/// request identity also rejects late network responses even when cancellation arrives too late.
@MainActor
final class LanguageLearningCoordinator {
    private let service: any LearningExpressionGenerating
    private let replacement: any LearningSelectionReplacing
    private let focus: any SuggestionFocusProviding
    private let panel: any LearningTranslationPresenting
    private var subscriptions = Set<AnyCancellable>()
    private let availability: () -> String?
    private var work: Task<Void, Never>?
    private var requestID = UUID()
    private var saved: LearningSelectionCapture?
    private var english = ""
    private var committing = false
    private var triggerPending = false
    private var sourceLanguage: LearningLanguage = .chinese
    var isActive: Bool { panel.isVisible || work != nil || committing || triggerPending }

    init(
        service: any LearningExpressionGenerating, focus: any SuggestionFocusProviding,
        replacement: any LearningSelectionReplacing,
        panel: any LearningTranslationPresenting,
        availability: @escaping () -> String? = { nil }
    ) {
        self.availability = availability
        self.service = service
        self.focus = focus
        self.replacement = replacement
        self.panel = panel
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        focus.snapshotPublisher.sink { [weak self] snapshot in
            guard let self, let saved = self.saved, !self.committing else { return }
            guard snapshot.context?.sessionIdentity == saved.context.sessionIdentity,
                  snapshot.context?.documentSelection == saved.originalSelection,
                  snapshot.context?.contentSignature == saved.context.contentSignature,
                  snapshot.context?.hasHostMarkedText == false else { self.cancel(); return }
        }.store(in: &subscriptions)
        let learning = service.settings.languageLearning
        let changes: [AnyPublisher<Void, Never>] = [
            learning.changes,
            service.settings.$isGloballyEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.$pauseState.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.snapshotPublisher.map(\.disabledAppBundleIdentifiers).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            service.settings.snapshotPublisher.map(\.isLowPowerModeAutoDisableEnabled).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes).sink { [weak self] in self?.cancel() }.store(in: &subscriptions)
    }

    func stop() {
        // A queued commit must not begin editing after teardown. A commit already dispatched to
        // the host cannot be undone safely, but its late verification must not reopen this panel.
        requestID = UUID()
        work?.cancel()
        work = nil
        committing = false
        triggerPending = false
        saved = nil
        english = ""
        panel.hide()
        subscriptions.removeAll()
    }

    func observe(_ event: CapturedInputEvent) -> Bool {
        // Automatic sentence learning shares the shortcut but owns its read-only detail surface.
        // Its regular typing must never make autocomplete stand down through this legacy path.
        if service.settings.languageLearning.sentencePreviewEnabled { return false }
        let settings = service.settings.languageLearning
        if settings.translationEnabled, event.keyCode == settings.keyCode,
           ShortcutModifierMask(eventFlags: event.flags) == settings.modifiers {
            // A learning shortcut that overlaps an established app binding must reach the normal
            // accept/toggle handlers unchanged; claiming it here could cancel ordinary generation.
            return !translationShortcutConflictsWithExistingBinding(settings)
        }
        if triggerPending, event.shouldClearSuggestion { cancel() }
        if panel.isVisible, event.keyCode == 53 { return true }
        if saved != nil, [UInt16(36), 76].contains(event.keyCode) { return true }
        if panel.isVisible, event.shouldClearSuggestion {
            let hadSelection = saved != nil
            cancel()
            return hadSelection
        }
        return saved != nil
    }

    /// The consuming tap owns the trigger. Observer events can arrive before or after it, so
    /// observe never starts a second task for the same key. Esc consumes only an open preview.
    func decide(_ event: InputMonitorKeyEvent) -> InputMonitorAcceptTapDecision {
        let learning = service.settings.languageLearning
        if event.keyCode == 53, panel.isVisible {
            cancel()
            return .consume
        }
        if panel.isVisible, saved != nil, event.keyCode == 36 || event.keyCode == 76 {
            if focus.snapshot.context?.hasHostMarkedText == true { cancel(); return .notHandled }
            return .consume
        }
        guard learning.translationEnabled, event.keyCode == learning.keyCode,
              ShortcutModifierMask(eventFlags: event.flags) == learning.modifiers else { return .notHandled }
        guard !translationShortcutConflictsWithExistingBinding(learning) else { return .notHandled }
        if !event.isAutorepeat, work == nil, !committing, !triggerPending {
            triggerPending = true
            let identifier = requestID
            // The active event tap must return promptly: AX cross-process reads and scope parsing
            // happen on the next main-actor task, after this key has been consumed by the tap.
            Task { [weak self] in
                guard let self, self.requestID == identifier else { return }
                self.triggerPending = false
                guard self.service.settings.languageLearning.translationEnabled else { return }
                self.begin()
            }
        }
        return .consume
    }

    /// Resolves the app-specific Accept Word and Accept Entire Suggestion bindings together with
    /// the global toggle, so the learning tap cannot race an existing handler for the same key.
    private func translationShortcutConflictsWithExistingBinding(
        _ learning: LanguageLearningSettings
    ) -> Bool {
        service.settings.conflictingPerAppShortcutName(
            forBundleIdentifier: focus.snapshot.bundleIdentifier ?? "",
            keyCode: CGKeyCode(learning.keyCode),
            modifiers: learning.modifiers,
            excluding: .toggleTabby,
            includingLearningShortcut: false
        ) != nil
    }

    private func begin() {
        cancel()
        do {
            focus.refreshNow()
            if let reason = availability() { throw LearningFailure.message(reason) }
            let capture = try replacement.capture()
            let settings = service.settings.languageLearning
            guard let language = LearningSourceLanguageResolver().resolve(
                text: capture.source,
                enabledSourceLanguages: settings.sourceLanguages,
                targetLanguage: settings.targetLanguage
            ) else {
                throw LearningFailure.message(String(localized: """
                The source language could not be confirmed or matches the target. Adjust the source-language settings or select more \
                text.
                """,
                    table: "Learning", comment: """
                    Error shown when a translation direction cannot be resolved from the selected source languages and target.
                    """))
            }
            sourceLanguage = language
            saved = capture
            let traceIdentifier = RequestID.generate()
            let task = LearningExpressionTask.translation(source: language, target: settings.targetLanguage)
            let identifier = requestID
            show(message: String(localized: "Generating the target expression… Keep typing to dismiss this preview.",
                table: "Learning", comment: """
                Status while an explicit translation preview is being generated; typing cancels it.
                """), accept: nil)
            work = Task { [weak self] in
                guard let self else { return }
                await LearningRequestTrace.$requestID.withValue(traceIdentifier) {
                    do {
                        let result = try await self.service.generate(source: capture.source, task: task)
                        guard self.requestID == identifier, !Task.isCancelled else { return }
                        self.work = nil
                        guard self.replacement.isCurrent(capture) else { self.cancel(); return }
                        self.english = result
                        if capture.supportsReplacement {
                            self.show(message: String(localized: """
                            You can read or copy the expression. The source text will be checked again before replacement.
                            """,
                                table: "Learning", comment: """
                                Explains that replacement is available and the source is revalidated after the user confirms.
                                """),
                                accept: { [weak self] in self?.accept() })
                        } else {
                            self.show(message: capture.replacementUnavailableReason ??
                                String(localized: """
                                You can read or copy the expression. To replace text, select the source manually and preview it again.
                                """,
                                    table: "Learning", comment: """
                                    Copy-only preview guidance when the editor does not support a safe automatic replacement.
                                    """),
                                accept: nil)
                        }
                        if self.panel.isVisible { self.service.recordDisplay(source: .translation, requestID: traceIdentifier) }
                    } catch {
                        guard self.requestID == identifier, !Task.isCancelled else { return }
                        self.work = nil
                        self.show(message: error.localizedDescription, accept: nil)
                    }
                }
            }
        } catch {
            panel.show(.init(source: "", english: "", message: error.localizedDescription,
                caret: focus.snapshot.context?.caretRect ?? .zero,
                targetLanguage: service.settings.languageLearning.targetLanguage),
                accept: nil, cancel: { [weak self] in self?.cancel() })
        }
    }

    private func accept() {
        // A preview can carry readable text without permission to edit it. Keep that capability
        // check here as well as in the AX transaction, even if an old UI callback survives a redraw.
        guard let saved, saved.supportsReplacement, !english.isEmpty, !committing,
              service.settings.languageLearning.translationEnabled else { return }
        focus.refreshNow()
        if let reason = availability() { show(message: reason, accept: nil); return }
        committing = true
        show(message: String(localized: "Verifying the replacement…", table: "Learning",
            comment: "Status while the coordinator checks whether the editor applied the confirmed replacement."), accept: nil)
        let identifier = requestID
        work = Task { [weak self] in
            guard let self else { return }
            var startedEditing = false
            do {
                try Task.checkCancellation()
                guard self.requestID == identifier, self.service.settings.languageLearning.translationEnabled,
                      self.availability() == nil else { throw CancellationError() }
                startedEditing = true
                try await self.replacement.replace(saved, with: self.english)
                guard self.requestID == identifier else { return }
                self.committing = false
                self.cancel()
            } catch {
                guard self.requestID == identifier else { return }
                self.committing = false
                self.work = nil
                if error is CancellationError, !startedEditing { self.cancel(); return }
                let message = error is CancellationError
                    ? String(localized: """
                    The operation was canceled before the replacement could be verified. Copy the translation or restore the source \
                    text if needed.
                    """,
                        table: "Learning", comment: """
                        Recovery guidance when cancellation occurs after an editor replacement may have started.
                        """)
                    : error.localizedDescription
                self.show(message: message, accept: nil)
            }
        }
    }

    private func show(message: String, accept: (() -> Void)?) {
        guard let saved else { return }
        let settings = service.settings.languageLearning
        panel.show(.init(source: saved.source, english: english, message: message,
            caret: saved.context.caretRect, sourceLanguage: sourceLanguage, targetLanguage: settings.targetLanguage,
            isSentence: saved.originalSelection.length == 0), accept: accept, cancel: { [weak self] in self?.cancel() })
    }

    func cancel() {
        if committing {
            // Cancellation before the task starts prevents mutation. After dispatch it only stops
            // verification; retain both texts for recovery instead of pretending to roll back.
            work?.cancel()
            return
        }
        requestID = UUID()
        triggerPending = false
        work?.cancel()
        work = nil
        saved = nil
        english = ""
        panel.hide()
    }
}
