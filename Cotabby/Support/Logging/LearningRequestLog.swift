import Foundation
import Logging

/// Shared log schema for async services, UI and detached native work. Ordinary events contain
/// identities/counts/timings only; prompt/output content goes exclusively to the gated LLM I/O sink.
nonisolated enum LearningRequestLog {
    static func metadata(_ context: LearningRequestContext, phase: String,
                         details: [String: String] = [:]) -> Logger.Metadata {
        var values: Logger.Metadata = ["request_id": .string(context.requestID),
            "operation_id": .string(context.operationID), "source": .string(context.source.rawValue),
            "model": .string(context.modelName), "engine": .string(context.engine), "phase": .string(phase)]
        for (key, value) in details { values[key] = .string(value) }
        return values
    }
    static func emit(_ context: LearningRequestContext, phase: String, details: [String: String] = [:]) {
        CotabbyLogger.learning.info("Learning request \(phase)", metadata: metadata(context, phase: phase, details: details))
    }
}
