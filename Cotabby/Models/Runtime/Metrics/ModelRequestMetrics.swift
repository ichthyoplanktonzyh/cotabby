import Foundation

/// Request kind is independent of model/backend: one server can serve several tasks without
/// making their durations or quality counters comparable. Performance defaults to completion.
nonisolated enum ModelRequestSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case completion, translation, analysis
    var id: String { rawValue }
    var label: String {
        switch self {
        case .completion: "Autocomplete"
        case .translation: "Translation"
        case .analysis: "Learning Analysis"
        }
    }
}

/// Completed means the task returned a validated result, not that a human judged its quality.
/// In old completion records it also includes normalized/suppressed results, so it stays neutral.
nonisolated enum ModelRequestOutcome: String, Codable, Sendable {
    case completed, failed, cancelled
    var label: String {
        switch self { case .completed: "Completed"; case .failed: "Failed"; case .cancelled: "Cancelled" }
    }
}

/// Content-free persisted request record. Optional stage timings mean unobserved/not applicable;
/// zero is a measured duration. The decoder preserves literal pre-learning history without a reset.
nonisolated struct PerformanceMetricEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let modelName: String
    let latencyMs: Int
    let source: ModelRequestSource
    let outcome: ModelRequestOutcome
    let requestID: String?
    let modelLoadMs: Int?
    let firstOutputMs: Int?
    let usableResultMs: Int?
    var displayMs: Int?

    init(id: UUID = UUID(), timestamp: Date = Date(), modelName: String, latencyMs: Int,
         source: ModelRequestSource = .completion, outcome: ModelRequestOutcome = .completed,
         requestID: String? = nil, modelLoadMs: Int? = nil, firstOutputMs: Int? = nil,
         usableResultMs: Int? = nil, displayMs: Int? = nil) {
        self.id = id; self.timestamp = timestamp; self.modelName = modelName; self.latencyMs = latencyMs
        self.source = source; self.outcome = outcome; self.requestID = requestID
        self.modelLoadMs = modelLoadMs; self.firstOutputMs = firstOutputMs
        self.usableResultMs = usableResultMs; self.displayMs = displayMs
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, modelName, latencyMs, source, outcome, requestID
        case modelLoadMs, firstOutputMs, usableResultMs, displayMs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); timestamp = try c.decode(Date.self, forKey: .timestamp)
        modelName = try c.decode(String.self, forKey: .modelName); latencyMs = try c.decode(Int.self, forKey: .latencyMs)
        source = try c.decodeIfPresent(ModelRequestSource.self, forKey: .source) ?? .completion
        outcome = try c.decodeIfPresent(ModelRequestOutcome.self, forKey: .outcome) ?? .completed
        requestID = try c.decodeIfPresent(String.self, forKey: .requestID)
        modelLoadMs = try c.decodeIfPresent(Int.self, forKey: .modelLoadMs)
        firstOutputMs = try c.decodeIfPresent(Int.self, forKey: .firstOutputMs)
        usableResultMs = try c.decodeIfPresent(Int.self, forKey: .usableResultMs)
        displayMs = try c.decodeIfPresent(Int.self, forKey: .displayMs)
    }
}
