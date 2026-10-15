import Foundation

/// Destination identity and allocation rules shared by otherwise independent task settings.
/// This pure boundary never reads preferences or allocates a native runtime. Callers freeze its
/// result into a request, so UI edits cannot resize an in-flight request behind the writer's back.
nonisolated enum ModelContextBudget {
    static let maximumLocalTokens = 32_768
    static let maximumEndpointTokens = 131_072
    static let maximumTextBytes = 262_144
    static let maximumTranslationOutputTokens = 32_768

    static func identity(backend: String, model: String, baseURL: String = "", mode: String = "") -> String {
        let candidate = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = candidate
        if var url = URLComponents(string: candidate) {
            let scheme = url.scheme?.lowercased()
            let host = url.host?.lowercased()
            url.scheme = scheme
            url.host = host
            url.user = nil
            url.password = nil
            if url.port == 443 && scheme == "https" || url.port == 80 && scheme == "http" { url.port = nil }
            while url.path.hasSuffix("/") { url.path.removeLast() }
            // The transport maps a root endpoint to /v1. Equivalent destinations reuse a budget.
            if !candidate.isEmpty, url.path.isEmpty { url.path = "/v1" }
            normalized = url.string ?? candidate
        }
        let fields = [backend, model.trimmingCharacters(in: .whitespacesAndNewlines), normalized, mode]
        return String(decoding: (try? JSONEncoder().encode(fields)) ?? Data(), as: UTF8.self)
    }

    /// Unknown endpoint tokenizers need a conservative estimate, including a framing/error margin.
    /// This is an estimate, not a claim about a provider's tokenizer or server-side capacity.
    static func estimatedTokens(_ text: String) -> Int {
        max(TokenCountEstimator.estimate(text), (text.utf8.count + 1) / 2)
    }

    static func inputAllowance(total: Int, output: Int, estimated: Bool) -> Int {
        max(0, total - output - (estimated ? max(128, total / 10) : 32))
    }

    static func translationOutputTokens(source: String, total: Int) throws -> Int {
        let desired = max(min(2_048, max(256, total / 3)), estimatedTokens(source) * 2 + 64)
        guard desired < total, desired <= maximumTranslationOutputTokens else { throw oversizedTarget() }
        return desired
    }

    static func oversizedTarget() -> LearningFailure {
        .message(
            String(
                localized:
                    "The full target and output reserve exceed this model's budget. Select less text or raise the budget. Nothing was shortened or replaced.",
                table: "Learning", comment: "Rejects an oversized translation target without silently shortening it."))
    }
}
