import Foundation

/// Builds a complete target with optional nearest-neighbor reference. Native callers inject the
/// real tokenizer (including template framing); endpoint callers inject a conservative estimator.
/// This planner has no services or retained state and can execute away from MainActor.
nonisolated enum LearningTranslationBudget {
    /// Carries the winning candidate's measured work with its exact prompt. Native planning keeps
    /// token IDs here; estimated endpoint planning uses Void and retains no extra representation.
    struct Plan<Payload> {
        let request: LearningTranslationPrompt.Request
        let payload: Payload
    }

    /// Immutable allocation policy shared by estimated and native measurements of one request.
    struct Limits {
        let family: LearningTranslationPrompt.Family
        let total: Int
        let output: Int
        let estimated: Bool
        var maximumInputTokens: Int = .max
    }

    static func prompt(
        input: LearningTranslationInput, sourceLanguage: LearningLanguage,
        targetLanguage: LearningLanguage, family: LearningTranslationPrompt.Family,
        total: Int, output: Int, estimated: Bool, maximumInputTokens: Int = .max,
        count: (String) throws -> Int
    ) throws -> LearningTranslationPrompt.Request {
        try plan(input: input, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                 limits: Limits(family: family, total: total, output: output, estimated: estimated,
                                maximumInputTokens: maximumInputTokens)) { text in
            (try count(text), ())
        }.request
    }

    /// Keeps only the best fitting payload. The final binary-search probe can be oversized, so
    /// caching the most recently measured tokens would pair the returned prompt with wrong IDs.
    static func plan<Payload>(
        input: LearningTranslationInput, sourceLanguage: LearningLanguage,
        targetLanguage: LearningLanguage, limits: Limits,
        measure: (String) throws -> (count: Int, payload: Payload)
    ) throws -> Plan<Payload> {
        let family = limits.family
        let allowance = min(
            family.maximumInputTokens, limits.maximumInputTokens,
            ModelContextBudget.inputAllowance(total: limits.total, output: limits.output, estimated: limits.estimated))
        let bare = try LearningTranslationPrompt.render(
            source: input.source, sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage, family: family)
        let bareMeasurement = try measure(bare.prompt)
        guard bareMeasurement.count <= allowance else { throw ModelContextBudget.oversizedTarget() }
        var best = Plan(request: bare, payload: bareMeasurement.payload)
        guard !input.referenceBefore.isEmpty || !input.referenceAfter.isEmpty else { return best }
        var low = 0
        var high = min(131_072, input.referenceBefore.count + input.referenceAfter.count)
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
            let measured = try measure(request.prompt)
            if measured.count <= allowance {
                best = Plan(request: request, payload: measured.payload)
                low = length + 1
            } else {
                high = length - 1
            }
        }
        return best
    }
}
