import Foundation

/// The native allocation identity, independent of a task's prompt or sampling strategy. Each
/// runtime passes its own values; equal files with different context budgets require a reload.
nonisolated struct NativeLlamaModelConfiguration: Equatable, Sendable {
    let modelURL: URL
    let gpuLayerCount: Int32
    let contextWindowTokens: Int32
    let batchSize: Int32

    init(modelURL: URL, gpuLayerCount: Int32, contextWindowTokens: Int32, batchSize: Int32) {
        self.modelURL = modelURL.standardizedFileURL
        self.gpuLayerCount = gpuLayerCount
        self.contextWindowTokens = contextWindowTokens
        self.batchSize = batchSize
    }
}

/// A value snapshot leaves the serialized native boundary without exposing C++ pointers. Runtime
/// owners map it into their existing diagnostics and learning telemetry after preparation.
nonisolated struct NativeLlamaPreparation: Sendable {
    let contextWindowTokens: Int
    let batchSize: Int
    let threadCount: Int
    let gpuLayerCount: Int
    let loadMilliseconds: Int
    let cached: Bool
}

/// Task-specific owners translate this low-level failure into their existing user-facing errors.
nonisolated enum NativeLlamaSessionError: Error {
    case loadFailed
}
