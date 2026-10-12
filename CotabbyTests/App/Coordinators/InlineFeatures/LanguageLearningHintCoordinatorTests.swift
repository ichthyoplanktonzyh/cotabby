import Combine
import Foundation
import Testing
@testable import Cotabby

/// Locks down the passive hint workflow without invoking Accessibility, a real model, or a panel.
/// Each rig owns isolated settings and collaborators; focus snapshots flow through the same
/// publisher the app coordinator observes, while the service holds replies until a test releases them.
@Suite(.serialized)
@MainActor
struct LanguageLearningHintCoordinatorTests {
    private let reply = #"{"expression":"apple","explanation":"a fruit"}"#

    @Test
    func defaultOffAndInitialFocusDoNotRequestHints() async {
        let rig = Rig(hintsEnabled: false)
        defer { rig.cleanup() }

        rig.coordinator.start()
        rig.publish(text: "I like apples", source: "apple")
        rig.publish(text: "I really like apples", source: "apple")
        try? await Task.sleep(for: .milliseconds(850))

        #expect(rig.service.requests.isEmpty)
        #expect(rig.panel.presentations.isEmpty)
    }

    @Test
    func movingCaretAcrossUnchangedTextDoesNotScheduleHintButTypedTextDoes() async {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()

        rig.publish(text: "We use apple today.", source: "apple")
        rig.publish(text: "We use apple today.", source: "apple", caretLocation: ("We use ").utf16.count)
        try? await Task.sleep(for: .milliseconds(850))
        #expect(rig.service.requests.isEmpty, "A caret move changes selection offsets but not committed text")

        rig.publish(text: "We use xapple today.", source: "apple", caretLocation: ("We use x").utf16.count)
        let requestArrived = await rig.service.waitForRequestCount(1, within: .seconds(2))
        #expect(requestArrived)
        #expect(rig.service.requests.first?.source == "apple")
    }

    @Test
    func missingTrailingExcerptAndUnknownDocumentLengthDoNotTurnCaretMoveIntoAppend() async {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()

        rig.publish(text: "We use apple today.", source: "apple", trailingTextUnavailable: true,
                    documentLengthUnknown: true)
        rig.publish(text: "We use apple today.", source: "apple", caretLocation: ("We use ").utf16.count,
                    trailingTextUnavailable: true, documentLengthUnknown: true)
        try? await Task.sleep(for: .milliseconds(850))

        #expect(rig.service.requests.isEmpty,
                "An empty trailing excerpt and absent document length cannot prove an end-of-document append")
    }

    @Test
    func onlySameSessionTextChangeSchedulesRequestAfterDebounce() async throws {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()

        rig.publish(text: "I like apple", source: "apple")
        rig.publish(text: "I like apple today", source: "apple", focusSequence: 2)
        try? await Task.sleep(for: .milliseconds(850))
        #expect(rig.service.requests.isEmpty, "Entering a new field session must not send its existing text")

        rig.publish(text: "I like apple today.", source: "apple", focusSequence: 2)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(rig.service.requests.isEmpty, "The AX text change is debounced before generation")
        #expect(rig.reader.candidateReadCount == 0, "The reader does no AX work in the focus publisher")
        let firstRequestArrived = await rig.service.waitForRequestCount(1, within: .seconds(2))
        #expect(firstRequestArrived)
        #expect(rig.reader.candidateReadCount > 0, "A committed-word candidate is read after the debounce")

        let request = try #require(rig.service.requests.first)
        #expect(request.source == "apple")
        #expect(request.task == .hint(source: .english, target: .chinese))

        rig.service.completeRequest(0, with: .success(reply))
        let firstHintPresented = await rig.panel.waitForPresentationCount(1, within: .seconds(1))
        #expect(firstHintPresented)
        #expect(rig.panel.presentations.first?.hint.expression == "apple")
    }

    @Test
    func staleReplyAfterTextChangeCannotDisplayOrSeedCache() async {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()
        rig.publish(text: "We discussed apple", source: "apple")
        rig.publish(text: "We discussed apple yesterday", source: "apple")
        let firstRequestArrived = await rig.service.waitForRequestCount(1, within: .seconds(2))
        #expect(firstRequestArrived)

        // The new snapshot invalidates request 0 but keeps the cache key (source/languages) the same.
        rig.publish(text: "Yesterday we discussed apple", source: "apple")
        await rig.service.waitForCancellation(of: 0)
        rig.service.completeRequest(0, with: .success(#"{"expression":"stale","explanation":"old"}"#))

        // A second HTTP/model call proves the late first result did not populate the in-memory cache.
        let secondRequestArrived = await rig.service.waitForRequestCount(2, within: .seconds(3))
        #expect(secondRequestArrived)
        let firstRequest = rig.service.requests.first
        let secondRequest = rig.service.requests.dropFirst().first
        #expect(firstRequest != nil && secondRequest != nil)
        if let firstRequest, let secondRequest {
            #expect(secondRequest.startedAt.timeIntervalSince(firstRequest.startedAt) >= 1.9,
                    "Model calls remain at least two seconds apart")
        }
        #expect(rig.panel.presentations.isEmpty)
        rig.service.completeRequest(1, with: .success(#"{"expression":"fresh","explanation":"current"}"#))
        let freshHintPresented = await rig.panel.waitForPresentationCount(1, within: .seconds(1))
        #expect(freshHintPresented)
        #expect(rig.panel.presentations.first?.hint.expression == "fresh")
        #expect(rig.panel.presentations.first?.candidate.context.precedingText == "Yesterday we discussed apple")
    }

    @Test
    func escapeOnlyConsumesWhileHintIsVisibleAndEnterPassesThrough() async {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()
        rig.publish(text: "I learned apple", source: "apple")
        rig.publish(text: "I learned apple today", source: "apple")
        let requestArrived = await rig.service.waitForRequestCount(1, within: .seconds(2))
        #expect(requestArrived)
        rig.service.completeRequest(0, with: .success(reply))
        let hintPresented = await rig.panel.waitForPresentationCount(1, within: .seconds(1))
        #expect(hintPresented)

        let candidateReadsBeforeKeys = rig.reader.candidateReadCount
        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 36)) == .notHandled)
        #expect(rig.panel.isVisible, "Enter must remain available to the host app")
        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 53)) == .consume)
        #expect(rig.reader.candidateReadCount == candidateReadsBeforeKeys,
                "Escape uses the already visible candidate and performs no tap-time AX read")
        #expect(!rig.panel.isVisible)
        #expect(rig.coordinator.decide(InputMonitorKeyEvent(keyCode: 53)) == .notHandled)
    }

    @Test
    func stopCancelsInFlightGenerationAndDropsItsLateReply() async {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()
        rig.publish(text: "I found apple", source: "apple")
        rig.publish(text: "I found apple nearby", source: "apple")
        let requestArrived = await rig.service.waitForRequestCount(1, within: .seconds(2))
        #expect(requestArrived)

        rig.coordinator.stop()
        await rig.service.waitForCancellation(of: 0)
        rig.service.completeRequest(0, with: .success(reply))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(rig.panel.presentations.isEmpty)
        #expect(!rig.panel.isVisible)
    }

    @Test
    func settingsChangeCancelsInFlightGenerationAndDropsItsLateReply() async {
        let rig = Rig(hintsEnabled: true)
        defer { rig.cleanup() }
        rig.coordinator.start()
        rig.publish(text: "We use apple", source: "apple")
        rig.publish(text: "We use apple often", source: "apple")
        let requestArrived = await rig.service.waitForRequestCount(1, within: .seconds(2))
        #expect(requestArrived)

        rig.settings.languageLearning.targetLanguage = .french
        await rig.service.waitForCancellation(of: 0)
        rig.service.completeRequest(0, with: .success(reply))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(rig.panel.presentations.isEmpty)
        #expect(!rig.panel.isVisible)
    }

    /// Owns one isolated settings suite and the in-memory graph for a test. Publishing a new
    /// snapshot updates the reader's local candidate before notifying the coordinator, matching
    /// the ordering of a completed AX capture without ever reading a real field.
    @MainActor
    private final class Rig {
        let settings: SuggestionSettingsModel
        let service: HintServiceStub
        let reader: HintReaderStub
        let panel: HintPanelStub
        let focus: HintFocusStub
        let coordinator: LanguageLearningHintCoordinator
        private let defaults: UserDefaults
        private let suiteName: String
        private var focusSequence: UInt64 = 1

        init(hintsEnabled: Bool) {
            suiteName = "io.cotabby.tests.LanguageLearningHintCoordinator-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
            settings.languageLearning.translationEnabled = true
            settings.languageLearning.hintsEnabled = hintsEnabled

            service = HintServiceStub(settings: settings)
            reader = HintReaderStub(settings: settings)
            panel = HintPanelStub()
            focus = HintFocusStub()
            coordinator = LanguageLearningHintCoordinator(
                service: service,
                reader: reader,
                panel: panel,
                focus: focus,
                availability: { true }
            )
        }

        func publish(
            text: String,
            source: String,
            focusSequence: UInt64? = nil,
            caretLocation: Int? = nil,
            trailingTextUnavailable: Bool = false,
            documentLengthUnknown: Bool = false
        ) {
            if let focusSequence { self.focusSequence = focusSequence }
            let fullValue = text as NSString
            let location = caretLocation ?? fullValue.length
            precondition(location >= 0 && location <= fullValue.length)
            let precedingText = fullValue.substring(to: location)
            let trailingText = trailingTextUnavailable ? "" : fullValue.substring(from: location)
            let context = CotabbyTestFixtures.focusedInputSnapshot(
                applicationName: "Hint Host",
                bundleIdentifier: "com.example.HintHost",
                processIdentifier: 481,
                elementIdentifier: "composer",
                precedingText: precedingText,
                trailingText: trailingText,
                selection: NSRange(location: location, length: 0),
                focusChangeSequence: self.focusSequence,
                focusedURLString: "https://example.test/chat/one",
                documentLength: documentLengthUnknown ? nil : fullValue.length
            )
            reader.liveCandidate = LearningHintCandidate(
                context: context,
                source: source,
                sourceLanguage: .english,
                targetLanguage: .chinese
            )
            focus.publish(context)
        }

        func cleanup() {
            coordinator.stop()
            service.completeUnresolvedRequests(with: .success(#"{"expression":"cleanup","explanation":"cleanup"}"#))
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// Mimics the production reader's setting gate and exposes only the current committed-word
    /// candidate. The production AX identity and IME checks remain outside this coordinator test.
    @MainActor
    private final class HintReaderStub: LearningHintReading {
        private let settings: SuggestionSettingsModel
        var liveCandidate: LearningHintCandidate?
        private(set) var candidateReadCount = 0

        init(settings: SuggestionSettingsModel) { self.settings = settings }

        func candidate() -> LearningHintCandidate? {
            candidateReadCount += 1
            return settings.languageLearning.translationEnabled && settings.languageLearning.hintsEnabled
                ? liveCandidate : nil
        }

        func isCurrent(_ candidate: LearningHintCandidate) -> Bool { self.candidate() == candidate }
    }

    /// Captures presentations as values and retains the dismiss callback so Escape handling is
    /// exercised through the coordinator's real decision method, not a panel-specific shortcut.
    @MainActor
    private final class HintPanelStub: LearningHintPresenting {
        struct Presentation {
            let hint: LearningWordHint
            let candidate: LearningHintCandidate
        }

        private(set) var isVisible = false
        private(set) var presentations: [Presentation] = []
        private var dismissAction: (() -> Void)?

        func hide() { isVisible = false; dismissAction = nil }

        func show(_ hint: LearningWordHint, candidate: LearningHintCandidate, dismiss: @escaping () -> Void) {
            presentations.append(.init(hint: hint, candidate: candidate))
            dismissAction = dismiss
            isVisible = true
        }

        func dismiss() { dismissAction?() }

        func waitForPresentationCount(_ count: Int, within timeout: Duration) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while presentations.count < count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            return presentations.count >= count
        }
    }

    /// Publishes editor snapshots on demand. It intentionally does not auto-publish its initial
    /// value, so tests distinguish focus entry from a subsequent value notification.
    @MainActor
    private final class HintFocusStub: SuggestionFocusProviding {
        private let subject = PassthroughSubject<FocusSnapshot, Never>()
        private(set) var snapshot = FocusSnapshot.inactive
        var snapshotPublisher: AnyPublisher<FocusSnapshot, Never> { subject.eraseToAnyPublisher() }

        func publish(_ context: FocusedInputSnapshot) {
            snapshot = FocusSnapshot(
                applicationName: context.applicationName,
                bundleIdentifier: context.bundleIdentifier,
                capability: .supported,
                context: context
            )
            subject.send(snapshot)
        }

        func refreshNow() {}
    }

    /// Holds each generated response until the test releases it, making stale-result and
    /// cancellation races observable without a network request or timing-dependent server.
    @MainActor
    private final class HintServiceStub: LearningExpressionGenerating {
        struct Request: Equatable {
            let source: String
            let task: LearningExpressionTask
            let startedAt: Date
        }

        let settings: SuggestionSettingsModel
        private(set) var requests: [Request] = []
        private var pending: [Int: CheckedContinuation<String, Error>] = [:]
        private let cancellationRecorder = HintCancellationRecorder()

        init(settings: SuggestionSettingsModel) { self.settings = settings }

        func generate(source: String, task: LearningExpressionTask) async throws -> String {
            let id = requests.count
            requests.append(.init(source: source, task: task, startedAt: Date()))
            let cancellationRecorder = self.cancellationRecorder
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    pending[id] = continuation
                }
            } onCancel: {
                Task { await cancellationRecorder.record(id) }
            }
        }

        func waitForRequestCount(_ count: Int, within timeout: Duration) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while requests.count < count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            return requests.count >= count
        }

        func waitForCancellation(of id: Int) async { await cancellationRecorder.wait(for: id) }

        func completeRequest(_ id: Int, with result: Result<String, Error>) {
            pending.removeValue(forKey: id)?.resume(with: result)
        }

        func completeUnresolvedRequests(with result: Result<String, Error>) {
            let continuations = Array(pending.values)
            pending.removeAll()
            continuations.forEach { $0.resume(with: result) }
        }

    }

    /// Records cancellation from the service task's cancellation handler, which may run outside
    /// the main actor while the fake service itself remains actor-isolated.
    private actor HintCancellationRecorder {
        private var cancelled = Set<Int>()
        private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

        func record(_ id: Int) {
            cancelled.insert(id)
            waiters.removeValue(forKey: id)?.forEach { $0.resume() }
        }

        func wait(for id: Int) async {
            guard !cancelled.contains(id) else { return }
            await withCheckedContinuation { waiters[id, default: []].append($0) }
        }
    }
}
