import Foundation

/// Each task's settings model owns this memo for canonical destination strings. Two slots bound
/// memory while a user types an endpoint URL: one nonlocal destination and one local/fallback.
/// Callers pass explicit incoming values, so Combine's willSet publication cannot cache old state.
nonisolated struct ModelContextIdentityCache {
    struct Input: Equatable {
        let backend: String
        let model: String
        let baseURL: String
        let mode: String
    }

    private struct Entry {
        let input: Input
        let identity: String
    }
    private var local: Entry?
    private var other: Entry?
    private let makeIdentity: (Input) -> String

    init(makeIdentity: @escaping (Input) -> String = {
        ModelContextBudget.identity(backend: $0.backend, model: $0.model, baseURL: $0.baseURL, mode: $0.mode)
    }) {
        self.makeIdentity = makeIdentity
    }

    mutating func identity(engine: SuggestionEngineKind, localModel: String, baseURL: String,
                           endpointModel: String, mode: OpenAICompatibleAPIMode) -> String {
        identity(backend: engine.rawValue,
                 model: engine == .llamaOpenSource ? localModel : engine == .openAICompatible ? endpointModel : "system",
                 baseURL: engine == .openAICompatible ? baseURL : "",
                 mode: engine == .openAICompatible ? mode.rawValue : "", isLocal: engine == .llamaOpenSource)
    }

    mutating func identity(backend: String, model: String, baseURL: String = "", mode: String = "", isLocal: Bool) -> String {
        let input = Input(backend: backend, model: model, baseURL: baseURL, mode: mode)
        let previous = isLocal ? local : other
        if let previous, previous.input == input { return previous.identity }
        let entry = Entry(input: input, identity: makeIdentity(input))
        if isLocal { local = entry } else { other = entry }
        return entry.identity
    }
}
