import CotabbyInference
import Foundation
import XCTest
@testable import Cotabby

/// Opt-in native checks use an existing GGUF supplied by the runner. They never download a model
/// or change app settings; normal CI skips them. Two engines exercise the shared backend lifetime.
final class LearningLocalRuntimeIntegrationTests: XCTestCase {
    /// Uses the pinned real files downloaded by a validation runner. Native framing, literal
    /// tokenization, model load, complete generation and output policy all run as in the product.
    /// Synthetic short fixtures exercise both directions; this is not a comparative quality score.
    func testRecommendedTranslationSpecialistsUseNativeProductPath() async throws {
        guard let directory = ProcessInfo.processInfo.environment["COTABBY_TRANSLATION_CATALOG_DIR"] else {
            throw XCTSkip("Set COTABBY_TRANSLATION_CATALOG_DIR to the pinned translation GGUF directory")
        }
        let fixtures: [(String, String, LearningLanguage, LearningLanguage)] = [
            ("greeting", "你好", .chinese, .english),
            ("ability", "我能做到。", .chinese, .english),
            ("reverse", "I like the food you cooked.", .english, .chinese),
            ("korean", "你方便的时候给我回个电话就好。", .chinese, .korean),
            ("traditional", "Please reply when you have time.", .english, .traditionalChinese)
        ]
        var evidence: [[String: String]] = []
        for model in LearningRuntimeCatalog.translationModels {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(model.filename)
            let template = try LearningLocalPrompt.resolve(.automatic, modelURL: url)
            for (id, source, sourceLanguage, targetLanguage) in fixtures {
                let request = try LearningTranslationPrompt.render(source: source, sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage, family: .init(template: template))
                let raw = try await Task.detached {
                    let runtime = LearningLocalRuntime(), operation = UUID()
                    defer { runtime.shutdownSync() }
                    runtime.claim(operation)
                    return try runtime.generate(modelURL: url, template: .automatic, prompt: request.prompt,
                        maxTokens: 512, operationID: operation) { _ in }
                }.value
                let text = try LearningExpressionOutputPolicy.validatedText(raw)
                XCTAssertFalse(text.isEmpty)
                XCTAssertNil(text.range(of: #"<[|｜]"#, options: .regularExpression), text)
                if id == "greeting" {
                    XCTAssertNotNil(text.range(of: #"\b(hello|hi)\b"#, options: [.regularExpression, .caseInsensitive]), text)
                }
                if id == "traditional" {
                    XCTAssertNil(text.range(of: "[请时复]", options: .regularExpression), text)
                }
                evidence.append(["model": model.filename, "case": id, "source": source,
                    "sourceLanguage": sourceLanguage.rawValue, "targetLanguage": targetLanguage.rawValue,
                    "template": template.rawValue, "prompt": request.prompt, "translation": text])
            }
        }
        let output = URL(fileURLWithPath: directory).appendingPathComponent("native-translations.json")
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }

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
        let result = try LearningAlignmentParser.parse(raw, source: "你好", translation: "Hello.")
        XCTAssertEqual(result.translation, "Hello.")
        XCTAssertFalse(result.chunks.isEmpty)
    }

    func testGemmaAlignmentUsesProductTemplateAndFixedMultilingualEvidence() async throws {
        guard let path = ProcessInfo.processInfo.environment["COTABBY_ALIGNMENT_GGUF"] else {
            throw XCTSkip("Set COTABBY_ALIGNMENT_GGUF to the pinned Gemma 4 E4B GGUF")
        }
        let fixtures: [(String, String, LearningLanguage, LearningLanguage)] = [
            ("你好", "Hello.", .chinese, .english),
            ("我能做到", "I can do it.", .chinese, .english),
            ("如果明天不下雨，我们就去散步。", "明日雨が降らなければ、私たちは散歩に行きます。", .chinese, .japanese)
        ]
        for (source, translation, sourceLanguage, targetLanguage) in fixtures {
            let prompt = try LearningAnalysisPrompt.render(source: source, translation: translation,
                sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            let raw = try await Task.detached {
                let runtime = LearningLocalRuntime(), id = UUID()
                defer { runtime.shutdownSync() }
                runtime.claim(id)
                return try runtime.generate(modelURL: URL(fileURLWithPath: path), template: .automatic,
                    prompt: prompt, maxTokens: 1_024, operationID: id) { _ in }
            }.value
            let result = try LearningAlignmentParser.parse(raw, source: source, translation: translation)
            XCTAssertEqual(result.translation, translation)
            XCTAssertFalse(result.chunks.isEmpty)
            XCTAssertFalse(raw.contains("<think>"), raw)
        }
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
