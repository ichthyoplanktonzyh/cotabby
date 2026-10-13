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
    func typingHidesImmediatelyAndOnlyTheLatestPauseCanPresent() async throws {
        let pause = PauseGate(), rig = try Rig(pause: pause)
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { pause.pending.count == 1 }
        #expect(!rig.panel.isVisible && rig.service.requests.isEmpty)
        pause.release(0)
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        await waitUntil { rig.service.analysisCalls == 1 }
        let oldCallback = try #require(rig.service.analysisCallbacks.first)
        #expect(rig.panel.isVisible)
        #expect(!rig.coordinator.observe(.init(kind: .textMutation, keyCode: 0, characters: "a", flags: [])))
        #expect(!rig.panel.isVisible, "Keyboard input must hide before AX catches up")
        let shown = rig.panel.showCount
        oldCallback(.chunk(Self.chunk))
        #expect(!rig.panel.isVisible && rig.panel.showCount == shown)
        try rig.edit("我能做到更多")
        await waitUntil { pause.pending.count == 2 }
        try rig.edit("我能做到更多事情")
        await waitUntil { pause.pending.count == 3 }
        #expect(!rig.panel.isVisible && rig.service.requests.count == 1)
        pause.release(1)
        await Task.yield()
        #expect(!rig.panel.isVisible && rig.service.requests.count == 1)
        pause.release(2)
        await waitUntil { rig.service.requests.count == 2 }
        #expect(rig.panel.isVisible)
        #expect(rig.panel.last?.source == "我能做到更多事情")
        #expect(pause.durations.allSatisfy { $0 == .milliseconds(600) })
    }

    @Test
    func cachedPreviewAlsoWaitsForPause() async throws {
        let pause = PauseGate(), rig = try Rig(pause: pause)
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { pause.pending.count == 1 }
        pause.release(0)
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        await waitUntil { rig.service.analysisCalls == 1 }
        rig.service.finish()
        await waitUntil { rig.panel.last?.isGenerating == false }
        try rig.edit("你能做到")
        await waitUntil { pause.pending.count == 2 }
        pause.release(1)
        await waitUntil { rig.service.requests.count == 2 }
        try rig.edit("我能做到")
        await waitUntil { pause.pending.count == 3 }
        #expect(!rig.panel.isVisible)
        pause.release(2)
        await waitUntil { rig.panel.isVisible && rig.panel.last?.translation == "I can do it." }
        #expect(rig.service.requests.count == 2)
        #expect(rig.panel.last?.chunks == [Self.chunk])
    }

    @Test
    func explicitShortcutCanReopenAfterInputSuspendsThePreview() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        await waitUntil { rig.service.analysisCalls == 1 }
        rig.service.finish()
        await waitUntil { rig.panel.last?.isGenerating == false }
        _ = rig.coordinator.observe(.init(kind: .navigation, keyCode: 123, characters: "", flags: []))
        #expect(!rig.panel.isVisible)
        #expect(rig.coordinator.decide(.init(keyCode: 17, flags: .maskAlternate)) == .consume)
        await waitUntil { rig.panel.isVisible && rig.panel.last?.isExpanded == true }
        #expect(rig.panel.last?.isStale == false)
        #expect(rig.service.requests.count == 1)
    }
    @Test(arguments: ["off", "model", "credential"])
    func analysisConfigurationCancelsOnlyAnalysisAndPreservesTranslation(_ change: String) async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        await waitUntil { rig.service.analysisCalls == 1 }
        let oldCallback = try #require(rig.service.analysisCallbacks.first)
        if change == "off" { rig.settings.languageLearning.analysisEnabled = false }
        else if change == "model" { rig.settings.languageLearning.analysis.endpointModel = "new-analyst" }
        else { rig.settings.languageLearning.analysis.saveAPIKey("new-key") }
        await waitUntil { rig.service.cancelledAnalysis == 1 }
        if change != "off" { await waitUntil { rig.service.analysisCalls == 2 } }
        oldCallback(.chunk(Self.chunk))
        #expect(rig.panel.last?.translation == "I can do it.")
        #expect(rig.panel.last?.chunks.isEmpty == true)
        #expect(rig.service.requests.count == 1)
        if change == "off" { #expect(rig.service.analysisCalls == 1) }
    }

    @Test(arguments: [false, true])
    func editingCancelsTheActiveModelStage(_ analysis: Bool) async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        if analysis {
            rig.service.emit(.translation("I can do it."))
            await waitUntil { rig.service.analysisCalls == 1 }
        }
        try rig.edit("我能做到更多")
        await waitUntil { analysis ? rig.service.cancelledAnalysis == 1 : rig.service.cancelledTranslation == 1 }
        await waitUntil { rig.service.requests.count == 2 }
        #expect(rig.service.requests.last?.source == "我能做到更多")
    }

    @Test(arguments: [false, true])
    func lowPowerPauseCancelsTheActiveStageAndRequiresANewEdit(_ analysis: Bool) async throws {
        var paused = false
        let rig = try Rig(availability: { paused ? "Paused in Low Power Mode" : nil })
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        if analysis {
            rig.service.emit(.translation("I can do it."))
            await waitUntil { rig.service.analysisCalls == 1 }
        }
        paused = true
        rig.coordinator.availabilityChanged()
        await waitUntil { analysis ? rig.service.cancelledAnalysis == 1 : rig.service.cancelledTranslation == 1 }
        #expect(!rig.panel.isVisible)
        paused = false
        await Task.yield()
        #expect(rig.service.requests.count == 1)
        try rig.edit("我能做到更多")
        await waitUntil { rig.service.requests.count == 2 }
    }

    @Test
    func cachedSentencePairReusesBothStagesAndFailedAnalysisCanRetryAlone() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        await waitUntil { rig.service.analysisCalls == 1 }
        rig.service.fail()
        await waitUntil { rig.panel.last?.isGenerating == false }
        rig.settings.languageLearning.analysis.endpointModel = "retry-analyst"
        await waitUntil { rig.service.analysisCalls == 2 }
        #expect(rig.service.requests.count == 1)
        rig.service.finish()
        await waitUntil { rig.panel.last?.isGenerating == false }
        try rig.edit("你能做到")
        await waitUntil { rig.service.requests.count == 2 }
        try rig.edit("我能做到")
        await waitUntil { rig.panel.last?.source == "我能做到" && rig.panel.last?.isStale == false &&
            rig.panel.last?.translation == "I can do it." }
        #expect(rig.service.requests.count == 2)
        #expect(rig.service.analysisCalls == 2)
        #expect(rig.panel.last?.chunks == [Self.chunk])
    }
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
        rig.service.emit(.chunks([Self.chunk]))
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
        try rig.edit("我喜欢你做的饭")
        #expect(!rig.panel.isVisible)
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
        case "endpoint": rig.settings.languageLearning.translation.baseURL = "https://another.invalid/v1"
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
        rig.service.finish(translation: "I like you.")
        await waitUntil { rig.panel.last?.isGenerating == false }
        try rig.edit("我喜欢你。我想多了解你")
        await waitUntil { rig.service.requests.count == 2 }
        rig.service.emit(.translation("I'd like to know you better."))
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
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
        await Task.yield()
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
        await waitUntil { rig.panel.last?.translation.isEmpty == false && !rig.service.pending.isEmpty }
        rig.service.fail()
        await waitUntil { rig.panel.last?.isGenerating == false }
        #expect(rig.panel.last?.translation == "I can do it.")
        #expect(rig.panel.last?.message.contains("analysis unavailable") == true)
    }

    private static let chunk = LearningMeaningChunk(id: 0, sourceRanges: [.init(location: 1, length: 1)],
        targetRanges: [.init(location: 2, length: 3)])

    @Test
    func completeBatchReplacesChunksAndPartialLocationKeepsTranslation() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        rig.coordinator.start()
        try rig.edit("我能做到")
        await waitUntil { rig.service.requests.count == 1 }
        rig.service.emit(.translation("I can do it."))
        await waitUntil { rig.service.analysisCalls == 1 }
        let batch = [Self.chunk]
        rig.service.emit(.chunks(batch))
        rig.service.emit(.chunks(batch))
        #expect(rig.panel.last?.chunks == batch)
        rig.service.finish(unresolvedChunkCount: 1)
        await waitUntil { rig.panel.last?.isGenerating == false }
        #expect(rig.panel.last?.translation == "I can do it.")
        #expect(rig.panel.last?.message.contains("部分语块无法可靠定位") == true)
    }

    /// Hold debounce completion explicitly so assertions never depend on machine speed. Obsolete
    /// waits may resume too; the production request identity must still reject their publication.
    @MainActor
    private final class PauseGate {
        var pending: [CheckedContinuation<Void, Never>?] = []
        var durations: [Duration] = []
        func wait(_ duration: Duration) async {
            durations.append(duration)
            await withCheckedContinuation { pending.append($0) }
        }
        func release(_ index: Int) {
            pending[index]?.resume()
            pending[index] = nil
        }
        func finishAll() { for index in pending.indices { release(index) } }
    }

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
        let pause: PauseGate?

        init(initial: String = "", isFrontmost: @escaping @MainActor () -> Bool = { true },
             availability: @escaping @MainActor () -> String? = { nil }, pause: PauseGate? = nil) throws {
            self.pause = pause
            defaults = try #require(UserDefaults(suiteName: suite))
            settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
            settings.languageLearning.translationEnabled = true
            settings.languageLearning.analysisEnabled = true
            settings.languageLearning.analysis.backend = .endpoint
            settings.languageLearning.analysis.endpointModel = "analysis-model"
            settings.languageLearning.sentencePreviewEnabled = true
            settings.languageLearning.model = "learning-model"
            service = StreamService(settings: settings)
            let context = CotabbyTestFixtures.focusedInputSnapshot(precedingText: initial, documentLength: initial.utf16.count)
            focus = RigFocusProvider(snapshot: FocusSnapshot(applicationName: context.applicationName,
                bundleIdentifier: context.bundleIdentifier, capability: .supported, context: context))
            reader = SentenceReader(focus: focus)
            coordinator = LearningSentencePreviewCoordinator(service: service, reader: reader, focus: focus,
                panel: panel, debounce: pause == nil ? .zero : .milliseconds(600),
                waitForPause: { delay in
                    if let pause { await pause.wait(delay) }
                    else { try await Task.sleep(for: delay) }
                }, isFrontmost: { _ in isFrontmost() }, availability: availability)
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
            pause?.finishAll()
            service.cleanup()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class StreamService: LearningSentenceGenerating {
        struct Request { let source: String; var update: (LearningSentenceUpdate) -> Void }
        let settings: SuggestionSettingsModel
        var requests: [Request] = []
        var pending: [UUID: CheckedContinuation<LearningSentenceResult, Error>] = [:]
        var translationIDs: [Int: UUID] = [:]
        var analysisIDs: [Int: UUID] = [:]
        var translated: [Int: String] = [:]
        var analysisCalls = 0
        var cancelledTranslation = 0
        var cancelledAnalysis = 0
        var analysisCallbacks: [(LearningSentenceUpdate) -> Void] = []
        init(settings: SuggestionSettingsModel) { self.settings = settings }
        func generateSentence(source: String, sourceLanguage: LearningLanguage, targetLanguage: LearningLanguage,
                              onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
            throw CancellationError()
        }
        private func wait(index: Int, analysis: Bool) async throws -> LearningSentenceResult {
            let id = UUID()
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation {
                    pending[id] = $0
                    if analysis { analysisIDs[index] = id } else { translationIDs[index] = id }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, let continuation = self.pending.removeValue(forKey: id) else { return }
                    if analysis { self.cancelledAnalysis += 1 } else { self.cancelledTranslation += 1 }
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
        func translateSentence(source: String, sourceLanguage: LearningLanguage,
                               targetLanguage: LearningLanguage) async throws -> String {
            let index = requests.count
            requests.append(.init(source: source, update: { _ in }))
            return try await wait(index: index, analysis: false).translation
        }
        func analyzeSentence(source: String, translation: String, sourceLanguage: LearningLanguage,
                             targetLanguage: LearningLanguage,
                             onUpdate: @escaping @MainActor (LearningSentenceUpdate) -> Void) async throws -> LearningSentenceResult {
            let index = requests.lastIndex { $0.source == source }!
            requests[index].update = onUpdate
            analysisCalls += 1
            analysisCallbacks.append(onUpdate)
            return try await wait(index: index, analysis: true)
        }
        func emit(_ update: LearningSentenceUpdate, request: Int? = nil) {
            let index = request ?? (requests.count - 1)
            guard requests.indices.contains(index) else { Issue.record("No generation request to deliver to"); return }
            if case .translation(let text) = update {
                translated[index] = text
                if let id = translationIDs[index] {
                    pending.removeValue(forKey: id)?.resume(returning: .init(translation: text, chunks: []))
                }
            } else { requests[index].update(update) }
        }
        func finish(translation: String = "I can do it.", unresolvedChunkCount: Int = 0) {
            let index = requests.count - 1
            if let id = analysisIDs[index] {
                pending.removeValue(forKey: id)?.resume(returning: .init(translation: translated[index] ?? translation,
                    chunks: [chunk], unresolvedChunkCount: unresolvedChunkCount))
            }
        }
        func fail() {
            if let id = analysisIDs[requests.count - 1] {
                pending.removeValue(forKey: id)?.resume(throwing: LearningFailure.message("analysis unavailable"))
            }
        }
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
        var showCount = 0
        func hide() { isVisible = false }
        func dismissDetail() -> Bool {
            guard hasDetail else { return false }
            hasDetail = false
            return true
        }
        func show(_ presentation: LearningSentencePresentation, expand: @escaping () -> Void, dismiss: @escaping () -> Void) {
            showCount += 1
            isVisible = true
            last = presentation
        }
    }
}
