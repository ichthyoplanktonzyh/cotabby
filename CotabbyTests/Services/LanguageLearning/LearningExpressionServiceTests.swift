import Foundation
import Testing
@testable import Cotabby

/// Exercises the request and cancellation boundary using the production API client with an
/// in-process URLProtocol. The service owns task eligibility and stale-result checks; this harness
/// makes each endpoint response deterministic without contacting a configured model server.
@Suite(.serialized)
@MainActor
struct LearningExpressionServiceTests {
    @Test(arguments: [false, true])
    func sentenceStreamPreservesTranslationWhenLaterAnalysisIsMalformed(_ malformed: Bool) async throws {
        let harness = try makeHarness(translationEnabled: true, reply: sentenceReply(malformed: malformed))
        defer { harness.cleanUp() }
        var updates: [LearningSentenceUpdate] = []
        do {
            let result = try await harness.service.generateSentence(source: "我能做到", sourceLanguage: .chinese,
                targetLanguage: .english) { updates.append($0) }
            #expect(!malformed)
            #expect(result.translation == "I can do it.")
            #expect(result.chunks.count == 1)
        } catch {
            #expect(malformed)
        }
        #expect(updates.first == .translation("I can do it."))
        #expect(updates.count == (malformed ? 1 : 2))
        let prompt = try instructionPrompt(from: await harness.exchange.waitForRequest())
        let expectedPrompt = try LearningSentencePrompt.render(source: "我能做到", sourceLanguage: .chinese, targetLanguage: .english)
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
        let translation = #"{"type":"translation","text":"I can do it."}"# + "\n"
        let chunk = malformed ? "invalid analysis\n" :
            #"{"type":"chunk","source":["能"],"target":["can"],"explanation":"能力"}"# + "\n"
        let content = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": translation + chunk]]]])
        let wire = "data: " + String(decoding: content, as: UTF8.self) + "\n\n" +
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        return .init(statusCode: 200, body: Data(wire.utf8))
    }

    @Test
    func disabledTranslationAndHintTasksCancelBeforeSending() async throws {
        let translationHarness = try makeHarness()
        defer { translationHarness.cleanUp() }
        await expectCancellationWithoutRequest(
            translationHarness,
            task: .translation(source: .chinese, target: .english),
            source: "我今天会晚到。"
        )

        let hintHarness = try makeHarness(translationEnabled: true)
        defer { hintHarness.cleanUp() }
        await expectCancellationWithoutRequest(
            hintHarness,
            task: .hint(source: .english, target: .chinese),
            source: "schedule"
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
    func hintUsesTheOriginalPromptAndOnlyTheRequestedWord() async throws {
        let source = "schedule"
        let harness = try makeHarness(
            translationEnabled: true,
            hintsEnabled: true,
            sourceLanguages: [.english],
            targetLanguage: .chinese,
            reply: .hint
        )
        defer { harness.cleanUp() }

        let result = try await harness.service.generate(
            source: source,
            task: .hint(source: .english, target: .chinese)
        )
        let prompt = try instructionPrompt(from: await harness.exchange.waitForRequest())

        #expect(result == #"{"expression":"日程","explanation":"安排活动的计划。"}"#)
        let expectedPrompt = try LearningExpressionPrompt.hint(
            source: source,
            sourceLanguage: .english,
            targetLanguage: .chinese
        )
        #expect(prompt == expectedPrompt)
        #expect(prompt.contains("natural Simplified Chinese equivalent"))
        #expect(prompt.contains("schedule"))
        #expect(!prompt.contains("CLIPBOARD_SECRET"))
        #expect(!prompt.contains("HISTORY_SECRET"))
        #expect(harness.exchange.requestCount == 1)
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
    func sourceAndHintBudgetsRejectWholeInputBeforeHttp() async throws {
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

        let hintHarness = try makeHarness(
            translationEnabled: true,
            hintsEnabled: true,
            sourceLanguages: [.english],
            targetLanguage: .chinese
        )
        defer { hintHarness.cleanUp() }
        do {
            _ = try await hintHarness.service.generate(
                source: String(repeating: "x", count: 161),
                task: .hint(source: .english, target: .chinese)
            )
            Issue.record("A hint source above its 160-byte budget must not be sent.")
        } catch let failure as LearningFailure {
            #expect(failure.errorDescription?.contains("过长") == true)
        }
        #expect(hintHarness.exchange.requestCount == 0)
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
            harness.settings.setOpenAICompatibleBaseURL("https://replacement.learning.invalid/v1")
        case .credential:
            try harness.settings.saveOpenAICompatibleAPIKey("replacement-secret")
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
        hintsEnabled: Bool = false,
        sourceLanguages: [LearningLanguage] = [.chinese],
        targetLanguage: LearningLanguage = .english,
        legacyVocabularyEnabled: Bool = false,
        holdResponse: Bool = false,
        reply: LearningExpressionServiceReply = .translation
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
        settings.languageLearning.translationEnabled = translationEnabled
        settings.languageLearning.hintsEnabled = hintsEnabled
        settings.languageLearning.model = "learning-instruction-model"
        settings.languageLearning.sourceLanguages = sourceLanguages
        settings.languageLearning.targetLanguage = targetLanguage

        let host = "\(UUID().uuidString.lowercased()).learning.invalid"
        settings.setOpenAICompatibleBaseURL("https://\(host)/v1")
        settings.setOpenAICompatibleModelName("completion-model")

        let exchange = LearningExpressionServiceExchange(automaticReply: holdResponse ? nil : reply)
        LearningExpressionServiceStubRegistry.register(exchange, for: host)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LearningExpressionServiceURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAICompatibleAPIClient(session: session)
        let service = LearningExpressionService(settings: settings, client: client)

        return LearningExpressionServiceHarness(
            settings: settings,
            service: service,
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

    private func instructionResponse(_ content: String) throws -> LearningExpressionServiceReply {
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["finish_reason": "stop", "message": ["content": content]]]
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
    static let hint = LearningExpressionServiceReply(
        statusCode: 200,
        body: Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"{\"expression\":\"日程\",\"explanation\":\"安排活动的计划。\"}"}}]}"#.utf8)
    )
}

/// A lock protects request/continuation handoff because URLProtocol callbacks run away from the
/// main actor. The test controls when a held response is released to make each stale guard exact.
nonisolated private final class LearningExpressionServiceExchange: @unchecked Sendable {
    private let lock = NSLock()
    private let automaticReply: LearningExpressionServiceReply?
    private var pendingReply: LearningExpressionServiceReply?
    private var capturedRequest: CapturedLearningHTTPRequest?
    private var observedRequestCount = 0
    private var requestWaiter: CheckedContinuation<CapturedLearningHTTPRequest, Never>?
    private var activeProtocol: LearningExpressionServiceURLProtocol?
    private var hasDeliveredReply = false

    init(automaticReply: LearningExpressionServiceReply?) {
        self.automaticReply = automaticReply
        pendingReply = automaticReply
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observedRequestCount
    }

    func waitForRequest() async -> CapturedLearningHTTPRequest {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let capturedRequest {
                lock.unlock()
                continuation.resume(returning: capturedRequest)
            } else {
                requestWaiter = continuation
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
        let waiter = requestWaiter
        requestWaiter = nil
        let reply = pendingReply
        let shouldDeliver = reply != nil && !hasDeliveredReply
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
