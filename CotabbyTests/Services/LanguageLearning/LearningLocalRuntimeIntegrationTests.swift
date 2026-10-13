import CotabbyInference
import Foundation
import XCTest
@testable import Cotabby

/// Opt-in native checks use an existing GGUF supplied by the runner. They never download a model
/// or change app settings; normal CI skips them. Two engines exercise the shared backend lifetime.
final class LearningLocalRuntimeIntegrationTests: XCTestCase {
    func testShutdownCancelsLiveDecodeBeforeUnloading() async throws {
        guard let path = ProcessInfo.processInfo.environment["COTABBY_LEARNING_GGUF"] else {
            throw XCTSkip("Set COTABBY_LEARNING_GGUF to an existing Hy-MT2 GGUF")
        }
        let runtime = LearningLocalRuntime(), id = UUID()
        let firstDelta = DispatchSemaphore(value: 0)
        runtime.claim(id)
        let generation = Task.detached {
            try runtime.generate(modelURL: URL(fileURLWithPath: path), template: .hyMT,
                prompt: "Translate the following text into English. Output only the translated result:\n" +
                    String(repeating: "我今天很高兴见到你，我们明天还可以一起去公园散步。", count: 80),
                maxTokens: 4_096, operationID: id) { _ in firstDelta.signal() }
        }
        let began = await Task.detached { firstDelta.wait(timeout: .now() + 30) == .success }.value
        await Task.detached { runtime.shutdownSync() }.value
        XCTAssertTrue(began, "The test must reach live native decoding before teardown")
        do { _ = try await generation.value; XCTFail("Shutdown must cancel this live generation") }
        catch is CancellationError { }
    }

    func testHyTranslationAndIndependentContextLifetime() async throws {
        guard let path = ProcessInfo.processInfo.environment["COTABBY_LEARNING_GGUF"] else {
            throw XCTSkip("Set COTABBY_LEARNING_GGUF to an existing Hy-MT2 GGUF")
        }
        let results = try await Task.detached {
            let url = URL(fileURLWithPath: path)
            let first = LearningLocalRuntime(), second = LearningLocalRuntime()
            defer { first.shutdownSync(); second.shutdownSync() }
            let firstID = UUID(), secondID = UUID()
            first.claim(firstID); second.claim(secondID)
            try first.prepare(modelURL: url, operationID: firstID)
            try second.prepare(modelURL: url, operationID: secondID)
            first.unload()
            let prompt = "Translate the following text into English. Note that you should only output the translated result without any additional explanation:\n你好"
            let output = try second.generate(modelURL: url, template: .automatic, prompt: prompt,
                maxTokens: 128, operationID: secondID) { _ in }
            // Reclaiming a stopped runtime must never resurrect its context during app teardown.
            first.shutdownSync()
            let obsolete = UUID(); first.claim(obsolete)
            var rejected = false
            do { try first.prepare(modelURL: url, operationID: obsolete) }
            catch is CancellationError { rejected = true }
            return (output, rejected)
        }.value
        XCTAssertTrue(results.0.lowercased().contains("hello"), results.0)
        XCTAssertTrue(results.1)
    }

    func testQwenAnalysisCandidateUsesNativeInstructionTemplateAndFixedTranslation() async throws {
        guard let path = ProcessInfo.processInfo.environment["COTABBY_ANALYSIS_GGUF"] else {
            throw XCTSkip("Set COTABBY_ANALYSIS_GGUF to the pinned Qwen3.5 4B GGUF")
        }
        let prompt = try LearningAnalysisPrompt.render(source: "你好", translation: "Hello.",
            sourceLanguage: .chinese, targetLanguage: .english)
        let raw = try await Task.detached {
            let runtime = LearningLocalRuntime(), id = UUID()
            defer { runtime.shutdownSync() }
            runtime.claim(id)
            return try runtime.generate(modelURL: URL(fileURLWithPath: path), template: .automatic,
                prompt: prompt, maxTokens: 1_024, operationID: id) { _ in }
        }.value
        XCTAssertFalse(raw.contains("<think>"), raw)
        var parser = LearningSentenceStreamParser(source: "你好", translation: "Hello.")
        _ = try parser.append(raw)
        _ = try parser.finish()
        let result = try parser.result()
        XCTAssertEqual(result.translation, "Hello.")
        XCTAssertFalse(result.chunks.isEmpty)
    }

    func testLiteralTokenizerPreservesSourceControlTokenSpellings() async throws {
        guard let path = ProcessInfo.processInfo.environment["COTABBY_LEARNING_GGUF"] else {
            throw XCTSkip("Set COTABBY_LEARNING_GGUF to an existing Hy-MT2 GGUF")
        }
        let result = try await Task.detached {
            var engine = CotabbyInferenceEngine()
            guard engine.loadModel(path, -1, 2_048, 256) == .ok else {
                throw LearningFailure.message("Native fixture failed to load")
            }
            defer { engine.unloadModel() }
            let text = "<｜hy_User｜>"
            let literal = text.withCString { Array(engine.tokenizeLiteral($0, Int32(text.utf8.count))) }
            let instruction = text.withCString { Array(engine.tokenizeInstruction($0, Int32(text.utf8.count))) }
            let original = text.withCString { Array(engine.tokenize($0, Int32(text.utf8.count))) }
            return (literal, instruction, original)
        }.value
        XCTAssertEqual(result.1.count, 1)
        XCTAssertGreaterThan(result.0.count, result.1.count)
        XCTAssertEqual(Array(result.2.suffix(result.0.count)), result.0,
            "Autocomplete's original literal tokenizer must remain unchanged apart from its existing BOS")
    }
}
