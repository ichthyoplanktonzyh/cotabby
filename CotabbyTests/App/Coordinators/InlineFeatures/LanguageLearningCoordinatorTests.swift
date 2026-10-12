import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Cotabby

/// Exercises the coordinator's short-lived translation transaction through its narrow contracts.
/// A fake service holds each result until the test releases it, while focus, replacement, and panel
/// doubles expose the cancellation and commit boundaries without invoking real Accessibility APIs.
@Suite(.serialized)
@MainActor
struct LanguageLearningCoordinatorTests {
    private let source = "我今天没有在3点发送2个文件。"
    private let english = "I did not send 2 files today at 3 PM."

    @Test
    func disabledTranslationShortcutDoesNotCaptureOrGenerate() throws {
        let rig = try Rig(translationEnabled: false)
        defer { rig.cleanup() }
        rig.coordinator.start()

        #expect(!rig.coordinator.observe(rig.shortcutEvent))
        #expect(rig.coordinator.decide(rig.shortcutTap) == .notHandled)
        #expect(rig.service.requests.isEmpty)
        #expect(rig.replacement.captureCount == 0)
        #expect(rig.panel.presentations.isEmpty)
    }

    @Test(arguments: ["acceptWord", "fullAcceptance", "globalToggle", "appAccept", "appFullAcceptance"])
    func conflictingTranslationShortcutDoesNotClaimTheEventOrStartLearningWork(_ conflict: String) async throws {
        let rig = try Rig(shortcutConflict: conflict)
        defer { rig.cleanup() }
        rig.coordinator.start()

        #expect(!rig.coordinator.observe(rig.shortcutEvent))
        #expect(rig.coordinator.decide(rig.shortcutTap) == .notHandled)
        await Task.yield()

        #expect(rig.service.requests.isEmpty)
        #expect(rig.replacement.captureCount == 0)
        #expect(rig.panel.presentations.isEmpty)
    }

    @Test(arguments: ["stop", "input", "disable"])
    func queuedShortcutDoesNotCaptureAfterInvalidation(_ invalidation: String) async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()

        #expect(rig.coordinator.decide(rig.shortcutTap) == .consume)
        switch invalidation {
        case "stop":
            rig.coordinator.stop()
        case "input":
            _ = rig.coordinator.observe(CotabbyTestFixtures.inputEvent(
                kind: .textMutation, keyCode: 0, characters: "x"
            ))
        case "disable":
            rig.settings.languageLearning.translationEnabled = false
        default:
            Issue.record("Unexpected invalidation: \(invalidation)")
        }

        // `decide` queues begin work for the next MainActor turn. Give that queued work a chance
        // to run after invalidation; its captured request UUID must prevent an AX selection read.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(rig.replacement.captureCount == 0)
        #expect(rig.service.requests.isEmpty)
        #expect(rig.panel.presentations.isEmpty)
    }

    @Test
    func observerAndActiveTapForOneShortcutStartOnlyOneRequest() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()

        #expect(rig.coordinator.observe(rig.shortcutEvent))
        #expect(rig.coordinator.decide(rig.shortcutTap) == .consume)
        #expect(rig.coordinator.observe(rig.shortcutEvent))
        #expect(rig.coordinator.decide(rig.shortcutTap) == .consume)
        await rig.service.waitForCallCount(1)

        #expect(rig.service.requests.count == 1)
        #expect(rig.service.requests.first?.source == source)
        #expect(rig.service.requests.first?.task == .translation(source: .chinese, target: .english))
        #expect(rig.replacement.captureCount == 1)
    }

    @Test
    func shortChineseExpressionUsesTheConfiguredSourceAndShowsBothLanguages() async throws {
        let rig = try Rig(sourceText: "你好")
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        #expect(rig.service.requests.count == 1)
        #expect(rig.service.requests.first?.source == "你好")
        #expect(rig.service.requests.first?.task == .translation(source: .chinese, target: .english))

        rig.service.completeRequest(0, with: .success("Hello"))
        await rig.panel.waitForPresentationCount(2)
        let preview = try #require(rig.panel.presentations.last)
        #expect(preview.source == "你好")
        #expect(preview.english == "Hello")
        #expect(preview.sourceLanguage == .chinese)
        #expect(preview.targetLanguage == .english)
    }

    @Test(arguments: [LearningLanguage.chinese, .spanish])
    func sourceLanguageCannotAlsoBeTheConfiguredTarget(_ language: LearningLanguage) async throws {
        let rig = try Rig(sourceText: "你好", sourceLanguages: [language], targetLanguage: language)
        defer { rig.cleanup() }
        rig.coordinator.start()

        #expect(rig.coordinator.decide(rig.shortcutTap) == .consume)
        await rig.panel.waitForPresentationCount(1)

        #expect(rig.service.requests.isEmpty)
        #expect(rig.panel.presentations.last?.message.contains("源语言与目标相同") == true)
        #expect(rig.panel.presentations.last?.sourceLanguage == nil)
        #expect(rig.panel.presentations.last?.targetLanguage == language)
    }

    @Test
    func textMarkerSentenceCanShowTranslationForCopyWithoutReplacementAction() async throws {
        let rig = try Rig(usesTextMarkers: true)
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        rig.service.completeRequest(0, with: .success(english))
        await rig.panel.waitForPresentationCount(2)
        let presentation = try #require(rig.panel.presentations.last)

        #expect(presentation.source == source)
        #expect(presentation.english == english)
        #expect(presentation.isSentence)
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.replaceCalls.isEmpty)
    }

    @Test(arguments: ["selection", "sentence"])
    func inputMethodCopyOnlyCaptureShowsWholeSourceAndTranslationWithoutEditing(_ scope: String) async throws {
        let reason = "当前输入法下只能复制译文，不能安全替换原文。"
        let rig = try Rig(
            replacementUnavailableReason: reason,
            nativeSentenceAtCaret: scope == "sentence"
        )
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        rig.service.completeRequest(0, with: .success(english))
        await rig.panel.waitForPresentationCount(2)
        let preview = try #require(rig.panel.presentations.last)

        #expect(preview.source == source)
        #expect(preview.english == english)
        #expect(preview.isSentence == (scope == "sentence"))
        #expect(preview.message == reason)
        #expect(rig.service.requests.first?.source == source)
        #expect(!rig.panel.hasAcceptAction)
        rig.panel.clickAccept()
        #expect(rig.replacement.replaceCalls.isEmpty)
    }

    @Test
    func lateModelResultAfterExplicitCancellationCannotPresentOrAccept() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        rig.coordinator.cancel()
        await rig.service.cancellationRecorder.waitForCancellation(of: 0)
        #expect(!rig.panel.isVisible)

        rig.service.completeRequest(0, with: .success(english))
        await Task.yield()

        #expect(rig.panel.presentations.count == 1, "Only the loading preview may have been shown")
        #expect(!rig.panel.isVisible)
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.currentCheckCount == 0)
    }

    @Test(arguments: ["editing", "focus", "chat"])
    func editorOrConversationChangeCancelsPendingTranslation(_ change: String) async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        rig.publishFocusContext(try rig.changedContext(for: change))
        await rig.service.cancellationRecorder.waitForCancellation(of: 0)
        #expect(!rig.panel.isVisible)

        rig.service.completeRequest(0, with: .success(english))
        await Task.yield()

        #expect(rig.panel.presentations.count == 1)
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.currentCheckCount == 0)
    }

    @Test
    func hostMarkedTextCancelsPendingTranslationWithoutChangingTextOrSelection() async throws {
        let rig = try Rig(nativeSentenceAtCaret: true)
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        let original = try #require(rig.focus.snapshot.context)
        let marked = try rig.changedContext(for: "marked")
        #expect(marked.sessionIdentity == original.sessionIdentity)
        #expect(marked.contentSignature == original.contentSignature)
        #expect(marked.documentSelection == original.documentSelection)
        #expect(marked.hasHostMarkedText)

        rig.publishFocusContext(marked)
        await rig.service.cancellationRecorder.waitForCancellation(of: 0)
        #expect(!rig.panel.isVisible)

        rig.service.completeRequest(0, with: .success(english))
        await Task.yield()

        #expect(rig.panel.presentations.count == 1)
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.currentCheckCount == 0)
    }

    @Test(arguments: ["disableTranslation", "changeTargetLanguage"])
    func changingLearningSettingsCancelsPendingTranslation(_ change: String) async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        switch change {
        case "disableTranslation": rig.settings.languageLearning.translationEnabled = false
        case "changeTargetLanguage": rig.settings.languageLearning.targetLanguage = .french
        default: Issue.record("Unexpected setting change: \(change)")
        }
        await rig.service.cancellationRecorder.waitForCancellation(of: 0)
        #expect(!rig.panel.isVisible)

        rig.service.completeRequest(0, with: .success(english))
        await Task.yield()

        #expect(rig.panel.presentations.count == 1)
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.currentCheckCount == 0)
    }

    @Test
    func expiredSelectionCaptureIsNeverPresentedWithAnAcceptAction() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await beginRequest(in: rig)
        rig.replacement.isCurrentResult = false

        rig.service.completeRequest(0, with: .success(english))
        await rig.replacement.waitForCurrentCheckCount(1)
        await rig.panel.waitForHideCount(2)

        #expect(rig.replacement.currentCheckCount == 1)
        #expect(rig.panel.presentations.count == 1)
        #expect(!rig.panel.isVisible)
        #expect(!rig.panel.hasAcceptAction)
    }

    @Test
    func serviceFailureKeepsTheSourceShowsNoAcceptAndEscapeCancelsTheErrorCard() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await beginRequest(in: rig)

        rig.service.completeRequest(0, with: .failure(LearningFailure.message("endpoint unavailable")))
        await rig.panel.waitForPresentationCount(2)
        let errorCard = try #require(rig.panel.presentations.last)

        #expect(errorCard.source == source)
        #expect(errorCard.english.isEmpty)
        #expect(errorCard.message.contains("endpoint unavailable"))
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.replaceCalls.isEmpty)
        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 36)) == .consume)
        #expect(rig.replacement.replaceCalls.isEmpty, "Enter must not accept a translation")
        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 53)) == .consume)
        #expect(!rig.panel.isVisible)
    }

    @Test
    func enterDoesNotConfirmPreviewAndEscapeCancelsIt() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await showSuccessfulPreview(in: rig)

        #expect(rig.panel.hasAcceptAction)
        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 36)) == .consume)
        #expect(rig.replacement.replaceCalls.isEmpty)
        #expect(rig.panel.isVisible)

        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 53)) == .consume)
        #expect(!rig.panel.isVisible)
        #expect(rig.replacement.replaceCalls.isEmpty)
    }

    @Test
    func clickingConfirmWaitsForSuccessfulReplacementBeforeHiding() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await showSuccessfulPreview(in: rig)
        let hideCountBeforeConfirm = rig.panel.hideCount

        rig.panel.clickAccept()
        await rig.replacement.waitForReplaceCount(1)
        await rig.panel.waitForPresentationCount(3)

        #expect(rig.panel.isVisible)
        #expect(rig.panel.hideCount == hideCountBeforeConfirm)
        #expect(rig.panel.presentations.last?.message == "正在核对替换结果…")
        #expect(rig.replacement.replaceCalls == [.init(source: source, english: english)])

        rig.replacement.completeReplace(.success(()))
        await rig.panel.waitForHideCount(hideCountBeforeConfirm + 1)

        #expect(!rig.panel.isVisible)
        #expect(rig.panel.hideCount == hideCountBeforeConfirm + 1)
    }

    @Test
    func failedReplacementRemovesAcceptButKeepsSourceAndEnglishVisible() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await showSuccessfulPreview(in: rig)

        rig.panel.clickAccept()
        await rig.replacement.waitForReplaceCount(1)
        rig.replacement.completeReplace(.failure(LearningFailure.message("editor refused replacement")))
        await rig.panel.waitForPresentationCount(4)

        let recoverableCard = try #require(rig.panel.presentations.last)
        #expect(rig.panel.isVisible)
        #expect(recoverableCard.source == source)
        #expect(recoverableCard.english == english)
        #expect(recoverableCard.message.contains("editor refused replacement"))
        #expect(!rig.panel.hasAcceptAction)
        #expect(rig.replacement.replaceCalls == [.init(source: source, english: english)])
    }

    @Test
    func disablingTranslationImmediatelyAfterConfirmPreventsTheQueuedEdit() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await showSuccessfulPreview(in: rig)
        let hideCount = rig.panel.hideCount

        // These synchronous operations share MainActor: the queued commit cannot start before
        // the switch emits cancellation. Await the ensuing hide to observe that task finishing.
        rig.panel.clickAccept()
        rig.settings.languageLearning.translationEnabled = false
        await rig.panel.waitForHideCount(hideCount + 1)

        #expect(rig.replacement.replaceCalls.isEmpty)
        #expect(!rig.panel.isVisible)
        #expect(rig.focus.snapshot.context?.selection.length == (source as NSString).length)
    }

    @Test
    func stoppingDuringCommitIgnoresLateVerificationAndKeepsThePanelClosed() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        await showSuccessfulPreview(in: rig)
        rig.panel.clickAccept()
        await rig.replacement.waitForReplaceCount(1)

        rig.coordinator.stop()
        let presentations = rig.panel.presentations.count
        rig.replacement.completeReplace(.success(()))
        await rig.replacement.waitForReturnedReplaceCount(1)

        #expect(!rig.panel.isVisible)
        #expect(rig.panel.presentations.count == presentations)
        #expect(!rig.panel.hasAcceptAction)
    }

    @MainActor
    private func beginRequest(in rig: Rig) async {
        rig.coordinator.start()
        #expect(rig.coordinator.decide(rig.shortcutTap) == .consume)
        await rig.service.waitForCallCount(1)
    }

    @MainActor
    private func showSuccessfulPreview(in rig: Rig) async {
        await beginRequest(in: rig)
        rig.service.completeRequest(0, with: .success(english))
        await rig.panel.waitForPresentationCount(2)

        #expect(rig.panel.presentations.last?.source == source)
        #expect(rig.panel.presentations.last?.english == english)
        #expect(rig.panel.hasAcceptAction)
    }

    /// A rig owns the isolated settings suite and in-memory collaborators for one coordinator test.
    /// Its capture contains a synthetic AX handle only; the fakes never query or mutate that handle.
    @MainActor
    private final class Rig {
        let settings: SuggestionSettingsModel
        let service: ControlledLearningService
        let focus: RigFocusProvider
        let replacement: ControlledSelectionReplacement
        let panel: RecordingTranslationPanel
        let coordinator: LanguageLearningCoordinator
        let shortcutEvent: CapturedInputEvent
        let shortcutTap: InputMonitorKeyEvent
        private let suiteName: String
        private let defaults: UserDefaults
        private let source: String

        @MainActor
        init(
            translationEnabled: Bool = true,
            usesTextMarkers: Bool = false,
            replacementUnavailableReason: String? = nil,
            nativeSentenceAtCaret: Bool = false,
            shortcutConflict: String? = nil,
            sourceText: String? = nil,
            sourceLanguages: [LearningLanguage] = [.chinese],
            targetLanguage: LearningLanguage = .english
        ) throws {
            let suiteName = "io.cotabby.tests.LanguageLearningCoordinator-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            self.suiteName = suiteName
            self.defaults = defaults

            let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
            settings.languageLearning.translationEnabled = translationEnabled
            settings.languageLearning.sentencePreviewEnabled = false
            settings.languageLearning.sourceLanguages = sourceLanguages
            settings.languageLearning.targetLanguage = targetLanguage
            settings.languageLearning.keyCode = 17
            settings.languageLearning.modifiers = [.command, .control]
            if let shortcutConflict {
                switch shortcutConflict {
                case "acceptWord":
                    settings.setAcceptanceKey(keyCode: 17, modifiers: [.command, .control], label: "⌃⌘T")
                case "fullAcceptance":
                    settings.setFullAcceptanceKey(keyCode: 17, modifiers: [.command, .control], label: "⌃⌘T")
                case "globalToggle":
                    settings.setGlobalToggleKey(keyCode: 17, modifiers: [.command, .control], label: "⌃⌘T")
                case "appAccept":
                    settings.setPerAppAcceptKey(
                        bundleIdentifier: "com.example.ChatHost",
                        displayName: "Chat Host",
                        keyCode: 17,
                        modifiers: [.command, .control],
                        label: "⌃⌘T"
                    )
                case "appFullAcceptance":
                    settings.setPerAppFullAcceptKey(
                        bundleIdentifier: "com.example.ChatHost",
                        displayName: "Chat Host",
                        keyCode: 17,
                        modifiers: [.command, .control],
                        label: "⌃⌘T"
                    )
                default:
                    Issue.record("Unexpected shortcut conflict: \(shortcutConflict)")
                }
            }
            self.settings = settings

            source = sourceText ?? "我今天没有在3点发送2个文件。"
            let fullRange = NSRange(location: 0, length: (source as NSString).length)
            let editorSelection = usesTextMarkers || nativeSentenceAtCaret
                ? NSRange(location: fullRange.length, length: 0)
                : fullRange
            let context = CotabbyTestFixtures.focusedInputSnapshot(
                applicationName: "Chat Host",
                bundleIdentifier: "com.example.ChatHost",
                processIdentifier: 123,
                precedingText: source,
                selection: editorSelection,
                focusedURLString: "https://chat.example/conversation/one",
                documentLength: fullRange.length
            )
            let focus = RigFocusProvider(snapshot: FocusSnapshot(
                applicationName: "Chat Host",
                bundleIdentifier: "com.example.ChatHost",
                capability: .supported,
                context: context
            ))
            self.focus = focus

            let service = ControlledLearningService(settings: settings)
            self.service = service
            let replacement = ControlledSelectionReplacement(capture: LearningSelectionCapture(
                element: AXUIElementCreateApplication(123),
                context: context,
                value: source,
                range: fullRange,
                source: source,
                usesTextMarkers: usesTextMarkers,
                editorSelection: usesTextMarkers ? editorSelection : nil,
                replacementUnavailableReason: replacementUnavailableReason,
                inputMethodAssessment: replacementUnavailableReason.map {
                    LearningInputMethodPolicy.Assessment.copyOnly(reason: $0)
                } ?? .replacementAllowed(.explicitlyEmpty)
            ))
            self.replacement = replacement
            let panel = RecordingTranslationPanel()
            self.panel = panel
            coordinator = LanguageLearningCoordinator(
                service: service,
                focus: focus,
                replacement: replacement,
                panel: panel
            )

            let flags: CGEventFlags = [.maskCommand, .maskControl]
            shortcutEvent = CotabbyTestFixtures.inputEvent(
                kind: .shortcutMutation,
                keyCode: 17,
                flags: flags
            )
            shortcutTap = InputMonitorKeyEvent(keyCode: 17, flags: flags)
        }

        @MainActor
        func publishFocusContext(_ context: FocusedInputSnapshot) {
            focus.snapshot = FocusSnapshot(
                applicationName: context.applicationName,
                bundleIdentifier: context.bundleIdentifier,
                capability: .supported,
                context: context
            )
            focus.snapshotSubject.send(focus.snapshot)
        }

        @MainActor
        func changedContext(for change: String) throws -> FocusedInputSnapshot {
            let original = try #require(focus.snapshot.context)
            switch change {
            case "editing":
                return CotabbyTestFixtures.focusedInputSnapshot(
                    applicationName: original.applicationName,
                    bundleIdentifier: original.bundleIdentifier,
                    processIdentifier: original.processIdentifier,
                    elementIdentifier: original.elementIdentifier,
                    precedingText: original.precedingText + "已编辑",
                    selection: original.selection,
                    focusChangeSequence: original.focusChangeSequence,
                    focusedURLString: original.focusedURLString
                )
            case "focus":
                return CotabbyTestFixtures.focusedInputSnapshot(
                    applicationName: original.applicationName,
                    bundleIdentifier: original.bundleIdentifier,
                    processIdentifier: original.processIdentifier,
                    elementIdentifier: original.elementIdentifier,
                    precedingText: original.precedingText,
                    selection: original.selection,
                    focusChangeSequence: original.focusChangeSequence + 1,
                    focusedURLString: original.focusedURLString
                )
            case "chat":
                return CotabbyTestFixtures.focusedInputSnapshot(
                    applicationName: original.applicationName,
                    bundleIdentifier: original.bundleIdentifier,
                    processIdentifier: original.processIdentifier,
                    elementIdentifier: original.elementIdentifier,
                    precedingText: original.precedingText,
                    selection: original.selection,
                    focusChangeSequence: original.focusChangeSequence,
                    focusedURLString: "https://chat.example/conversation/two"
                )
            case "marked":
                return CotabbyTestFixtures.focusedInputSnapshot(
                    applicationName: original.applicationName,
                    bundleIdentifier: original.bundleIdentifier,
                    processIdentifier: original.processIdentifier,
                    elementIdentifier: original.elementIdentifier,
                    precedingText: original.precedingText,
                    trailingText: original.trailingText,
                    selection: original.documentSelection,
                    focusChangeSequence: original.focusChangeSequence,
                    focusedURLString: original.focusedURLString,
                    hostMarkedTextRange: NSRange(location: original.documentSelection.location, length: 1)
                )
            default:
                preconditionFailure("Unknown focus mutation: \(change)")
            }
        }

        @MainActor
        func cleanup() {
            coordinator.stop()
            service.completeUnresolvedRequests(with: .success("cleanup"))
            replacement.completeUnresolvedReplace(with: .success(()))
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

/// The service fake records the exact source and deliberately waits on checked continuations.
/// Tests decide when a request returns, which makes cancellation races reproducible without sleeps.
@MainActor
private final class ControlledLearningService: LearningExpressionGenerating {
    struct Request {
        let source: String
        let task: LearningExpressionTask
    }

    let settings: SuggestionSettingsModel
    let cancellationRecorder = LearningTaskCancellationRecorder()
    private(set) var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    private var callWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(settings: SuggestionSettingsModel) {
        self.settings = settings
    }

    func generate(source: String, task: LearningExpressionTask) async throws -> String {
        let requestID = requests.count
        requests.append(Request(source: source, task: task))
        resumeCallWaiters()
        let cancellationRecorder = self.cancellationRecorder
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                pending[requestID] = continuation
            }
        } onCancel: {
            Task { await cancellationRecorder.record(requestID) }
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { callWaiters[count, default: []].append($0) }
    }

    func completeRequest(_ requestID: Int, with result: Result<String, Error>) {
        pending.removeValue(forKey: requestID)?.resume(with: result)
    }

    func completeUnresolvedRequests(with result: Result<String, Error>) {
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume(with: result) }
    }

    private func resumeCallWaiters() {
        for expectedCount in callWaiters.keys.filter({ $0 <= requests.count }) {
            callWaiters.removeValue(forKey: expectedCount)?.forEach { $0.resume() }
        }
    }
}

/// Records cancellation from the task's cancellation handler, which may run outside the main actor.
private actor LearningTaskCancellationRecorder {
    private var cancelledRequests = Set<Int>()
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func record(_ requestID: Int) {
        cancelledRequests.insert(requestID)
        waiters.removeValue(forKey: requestID)?.forEach { $0.resume() }
    }

    func waitForCancellation(of requestID: Int) async {
        guard !cancelledRequests.contains(requestID) else { return }
        await withCheckedContinuation { waiters[requestID, default: []].append($0) }
    }
}

/// Simulates the editor transaction without calling Accessibility. `isCurrent` and replacement
/// completion are separately controlled so tests can distinguish stale captures from failed edits.
@MainActor
private final class ControlledSelectionReplacement: LearningSelectionReplacing {
    struct ReplaceCall: Equatable {
        let source: String
        let english: String
    }

    private let savedCapture: LearningSelectionCapture
    var isCurrentResult = true
    private(set) var captureCount = 0
    private(set) var currentCheckCount = 0
    private(set) var replaceCalls: [ReplaceCall] = []
    private var currentCheckWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var replaceWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var pendingReplace: CheckedContinuation<Void, Error>?

    init(capture: LearningSelectionCapture) {
        savedCapture = capture
    }

    func capture() throws -> LearningSelectionCapture {
        captureCount += 1
        return savedCapture
    }

    func isCurrent(_ saved: LearningSelectionCapture) -> Bool {
        currentCheckCount += 1
        resumeWaiters(currentCheckCount, from: &currentCheckWaiters)
        return isCurrentResult
    }

    private var returnedReplaceCount = 0
    private var returnedReplaceWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func waitForReturnedReplaceCount(_ count: Int) async {
        guard returnedReplaceCount < count else { return }
        await withCheckedContinuation { returnedReplaceWaiters[count, default: []].append($0) }
    }

    func replace(_ saved: LearningSelectionCapture, with english: String) async throws {
        defer {
            returnedReplaceCount += 1
            resumeWaiters(returnedReplaceCount, from: &returnedReplaceWaiters)
        }
        replaceCalls.append(.init(source: saved.source, english: english))
        resumeWaiters(replaceCalls.count, from: &replaceWaiters)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingReplace = continuation
        }
    }

    func waitForCurrentCheckCount(_ count: Int) async {
        guard currentCheckCount < count else { return }
        await withCheckedContinuation { currentCheckWaiters[count, default: []].append($0) }
    }

    func waitForReplaceCount(_ count: Int) async {
        guard replaceCalls.count < count else { return }
        await withCheckedContinuation { replaceWaiters[count, default: []].append($0) }
    }

    func completeReplace(_ result: Result<Void, Error>) {
        pendingReplace?.resume(with: result)
        pendingReplace = nil
    }

    func completeUnresolvedReplace(with result: Result<Void, Error>) {
        completeReplace(result)
    }

    private func resumeWaiters(
        _ observedCount: Int,
        from waiters: inout [Int: [CheckedContinuation<Void, Never>]]
    ) {
        for expectedCount in waiters.keys.filter({ $0 <= observedCount }) {
            waiters.removeValue(forKey: expectedCount)?.forEach { $0.resume() }
        }
    }
}

/// Stores display data and callbacks exactly as a panel would. Count-based async waiters let tests
/// synchronize on actual presentations and hides instead of guessing how much time a task needs.
@MainActor
private final class RecordingTranslationPanel: LearningTranslationPresenting {
    private(set) var isVisible = false
    private(set) var presentations: [LearningTranslationPresentation] = []
    private(set) var hideCount = 0
    private var acceptAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var presentationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var hideWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    var hasAcceptAction: Bool { acceptAction != nil }

    func show(
        _ presentation: LearningTranslationPresentation,
        accept: (() -> Void)?,
        cancel: @escaping () -> Void
    ) {
        presentations.append(presentation)
        acceptAction = accept
        cancelAction = cancel
        isVisible = true
        resumeWaiters(presentations.count, from: &presentationWaiters)
    }

    func hide() {
        hideCount += 1
        isVisible = false
        acceptAction = nil
        cancelAction = nil
        resumeWaiters(hideCount, from: &hideWaiters)
    }

    func clickAccept() { acceptAction?() }
    func clickCancel() { cancelAction?() }

    func waitForPresentationCount(_ count: Int) async {
        guard presentations.count < count else { return }
        await withCheckedContinuation { presentationWaiters[count, default: []].append($0) }
    }

    func waitForHideCount(_ count: Int) async {
        guard hideCount < count else { return }
        await withCheckedContinuation { hideWaiters[count, default: []].append($0) }
    }

    private func resumeWaiters(
        _ observedCount: Int,
        from waiters: inout [Int: [CheckedContinuation<Void, Never>]]
    ) {
        for expectedCount in waiters.keys.filter({ $0 <= observedCount }) {
            waiters.removeValue(forKey: expectedCount)?.forEach { $0.resume() }
        }
    }
}
