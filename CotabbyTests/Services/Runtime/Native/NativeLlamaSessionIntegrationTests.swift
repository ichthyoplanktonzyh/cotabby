import Foundation
import XCTest
@testable import Cotabby

/// Opt-in allocation checks borrow existing GGUF fixtures. No downloads or app preferences change.
/// Three real owners verify shared code does not imply a shared context or autocomplete cache.
final class NativeLlamaSessionIntegrationTests: XCTestCase {
    func testAllocationIdentityIncludesConfigurationAndFailedLoadsCanRetry() throws {
        let url = try fixture("COTABBY_LEARNING_GGUF")
        let session = NativeLlamaSession()
        defer { session.release(permanently: true) }
        func config(_ context: Int32) -> NativeLlamaModelConfiguration {
            NativeLlamaModelConfiguration(modelURL: url, gpuLayerCount: -1,
                contextWindowTokens: context, batchSize: 256)
        }
        try session.withOperation {
            let missing = NativeLlamaModelConfiguration(modelURL: url.appendingPathComponent("missing.gguf"),
                gpuLayerCount: -1, contextWindowTokens: 2_048, batchSize: 256)
            XCTAssertThrowsError(try session.prepare(missing))
            XCTAssertFalse(session.isPrepared(missing))
            let first = try session.prepare(config(2_048))
            XCTAssertFalse(first.cached)
            let cached = try session.prepare(config(2_048))
            XCTAssertTrue(cached.cached)
            XCTAssertEqual(cached.loadMilliseconds, 0)
            let changed = try session.prepare(config(4_096))
            XCTAssertFalse(changed.cached, "The same file with a new context budget must reload")
            XCTAssertEqual(changed.contextWindowTokens, 4_096)
        }
        XCTAssertTrue(session.release())
        try session.withOperation {
            XCTAssertFalse(try session.prepare(config(4_096)).cached)
        }
    }

    func testThreeOwnersReleaseIndependentlyAndPreserveCompletionCache() throws {
        let translationURL = try fixture("COTABBY_LEARNING_GGUF")
        let completionURL = try fixture("COTABBY_TEST_MODEL_PATH")
        let completion = LlamaRuntimeCore(), translator = LearningLocalRuntime(), analyzer = LearningLocalRuntime()
        defer { completion.shutdown(); translator.shutdownSync(); analyzer.shutdownSync() }
        _ = try completion.prepare(resolvedRuntime: ResolvedLlamaRuntime(
            runtimeDirectoryURL: completionURL.deletingLastPathComponent(), modelFileURL: completionURL,
            modelDisplayName: completionURL.lastPathComponent), configuration: LlamaRuntimeConfiguration(
                runtimeDirectoryPath: nil, preferredModelNames: [], contextWindowTokens: 1_024,
                batchSize: 256, gpuLayerCount: -1))
        let prompt = "Hi Alex, thanks for sending the project update. I will review the schedule and send you my"
        let options = LlamaGenerationOptions(maxPredictionTokens: 12, temperature: 0, topK: 20,
            topP: 0.7, minP: 0.08, repetitionPenalty: 1.05, seed: 42, stopAtArgmaxEOG: false)
        let cold = try completion.generate(prompt: prompt, options: options)
        XCTAssertFalse(cold.text.isEmpty)
        let translationID = UUID(), analysisID = UUID()
        translator.claim(translationID); analyzer.claim(analysisID)
        try translator.prepare(modelURL: translationURL, operationID: translationID)
        try analyzer.prepare(modelURL: translationURL, operationID: analysisID)
        analyzer.shutdownSync()
        let reused = try completion.generate(prompt: prompt, cachedPrefixBytes: prompt.utf8.count, options: options)
        XCTAssertEqual(reused, cold, "Unloading learning must leave completion's sequence and sampler untouched")
        completion.shutdown()
        let translated = try translator.generate(modelURL: translationURL, template: .hyMT,
            prompt: "Translate the following text into English. Output only the translated result:\n你好",
            maxTokens: 128, operationID: translationID) { _ in }
        XCTAssertTrue(translated.lowercased().contains("hello"), translated)
    }

    private func fixture(_ key: String) throws -> URL {
        guard let path = ProcessInfo.processInfo.environment[key], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Set \(key) to an existing absolute GGUF fixture path")
        }
        return URL(fileURLWithPath: path)
    }
}
