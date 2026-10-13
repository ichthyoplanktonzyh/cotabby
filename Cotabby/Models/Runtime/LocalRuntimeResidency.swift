import Foundation

/// Shared residency vocabulary separates permission to generate from keeping a native context in
/// memory. Endpoint work can stay eligible while its local residency is released.
nonisolated enum LocalRuntimeResidency: Equatable, Sendable {
    case released, warm, onDemand
}
