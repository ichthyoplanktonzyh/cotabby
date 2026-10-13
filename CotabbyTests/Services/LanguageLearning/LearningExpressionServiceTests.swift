import Foundation
import Testing
@testable import Cotabby

/// Exercises the request and cancellation boundary using the production API client with an
/// in-process URLProtocol. The service owns task eligibility and stale-result checks; this harness
/// makes each endpoint response deterministic without contacting a configured model server.
@Suite(.serialized)
@MainActor
struct LearningExpressionServiceTests {
    @Test(arguments: ["translategemma:4b", "hy-mt2:7b", "learning-instruction-model"])
    func specialistEndpointUsesItsOwnPromptAndSampling(_ model: String) async throws {
        let harness = try makeHarness(translationEnabled: true, reply: instructionResponse("Hello."))
        defer { harness.cleanUp() }
        harness.settings.languageLearning.translation.endpointModel = model
        let text = try await harness.service.translateSentence(source: "你好", sourceLanguage: .chinese, targetLanguage: .english)
        #expect(text == "Hello.")
        let request = await harness.exchange.waitForRequest()
        let data = try #require(request.body)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        let family = LearningTranslationPrompt.Family(endpointModel: model)
        let expected = try LearningTranslationPrompt.render(source: "你好", sourceLanguage: .chinese,
            targetLanguage: .english, family: family)
        #expect(messages.count == (expected.userOnly ? 1 : 2))
        #expect(messages.last?["role"] == "user")
        #expect(messages.last?["content"] == expected.prompt)
        #expect(body["temperature"] as? Double == expected.sampling.temperature)
        #expect(body["top_p"] as? Double == expected.sampling.topP)
        #expect(harness.exchange.requestCount == 1)
    }

    @Test
    func disabledAnalysisUsesOneTranslationRequestAndKeepsTranslationWhenAnalysisSettingsChange() async throws {
        let harness = try makeHarness(translationEnabled: true, holdResponse: true)
        defer { harness.cleanUp() }
        let operation = Task { try await harness.service.generateSentence(source: "我能做到",
            sourceLanguage: .chinese, targetLanguage: .english) { _ in } }
        _ = await harness.exchange.waitForRequest()
        harness.settings.languageLearning.analysis.endpointModel = "different-analyst"
        harness.settings.languageLearning.analysis.saveAPIKey("analysis-key")
        harness.settings.setOpenAICompatibleBaseURL("https://completion.invalid/v1")
        harness.exchange.release(with: try instructionResponse("I can do it."))
        let result = try await operation.value
        #expect(result.translation == "I can do it.")
        #expect(result.chunks.isEmpty)
        #expect(harness.exchange.requestCount == 1)
    }

    @Test
    func connectSubmitsDraftKeyAndKeepsDiscoverySeparateFromRuntime() async throws {
        let catalog = LearningExpressionServiceReply(statusCode: 200,
            body: Data(#"{"data":[{"id":"test-model"}]}"#.utf8))
        let failure = LearningExpressionServiceReply(statusCode: 500, body: Data())
        let harness = try makeHarness(reply: catalog, analysisReply: failure)
        defer { harness.cleanUp() }
        let controller = harness.service.models.translation
        // Discovery is available even when the task uses a local model.
        controller.profile.backend = .local
        await controller.connect(using: "draft-test-key")
        let request = await harness.exchange.waitForRequest()
        #expect(request.headers["Authorization"] == "Bearer draft-test-key")
        #expect(request.method == "GET")
        #expect(request.url?.path == "/v1/models")
        #expect(controller.endpointConnection.models.map(\.id) == ["test-model"])
        #expect(controller.status == "未加载")
        controller.profile.endpointModel = "custom-identifier"
        #expect(controller.endpointConnection.models.count == 1)
        await controller.discoverEndpoint()
        #expect(controller.endpointConnection.models.isEmpty)
        #expect(controller.endpointConnection.state.failureDetail != nil)
    }

    @Test(arguments: ["url", "key"])
    func endpointIdentityChangeRejectsLateDiscovery(_ change: String) async throws {
        let harness = try makeHarness(holdResponse: true)
        defer { harness.cleanUp() }
        let controller = harness.service.models.translation
        let discovery = Task { await controller.discoverEndpoint() }
        _ = await harness.exchange.waitForRequest()
        if change == "url" { controller.profile.baseURL = "https://new.invalid/v1" }
        else { controller.profile.saveAPIKey("new-key") }
        #expect(controller.endpointConnection.models.isEmpty)
        #expect(controller.endpointConnection.state == .idle)
        harness.exchange.release(with: .init(statusCode: 200,
            body: Data(#"{"data":[{"id":"obsolete-model"}]}"#.utf8)))
        await discovery.value
        #expect(controller.endpointConnection.models.isEmpty)
        #expect(controller.endpointConnection.state == .idle)
    }

    @Test
    func inactiveBatteryAndManualChoicesDoNotCancelActiveEndpointWork() async throws {
        let harness = try makeHarness(translationEnabled: true, holdResponse: true)
        defer { harness.cleanUp() }
        let profile = harness.settings.languageLearning.translation
        profile.setPowerSwitchingEnabled(true)
        let operation = Task { try await harness.service.translateSentence(source: "我能做到",
            sourceLanguage: .chinese, targetLanguage: .english) }
        _ = await harness.exchange.waitForRequest()
        profile.batteryProfile = .local("future-battery.gguf")
        profile.endpointModel = "future-manual-endpoint"
        profile.localModel = "future-manual.gguf"
        harness.exchange.release(with: try instructionResponse("I can do it."))
        #expect(try await operation.value == "I can do it.")
    }

    @Test(arguments: [false, true])
    func realTransportRecordsValidatedStageOutcomesWithOneSentenceID(_ malformed: Bool) async throws {
        let harness = try makeHarness(translationEnabled: true, analysisEnabled: true, trackingEnabled: true,
            reply: instructionResponse("I can do it."), analysisReply: sentenceReply(malformed: malformed))
        defer { harness.cleanUp() }
        do {
            _ = try await harness.service.generateSentence(source: "我能做到", sourceLanguage: .chinese,
                targetLanguage: .english) { _ in }
            #expect(!malformed)
        } catch { #expect(malformed) }
        let rows = harness.metrics.entries
        #expect(rows.count == 2)
        #expect(rows.map(\.source) == [.translation, .analysis])
        #expect(rows.map(\.outcome) == [.completed, malformed ? .failed : .completed])
        #expect(rows[0].requestID == rows[1].requestID)
        #expect(rows[0].requestID?.hasPrefix("req_") == true)
        #expect(rows.allSatisfy { $0.firstOutputMs != nil })
        #expect(rows[0].usableResultMs != nil)
        #expect((rows[1].usableResultMs == nil) == malformed)
        let data = try #require(harness.defaults.data(forKey: "cotabbyPerformanceMetricEntries"))
        #expect(!String(decoding: data, as: UTF8.self).contains("我能做到"))
    }

    @Test
    func incompleteTranslationRetainsFirstOutputButNeverBecomesUsable() async throws {
        let harness = try makeHarness(translationEnabled: true, trackingEnabled: true,
            reply: instructionResponse("partial text", finishReason: "length"))
        defer { harness.cleanUp() }
        do {
            _ = try await harness.service.translateSentence(source: "我能做到", sourceLanguage: .chinese, targetLanguage: .english)
            Issue.record("Incomplete output must be rejected")
        } catch { #expect(error is OpenAICompatibleClientError) }
        let row = try #require(harness.metrics.entries.first)
        #expect(row.outcome == .failed)
        #expect(row.firstOutputMs != nil && row.usableResultMs == nil && row.displayMs == nil)
    }

    @Test
    func transportRespectsTheExistingDefaultOffTrackingSetting() async throws {
        let harness = try makeHarness(translationEnabled: true)
        defer { harness.cleanUp() }
        _ = try await harness.service.translateSentence(source: "我能做到", sourceLanguage: .chinese, targetLanguage: .english)
        #expect(harness.metrics.entries.isEmpty)
    }

    @Test
    func eachStageUsesItsOwnModelAndCredential() async throws {
        let harness = try makeHarness(translationEnabled: true, analysisEnabled: true,
            reply: instructionResponse("I can do it."), analysisReply: sentenceReply(malformed: false))
        defer { harness.cleanUp() }
        harness.settings.languageLearning.translation.saveAPIKey("translation-key")
        harness.settings.languageLearning.analysis.saveAPIKey("analysis-key")
        let result = try await harness.service.generateSentence(source: "我能做到", sourceLanguage: .chinese,
            targetLanguage: .english) { _ in }
        #expect(result.chunks.count == 3)
        let translationRequest = await harness.exchange.waitForRequest()
        let analysisRequest = await harness.exchange.waitForRequest(index: 1)
        #expect(translationRequest.headers["Authorization"] == "Bearer translation-key")
        #expect(analysisRequest.headers["Authorization"] == "Bearer analysis-key")
        let translationData = try #require(translationRequest.body)
        let analysisData = try #require(analysisRequest.body)
        let translationBody = try #require(JSONSerialization.jsonObject(with: translationData) as? [String: Any])
        let analysisBody = try #require(JSONSerialization.jsonObject(with: analysisData) as? [String: Any])
        #expect(translationBody["model"] as? String == "learning-instruction-model")
        #expect(analysisBody["model"] as? String == "analysis-instruction-model")
    }
    @Test(arguments: [false, true])
    func sentenceStreamPreservesTranslationWhenLaterAnalysisIsMalformed(_ malformed: Bool) async throws {
        let harness = try makeHarness(translationEnabled: true, analysisEnabled: true,
            reply: instructionResponse("I can do it."), analysisReply: sentenceReply(malformed: malformed))
        defer { harness.cleanUp() }
        var updates: [LearningSentenceUpdate] = []
        do {
            let result = try await harness.service.generateSentence(source: "我能做到", sourceLanguage: .chinese,
                targetLanguage: .english) { updates.append($0) }
            #expect(!malformed)
            #expect(result.translation == "I can do it.")
            #expect(result.chunks.count == 3)
        } catch {
            #expect(malformed)
        }
        #expect(updates.first == .translation("I can do it."))
        #expect(updates.count == (malformed ? 1 : 2))
        if !malformed, case .chunks(let chunks) = updates.last { #expect(chunks.count == 3) }
        else if !malformed { Issue.record("Alignment must publish one complete batch") }
        let prompt = try instructionPrompt(from: await harness.exchange.waitForRequest())
        let expectedPrompt = try LearningExpressionPrompt.translation(source: "我能做到", sourceLanguage: .chinese, targetLanguage: .english)
        let analysisPrompt = try instructionPrompt(from: await harness.exchange.waitForRequest(index: 1))
        let expectedAnalysis = try LearningAnalysisPrompt.render(source: "我能做到", translation: "I can do it.",
            sourceLanguage: .chinese, targetLanguage: .english)
        #expect(analysisPrompt == expectedAnalysis)
        #expect(harness.exchange.requestCount == 2)
        #expect(prompt == expectedPrompt)
        #expect(!prompt.contains("CLIPBOARD_SECRET"))
        #expect(!prompt.contains("HISTORY_SECRET"))
    }

    @Test
    func changedLearningModelRejectsEveryBufferedSentenceUpdate() async throws {
        let harness = try makeHarness(translationEnabled: true, holdResponse: true)
        defer { harness.cleanUp() }
        var updates: [LearningSentenceUpdate] = []
        let operation = Task {
            try await harness.service.generateSentence(source: "我能做到", sourceLanguage: .chinese,
                targetLanguage: .english) { updates.append($0) }
        }
        _ = await harness.exchange.waitForRequest()
        harness.settings.languageLearning.model = "new-learning-model"
        harness.exchange.release(with: try sentenceReply(malformed: false))
        do {
            _ = try await operation.value
            Issue.record("A response from the previous model must not reach the display")
        } catch { #expect(error is CancellationError) }
        #expect(updates.isEmpty)
    }

    private func sentenceReply(malformed: Bool) throws -> LearningExpressionServiceReply {
        let chunk = malformed ? #"[["能","can"],{"broken":true}]"# :
            #"[["我","I"],["能","can"],["做到","do it"]]"# + "\n"
        let content = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": chunk]]]])
        let wire = "data: " + String(decoding: content, as: UTF8.self) + "\n\n" +
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        return .init(statusCode: 200, body: Data(wire.utf8))
    }

    @Test
    func oversizedAlignmentDeltaCannotPublishAnyHighlight() async throws {
        let delta = String(repeating: "x", count: 48_001)
        let content = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": delta]]]])
        let wire = "data: " + String(decoding: content, as: UTF8.self) + "\n\n" +
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        let harness = try makeHarness(translationEnabled: true, analysisEnabled: true,
            reply: instructionResponse("I can do it."), analysisReply: .init(statusCode: 200, body: Data(wire.utf8)))
        defer { harness.cleanUp() }
        var updates: [LearningSentenceUpdate] = []
        do {
            _ = try await harness.service.generateSentence(source: "我能做到", sourceLanguage: .chinese,
                targetLanguage: .english) { updates.append($0) }
            Issue.record("Oversized alignment must be rejected")
        } catch {
            #expect(updates == [.translation("I can do it.")])
        }
    }

    @Test
    func disabledTranslationCancelsBeforeSending() async throws {
        let translationHarness = try makeHarness()
        defer { translationHarness.cleanUp() }
        await expectCancellationWithoutRequest(
            translationHarness,
            task: .translation(source: .chinese, target: .english),
            source: "我今天会晚到。"
        )

    }

    @Test
    func legacyVocabularyPreferencesCannotEnableTranslation() async throws {
        let harness = try makeHarness(legacyVocabularyEnabled: true)
        defer { harness.cleanUp() }

        await expectCancellationWithoutRequest(
            harness,
            task: .translation(source: .chinese, target: .english),
            source: "我明天会联系你。"
        )
        #expect(harness.defaults.bool(forKey: "learningVocabularyEnabled"))
        #expect(harness.defaults.bool(forKey: "learningTranslationVocabularyEnabled"))
    }

    @Test
    func translationUsesOnlyTheExplicitSourceWithoutClaimingInputMethodCommitEvidence() async throws {
        let source = "我明天会联系你。"
        let harness = try makeHarness(translationEnabled: true, legacyVocabularyEnabled: true)
        defer { harness.cleanUp() }

        let result = try await harness.service.generate(
            source: source,
            task: .translation(source: .chinese, target: .english)
        )
        let request = await harness.exchange.waitForRequest()
        let prompt = try instructionPrompt(from: request)

        #expect(result == "We can meet tomorrow.")
        let expectedPrompt = try LearningExpressionPrompt.translation(source: source)
        #expect(prompt == expectedPrompt)
        #expect(prompt.contains("Translate the following Chinese text into natural English."))
        #expect(!prompt.contains("committed"))
        #expect(!prompt.contains("Prefer these words"))
        #expect(!prompt.contains("apple banana"))
    }

    @Test
    func rejectsUnsupportedLanguageDirectionBeforeHttp() async throws {
        let harness = try makeHarness(
            translationEnabled: true,
            sourceLanguages: [.chinese],
            targetLanguage: .english
        )
        defer { harness.cleanUp() }

        do {
            _ = try await harness.service.generate(
                source: "The meeting is today.",
                task: .translation(source: .english, target: .chinese)
            )
            Issue.record("A source language outside the configured set must not reach the endpoint.")
        } catch let failure as LearningFailure {
            #expect(failure.errorDescription?.contains("源语言") == true)
        }
        #expect(harness.exchange.requestCount == 0)
    }

    @Test
    func sourceBudgetRejectsWholeInputBeforeHttp() async throws {
        let translationHarness = try makeHarness(translationEnabled: true)
        defer { translationHarness.cleanUp() }
        do {
            _ = try await translationHarness.service.generate(
                source: String(repeating: "我", count: 2_001),
                task: .translation(source: .chinese, target: .english)
            )
            Issue.record("Source larger than 6 KB must be rejected before transmission.")
        } catch let failure as LearningFailure {
            #expect(failure.errorDescription?.contains("6 KB") == true)
        }
        #expect(translationHarness.exchange.requestCount == 0)

    }

    @Test
    func alreadyCancelledTaskDoesNotReachTheEndpoint() async throws {
        let harness = try makeHarness(translationEnabled: true)
        defer { harness.cleanUp() }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await harness.service.generate(
                source: "我明天会联系你。",
                task: .translation(source: .chinese, target: .english)
            )
        }

        do {
            _ = try await task.value
            Issue.record("A task cancelled at service entry must not generate a response.")
        } catch is CancellationError {
            #expect(harness.exchange.requestCount == 0)
        }
    }

    @Test(arguments: StaleLearningChange.allCases)
    func rejectsLateResponseAfterSettingsOrGlobalAvailabilityChanges(_ change: StaleLearningChange) async throws {
        let harness = try makeHarness(translationEnabled: true, holdResponse: true)
        defer { harness.cleanUp() }
        let task = Task { @MainActor in
            try await harness.service.generate(
                source: "我明天会联系你。",
                task: .translation(source: .chinese, target: .english)
            )
        }

        _ = await harness.exchange.waitForRequest()
        switch change {
        case .learningSettings:
            harness.settings.languageLearning.targetLanguage = .spanish
        case .model:
            harness.settings.languageLearning.model = "replacement-instruction-model"
        case .endpoint:
            harness.settings.languageLearning.translation.baseURL = "https://replacement.learning.invalid/v1"
        case .credential:
            harness.settings.languageLearning.translation.saveAPIKey("replacement-secret")
        case .globalOptOut:
            harness.settings.setGloballyEnabled(false)
        case .temporaryPause:
            harness.settings.pauseSuggestions(for: .indefinitely)
        }
        harness.exchange.release(with: try instructionResponse("We will contact you tomorrow."))

        do {
            _ = try await task.value
            Issue.record("A response produced under an obsolete setting or app state must be discarded.")
        } catch is CancellationError {
            #expect(harness.exchange.requestCount == 1)
        }
    }

    private func expectCancellationWithoutRequest(
        _ harness: LearningExpressionServiceHarness,
        task: LearningExpressionTask,
        source: String
    ) async {
        do {
            _ = try await harness.service.generate(source: source, task: task)
            Issue.record("A disabled learning task must cancel before HTTP.")
        } catch is CancellationError {
            #expect(harness.exchange.requestCount == 0)
        } catch {
            Issue.record("Expected pre-request cancellation, received \(error).")
        }
    }

    private func makeHarness(
        translationEnabled: Bool = false,
        analysisEnabled: Bool = false,
        sourceLanguages: [LearningLanguage] = [.chinese],
        targetLanguage: LearningLanguage = .english,
        legacyVocabularyEnabled: Bool = false,
        holdResponse: Bool = false,
        trackingEnabled: Bool = false,
        reply: LearningExpressionServiceReply = .translation,
        analysisReply: LearningExpressionServiceReply? = nil
    ) throws -> LearningExpressionServiceHarness {
        let suiteName = "cotabby.test.learningExpressionService.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        if legacyVocabularyEnabled {
            defaults.set(true, forKey: "learningVocabularyEnabled")
            defaults.set(true, forKey: "learningTranslationVocabularyEnabled")
            defaults.set("apple banana", forKey: "learningVocabulary")
        }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.setGloballyEnabled(true)
        settings.setPerformanceTrackingEnabled(trackingEnabled)
        settings.languageLearning.translationEnabled = translationEnabled
        settings.languageLearning.analysisEnabled = analysisEnabled
        settings.languageLearning.model = "learning-instruction-model"
        settings.languageLearning.sourceLanguages = sourceLanguages
        settings.languageLearning.targetLanguage = targetLanguage

        let host = "\(UUID().uuidString.lowercased()).learning.invalid"
        settings.setOpenAICompatibleBaseURL("https://\(host)/v1")
        settings.languageLearning.translation.baseURL = "https://\(host)/v1"
        settings.setOpenAICompatibleModelName("completion-model")
        settings.languageLearning.analysis.backend = .endpoint
        settings.languageLearning.analysis.baseURL = "https://\(host)/v1"
        settings.languageLearning.analysis.endpointModel = "analysis-instruction-model"

        let exchange = LearningExpressionServiceExchange(automaticReply: holdResponse ? nil : reply, analysisReply: analysisReply)
        LearningExpressionServiceStubRegistry.register(exchange, for: host)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LearningExpressionServiceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAICompatibleAPIClient(session: session)
        let metrics = PerformanceMetricsStore(userDefaults: defaults)
        let service = LearningExpressionService(settings: settings, client: client,
            telemetry: LearningRequestTelemetry(metrics: metrics,
                trackingEnabled: { settings.isPerformanceTrackingEnabled }))

        return LearningExpressionServiceHarness(
            settings: settings,
            service: service,
            metrics: metrics,
            exchange: exchange,
            session: session,
            defaults: defaults,
            suiteName: suiteName,
            host: host
        )
    }

    private func instructionPrompt(from request: CapturedLearningHTTPRequest) throws -> String {
        let data = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        return try #require(messages.last?["content"] as? String)
    }

    private func instructionResponse(_ content: String, finishReason: String = "stop") throws -> LearningExpressionServiceReply {
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["finish_reason": finishReason, "message": ["content": content]]]
        ])
        return LearningExpressionServiceReply(statusCode: 200, body: body)
    }
}

enum StaleLearningChange: String, CaseIterable, CustomStringConvertible, Sendable {
    case learningSettings
    case model
    case endpoint
    case credential
    case globalOptOut
    case temporaryPause

    var description: String { rawValue }
}

/// Each harness keeps its private preferences, endpoint session, and response exchange together.
/// Cleanup removes only that test's URLProtocol registration and suite.
@MainActor
private struct LearningExpressionServiceHarness {
    let settings: SuggestionSettingsModel
    let service: LearningExpressionService
    let metrics: PerformanceMetricsStore
    let exchange: LearningExpressionServiceExchange
    let session: URLSession
    let defaults: UserDefaults
    let suiteName: String
    let host: String

    func cleanUp() {
        LearningExpressionServiceStubRegistry.unregister(host: host)
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct CapturedLearningHTTPRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?
}

private struct LearningExpressionServiceReply {
    let statusCode: Int
    let body: Data

    static let translation = LearningExpressionServiceReply(
        statusCode: 200,
        body: Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"  We can meet tomorrow.  "}}]}"#.utf8)
    )

}

/// A lock protects request/continuation handoff because URLProtocol callbacks run away from the
/// main actor. The test controls when a held response is released to make each stale guard exact.
nonisolated private final class LearningExpressionServiceExchange: @unchecked Sendable {
    private let lock = NSLock()
    private let automaticReply: LearningExpressionServiceReply?
    private let analysisReply: LearningExpressionServiceReply?
    private var requests: [CapturedLearningHTTPRequest] = []
    private var pendingReply: LearningExpressionServiceReply?
    private var capturedRequest: CapturedLearningHTTPRequest?
    private var observedRequestCount = 0
    private var requestWaiters: [Int: CheckedContinuation<CapturedLearningHTTPRequest, Never>] = [:]
    private var activeProtocol: LearningExpressionServiceURLProtocol?
    private var hasDeliveredReply = false

    init(automaticReply: LearningExpressionServiceReply?, analysisReply: LearningExpressionServiceReply?) {
        self.automaticReply = automaticReply
        self.analysisReply = analysisReply
        pendingReply = automaticReply
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observedRequestCount
    }

    func waitForRequest(index: Int = 0) async -> CapturedLearningHTTPRequest {
        await withCheckedContinuation { continuation in
            lock.lock()
            if requests.indices.contains(index) {
                let request = requests[index]
                lock.unlock()
                continuation.resume(returning: request)
            } else {
                requestWaiters[index] = continuation
                lock.unlock()
            }
        }
    }

    func attach(
        protocolInstance: LearningExpressionServiceURLProtocol,
        request: CapturedLearningHTTPRequest
    ) {
        lock.lock()
        observedRequestCount += 1
        capturedRequest = request
        activeProtocol = protocolInstance
        let index = requests.count
        requests.append(request)
        let waiter = requestWaiters.removeValue(forKey: index)
        let reply = index == 0 ? pendingReply : analysisReply
        let shouldDeliver = reply != nil && (index > 0 || !hasDeliveredReply)
        if shouldDeliver { hasDeliveredReply = true }
        lock.unlock()

        waiter?.resume(returning: request)
        if let reply, shouldDeliver {
            deliver(reply, to: protocolInstance, for: request)
        }
    }

    func release(with reply: LearningExpressionServiceReply) {
        lock.lock()
        pendingReply = reply
        let protocolInstance = activeProtocol
        let request = capturedRequest
        let shouldDeliver = protocolInstance != nil && request != nil && !hasDeliveredReply
        if shouldDeliver { hasDeliveredReply = true }
        lock.unlock()

        if shouldDeliver, let protocolInstance, let request {
            deliver(reply, to: protocolInstance, for: request)
        }
    }

    func stop(_ protocolInstance: LearningExpressionServiceURLProtocol) {
        lock.lock()
        if activeProtocol === protocolInstance { activeProtocol = nil }
        lock.unlock()
    }

    private func deliver(
        _ reply: LearningExpressionServiceReply,
        to protocolInstance: LearningExpressionServiceURLProtocol,
        for request: CapturedLearningHTTPRequest
    ) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: reply.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            protocolInstance.client?.urlProtocol(protocolInstance, didFailWithError: URLError(.badServerResponse))
            return
        }
        protocolInstance.client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
        protocolInstance.client?.urlProtocol(protocolInstance, didLoad: reply.body)
        protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
    }
}

/// URLProtocol can consult this registry on a URLSession callback queue. Each test uses a distinct
/// synthetic host, and the lock protects only registration and lookup rather than model work.
nonisolated private enum LearningExpressionServiceStubRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var exchanges: [String: LearningExpressionServiceExchange] = [:]

    static func register(_ exchange: LearningExpressionServiceExchange, for host: String) {
        lock.lock()
        exchanges[host] = exchange
        lock.unlock()
    }

    static func exchange(for host: String) -> LearningExpressionServiceExchange? {
        lock.lock()
        defer { lock.unlock() }
        return exchanges[host]
    }

    static func unregister(host: String) {
        lock.lock()
        exchanges.removeValue(forKey: host)
        lock.unlock()
    }
}

/// Captures the request and routes it to the matching per-test exchange; it never opens a socket.
nonisolated private final class LearningExpressionServiceURLProtocol: URLProtocol {
    private var exchange: LearningExpressionServiceExchange?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".learning.invalid") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
              let exchange = LearningExpressionServiceStubRegistry.exchange(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        self.exchange = exchange
        exchange.attach(protocolInstance: self, request: Self.capture(request))
    }

    override func stopLoading() {
        exchange?.stop(self)
    }

    private static func capture(_ request: URLRequest) -> CapturedLearningHTTPRequest {
        CapturedLearningHTTPRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: bodyData(from: request)
        )
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
