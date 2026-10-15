import Foundation

/// Builds a complete target with optional nearest-neighbor reference. Native callers inject the
/// real tokenizer (including template framing); endpoint callers inject a conservative estimator.
/// This planner has no services or retained state and can execute away from MainActor.
nonisolated enum LearningTranslationBudget {
    static func prompt(
        input: LearningTranslationInput, sourceLanguage: LearningLanguage,
        targetLanguage: LearningLanguage, family: LearningTranslationPrompt.Family,
        total: Int, output: Int, estimated: Bool, maximumInputTokens: Int = .max,
        count: (String) throws -> Int
    ) throws -> LearningTranslationPrompt.Request {
        let allowance = min(
            family.maximumInputTokens, maximumInputTokens,
            ModelContextBudget.inputAllowance(total: total, output: output, estimated: estimated))
        let bare = try LearningTranslationPrompt.render(
            source: input.source, sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage, family: family)
        guard try count(bare.prompt) <= allowance else { throw ModelContextBudget.oversizedTarget() }
        guard !input.referenceBefore.isEmpty || !input.referenceAfter.isEmpty else { return bare }
        var low = 0
        var high = min(131_072, input.referenceBefore.count + input.referenceAfter.count)
        var best = bare
        // Search only reference size. Re-rendering keeps quotation/JSON boundaries complete and
        // counts framing each time, rather than cutting a serialized instruction mid-field.
        while low <= high {
            let length = low + (high - low) / 2
            let beforeCount = min(input.referenceBefore.count, (length * 3) / 4)
            let afterCount = min(input.referenceAfter.count, length - beforeCount)
            let extraBefore = min(input.referenceBefore.count - beforeCount, length - beforeCount - afterCount)
            let candidate = LearningTranslationInput(
                source: input.source,
                referenceBefore: String(input.referenceBefore.suffix(beforeCount + extraBefore)),
                referenceAfter: String(input.referenceAfter.prefix(afterCount)))
            let request = try LearningTranslationPrompt.render(
                input: candidate, sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage, family: family)
            if try count(request.prompt) <= allowance {
                best = request
                low = length + 1
            } else {
                high = length - 1
            }
        }
        return best
    }
}
