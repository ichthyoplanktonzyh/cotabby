import Foundation
import Testing
@testable import Cotabby

/// Checks the actual request/rendering boundary: valid app notes and global notes retain separate
/// budgets, and apps that inherit defaults produce the previous prompt byte for byte.
@MainActor
struct PerAppInstructionsTests {
    @Test(arguments: [false, true])
    func fullGlobalAndAppNotesSurviveTheirIndependentCaps(tokenMode: Bool) {
        let global = String(repeating: "g", count: 1200)
        let notes = String(repeating: "a", count: 1160) + " APP_RULE_END"
        let prompt = BaseCompletionPromptRenderer.prompt(
            prefixText: "Please follow up on ", applicationName: "Mail", userName: nil,
            extendedContext: global, applicationInstructions: notes,
            tokenBudget: tokenMode ? 4000 : nil
        )
        #expect(prompt.contains(global))
        #expect(prompt.contains(notes))
        #expect(prompt.hasSuffix("Please follow up on "))
    }

    @Test
    func instructionsAreScopedAndReachBothRendererShapes() {
        let app = "com.apple.mail"
        let settings = CotabbyTestFixtures.settingsSnapshot(
            extendedContext: "Global glossary", perAppBehaviors: [app: PerAppBehavior(instructions: "Use concise prose.")]
        )
        let context = CotabbyTestFixtures.focusedInputContext(bundleIdentifier: app, precedingText: "Please follow up on ")
        let request = SuggestionRequestFactory.buildRequest(context: context, settings: settings, configuration: .standard).request
        #expect(request.extendedContext == "Global glossary")
        #expect(request.applicationInstructions == "Use concise prose.")
        #expect(request.prompt.contains("Use concise prose."))
        #expect(FoundationModelPromptRenderer.sessionInstructions(for: request).contains("Use concise prose."))
        let other = CotabbyTestFixtures.focusedInputContext(bundleIdentifier: "other.app", precedingText: context.precedingText)
        let otherRequest = SuggestionRequestFactory.buildRequest(context: other, settings: settings, configuration: .standard).request
        #expect(otherRequest.applicationInstructions == nil)
        #expect(!otherRequest.prompt.contains("Use concise prose."))
    }

    @Test
    func explicitEmptyAppNotesPreserveTheOldPrompt() {
        let before = BaseCompletionPromptRenderer.prompt(prefixText: "A short sentence ", applicationName: "Mail", userName: nil)
        let after = BaseCompletionPromptRenderer.prompt(
            prefixText: "A short sentence ", applicationName: "Mail", userName: nil, applicationInstructions: " \n"
        )
        #expect(before == after)
    }
}
