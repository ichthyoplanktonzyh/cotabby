import Foundation

/// One translation plan's token IDs, owned by LearningLocalRuntime and accessed only inside its
/// serialized native operation. This is CPU work reuse, not a second model sequence or KV cache.
/// Consumption always retires the entry; model reload/unload also clears it before vocabulary can
/// change. Exact configuration, prompt and resolved framing must agree before IDs may be reused.
nonisolated struct LearningPromptTokenCache {
    private struct Entry {
        let configuration: LearningLocalModelConfiguration
        let prompt: String
        let template: LearningChatTemplate
        let tokens: [Int32]
    }

    private var entry: Entry?

    mutating func store(configuration: LearningLocalModelConfiguration, prompt: String,
                        template: LearningChatTemplate, tokens: [Int32]) {
        entry = Entry(configuration: configuration, prompt: prompt, template: template, tokens: tokens)
    }

    mutating func take(configuration: LearningLocalModelConfiguration, prompt: String,
                       template: LearningChatTemplate) -> [Int32]? {
        defer { entry = nil }
        guard let entry, entry.configuration == configuration,
              entry.prompt == prompt, entry.template == template else { return nil }
        return entry.tokens
    }

    mutating func reset() { entry = nil }
}
