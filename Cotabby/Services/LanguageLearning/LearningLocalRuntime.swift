import Foundation
import CotabbyInference

/// Keeps one learning role's instruction template, fresh sequence and lossless output policy.
/// Its NativeLlamaSession owns the move-only C++ engine and shared load/cancel/release safeguards;
/// translation and analysis each construct their own adapter/session and never use completion KV.
/// The controller dispatches this synchronous boundary onto its detached worker.
nonisolated final class LearningLocalRuntime: LearningLocalExecuting, @unchecked Sendable {
    private let native = NativeLlamaSession()

    func claim(_ operation: UUID) { native.claim(operation) }
    func invalidate() -> UUID { native.invalidate() }
    private func validate(_ operation: UUID) throws { try native.validate(operation) }

    private func load(_ modelURL: URL, trace: LearningRequestContext? = nil,
                      onLoad: (@Sendable (Int) -> Void)? = nil) throws {
        let preparation: NativeLlamaPreparation
        do {
            preparation = try native.prepare(NativeLlamaModelConfiguration(modelURL: modelURL,
                gpuLayerCount: -1, contextWindowTokens: 8_192, batchSize: 256)) {
                if let trace { LearningRequestLog.emit(trace, phase: "model_loading") }
            }
        } catch {
            throw LearningFailure.message("内置模型加载失败；请确认 GGUF 架构受当前推理库支持。")
        }
        if let trace { LearningRequestLog.emit(trace, phase: "model_ready",
            details: ["model_load_ms": String(preparation.loadMilliseconds), "cached": String(preparation.cached)]) }
        onLoad?(preparation.loadMilliseconds)
    }

    func prepare(modelURL: URL, operationID: UUID, trace: LearningRequestContext? = nil) throws {
        try native.withOperation(expectedLease: operationID) {
            try load(modelURL, trace: trace)
            try validate(operationID)
        }
    }

    func generate(modelURL: URL, template: LearningChatTemplate, prompt: String, maxTokens: Int,
                  operationID: UUID, trace: LearningRequestContext? = nil,
                  onLoad: (@Sendable (Int) -> Void)? = nil, onDelta: @Sendable (String) -> Void) throws -> String {
        return try native.withOperation(expectedLease: operationID) {
            try load(modelURL, trace: trace, onLoad: onLoad)
            try validate(operationID)
            let resolved = try LearningLocalPrompt.resolve(template, modelURL: modelURL)
            let (prefix, suffix) = try LearningLocalPrompt.delimiters(resolved)
            var tokens = Array(prefix.withCString { native.engine.tokenizeInstruction($0, Int32(prefix.utf8.count)) })
            tokens += Array(prompt.withCString { native.engine.tokenizeLiteral($0, Int32(prompt.utf8.count)) })
            tokens += Array(suffix.withCString { native.engine.tokenizeInstruction($0, Int32(suffix.utf8.count)) })
            guard !tokens.isEmpty, tokens.count + maxTokens < 8_192 else {
                throw LearningFailure.message("原文与输出预算超过内置模型上下文，请分段输入。")
            }
            let hy = resolved == .hyMT
            let sampling = SamplingConfig(temperature: hy ? 0.7 : 0.3, top_k: hy ? 20 : 40,
                top_p: hy ? 0.6 : 0.9, min_p: 0, repetition_penalty: hy ? 1.05 : 1,
                seed: UInt32.max, single_line: false)
            let sequence = native.engine.createSequence(sampling)
            guard sequence >= 0 else { throw LearningFailure.message("无法创建模型生成任务。") }
            native.engine.setComputeLogprob(sequence, false)
            native.publishTarget(operationID: operationID, sequenceID: sequence, expectedLease: operationID)
            defer {
                native.clearTarget()
                native.engine.destroySequence(sequence)
            }
            try validate(operationID)
            if let trace { LearningRequestLog.emit(trace, phase: "prefill_started", details: ["prompt_tokens": String(tokens.count)]) }
            let decoded = tokens.withUnsafeMutableBufferPointer {
                native.engine.decodePrompt(sequence, $0.baseAddress, Int32($0.count), 0)
            }
            guard decoded == .ok else {
                if decoded == .cancelled { throw CancellationError() }
                throw LearningFailure.message("内置模型无法处理本次输入。")
            }
            if let trace { LearningRequestLog.emit(trace, phase: "decode_started") }
            var bytes: [UInt8] = []
            var emitted = 0
            for _ in 0..<maxTokens {
                try validate(operationID)
                let token = native.engine.sampleNext(sequence)
                if token.was_cancelled { throw CancellationError() }
                if token.is_eos {
                    guard let text = String(bytes: bytes, encoding: .utf8) else {
                        throw LearningFailure.message("模型返回了不完整的文字编码。")
                    }
                    return text
                }
                guard let piece = token.piece, token.piece_length >= 0 else {
                    throw LearningFailure.message("模型返回了无效 token。")
                }
                // Native token bytes can split a Unicode scalar. Emit only a complete UTF-8 prefix,
                // preserving exact quotations for the analysis parser rather than replacing bytes.
                let pointer = UnsafeRawPointer(piece).assumingMemoryBound(to: UInt8.self)
                bytes.append(contentsOf: UnsafeBufferPointer(start: pointer, count: Int(token.piece_length)))
                guard bytes.count <= 48_000 else { throw LearningFailure.message("模型输出超过显示范围。") }
                if String(bytes: bytes, encoding: .utf8) != nil, bytes.count > emitted {
                    onDelta(String(decoding: bytes[emitted...], as: UTF8.self))
                    emitted = bytes.count
                }
            }
            throw LearningFailure.message("模型输出达到上限；未将截断结果当作完整表达。")
        }
    }

    func cancel(_ operation: UUID? = nil) { native.cancel(operation) }

    func unload(expectedLease: UUID? = nil, trace: LearningRequestContext? = nil) {
        if native.release(expectedLease: expectedLease), let trace {
            LearningRequestLog.emit(trace, phase: "runtime_released")
        }
    }

    func shutdownSync() {
        // Permanent shutdown closes future claims. The shared session drains a non-cancellable
        // loader before freeing its context, preserving the existing safe Metal teardown rule.
        native.release(permanently: true)
    }
}
