import Foundation

// The shared sentence-model file also declares a UI-service protocol that names this app type.
// The CLI never instantiates that service or settings: this nominal declaration lets the exact
// production value types compile without importing the app lifecycle or reading UserDefaults.
@MainActor
final class SuggestionSettingsModel {}

/// A self-authored fixture enters only the production prompt renderer; reviewer expectations
/// remain in Python's corpus and are deliberately absent from this wire-facing value.
private struct EvalCase: Codable, Sendable {
    let id: String
    let category: String
    let sourceLanguage: LearningLanguage
    let targetLanguage: LearningLanguage
    let source: String
}

private struct EvalJob: Decodable {
    let mode: String
    let model: String
    let baseURL: String
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    let cases: [EvalCase]
}

private struct TimedDelta: Codable {
    let milliseconds: Double
    let text: String
}

private struct Replay: Decodable {
    let example: EvalCase
    let deltas: [TimedDelta]
    let finishReason: String
    let mode: String?
}

private struct Span: Codable {
    let location: Int
    let length: Int
    init(_ range: NSRange) { location = range.location; length = range.length }
}

/// Serializable evidence preserves resolved UTF-16 ranges and quotes for independent review.
/// Neither these structural checks nor the coverage calculation judges semantic correctness.
private struct EvalChunk: Codable {
    let source: [String]
    let target: [String]
    let sourceRanges: [Span]
    let targetRanges: [Span]
    let explanation: String
}

private struct EvalResult: Codable {
    let id: String
    let category: String
    let sourceLanguage: LearningLanguage
    let targetLanguage: LearningLanguage
    let source: String
    var mode: String
    var prompt: String
    var rawOutput = ""
    var translation: String?
    var firstContentMilliseconds: Double?
    var translationAcceptedMilliseconds: Double?
    var firstChunkMilliseconds: Double?
    var completionMilliseconds: Double?
    var protocolSucceeded = false
    var finishVerified = false
    var failure: String?
    var parserStoppedMilliseconds: Double?
    var chunks: [EvalChunk] = []
    var sourceLetterCoverage: Double?
    var targetLetterCoverage: Double?
    var deltas: [TimedDelta] = []

    init(_ example: EvalCase, mode: String, prompt: String) {
        id = example.id; category = example.category; source = example.source
        sourceLanguage = example.sourceLanguage; targetLanguage = example.targetLanguage
        self.mode = mode; self.prompt = prompt
    }
}

/// One result collector lives for one HTTP request on MainActor, matching the app transport's
/// callback isolation. It uses the production parser, including preserved-prefix behavior when
/// a packet contains both a valid translation and malformed later analysis.
@MainActor
private final class Collector {
    var result: EvalResult
    private var parser: LearningSentenceStreamParser
    private let isJoint: Bool
    private let capturesAfterParserFailure: Bool

    init(_ example: EvalCase, mode: String, prompt: String) {
        result = EvalResult(example, mode: mode, prompt: prompt)
        parser = LearningSentenceStreamParser(source: example.source)
        isJoint = mode.hasPrefix("joint")
        capturesAfterParserFailure = mode == "joint-forensic"
    }

    func append(_ text: String, at milliseconds: Double) throws {
        if result.firstContentMilliseconds == nil { result.firstContentMilliseconds = milliseconds }
        result.rawOutput += text
        result.deltas.append(.init(milliseconds: milliseconds, text: text))
        guard result.rawOutput.utf8.count <= 96_000 else { throw LearningFailure.message("Eval output exceeded 96 KB") }
        guard isJoint else { return }
        if result.parserStoppedMilliseconds != nil { return }
        defer { publish(at: milliseconds) }
        do { _ = try parser.append(text) } catch {
            guard capturesAfterParserFailure else { throw error }
            // Diagnostic runs capture the rest of the answer for semantic review, but never
            // repair the parser or call that later content usable in the production UI.
            result.parserStoppedMilliseconds = milliseconds
            result.failure = error.localizedDescription
        }
    }

    func finish(at milliseconds: Double) throws {
        result.finishVerified = true
        result.completionMilliseconds = milliseconds
        if result.parserStoppedMilliseconds != nil { return }
        if isJoint {
            defer { publish(at: milliseconds) }
            do {
                _ = try parser.finish()
                _ = try parser.result()
            } catch {
                guard capturesAfterParserFailure else { throw error }
                result.parserStoppedMilliseconds = milliseconds
                result.failure = error.localizedDescription
                return
            }
        } else {
            result.translation = try LearningExpressionOutputPolicy.validatedText(result.rawOutput)
            result.translationAcceptedMilliseconds = milliseconds
        }
        result.protocolSucceeded = true
    }

    private func publish(at milliseconds: Double) {
        if result.translation == nil, let text = parser.translation {
            result.translation = text
            result.translationAcceptedMilliseconds = milliseconds
        }
        if result.firstChunkMilliseconds == nil, !parser.chunks.isEmpty {
            result.firstChunkMilliseconds = milliseconds
        }
        let target = parser.translation ?? ""
        result.chunks = parser.chunks.map { chunk in
            EvalChunk(source: quotes(chunk.sourceRanges, in: result.source), target: quotes(chunk.targetRanges, in: target),
                sourceRanges: chunk.sourceRanges.map(Span.init), targetRanges: chunk.targetRanges.map(Span.init),
                explanation: chunk.explanation)
        }
        result.sourceLetterCoverage = coverage(result.source, ranges: parser.chunks.flatMap(\.sourceRanges))
        if !target.isEmpty { result.targetLetterCoverage = coverage(target, ranges: parser.chunks.flatMap(\.targetRanges)) }
    }

    private func quotes(_ ranges: [NSRange], in text: String) -> [String] {
        ranges.map { (text as NSString).substring(with: $0) }
    }

    private func coverage(_ text: String, ranges: [NSRange]) -> Double? {
        let included = Set(ranges.flatMap { $0.location..<NSMaxRange($0) })
        var offset = 0
        var total = 0
        var mapped = 0
        for scalar in text.unicodeScalars {
            let length = scalar.utf16.count
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                total += 1
                if (offset..<(offset + length)).allSatisfy({ included.contains($0) }) { mapped += 1 }
            }
            offset += length
        }
        return total == 0 ? nil : Double(mapped) / Double(total)
    }
}

/// This immutable delegate refuses every redirect before it can transmit fixture text to a
/// different destination. The CLI separately accepts only numeric loopback endpoint addresses.
private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@main
private struct LearningEvalBridge {
    @MainActor
    static func main() async {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard input.count <= 2_000_000 else { throw LearningFailure.message("Eval input exceeds 2 MB") }
            let command = CommandLine.arguments.dropFirst().first ?? "run"
            if command == "replay" { try replay(input); return }
            let job = try JSONDecoder().decode(EvalJob.self, from: input)
            guard ["plain", "joint", "joint-forensic", "hy-official"].contains(job.mode), !job.cases.isEmpty,
                  job.cases.count <= 500 else { throw LearningFailure.message("Invalid eval job") }
            if command == "prompts" {
                for example in job.cases { try emit(EvalResult(example, mode: job.mode, prompt: prompt(example, mode: job.mode))) }
            } else {
                let configuration = try endpoint(job)
                let sessionConfiguration = URLSessionConfiguration.ephemeral
                sessionConfiguration.httpShouldSetCookies = false
                sessionConfiguration.urlCredentialStorage = nil
                sessionConfiguration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
                sessionConfiguration.timeoutIntervalForResource = 150
                let session = URLSession(configuration: sessionConfiguration, delegate: RejectRedirects(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                // Warm trials share the connection within a batch, as the app's long-lived client
                // does. The delegate retains stricter loopback-only routing for these test fixtures.
                for example in job.cases { try emit(await run(example, job: job, configuration: configuration, session: session)) }
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    @MainActor
    private static func run(_ example: EvalCase, job: EvalJob,
                            configuration: OpenAICompatibleEndpointConfiguration, session: URLSession) async -> EvalResult {
        let promptText: String
        do { promptText = try prompt(example, mode: job.mode) } catch {
            var result = EvalResult(example, mode: job.mode, prompt: "")
            result.failure = error.localizedDescription
            return result
        }
        let collector = Collector(example, mode: job.mode, prompt: promptText)
        let start = ContinuousClock.now
        let elapsed: () -> Double = { milliseconds(start.duration(to: .now)) }
        do {
            if job.mode == "hy-official" {
                try await officialTranslation(session: session, configuration: configuration, prompt: promptText,
                    options: .init(maxPredictionTokens: job.maxTokens, temperature: job.temperature, topP: job.topP)) {
                    try collector.append($0, at: elapsed())
                }
            } else {
                let client = OpenAICompatibleAPIClient(session: session)
                let options = OpenAICompatibleGenerationOptions(maxPredictionTokens: job.maxTokens,
                    temperature: job.temperature, topP: job.topP)
                if job.mode == "plain" {
                    let text = try await client.generateInstruction(configuration: configuration,
                        apiKey: nil, prompt: promptText, options: options)
                    try collector.append(text, at: elapsed())
                } else {
                    try await client.streamInstruction(configuration: configuration, apiKey: nil,
                        prompt: promptText, options: options) { try collector.append($0, at: elapsed()) }
                }
            }
            try collector.finish(at: elapsed())
        } catch {
            collector.result.failure = error.localizedDescription
            collector.result.completionMilliseconds = elapsed()
        }
        return collector.result
    }

    private static func endpoint(_ job: EvalJob) throws -> OpenAICompatibleEndpointConfiguration {
        let configuration = try OpenAICompatibleEndpointConfiguration(baseURLString: job.baseURL,
            modelName: job.model, apiMode: .chatCompletions)
        guard ["127.0.0.1", "::1", "[::1]"].contains(configuration.baseURL.host ?? "") else {
            throw LearningFailure.message("Eval accepts only numeric loopback endpoints")
        }
        return configuration
    }

    private static func prompt(_ example: EvalCase, mode: String) throws -> String {
        if mode.hasPrefix("joint") {
            return try LearningSentencePrompt.render(source: example.source,
                sourceLanguage: example.sourceLanguage, targetLanguage: example.targetLanguage)
        }
        if mode == "hy-official" {
            return "Translate the following text into \(example.targetLanguage == .chinese ? "Chinese" : example.targetLanguage.name). " +
                "Note that you should only output the translated result without any additional explanation:\n" + example.source
        }
        return try LearningExpressionPrompt.translation(source: example.source,
            sourceLanguage: example.sourceLanguage, targetLanguage: example.targetLanguage)
    }

    /// A test-only Hy-MT adapter uses the vendor's user-only translation instruction. It does not
    /// teach the production client a second wire format or change autocomplete's request shape.
    @MainActor
    private static func officialTranslation(session: URLSession, configuration: OpenAICompatibleEndpointConfiguration,
        prompt: String, options: OpenAICompatibleGenerationOptions, onDelta: (String) throws -> Void) async throws {
        var request = URLRequest(url: configuration.apiURL(path: "chat/completions"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": configuration.modelName,
            "messages": [["role": "user", "content": prompt]], "stream": true,
            "max_tokens": options.maxPredictionTokens, "temperature": options.temperature, "top_p": options.topP,
            "reasoning_effort": "none"])
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw OpenAICompatibleClientError.invalidResponse
        }
        var finishReason: String?
        for try await line in bytes.lines {
            try Task.checkCancellation()
            let event = try OpenAICompatibleSSEDecoder.decode(line, mode: .chatCompletions)
            if event == .done { break }
            let payload = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            if let data = payload.data(using: .utf8),
               let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = item["choices"] as? [[String: Any]], let reason = choices.first?["finish_reason"] as? String {
                finishReason = reason
            }
            if case .text(let text) = event { try onDelta(text) }
            if case .error(let message) = event { throw OpenAICompatibleClientError.streamError(message) }
        }
        guard finishReason == "stop" else { throw OpenAICompatibleClientError.incompleteTextResponse }
    }

    @MainActor
    private static func replay(_ input: Data) throws {
        let replay = try JSONDecoder().decode(Replay.self, from: input)
        let collector = Collector(replay.example, mode: replay.mode ?? "joint", prompt: "offline-replay")
        do {
            for delta in replay.deltas { try collector.append(delta.text, at: delta.milliseconds) }
            guard replay.finishReason == "stop" else { throw OpenAICompatibleClientError.incompleteTextResponse }
            try collector.finish(at: replay.deltas.last?.milliseconds ?? 0)
        } catch { collector.result.failure = error.localizedDescription }
        try emit(collector.result)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
