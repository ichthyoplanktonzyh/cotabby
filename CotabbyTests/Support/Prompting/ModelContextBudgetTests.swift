import Combine
import AppKit
import Foundation
import Testing

@testable import Cotabby

/// Budget decisions are tested without a model or network. The injected counter represents an
/// actual tokenizer, so target preservation and reference-only cropping can be asserted exactly.
@MainActor
struct ModelContextBudgetTests {
    @Test
    func aFocusCaptureReadsItsWindowConfigurationOnce() {
        var reads = 0
        let resolver = FocusSnapshotResolver(contextWindowUTF16: { reads += 1; return 8_192 })
        // An invalid AX application safely exercises capture entry/failure without granting the
        // unsigned test host Accessibility access or touching the user's focused input.
        let element = AXUIElementCreateApplication(-1)
        _ = resolver.resolveSnapshot(focusedElement: element, application: .current)
        #expect(reads == 1)
        _ = resolver.resolveSnapshot(focusedElement: element, application: .current)
        #expect(reads == 2, "The next capture must obtain a fresh configuration")
    }

    @Test
    func equivalentEndpointsShareBudgetIdentityButDistinctDestinationsDoNot() {
        let root = ModelContextBudget.identity(backend: "endpoint", model: " model ", baseURL: "HTTPS://EXAMPLE.COM:443/")
        #expect(root == ModelContextBudget.identity(backend: "endpoint", model: "model", baseURL: "https://example.com/v1/"))
        #expect(root != ModelContextBudget.identity(backend: "endpoint", model: "other", baseURL: "https://example.com/v1"))
        #expect(root != ModelContextBudget.identity(backend: "endpoint", model: "model", baseURL: "https://other.example/v1"))
    }

    @Test
    func taskBudgetsPersistIndependentlyAndFollowModelAndBackend() throws {
        let name = "io.cotabby.tests.Context-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.selectEngine(.llamaOpenSource)
        settings.setCompletionLocalModelFilename("a.gguf")
        settings.setCompletionContextWindowTokens(16_384)
        settings.languageLearning.translation.backend = .local
        settings.languageLearning.translation.localModel = "a.gguf"
        settings.languageLearning.translation.setContextWindowTokens(24_576)
        #expect(settings.snapshot.contextWindowTokens == 16_384)
        #expect(settings.languageLearning.translation.snapshot.contextWindowTokens == 24_576)
        settings.setCompletionLocalModelFilename("b.gguf")
        #expect(settings.snapshot.contextWindowTokens == nil)
        settings.setCompletionLocalModelFilename("a.gguf")
        #expect(settings.snapshot.contextWindowTokens == 16_384)
        settings.selectEngine(.openAICompatible)
        settings.setOpenAICompatibleModelName("endpoint-model")
        settings.setCompletionContextWindowTokens(65_536)
        #expect(settings.snapshot.contextWindowTokens == 65_536)
        #expect(settings.snapshot.localContextWindowTokens == 16_384)
        let restored = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        restored.setCompletionLocalModelFilename("a.gguf")
        #expect(restored.snapshot.contextWindowTokens == 65_536)
        #expect(restored.languageLearning.translation.snapshot.contextWindowTokens == 24_576)
    }

    @Test
    func pendingBudgetEditCannotResizeANewlySelectedModel() throws {
        let name = "io.cotabby.tests.StaleBudgetEdit-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.selectEngine(.llamaOpenSource)
        settings.setCompletionLocalModelFilename("first.gguf")
        settings.setCompletionContextWindowTokens(16_384)
        let oldCompletion = settings.completionContextIdentity
        settings.setCompletionLocalModelFilename("second.gguf")
        settings.setCompletionContextWindowTokens(24_576, expectedIdentity: oldCompletion)
        #expect(settings.snapshot.contextWindowTokens == nil)
        settings.setCompletionLocalModelFilename("first.gguf")
        #expect(settings.snapshot.contextWindowTokens == 16_384)
        let translation = settings.languageLearning.translation
        translation.backend = .local; translation.localModel = "first.gguf"
        translation.setContextWindowTokens(16_384)
        let oldTranslation = translation.contextIdentity
        translation.localModel = "second.gguf"
        translation.setContextWindowTokens(24_576, expectedIdentity: oldTranslation)
        #expect(translation.snapshot.contextWindowTokens == 8_192)
        translation.localModel = "first.gguf"
        #expect(translation.snapshot.contextWindowTokens == 16_384)
    }

    @Test(arguments: [false, true])
    func dormantPerAppBindingConflictsAreVisibleWhenTranslationIsEnabled(_ replacement: Bool) throws {
        let name = "io.cotabby.tests.LearningConflict-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        let learning = settings.languageLearning
        let modifiers = replacement ? learning.replacementModifiers : learning.modifiers
        settings.setPerAppAcceptKey(bundleIdentifier: "test.conflict", displayName: "Conflict App",
            keyCode: 17, modifiers: modifiers, label: replacement ? "⌃⌥T" : "⌥T")
        learning.translationEnabled = true
        #expect(settings.learningShortcutConflict(keyCode: 17, modifiers: modifiers, replacement: replacement) != nil)
        #expect(settings.learningShortcutConflict(keyCode: 17, modifiers: modifiers, replacement: replacement,
            bundleIdentifier: "test.conflict") != nil)
        #expect(settings.learningShortcutConflict(keyCode: 17, modifiers: modifiers, replacement: replacement,
            bundleIdentifier: "test.other") == nil)
    }

    @Test
    func switchingEqualBudgetModelsPublishesANewImmutableIdentity() throws {
        let name = "io.cotabby.tests.ContextIdentity-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.selectEngine(.openAICompatible)
        settings.setOpenAICompatibleModelName("first")
        var values: [SuggestionSettingsSnapshot] = []
        let subscription = settings.snapshotPublisher.sink { values.append($0) }
        defer { subscription.cancel() }
        let first = try #require(values.last)
        settings.setOpenAICompatibleModelName("second")
        let second = try #require(values.last)
        #expect(first.contextWindowTokens == second.contextWindowTokens)
        #expect(first.completionModelIdentity != second.completionModelIdentity)
        #expect(first != second)
    }

    @Test
    func captureOverrideExpandsTheAXWindowAndResetRestoresDefault() throws {
        let name = "io.cotabby.tests.CaptureBudget-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SuggestionSettingsModel(configuration: .standard, userDefaults: defaults)
        settings.selectEngine(.llamaOpenSource)
        let resolver = FocusSnapshotResolver(contextWindowUTF16: { settings.completionCaptureWindowUTF16 })
        let text = String(repeating: "earlier ", count: 2_000) + "CARET"
        let end = NSRange(location: text.utf16.count, length: 0)
        func captured() throws -> (text: String, selection: NSRange) {
            let rangeRead = try #require(
                FocusSnapshotResolver.windowedTextSelection(
                    selection: end,
                    documentLength: text.utf16.count, contextWindow: resolver.captureWindow,
                    readRange: { (text as NSString).substring(with: $0) }))
            return resolver.boundedContextWindow(text: rangeRead.text, selection: rangeRead.selection)
        }
        #expect(try captured().text.utf16.count == 4_096)
        settings.setCompletionContextWindowTokens(16_384)
        #expect(try captured().text == text)
        let expanded = FocusedInputSnapshot(
            applicationName: "Test", bundleIdentifier: "test.app", processIdentifier: 1,
            elementIdentifier: "field", role: "AXTextField", subrole: nil, caretRect: .zero, inputFrameRect: nil,
            caretSource: "test", caretQuality: .exact, observedCharWidth: nil, precedingText: text, trailingText: "",
            selection: end, isSecure: false, capturedTextWindowUTF16: resolver.captureWindow)
        #expect(!expanded.precedingTextMayBeTruncated)
        let optimistic = SpeculativeAcceptanceContext.optimisticSnapshot(after: expanded, inserting: " next")
        #expect(optimistic.capturedTextWindowUTF16 == expanded.capturedTextWindowUTF16)
        #expect(!FocusedInputContext(snapshot: optimistic, generation: 2).precedingTextMayBeTruncated)
        settings.setCompletionContextWindowTokens(nil)
        #expect(try captured().text.utf16.count == 4_096)
        #expect(CotabbyTestFixtures.focusedInputSnapshot(precedingText: String(repeating: "x", count: 4_096)).precedingTextMayBeTruncated)
    }

    @Test
    func largerCompletionBudgetKeepsEarlierTextAndStillEndsAtCaret() {
        let text = String(repeating: "earlier draft paragraph ", count: 800) + "CURRENT CARET "
        var settings = CotabbyTestFixtures.settingsSnapshot(selectedEngine: .llamaOpenSource)
        let context = CotabbyTestFixtures.focusedInputContext(precedingText: text)
        let old = SuggestionRequestFactory.buildRequest(context: context, settings: settings, configuration: .standard)
        settings.contextWindowTokens = 16_384
        let expanded = SuggestionRequestFactory.buildRequest(context: context, settings: settings, configuration: .standard)
        #expect(expanded.request.prompt.count > old.request.prompt.count)
        #expect(expanded.request.prompt.hasSuffix("CURRENT CARET "))
        #expect(expanded.request.contextWindowTokens == 16_384)
    }

    @Test(arguments: [LearningTranslationPrompt.Family.generic, .hyMT, .translateGemma])
    func referenceCroppingPreservesCompleteTargetAndTemplate(_ family: LearningTranslationPrompt.Family) throws {
        let target = "完整的目标含有 emoji 👩🏽‍💻 与换行\n不能静默裁剪。"
        let input = LearningTranslationInput(
            source: target, referenceBefore: String(repeating: "旧草稿", count: 4_000) + "NEAREST-BEFORE",
            referenceAfter: "NEAREST-AFTER" + String(repeating: "后文", count: 4_000))
        let prompt = try LearningTranslationBudget.prompt(
            input: input, sourceLanguage: .chinese, targetLanguage: .english,
            family: family, total: 2_048, output: 512, estimated: false, count: { $0.utf8.count })
        #expect(prompt.prompt.utf8.count <= 1_504)
        #expect(prompt.prompt.hasSuffix(target) || prompt.prompt.contains(target.replacingOccurrences(of: "\n", with: "\\n")))
        #expect(prompt.prompt.contains("NEAREST-BEFORE"))
        #expect(prompt.prompt.contains("NEAREST-AFTER"))
        #expect(!prompt.prompt.contains(String(repeating: "旧草稿", count: 1_000)))
    }

    @Test(arguments: [LearningTranslationPrompt.Family.generic, .hyMT, .translateGemma])
    func emptyReferenceRetainsExistingTaskBytesAndLargeTargetIsRejectedWhole(_ family: LearningTranslationPrompt.Family) throws {
        let source = "你好。"
        let bare = try LearningTranslationPrompt.render(source: source, sourceLanguage: .chinese, targetLanguage: .english, family: family)
        let planned = try LearningTranslationBudget.prompt(
            input: .init(source: source), sourceLanguage: .chinese,
            targetLanguage: .english, family: family, total: 8_192, output: 2_048, estimated: false, count: { $0.utf8.count })
        #expect(planned.prompt == bare.prompt)
        #expect(planned.userOnly == bare.userOnly)
        #expect(throws: LearningFailure.self) {
            try LearningTranslationBudget.prompt(
                input: .init(source: String(repeating: "a", count: 5_000)), sourceLanguage: .english,
                targetLanguage: .chinese, family: family, total: 2_048, output: 512, estimated: false, count: { $0.count })
        }
    }

    @Test
    func raisingTheModelBudgetAlsoPermitsALargerCompleteOutputReserve() throws {
        let draft = String(repeating: "A complete draft sentence. ", count: 400)
        #expect(throws: LearningFailure.self) { try ModelContextBudget.translationOutputTokens(source: draft, total: 8_192) }
        let reserve = try ModelContextBudget.translationOutputTokens(source: draft, total: 32_768)
        #expect(reserve > 8_192 && reserve < 32_768)
        let planned = try LearningTranslationBudget.prompt(input: .init(source: draft), sourceLanguage: .english,
            targetLanguage: .chinese, family: .generic, total: 32_768, output: reserve, estimated: true,
            count: ModelContextBudget.estimatedTokens)
        #expect(planned.prompt.contains(draft))
    }

    @Test
    func specialistInputLimitAppliesEvenWithLargeEndpointBudget() {
        #expect(throws: LearningFailure.self) {
            try LearningTranslationBudget.prompt(
                input: .init(source: String(repeating: "a", count: 2_000)), sourceLanguage: .english,
                targetLanguage: .chinese, family: .translateGemma, total: 32_768, output: 4_096, estimated: true, count: { $0.count })
        }
    }

    @Test
    func selectedTargetAndWholeDraftKeepTheirExactRangeSemantics() {
        let value = "前文😀。目标选区。后文。"
        let range = (value as NSString).range(of: "目标选区")
        let current = LearningTranslationInput.captured(value: value, range: range, source: "目标选区", mode: .currentSentence)
        #expect(current == .init(source: "目标选区"))
        let draft = LearningTranslationInput.captured(value: value, range: range, source: "目标选区", mode: .draft)
        #expect(draft.referenceBefore == "前文😀。")
        #expect(draft.referenceAfter == "。后文。")
        let all = LearningTranslationInput.captured(
            value: value, range: NSRange(location: 0, length: value.utf16.count), source: value, mode: .draft)
        #expect(all == .init(source: value))
    }

    @Test
    func estimatedTokenAllocatorNeverOverspendsOnADenseSuffix() {
        let content = String(repeating: "a", count: 1_000) + String(repeating: "中", count: 1_000)
        let sections = [
            PromptSection(
                name: "prefix", content: content, priority: 100, minChars: 1,
                maxChars: content.count, truncation: .preserveEnd)
        ]
        let kept = PromptSectionBudget.allocate(
            sections, totalTokens: 300, estimate: ModelContextBudget.estimatedTokens, enforcesTokenLimit: true)
        #expect(kept.reduce(0) { $0 + ModelContextBudget.estimatedTokens($1.content) } <= 300)
        #expect(kept.first?.content.hasSuffix("中") == true)
    }

    @Test
    func appleBudgetRetainsFollowingAndSurfaceFactsWhenTheyFit() throws {
        var settings = CotabbyTestFixtures.settingsSnapshot(selectedEngine: .appleIntelligence)
        settings.contextWindowTokens = 4_096
        let context = CotabbyTestFixtures.focusedInputContext(
            applicationName: "Mail", bundleIdentifier: "com.apple.mail",
            precedingText: "Please send ", trailingText: " before Friday.", windowTitle: "Project update", fieldPlaceholder: "Message body")
        let request = SuggestionRequestFactory.buildRequest(context: context, settings: settings, configuration: .standard).request
        let prompt = FoundationModelPromptRenderer.prompt(for: request)
        #expect(prompt.contains("before Friday."))
        #expect(prompt.contains("Mail"))
        #expect(prompt.contains("Project update"))
        #expect(prompt.contains("Message body"))
        try FoundationModelPromptRenderer.validateBudget(for: request)
    }
}
