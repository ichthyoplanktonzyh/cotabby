import Foundation

/// Immutable correlation evidence travels explicitly to detached native work. UUID leases still
/// own cancellation; these short IDs join logs across services and UI without retaining editor text.
nonisolated struct LearningRequestContext: Sendable {
    let requestID: String
    let operationID: String
    let source: ModelRequestSource
    let modelName: String
    let engine: String
}

/// Task-local scopes preserve existing narrow generation protocols. Coordinators supply the
/// sentence/word ID, services create a stage measurement, and inherited async tasks see both.
nonisolated enum LearningRequestTrace {
    @TaskLocal static var requestID: String?
    @TaskLocal static var measurement: LearningRequestMeasurement?
}

@MainActor
protocol LearningDisplayReporting: AnyObject {
    func recordDisplay(source: ModelRequestSource, requestID: String)
}

extension LearningDisplayReporting {
    // Fakes and alternate services need no metrics dependency. Production routes this callback
    // to the app-owned observer after a stale-guarded panel update actually presents usable text.
    func recordDisplay(source: ModelRequestSource, requestID: String) {}
}
