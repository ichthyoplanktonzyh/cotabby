import Foundation
import Logging

/// A stage-local measurement lives until that task finishes. It holds bounded debug content only
/// for the existing debug sink; persisted metrics carry no editor text, address or credentials.
@MainActor
final class LearningRequestMeasurement {
    let context: LearningRequestContext
    let startedAt: TimeInterval
    let timestamp = Date()
    private let now: () -> TimeInterval
    private let event: (LearningRequestContext, String, [String: String]) -> Void
    private(set) var generationBegan = false
    private(set) var modelLoadMs: Int?
    private(set) var firstOutputMs: Int?
    private(set) var usableResultMs: Int?
    private(set) var displayMs: Int?
    private(set) var prompt = ""
    private(set) var rawOutput = ""

    init(context: LearningRequestContext, now: @escaping () -> TimeInterval,
         event: @escaping (LearningRequestContext, String, [String: String]) -> Void) {
        self.context = context; self.now = now; self.event = event; startedAt = now()
    }
    var elapsedMs: Int { max(0, Int(((now() - startedAt) * 1_000).rounded())) }
    func beginGeneration(prompt: String) {
        generationBegan = true
        if CotabbyDebugOptions.isEnabled { self.prompt = prompt }
        event(context, "generation_started", ["prompt_bytes": String(prompt.utf8.count)])
    }
    func loaded(milliseconds: Int) { modelLoadMs = milliseconds }
    func received(_ delta: String) {
        if firstOutputMs == nil, !delta.isEmpty {
            firstOutputMs = elapsedMs
            event(context, "first_output", ["elapsed_ms": String(elapsedMs)])
        }
        if CotabbyDebugOptions.isEnabled, rawOutput.utf8.count < 48_000 {
            rawOutput += String(decoding: delta.utf8.prefix(48_000 - rawOutput.utf8.count), as: UTF8.self)
        }
    }
    func usable() {
        guard usableResultMs == nil else { return }
        usableResultMs = elapsedMs
        event(context, "usable_result", ["elapsed_ms": String(elapsedMs)])
    }
    func clearDebugContent() { prompt = ""; rawOutput = "" }
    func displayed() {
        guard displayMs == nil else { return }
        displayMs = elapsedMs
        event(context, "displayed", ["elapsed_ms": String(elapsedMs)])
    }
}

/// App-owned observer unifies learning with the original log sinks and opt-in metrics ring. It
/// tracks active stages plus a bounded set of completed stages whose UI publication follows later.
/// Independent model controllers receive no knowledge of the Performance pane or editor captures.
@MainActor
final class LearningRequestTelemetry {
    private struct Key: Hashable { let requestID: String; let source: ModelRequestSource }
    private struct Pending { let entryID: UUID; let measurement: LearningRequestMeasurement }
    private let metrics: PerformanceMetricsStore?
    private let trackingEnabled: () -> Bool
    private let now: () -> TimeInterval
    private let event: (LearningRequestContext, String, [String: String]) -> Void
    private var active: [Key: LearningRequestMeasurement] = [:]
    private var pending: [Key: Pending] = [:]

    init(metrics: PerformanceMetricsStore? = nil, trackingEnabled: @escaping () -> Bool = { false },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         event: @escaping (LearningRequestContext, String, [String: String]) -> Void = {
             LearningRequestLog.emit($0, phase: $1, details: $2)
         }) {
        self.metrics = metrics; self.trackingEnabled = trackingEnabled; self.now = now; self.event = event
    }

    func perform<T>(source: ModelRequestSource, profile: LearningModelSnapshot,
                    operation: () async throws -> T) async throws -> T {
        let context = LearningRequestContext(requestID: LearningRequestTrace.requestID ?? RequestID.generate(),
            operationID: RequestID.generate(), source: source,
            modelName: profile.backend == .local ? profile.localModel : profile.endpointModel,
            engine: profile.backend == .local ? "llama" : "openai_compatible")
        let measurement = LearningRequestMeasurement(context: context, now: now, event: event)
        let key = Key(requestID: context.requestID, source: source)
        pending.removeValue(forKey: key)
        active[key] = measurement
        event(context, "started", [:])
        do {
            let result = try await LearningRequestTrace.$measurement.withValue(measurement, operation: operation)
            try Task.checkCancellation()
            finish(measurement, key: key, outcome: .completed)
            return result
        } catch {
            finish(measurement, key: key, outcome: error is CancellationError ? .cancelled : .failed,
                   errorType: String(reflecting: type(of: error)))
            throw error
        }
    }

    private func finish(_ measurement: LearningRequestMeasurement, key: Key,
                        outcome: ModelRequestOutcome, errorType: String? = nil) {
        let isCurrent = active[key] === measurement
        if isCurrent { active.removeValue(forKey: key) }
        var details = ["elapsed_ms": String(measurement.elapsedMs), "outcome": outcome.rawValue]
        if let errorType { details["error_type"] = errorType }
        event(measurement.context, "finished", details)
        if CotabbyDebugOptions.isEnabled, measurement.generationBegan {
            CotabbyLogger.llmIO.debug("Learning generation", metadata:
                LearningRequestLog.metadata(measurement.context, phase: "finished", details: details).merging([
                    "prompt": .string(measurement.prompt), "completion_raw": .string(measurement.rawOutput)
                ]) { _, new in new })
        }
        measurement.clearDebugContent()
        guard measurement.generationBegan, trackingEnabled(), let metrics else { return }
        let id = metrics.record(modelName: measurement.context.modelName, latencyMs: measurement.elapsedMs,
            timestamp: measurement.timestamp, source: measurement.context.source, outcome: outcome,
            requestID: measurement.context.requestID, modelLoadMs: measurement.modelLoadMs,
            firstOutputMs: measurement.firstOutputMs, usableResultMs: measurement.usableResultMs,
            displayMs: measurement.displayMs)
        // Pending display must not keep full debug inputs/results alive beyond this operation.
        if isCurrent, outcome == .completed, measurement.displayMs == nil {
            pending = pending.filter { pair in metrics.entries.contains { $0.id == pair.value.entryID } }
            pending[key] = Pending(entryID: id, measurement: measurement)
        }
    }

    func recordDisplay(source: ModelRequestSource, requestID: String) {
        let key = Key(requestID: requestID, source: source)
        if let measurement = active[key] { measurement.displayed(); return }
        guard let record = pending.removeValue(forKey: key) else { return }
        record.measurement.displayed()
        if trackingEnabled() { metrics?.recordDisplay(entryID: record.entryID, elapsedMs: record.measurement.elapsedMs) }
    }
}
