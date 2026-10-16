import Combine
import Foundation

/// Completion borrows the runtime's selected filename; it does not own or persist another model
/// selection. Only model-specific budgets live here. Power switching therefore selects the same
/// budget whether it happened through a picker or automatically through the composition root.
extension SuggestionSettingsModel {
    func setCompletionLocalModelFilename(_ filename: String?) {
        let name = filename ?? ""
        if completionLocalModelFilename != name { completionLocalModelFilename = name }
    }

    var completionContextIdentity: String {
        completionContextIdentities.identity(
            engine: selectedEngine, localModel: completionLocalModelFilename,
            baseURL: openAICompatibleBaseURL, endpointModel: openAICompatibleModelName, mode: openAICompatibleAPIMode)
    }

    var completionContextWindowTokens: Int {
        min(
            completionContexts.tokens(for: completionContextIdentity) ?? 4_096,
            selectedEngine == .appleIntelligence
                ? 4_096
                : selectedEngine == .llamaOpenSource
                    ? ModelContextBudget.maximumLocalTokens : ModelContextBudget.maximumEndpointTokens)
    }

    /// Runtime preparation supplies its actual selected filename, which may be arriving before
    /// the UI's mirrored filename commits. The shared local slot avoids rebuilding its key per request.
    func localCompletionContextWindowTokens(modelFilename: String) -> Int? {
        let identity = completionContextIdentities.identity(engine: .llamaOpenSource, localModel: modelFilename,
                                                           baseURL: "", endpointModel: "", mode: .chatCompletions)
        return completionContexts.tokens(for: identity)
    }

    /// Default focus polling remains small. A deliberate model override expands the AX request
    /// before the prompt allocator chooses its caret-nearest token window; the byte/range ceiling
    /// keeps a very large provider budget from turning every focus poll into an unbounded read.
    var completionCaptureWindowUTF16: Int {
        guard !completionContexts.overrides.isEmpty,
              let tokens = completionContexts.tokens(for: completionContextIdentity)
        else { return FocusedInputSnapshot.textWindowUTF16 }
        let maximum = selectedEngine == .appleIntelligence ? 4_096
            : selectedEngine == .llamaOpenSource ? ModelContextBudget.maximumLocalTokens : ModelContextBudget.maximumEndpointTokens
        return min(262_144, max(FocusedInputSnapshot.textWindowUTF16, min(tokens, maximum) * 6))
    }

    /// A power/model switch can end editing in an old field. Its pending commit must not resize
    /// the newly selected model, so views can retain the identity they began editing.
    func setCompletionContextWindowTokens(_ tokens: Int?, expectedIdentity: String? = nil) {
        if let expectedIdentity, expectedIdentity != completionContextIdentity { return }
        let maximum =
            selectedEngine == .appleIntelligence
            ? 4_096
            : selectedEngine == .llamaOpenSource
                ? ModelContextBudget.maximumLocalTokens : ModelContextBudget.maximumEndpointTokens
        completionContexts.setTokens(tokens, for: completionContextIdentity, maximum: maximum)
        objectWillChange.send()
    }

    static func completionContextIdentity(
        engine: SuggestionEngineKind, localModel: String, baseURL: String,
        endpointModel: String, mode: OpenAICompatibleAPIMode
    ) -> String {
        ModelContextBudget.identity(
            backend: engine.rawValue,
            model: engine == .llamaOpenSource ? localModel : engine == .openAICompatible ? endpointModel : "system",
            baseURL: engine == .openAICompatible ? baseURL : "", mode: engine == .openAICompatible ? mode.rawValue : "")
    }

    func applyingContext(
        to value: SuggestionSettingsSnapshot, overrides: [String: Int], localModel: String,
        baseURL: String, endpointModel: String, mode: OpenAICompatibleAPIMode
    ) -> SuggestionSettingsSnapshot {
        var result = value
        let identity = completionContextIdentities.identity(
            engine: value.selectedEngine, localModel: localModel,
            baseURL: baseURL, endpointModel: endpointModel, mode: mode)
        let maximum =
            value.selectedEngine == .appleIntelligence
            ? 4_096
            : value.selectedEngine == .llamaOpenSource
                ? ModelContextBudget.maximumLocalTokens : ModelContextBudget.maximumEndpointTokens
        result.completionModelIdentity = identity
        result.contextWindowTokens = overrides[identity].map { min($0, maximum) }
        let local = value.selectedEngine == .llamaOpenSource ? identity : completionContextIdentities.identity(
            engine: .llamaOpenSource, localModel: localModel,
            baseURL: "", endpointModel: "", mode: mode)
        result.localModelIdentity = local
        result.localContextWindowTokens = overrides[local].map { min($0, ModelContextBudget.maximumLocalTokens) }
        return result
    }
}
