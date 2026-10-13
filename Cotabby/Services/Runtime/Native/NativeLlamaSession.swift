import Foundation
import CotabbyInference

/// Owns one move-only C++ engine for the lifetime of its runtime core. The app's completion core
/// and each learning role construct separate instances. This boundary centralizes allocation,
/// metadata, cancellation and teardown while callers retain their prompt/sequence/cache policy.
/// Heavy synchronous work belongs on a detached thread, never MainActor.
nonisolated final class NativeLlamaSession: @unchecked Sendable {
    /// Access only inside `withOperation` or the release callback. The cancellation methods below
    /// are the sole concurrent exception supported by CotabbyInference's atomic abort API. Keep
    /// the engine in its owner: returning the imported move-only value would transfer native state.
    var engine = CotabbyInferenceEngine()
    private let work = NativeRuntimeWorkGate()
    private var loadedConfiguration: NativeLlamaModelConfiguration?

    /// Called only in the operation scope; requested GPU layer count may be -1 while diagnostics
    /// report the resolved layer count, so compare allocation inputs rather than resolved metadata.
    func isPrepared(_ configuration: NativeLlamaModelConfiguration) -> Bool {
        loadedConfiguration == configuration
    }

    func withOperation<T>(expectedLease: UUID? = nil, checkCancellation: Bool = true,
                          _ body: () throws -> T) throws -> T {
        try work.withOperation(expectedLease: expectedLease, checkCancellation: checkCancellation, body)
    }

    /// Called within the operation scope. Failed loads leave no cached identity or partial native
    /// allocation, so retrying the same file really retries rather than reporting false readiness.
    func prepare(_ configuration: NativeLlamaModelConfiguration,
                 onWillLoad: () -> Void = {}) throws -> NativeLlamaPreparation {
        let cached = isPrepared(configuration)
        let began = ContinuousClock.now
        if !cached {
            onWillLoad()
            engine.unloadModel()
            loadedConfiguration = nil
            guard engine.loadModel(configuration.modelURL.path, configuration.gpuLayerCount,
                                   configuration.contextWindowTokens, configuration.batchSize) == .ok else {
                engine.unloadModel()
                throw NativeLlamaSessionError.loadFailed
            }
            loadedConfiguration = configuration
        }
        let elapsed = began.duration(to: .now).components
        return NativeLlamaPreparation(contextWindowTokens: Int(engine.getContextWindowTokens()),
            batchSize: Int(engine.getBatchSize()), threadCount: Int(engine.getThreadCount()),
            gpuLayerCount: Int(engine.getGPULayerCount()),
            loadMilliseconds: cached ? 0 : max(0, Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)),
            cached: cached)
    }

    func claim(_ operationID: UUID) { work.claim(operationID) }
    func invalidate() -> UUID { work.invalidate { engine.cancelSequence($0) } }
    func validate(_ operationID: UUID) throws { try work.validate(expectedLease: operationID) }

    func publishTarget(operationID: UUID, sequenceID: Int32, expectedLease: UUID? = nil) {
        work.publishTarget(operationID: operationID, sequenceID: sequenceID, expectedLease: expectedLease) {
            engine.cancelSequence($0)
        }
    }

    func clearTarget() { work.clearTarget() }
    func cancel(_ operationID: UUID? = nil) { work.cancel(operationID: operationID) { engine.cancelSequence($0) } }

    /// Drains first, then lets the owner clear its sequence bookkeeping while the model is still
    /// valid. Ordinary stops can reload later; permanent shutdown rejects future claims/work.
    @discardableResult
    func release(expectedLease: UUID? = nil, permanently: Bool = false, timeoutSeconds: TimeInterval? = nil,
                 beforeUnload: () -> Void = {}) -> Bool {
        var hadModel = false
        work.release(expectedLease: expectedLease, permanently: permanently, timeoutSeconds: timeoutSeconds,
                     cancelSequence: { engine.cancelSequence($0) }) {
            beforeUnload()
            hadModel = loadedConfiguration != nil
            engine.unloadModel()
            loadedConfiguration = nil
        }
        return hadModel
    }
}
