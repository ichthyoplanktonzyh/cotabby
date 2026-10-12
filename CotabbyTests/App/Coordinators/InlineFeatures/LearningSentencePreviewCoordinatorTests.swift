import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Cotabby

/// Controllable streamed updates verify user-visible ordering and stale rejection independently
/// from model speed. Synthetic AX handles are never queried or written by these collaborators.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct LearningSentencePreviewCoordinatorTests {
    @Test
    func focusEntryDoesNotSendExistingText() async throws {
        let rig = try Rig(initial: "已有内容")
        defer { rig.cleanup() }
        rig.coordinator.start()
        await Task.yield()
        #expect(rig.service.requests.isEmpty)
        #expect(!rig.panel.isVisible)
    }

    @Test
    func translationAppearsBeforeChunksAndTypingKeysAreNotClaimed() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        #expect(rig.panel.last?.translation == "I can do it.")
        #expect(rig.panel.last?.chunks.isEmpty == true)
        #expect(rig.panel.last?.isExpanded == false)
        #expect(rig.coordinator.decide(.init(keyCode: 36, flags: [])) == .notHandled)
        #expect(rig.coordinator.decide(.init(keyCode: 48, flags: [])) == .notHandled)
        rig.service.emit(.chunk(Self.chunk))
        #expect(rig.panel.last?.chunks == [Self.chunk])
        rig.service.finish()
        await waitUntil { rig.panel.last?.isGenerating == false }
        #expect(rig.reader.replaceCount == 0)
    }

    @Test(arguments: [false, true])
    func escapeClosesTheChildBeforeTheSentencePair(_ becomesUnavailable: Bool) async throws {
        var eligible = true
        let rig = try Rig(availability: { eligible ? nil : "unavailable" })
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        rig.panel.hasDetail = true
        eligible = !becomesUnavailable
        #expect(rig.coordinator.decide(.init(keyCode: 53, flags: [])) == .consume)
        #expect(rig.panel.isVisible)
        #expect(!rig.panel.hasDetail)
        #expect(rig.coordinator.decide(.init(keyCode: 53, flags: [])) == .consume)
        #expect(!rig.panel.isVisible)
        rig.service.finish()
    }

    @Test
    func expandingUsesAlreadyGeneratedTranslationAndAnalysis() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        rig.service.emit(.chunk(Self.chunk))
        rig.service.finish()
        await waitUntil { rig.panel.last?.isGenerating == false }
        #expect(rig.coordinator.decide(.init(keyCode: 17, flags: .maskAlternate)) == .consume)
        await waitUntil { rig.panel.last?.isExpanded == true }
        #expect(rig.service.requests.count == 1)
        #expect(rig.panel.last?.chunks == [Self.chunk])
    }

    @Test
    func aNewSentenceRetainsPreviousTranslationAndOnlySendsCurrentSentence() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我喜欢你")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I like you."))
        rig.service.finish(translation: "I like you.")
        await waitUntil { rig.panel.last?.isGenerating == false }
        try rig.edit("我喜欢你。我想多了解你")
        await waitUntil { rig.service.requests.count == 2 }
        #expect(rig.service.requests[1].source == "我想多了解你")
        #expect(rig.panel.last?.previousTranslation == "I like you.")
    }

    @Test
    func appendingToUnfinishedSentenceReplacesThatSentence() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我喜欢你")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I like you."))
        try rig.edit("我喜欢你做的饭")
        #expect(rig.panel.last?.isStale == true)
        await waitUntil { rig.service.requests.count == 2 }
        #expect(rig.service.requests[1].source == "我喜欢你做的饭")
        #expect(rig.panel.last?.previousTranslation == nil)
        rig.service.emit(.translation("stale translation"), request: 0)
        #expect(rig.panel.last?.translation != "stale translation")
    }

    @Test(arguments: ["disable", "endpoint", "focus", "stop"])
    func oldEventsCannotReopenAfterInvalidation(_ change: String) async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        switch change {
        case "disable": rig.settings.languageLearning.translationEnabled = false
        case "endpoint": rig.settings.setOpenAICompatibleBaseURL("https://another.invalid/v1")
        case "focus": try rig.edit("另一字段", element: "other-field")
        default: rig.coordinator.stop()
        }
        rig.service.emit(.translation("obsolete"))
        rig.service.emit(.chunk(Self.chunk))
        rig.service.finish()
        await Task.yield()
        #expect(!rig.panel.isVisible)
        #expect(rig.reader.replaceCount == 0)
    }

    @Test
    func editingEarlierTextDoesNotUseItsOldTranslationAsThePreviousSentence() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我喜欢你")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I like you."))
        rig.service.finish(translation: "I like you.")
        await waitUntil { rig.panel.last?.isGenerating == false }
        try rig.edit("我喜欢你。我想多了解你")
        await waitUntil { rig.service.requests.count == 2 }
        rig.service.emit(.translation("I'd like to know you better."))
        rig.service.finish()
        await waitUntil { rig.panel.last?.isGenerating == false }
        try rig.edit("我喜欢你做的饭")
        await waitUntil { rig.service.requests.count == 3 }
        #expect(rig.panel.last?.previousTranslation == nil)
    }

    @Test
    func queuedShortcutCannotRunAfterStop() async throws {
        let rig = try Rig(initial: "我能做到")
        defer { rig.cleanup() }
        rig.coordinator.start()
        #expect(rig.coordinator.decide(.init(keyCode: 17, flags: .maskAlternate)) == .consume)
        rig.coordinator.stop()
        await Task.yield()
        #expect(rig.service.requests.isEmpty)
        #expect(!rig.panel.isVisible)
    }

    @Test
    func frontmostChangeRejectsUpdatesBeforeTheNextFocusSnapshot() async throws {
        var frontmost = true
        let rig = try Rig(isFrontmost: { frontmost })
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        frontmost = false
        rig.service.emit(.translation("I can do it."))
        rig.service.emit(.chunk(Self.chunk))
        rig.service.finish()
        await Task.yield()
        #expect(rig.panel.last?.translation.isEmpty == true)
        #expect(rig.panel.last?.chunks.isEmpty == true)
    }

    @Test
    func knownMarkedTextDoesNotGenerateAndAnalysisFailureKeepsTranslation() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到", marked: NSRange(location: 0, length: 4))
        await Task.yield()
        #expect(rig.service.requests.isEmpty)
        try rig.edit("我能做到", marked: nil)
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        rig.service.fail()
        await waitUntil { rig.panel.last?.isGenerating == false }
        #expect(rig.panel.last?.translation == "I can do it.")
        #expect(rig.panel.last?.message.contains("analysis unavailable") == true)
    }

    private static let chunk = LearningMeaningChunk(id: 0, sourceRanges: [.init(location: 1, length: 1)],
        targetRanges: [.init(location: 2, length: 3)], explanation: "表达能力")

    @MainActor
    private final class Rig {
        let suite = "io.cotabby.tests.SentencePreview-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: SuggestionSettingsModel
        let service: StreamService
        let focus: RigFocusProvider
        let reader: SentenceReader
        let panel = SentencePanel()
        let coordinator: LearningSentencePreviewCoordinator

        init(initial: String = "", isFrontmost: @escaping @MainActor () -> Bool = { true },
             availability: @escaping @MainActor () -> String? = { nil }) throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
            settings.languageLearning.translationEnabled = true
            settings.languageLearning.sentencePreviewEnabled = true
            settings.languageLearning.model = "learning-model"
            service = StreamService(settings: settings)
            let context = CotabbyTestFixtures.focusedInputSnapshot(precedingText: initial, documentLength: initial.utf16.count)
            focus = RigFocusProvider(snapshot: FocusSnapshot(applicationName: context.applicationName,
                bundleIdentifier: context.bundleIdentifier, capability: .supported, context: context))
            reader = SentenceReader(focus: focus)
            coordinator = LearningSentencePreviewCoordinator(service: service, reader: reader, focus: focus,
                panel: panel, debounce: .zero, isFrontmost: { _ in isFrontmost() }, availability: availability)
        }

        func edit(_ text: String, element: String = "field", marked: NSRange? = nil) throws {
            let old = focus.snapshot.context
            let sequence = (old?.focusChangeSequence ?? 1) + (old?.elementIdentifier == element ? 0 : 1)
            let context = CotabbyTestFixtures.focusedInputSnapshot(elementIdentifier: element, precedingText: text,
                focusChangeSequence: sequence, hostMarkedTextRange: marked, documentLength: text.utf16.count)
            focus.snapshot = FocusSnapshot(applicationName: context.applicationName, bundleIdentifier: context.bundleIdentifier,
                capability: .supported, context: context)
            focus.snapshotSubject.send(focus.snapshot)
        }

        func cleanup() {
            coordinator.stop()
            service.cleanup()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class StreamService: LearningSentenceGenerating {
        struct Request { let source: String; let update: (LearningSentenceUpdate) -> Void }
        let settings: SuggestionSettingsModel
        var requests: [Request] = []
        var pending: [Int: CheckedContinuation<LearningSentenceResult, Error>] = [:]
        init(settings: SuggestionSettingsModel) { self.settings = settings }
        func generateSentence(source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage,
                              onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
            let index = requests.count
            requests.append(.init(source: source, update: onUpdate))
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func emit(_ update: LearningSentenceUpdate, request: Int? = nil) {
            let index = request ?? (requests.count - 1)
            guard requests.indices.contains(index) else { Issue.record("No generation request to deliver to"); return }
            requests[index].update(update)
        }
        func finish(translation: String = "I can do it.") {
            pending.removeValue(forKey: requests.count - 1)?.resume(returning: .init(translation: translation, chunks: [chunk]))
        }
        func fail() { pending.removeValue(forKey: requests.count - 1)?.resume(throwing: LearningFailure.message("analysis unavailable")) }
        func cleanup() { for continuation in pending.values { continuation.resume(throwing: CancellationError()) }; pending.removeAll() }
    }

    private final class SentenceReader: LearningSelectionReplacing {
        let focus: RigFocusProvider
        var replaceCount = 0
        init(focus: RigFocusProvider) { self.focus = focus }
        func capture() throws -> LearningSelectionCapture {
            let context = try #require(focus.snapshot.context)
            let range = try LearningTextScopePolicy.conversionRange(value: context.precedingText, selection: context.documentSelection)
            return .init(element: AXUIElementCreateApplication(123), context: context, value: context.precedingText,
                range: range, source: try LearningTextScopePolicy.text(value: context.precedingText, range: range),
                replacementUnavailableReason: "unknown IME evidence", inputMethodAssessment: .copyOnly(reason: "unknown IME evidence"))
        }
        func isCurrent(_ saved: LearningSelectionCapture) -> Bool { focus.snapshot.context == saved.context }
        func replace(_ saved: LearningSelectionCapture, with english: String) async throws { replaceCount += 1 }
    }

    private final class SentencePanel: LearningSentencePresenting {
        var isVisible = false
        var hasDetail = false
        var last: LearningSentencePresentation?
        func hide() { isVisible = false }
        func dismissDetail() -> Bool {
            guard hasDetail else { return false }
            hasDetail = false
            return true
        }
        func show(_ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void) {
            isVisible = true
            last = presentation
        }
    }
}
