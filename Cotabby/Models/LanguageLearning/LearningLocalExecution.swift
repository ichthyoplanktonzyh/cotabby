import Foundation

/// Narrow native ownership seam. The controller owns one executor; the production implementation
/// serializes C++ state and tests simulate load/decode/unload without touching real model files.
nonisolated protocol LearningLocalExecuting: AnyObject, Sendable {
    func claim(_ operation: UUID)
    func invalidate() -> UUID
    func prepare(modelURL: URL, operationID: UUID, trace: LearningRequestContext?) throws
    func generate(modelURL: URL, template: LearningChatTemplate, prompt: String, maxTokens: Int,
                  operationID: UUID, trace: LearningRequestContext?, onLoad: (@Sendable (Int) -> Void)?,
                  onDelta: @Sendable (String) -> Void) throws -> String
    func cancel(_ operation: UUID?)
    func unload(expectedLease: UUID?, trace: LearningRequestContext?)
    func shutdownSync()
}
